class_name Game
extends Node
## Runs a match: spawns players, drives every physics tick, and handles the
## networking. Lives in each map as a "Game" node next to "Players".
##
## How multiplayer works (QuakeWorld-style, server-authoritative):
## - Every tick, your client turns your input into a PlayerCmd, runs it on
##   your own player immediately (so movement feels instant), remembers the
##   result, and sends the command to the server.
## - The server runs each client's commands through the same movement code,
##   in order, as they arrive. Grenades, damage and explosions happen only on
##   the server.
## - Every other tick the server sends a snapshot: where everyone is, plus,
##   for you, the last command it ran and your exact state after it.
## - Your client compares that with what it predicted for the same command.
##   If they differ (an explosion hit you, packet loss, a respawn), it resets
##   to the server's state and quickly re-runs your newer commands on top.
## - Other players are drawn about 125 ms in the past, smoothly interpolated
##   between snapshots.

const PLAYER_SCENE := preload("res://player/player.tscn")
const GAME_UI := preload("res://ui/game_ui.gd")

const SNAPSHOT_EVERY := 2        ## Server sends 64 snapshots/s at 128 tick.
const INTERP_DELAY_TICKS := 16   ## Draw others 125 ms behind the server.
const CMD_REDUNDANCY := 4        ## Resend the last 4 commands each tick to survive packet loss.
const MAX_CMDS_PER_TICK := 4     ## Server catch-up limit per player per tick.
const MAX_QUEUED_CMDS := 64
const LAG_COMP_TICKS := 128      ## Rewind up to 1 s for hitscan checks.

static var instance: Game

@onready var players_root: Node3D = $"../Players"

var tick := 0

# Server side
var _cmd_queue := {}      ## peer id -> Array[PlayerCmd] waiting to run
var _last_queued := {}    ## peer id -> highest seq queued
var _last_run := {}       ## peer id -> seq of the last command run
var _next_grenade_id := 1
## Clients that have loaded the map and can receive game events.
var ready_peers: Array[int] = []
var _pos_history := {}    ## server tick -> {peer id: [hull center, half segment]}
var _pipes := {}          ## peer id -> Array[Bomb] (oldest first)
var _damage_batch := {}   ## attacker peer -> {victim peer: amount} this tick

## Scoreboard, on every machine: peer id -> {name, kills, deaths}.
var scores := {}
var ui: CanvasLayer        ## Menus, scoreboard, kill feed (not on a dedicated server).

# Client side
var local_player: Player
var corrections := 0      ## How often prediction had to be corrected (debug).
var max_correction := 0.0 ## Largest position error corrected, in meters (debug).
var _seq := 0
var _pending: Array[PlayerCmd] = []   ## Sent but not yet confirmed by the server.
var _history := {}                    ## seq -> predicted state after that command
var _latest_snapshot: Array = []
var _server_tick := 0.0               ## Our running estimate of the server's tick.
var _interp := {}                     ## peer id -> Array of [tick, pos, yaw, pitch, crouched]
var _projectiles := {}                ## net id -> Grenade/Rocket look-alike


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	if not (multiplayer.is_server() and get_node("/root/Net").dedicated):
		ui = GAME_UI.new()
		add_child(ui)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not get_node("/root/Net").dedicated:
			_add_player(1, get_node("/root/Net").player_name)  # The host plays too.
	else:
		# The map is loaded: tell the server we're ready to play.
		_client_ready.rpc_id(1, get_node("/root/Net").player_name)


## Server: send an RPC to every client that has loaded the map (and run it
## here too if local is true). Clients still loading never get events for
## nodes they don't have yet.
func send_all(obj: Object, method: StringName, args: Array = [], local := true) -> void:
	for peer in ready_peers:
		multiplayer.rpc(peer, obj, method, args)
	if local:
		obj.callv(method, args)


# --- Spawning -----------------------------------------------------------------

## Server: a client finished loading the map.
@rpc("any_peer", "call_remote", "reliable")
func _client_ready(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id in ready_peers or not multiplayer.is_server():
		return
	ready_peers.append(id)
	Console.send_server_vars_to(id)   # Movement settings first, so prediction matches.
	# Everyone already here, then the newcomer for everyone.
	var all := []
	for p: Player in players_root.get_children():
		all.append(_spawn_data(p))
	_spawn_players.rpc_id(id, all)
	_add_player(id, player_name)
	if MapLogic.instance:
		MapLogic.instance.send_full_state(id)


## Server: create a player and tell every ready client about it.
func _add_player(id: int, player_name: String) -> void:
	if players_root.has_node(str(id)):
		return
	var team := _smaller_team()
	var spawns := get_tree().get_nodes_in_group("spawn_team%d" % team)
	var at: Node3D = spawns.pick_random() if spawns.size() else null
	var pos := at.global_position if at else Vector3(0, 0.1, 60)
	var yaw := at.rotation.y if at else 0.0
	var n := player_name.strip_edges().substr(0, 24)
	scores[id] = {"name": n if n else "Player %d" % (scores.size() + 1), "kills": 0, "deaths": 0,
		"damage": 0.0, "touches": 0, "carry": 0.0, "caps": 0}
	var data := [id, pos, yaw, team]
	_spawn_player(data)
	for peer in ready_peers:
		_spawn_players.rpc_id(peer, [data])
	send_all(self, "_sync_scores", [scores])


func _spawn_data(p: Player) -> Array:
	return [p.peer_id, p.global_position, p.rotation.y, p.team]


func _smaller_team() -> int:
	var counts := [0, 0]
	for p: Player in players_root.get_children():
		counts[p.team] += 1
	return 0 if counts[0] <= counts[1] else 1


func _on_peer_disconnected(id: int) -> void:
	ready_peers.erase(id)
	var p := players_root.get_node_or_null(str(id))
	if p:
		p.grenades.drop_held()
		if MapLogic.instance:
			MapLogic.instance.on_player_gone(p)
		p.queue_free()
	_cmd_queue.erase(id)
	_last_queued.erase(id)
	_last_run.erase(id)
	scores.erase(id)
	send_all(self, "_despawn_player", [id], false)
	send_all(self, "_sync_scores", [scores])


@rpc("authority", "call_remote", "reliable")
func _spawn_players(list: Array) -> void:
	for data in list:
		if not players_root.has_node(str(data[0])):
			_spawn_player(data)


@rpc("authority", "call_remote", "reliable")
func _despawn_player(id: int) -> void:
	var p := players_root.get_node_or_null(str(id))
	if p:
		p.queue_free()
	_interp.erase(id)


func _spawn_player(data: Array) -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	p.peer_id = data[0]
	p.name = str(data[0])
	p.position = data[1]
	p.rotation.y = data[2]
	p.look_yaw = data[2]
	p.team = data[3]
	p.is_local = data[0] == multiplayer.get_unique_id()
	if p.is_local:
		local_player = p
	players_root.add_child(p)
	return p


# --- Tick loop ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick += 1
	if multiplayer.is_server():
		_server_tick_players(delta)
		if tick % SNAPSHOT_EVERY == 0:
			_send_snapshots()
	else:
		_server_tick += 1.0
		if _latest_snapshot.size():
			_apply_snapshot(_latest_snapshot)
			_latest_snapshot = []
		_client_predict(delta)
		_interpolate_others()


func _server_tick_players(delta: float) -> void:
	_record_positions()
	for p: Player in players_root.get_children():
		if p.is_queued_for_deletion():
			continue
		if p.is_local:
			# Host: no network in the way, just run our input.
			_seq += 1
			if not p.alive:
				continue
			var cmd := p.build_cmd(_seq)
			cmd.view_tick = tick   # The host sees everyone live.
			p.simulate(cmd, delta)
			p.grenades.tick(cmd, delta)
			p.weapons.tick(cmd, delta)
			_flag_input(p, cmd)
			continue
		var q: Array = _cmd_queue.get(p.peer_id, [])
		var n := 0
		while q.size() and n < MAX_CMDS_PER_TICK:
			var cmd: PlayerCmd = q.pop_front()
			_last_run[p.peer_id] = cmd.seq
			n += 1
			if not p.alive:
				continue  # Dead or still picking a class: drop the input.
			p.simulate(cmd, delta)
			p.grenades.tick(cmd, delta)
			p.weapons.tick(cmd, delta)
			_flag_input(p, cmd)
	_flush_damage_numbers()
	_scores_sync_left -= delta
	if _scores_dirty and _scores_sync_left <= 0.0:
		_scores_dirty = false
		_scores_sync_left = 0.5
		send_all(self, "_sync_scores", [scores])


var _scores_dirty := false
var _scores_sync_left := 0.0


## Server: add to a scoreboard stat (damage, touches, carry, caps). Sent to
## everyone at most twice a second.
func add_stat(peer: int, key: String, amount: float) -> void:
	if scores.has(peer):
		scores[peer][key] = scores[peer].get(key, 0) + amount
		_scores_dirty = true


func _flag_input(p: Player, cmd: PlayerCmd) -> void:
	if cmd.has(PlayerCmd.THROW_FLAG) and MapLogic.instance:
		MapLogic.instance.throw_flag(p)


func _client_predict(delta: float) -> void:
	if not is_instance_valid(local_player) or not local_player.alive:
		return
	_seq += 1
	var cmd := local_player.build_cmd(_seq)
	cmd.view_tick = int(_server_tick) - INTERP_DELAY_TICKS
	local_player.simulate(cmd, delta)
	_history[_seq] = local_player.get_state()
	_pending.append(cmd)
	var packed := []
	for c in _pending.slice(maxi(0, _pending.size() - CMD_REDUNDANCY)):
		packed.append(c.to_array())
	_submit_cmds.rpc_id(1, packed)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_cmds(packed: Array) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not players_root.has_node(str(id)):
		return
	var q: Array = _cmd_queue.get_or_add(id, [])
	var last: int = _last_queued.get(id, 0)
	for a in packed:
		var c := PlayerCmd.from_array(a) if a is Array else null
		if c and c.seq > last:
			q.append(c)
			last = c.seq
	_last_queued[id] = last
	while q.size() > MAX_QUEUED_CMDS:
		q.pop_front()


# --- Snapshots ------------------------------------------------------------------

func _send_snapshots() -> void:
	var everyone := []
	for p: Player in players_root.get_children():
		everyone.append([p.peer_id, p.global_position, p.rotation.y, p.head.rotation.x, p.crouched,
			p.team, p.class_id, p.alive])
	for id in ready_peers:
		var p := players_root.get_node_or_null(str(id)) as Player
		if p == null:
			continue
		var personal := [_last_run.get(id, 0), p.get_state(), p.health, p.grenades.snapshot(),
			p.weapons.snapshot(), p.pending_class]
		_receive_snapshot.rpc_id(id, tick, everyone, personal)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshot(server_tick: int, everyone: Array, personal: Array) -> void:
	# Applied at the start of our next physics tick, so replays run in step.
	_latest_snapshot = [server_tick, everyone, personal]


func _apply_snapshot(snap: Array) -> void:
	var server_tick: int = snap[0]
	if absf(_server_tick - server_tick) > 8.0:
		_server_tick = server_tick
	var my_id := multiplayer.get_unique_id()
	for e in snap[1]:
		var who := players_root.get_node_or_null(str(e[0])) as Player
		if who:
			_apply_identity(who, e[5], e[6], e[7])
		if e[0] == my_id:
			continue
		var buf: Array = _interp.get_or_add(e[0], [])
		buf.append([server_tick, e[1], e[2], e[3], e[4]])
		if buf.size() > 64:
			buf.pop_front()

	if not is_instance_valid(local_player):
		return
	var personal: Array = snap[2]
	var ack: int = personal[0]
	var server_state: Array = personal[1]
	local_player.health = personal[2]
	local_player.grenades.apply_snapshot(personal[3])
	local_player.weapons.apply_snapshot(personal[4])
	local_player.pending_class = personal[5]
	if not local_player.alive:
		_pending.clear()
		_history.clear()
		return

	while _pending.size() and _pending[0].seq <= ack:
		_pending.pop_front()
	var predicted: Variant = _history.get(ack)
	for s in _history.keys():
		if s <= ack:
			_history.erase(s)
	if predicted != null and _states_match(predicted, server_state):
		return

	# Prediction was off: rewind to the server's state and replay.
	corrections += 1
	if predicted != null:
		max_correction = maxf(max_correction, (predicted[0] as Vector3).distance_to(server_state[0]))
	local_player.set_state(server_state)
	var delta := 1.0 / Engine.physics_ticks_per_second
	local_player.replaying = true   # Re-running ticks: don't redo view effects.
	for c in _pending:
		local_player.simulate(c, delta)
		_history[c.seq] = local_player.get_state()
	local_player.replaying = false
	local_player.apply_look()


## Client: team, class and alive state from a snapshot.
func _apply_identity(p: Player, team: int, class_id: int, alive: bool) -> void:
	if p.team != team:
		p.set_team(team)
	if p.class_id != class_id and class_id != -1:
		p.apply_class(class_id)
	if p.alive != alive:
		p.set_alive(alive)
		if alive and p == local_player:
			_pending.clear()   # Fresh life: the next snapshot sets our state.
			_history.clear()


func _states_match(a: Array, b: Array) -> bool:
	return (a[0] as Vector3).distance_to(b[0]) < 0.02 \
		and (a[1] as Vector3).distance_to(b[1]) < 0.05 \
		and a[2] == b[2]


func _interpolate_others() -> void:
	var render_tick := _server_tick - INTERP_DELAY_TICKS
	for id in _interp:
		var p := players_root.get_node_or_null(str(id)) as Player
		var buf: Array = _interp[id]
		if p == null or buf.is_empty():
			continue
		var a: Array = buf[0]
		var b: Array = buf[0]
		for i in range(buf.size() - 1, -1, -1):
			if buf[i][0] <= render_tick:
				a = buf[i]
				b = buf[mini(i + 1, buf.size() - 1)]
				break
		var t := 0.0 if b[0] == a[0] else clampf((render_tick - a[0]) / float(b[0] - a[0]), 0.0, 1.0)
		p.global_position = (a[1] as Vector3).lerp(b[1], t)
		p.rotation.y = lerp_angle(a[2], b[2], t)
		p.head.rotation.x = lerpf(a[3], b[3], t)
		p.set_remote_crouched(b[4] if t > 0.5 else a[4])


# --- Grenades and explosions -------------------------------------------------

## Server: throw a real grenade and tell clients to show a look-alike.
func spawn_grenade(thrower: GrenadeThrower, type: Grenade.Type, pos: Vector3,
		vel: Vector3, fuse: float) -> void:
	var id := _new_projectile_id()
	_add_grenade(Grenade.create(type, fuse, thrower, id), pos, vel)
	send_all(self, "_show_grenade", [id, type, pos, vel], false)


@rpc("authority", "call_remote", "reliable")
func _show_grenade(id: int, type: int, pos: Vector3, vel: Vector3) -> void:
	var g := Grenade.create(type as Grenade.Type, 0.0, null, id)
	_projectiles[id] = g
	g.tree_exited.connect(func(): _projectiles.erase(id))
	_add_grenade(g, pos, vel)


func _add_grenade(g: Grenade, pos: Vector3, vel: Vector3) -> void:
	get_parent().add_child(g)
	g.global_position = pos
	g.linear_velocity = vel


func _new_projectile_id() -> int:
	_next_grenade_id += 1
	return _next_grenade_id


## Server: an explosion happened. Show it everywhere.
func announce_explosion(grenade_id: int, type: Grenade.Type, origin: Vector3, radius: float) -> void:
	send_all(self, "_explosion", [grenade_id, type, origin, radius])


@rpc("authority", "call_local", "reliable")
func _explosion(grenade_id: int, type: int, origin: Vector3, radius: float) -> void:
	# Untyped on purpose: the look-alike may already have removed itself, and
	# putting a freed object in a typed variable is an error.
	var g = _projectiles.get(grenade_id)
	if is_instance_valid(g):
		g.queue_free()
	_projectiles.erase(grenade_id)
	if radius > 0.0:
		GrenadeThrower.spawn_effect(get_parent(), type as Grenade.Type, origin, radius)


# --- Rockets, nails and Demoman bombs -------------------------------------

## Server: fire a real rocket or nail and tell clients to show a look-alike.
func spawn_projectile(shooter: Player, kind: int, pos: Vector3, vel: Vector3) -> void:
	var id := _new_projectile_id()
	var r := Rocket.create(shooter, kind, vel, id)
	r.position = pos
	get_parent().add_child(r)
	send_all(self, "_show_projectile", [id, kind, pos, vel], false)


@rpc("authority", "call_remote", "reliable")
func _show_projectile(id: int, kind: int, pos: Vector3, vel: Vector3) -> void:
	var r := Rocket.create(null, kind, vel, id)
	r.position = pos
	_projectiles[id] = r
	r.tree_exited.connect(func(): _projectiles.erase(id))
	get_parent().add_child(r)


## Server: launch a grenade or pipe bomb.
func spawn_bomb(shooter: Player, kind: int, pos: Vector3, vel: Vector3) -> void:
	var id := _new_projectile_id()
	var b := Bomb.create(shooter, kind, id, true)
	_add_bomb(b, pos, vel)
	if kind == WeaponStats.Kind.PIPEBOMB_LAUNCHER:
		var mine: Array = _pipes.get_or_add(shooter.peer_id, [])
		mine = mine.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
		mine.append(b)
		_pipes[shooter.peer_id] = mine
		if mine.size() > WeaponStats.get_stat(kind, "max_active"):
			mine.pop_front().explode()   # Too many out: the oldest goes off.
	send_all(self, "_show_bomb", [id, kind, pos, vel, shooter.peer_id], false)


@rpc("authority", "call_remote", "reliable")
func _show_bomb(id: int, kind: int, pos: Vector3, vel: Vector3, shooter_peer: int) -> void:
	var shooter := players_root.get_node_or_null(str(shooter_peer)) as Player
	var b := Bomb.create(shooter, kind, id, false)
	_projectiles[id] = b
	b.tree_exited.connect(func(): _projectiles.erase(id))
	_add_bomb(b, pos, vel)


func _add_bomb(b: Bomb, pos: Vector3, vel: Vector3) -> void:
	get_parent().add_child(b)
	b.global_position = pos
	b.linear_velocity = vel


## Server: Mouse 5. Every armed pipe this player has out goes off; pipes
## fired less than arm_time ago stay put for the next press.
func detonate_pipes(p: Player) -> void:
	var still_arming := []
	for b in _pipes.get(p.peer_id, []):
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if b.is_armed():
			b.explode()
		else:
			still_arming.append(b)
	_pipes[p.peer_id] = still_arming


# --- Hitscan with lag compensation ---------------------------------------------

## Server, every tick: remember where every player's hull was.
func _record_positions() -> void:
	var now := {}
	for p: Player in players_root.get_children():
		if p.alive:
			now[p.peer_id] = [p.center(), p.hull_half_segment()]
	_pos_history[tick] = now
	_pos_history.erase(tick - LAG_COMP_TICKS - 1)


## Server: trace bullets/pellets. Other players are checked where the shooter
## saw them (view_tick), up to 1 s in the past; walls are checked as they are now.
func hitscan(shooter: Player, origin: Vector3, dirs: Array[Vector3], max_range: float,
		damage_each: float, knockback: float, view_tick: int) -> void:
	var space := shooter.get_world_3d().direct_space_state
	var rewind: Dictionary = _pos_history.get(clampi(view_tick, tick - LAG_COMP_TICKS, tick), {})
	var damage := {}
	var ends: Array[Vector3] = []
	for d in dirs:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + d * max_range, 1)
		var wall := space.intersect_ray(query)
		var best_dist := max_range if wall.is_empty() else origin.distance_to(wall.position)
		var best: Player = null
		for p: Player in players_root.get_children():
			if p == shooter or not p.alive or (p.team == shooter.team and not friendly_fire()):
				continue  # Pellets pass through teammates (friendly fire off).
			if not rewind.has(p.peer_id) and not rewind.is_empty():
				continue  # Wasn't alive at that moment.
			var hull: Array = rewind.get(p.peer_id, [p.center(), p.hull_half_segment()])
			var a: Vector3 = hull[0] - Vector3.UP * hull[1]
			var b: Vector3 = hull[0] + Vector3.UP * hull[1]
			var pts := Geometry3D.get_closest_points_between_segments(origin, origin + d * best_dist, a, b)
			if pts[0].distance_to(pts[1]) <= Player.HULL_RADIUS + 0.05:
				best_dist = origin.distance_to(pts[0])
				best = p
		ends.append(origin + d * best_dist)
		if best:
			damage[best] = damage.get(best, 0.0) + damage_each
	for p: Player in damage:
		var dir := (p.center() - origin).normalized()
		p.hurt(damage[p], shooter, dir * damage[p] * knockback, "shotgun")
	send_all(self, "_tracers", [origin, ends])


## Tracer lines and impact puffs, on every machine.
@rpc("authority", "call_local", "unreliable")
func _tracers(origin: Vector3, ends: Array) -> void:
	var im := ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.9, 0.6, 0.8)
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	# Start the line a little ahead of the eye so it doesn't cover the screen.
	for e: Vector3 in ends:
		im.surface_add_vertex(origin + (e - origin).normalized() * 1.0)
		im.surface_add_vertex(e)
	im.surface_end()
	get_parent().add_child(lines)
	var tw := lines.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(lines.queue_free)


# --- Medkit ----------------------------------------------------------------------

## Server: the Medic's medkit. Heals the teammate you're touching, or hits an
## enemy. Checked against where the Medic saw players, like the shotgun.
func medkit(medic: Player, origin: Vector3, aim: Vector3, reach: float, heal_amount: float,
		damage: float, view_tick: int) -> void:
	var space := medic.get_world_3d().direct_space_state
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + aim * reach, 1))
	var best_dist := reach if wall.is_empty() else origin.distance_to(wall.position)
	var rewind: Dictionary = _pos_history.get(clampi(view_tick, tick - LAG_COMP_TICKS, tick), {})
	var best: Player = null
	for p: Player in players_root.get_children():
		if p == medic or not p.alive or not rewind.has(p.peer_id):
			continue
		var hull: Array = rewind[p.peer_id]
		var pts := Geometry3D.get_closest_points_between_segments(origin, origin + aim * best_dist,
			hull[0] - Vector3.UP * hull[1], hull[0] + Vector3.UP * hull[1])
		# A little more forgiving than bullets: it's a melee swing.
		if pts[0].distance_to(pts[1]) <= Player.HULL_RADIUS + 0.3:
			best_dist = origin.distance_to(pts[0])
			best = p
	if best == null:
		return
	if best.team == medic.team:
		best.heal(heal_amount, medic)
	else:
		best.hurt(damage, medic, aim * 2.0, "medkit")


# --- Teams, classes, scores ------------------------------------------------------

## Local player asks to change team (-1 = auto). Works on host and clients.
func request_team(t: int) -> void:
	if multiplayer.is_server():
		_do_team(1, t)
	else:
		_request_team.rpc_id(1, t)


func request_class(c: int) -> void:
	if multiplayer.is_server():
		_do_class(1, c)
	else:
		_request_class.rpc_id(1, c)


## Console "kill": respawn, counted as a suicide.
func request_kill() -> void:
	if multiplayer.is_server():
		_do_kill(1)
	else:
		_request_kill.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_kill() -> void:
	_do_kill(multiplayer.get_remote_sender_id())


func _do_kill(peer: int) -> void:
	var p := players_root.get_node_or_null(str(peer)) as Player
	if p and p.alive and p.class_id != -1:
		p.last_weapon = "skull"
		p.die(p)


## Server cvar mp_friendlyfire: teammates hurt (and push) each other.
static func friendly_fire() -> bool:
	return Console.sv("mp_friendlyfire") != 0.0


@rpc("any_peer", "call_remote", "reliable")
func _request_team(t: int) -> void:
	_do_team(multiplayer.get_remote_sender_id(), t)


@rpc("any_peer", "call_remote", "reliable")
func _request_class(c: int) -> void:
	_do_class(multiplayer.get_remote_sender_id(), c)


## Server. Switching team respawns you on the new side straight away (no
## death counted). Before you've picked a class you stay in the menu.
func _do_team(peer: int, t: int) -> void:
	var p := players_root.get_node_or_null(str(peer)) as Player
	if p == null:
		return
	if t != 0 and t != 1:
		t = _smaller_team() if p.team != _smaller_team() or not p.alive else p.team
	if t == p.team:
		return
	p.grenades.drop_held()
	if MapLogic.instance:
		MapLogic.instance.on_player_died(p)   # Switching team drops a carried flag.
	p.set_team(t)
	if p.alive:
		p.respawn()


## Server. Your first class spawns you right away; after that, a new class
## takes effect the next time you respawn (TFC rules).
func _do_class(peer: int, c: int) -> void:
	var p := players_root.get_node_or_null(str(peer)) as Player
	if p == null or not PlayerClasses.DATA.has(c):
		return
	if not p.alive:
		p.apply_class(c)
		p.pending_class = -1
		p.respawn()
	elif c == p.class_id:
		p.pending_class = -1
	else:
		p.pending_class = c


## Server: someone died. Count it and tell everyone.
func on_death(victim: Player, killer: Player) -> void:
	if scores.has(victim.peer_id):
		scores[victim.peer_id].deaths += 1
	var teamkill := killer != null and killer != victim and killer.team == victim.team
	if killer and killer != victim and scores.has(killer.peer_id):
		scores[killer.peer_id].kills += -1 if teamkill else 1   # TF: a team kill costs a frag.
	send_all(self, "_sync_scores", [scores])
	var kname: String = scores[killer.peer_id].name if killer and scores.has(killer.peer_id) else ""
	var vname: String = scores[victim.peer_id].name if scores.has(victim.peer_id) else "?"
	var weapon: String = victim.last_weapon if victim.last_weapon != "" else "skull"
	send_all(self, "_kill_feed", [kname if killer != victim else "", vname,
		killer.team if killer else -1, victim.team, victim.death_msg, weapon,
		killer.peer_id if killer else 0, victim.peer_id, teamkill])


@rpc("authority", "call_local", "reliable")
func _sync_scores(s: Dictionary) -> void:
	scores = s


@rpc("authority", "call_local", "reliable")
func _kill_feed(killer_name: String, victim_name: String, killer_team: int, victim_team: int, how := "",
		weapon := "skull", killer_peer := 0, victim_peer := 0, teamkill := false) -> void:
	if ui:
		var me := multiplayer.get_unique_id()
		ui.add_kill(killer_name, victim_name, killer_team, victim_team, how, weapon,
			me == killer_peer or me == victim_peer, teamkill)


# --- Damage numbers ---------------------------------------------------------------

## Server: remember damage (positive) or healing (negative) for the attacker's
## floating numbers. Sent once per tick, so a shotgun blast shows one total.
func report_damage(attacker: Player, victim: Player, amount: float) -> void:
	if attacker == null or attacker == victim or not attacker.is_inside_tree():
		return
	var per: Dictionary = _damage_batch.get_or_add(attacker.peer_id, {})
	per[victim.peer_id] = per.get(victim.peer_id, 0.0) + amount


func _flush_damage_numbers() -> void:
	for attacker_peer in _damage_batch:
		var list := []
		for victim_peer in _damage_batch[attacker_peer]:
			list.append([victim_peer, roundi(_damage_batch[attacker_peer][victim_peer])])
		if attacker_peer == multiplayer.get_unique_id():
			_show_damage_numbers(list)
		elif attacker_peer in multiplayer.get_peers():
			_show_damage_numbers.rpc_id(attacker_peer, list)
	_damage_batch.clear()


@rpc("authority", "call_remote", "reliable")
func _show_damage_numbers(list: Array) -> void:
	for e in list:
		var victim := players_root.get_node_or_null(str(e[0])) as Player
		if victim == null or e[1] == 0:
			continue
		var label := Label3D.new()
		var healing: bool = e[1] < 0
		label.text = ("+%d" % -e[1]) if healing else ("-%d" % e[1])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.font_size = 40
		label.outline_size = 12
		label.modulate = Color(0.4, 1.0, 0.45) if healing else Color(1.0, 0.85, 0.2)
		get_parent().add_child(label)
		label.global_position = victim.global_position + Vector3(randf_range(-0.3, 0.3), 2.2, randf_range(-0.3, 0.3))
		var tw := label.create_tween().set_parallel()
		tw.tween_property(label, "global_position:y", label.global_position.y + 0.8, 1.0)
		tw.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.4)
		tw.chain().tween_callback(label.queue_free)
