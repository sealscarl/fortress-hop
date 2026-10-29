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

const SNAPSHOT_EVERY := 2        ## Server sends 64 snapshots/s at 128 tick.
const INTERP_DELAY_TICKS := 16   ## Draw others 125 ms behind the server.
const CMD_REDUNDANCY := 4        ## Resend the last 4 commands each tick to survive packet loss.
const MAX_CMDS_PER_TICK := 4     ## Server catch-up limit per player per tick.
const MAX_QUEUED_CMDS := 64
const LAG_COMP_TICKS := 128      ## Rewind up to 1 s for hitscan checks.

static var instance: Game

@onready var players_root: Node3D = $"../Players"
@onready var spawner: MultiplayerSpawner = $"../PlayerSpawner"

var tick := 0

# Server side
var _cmd_queue := {}      ## peer id -> Array[PlayerCmd] waiting to run
var _last_queued := {}    ## peer id -> highest seq queued
var _last_run := {}       ## peer id -> seq of the last command run
var _next_grenade_id := 1
var _pos_history := {}    ## server tick -> {peer id: [hull center, half segment]}

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
	spawner.spawn_function = _spawn_player
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not get_node("/root/Net").dedicated:
			_on_peer_connected(1)  # The host plays too.
		for id in multiplayer.get_peers():
			_on_peer_connected(id)


# --- Spawning -----------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var spawns := get_tree().get_nodes_in_group("spawn_point")
	var at: Node3D = spawns[players_root.get_child_count() % spawns.size()] if spawns.size() else null
	var pos := at.global_position if at else Vector3(0, 0.1, 60)
	var yaw := at.rotation.y if at else 0.0
	spawner.spawn([id, pos, yaw])


func _on_peer_disconnected(id: int) -> void:
	var p := players_root.get_node_or_null(str(id))
	if p:
		p.queue_free()
	_cmd_queue.erase(id)
	_last_queued.erase(id)
	_last_run.erase(id)


## Runs on the server and on every client (MultiplayerSpawner replicates it).
func _spawn_player(data: Array) -> Node:
	var p: Player = PLAYER_SCENE.instantiate()
	p.peer_id = data[0]
	p.name = str(data[0])
	p.position = data[1]
	p.rotation.y = data[2]
	p.look_yaw = data[2]
	p.is_local = data[0] == multiplayer.get_unique_id()
	if p.is_local:
		local_player = p
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
			var cmd := p.build_cmd(_seq)
			cmd.view_tick = tick   # The host sees everyone live.
			p.simulate(cmd, delta)
			p.grenades.tick(cmd, delta)
			p.weapons.tick(cmd, delta)
			continue
		var q: Array = _cmd_queue.get(p.peer_id, [])
		var n := 0
		while q.size() and n < MAX_CMDS_PER_TICK:
			var cmd: PlayerCmd = q.pop_front()
			p.simulate(cmd, delta)
			p.grenades.tick(cmd, delta)
			p.weapons.tick(cmd, delta)
			_last_run[p.peer_id] = cmd.seq
			n += 1


func _client_predict(delta: float) -> void:
	if not is_instance_valid(local_player):
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
		everyone.append([p.peer_id, p.global_position, p.rotation.y, p.head.rotation.x, p.crouched])
	for id in multiplayer.get_peers():
		var p := players_root.get_node_or_null(str(id)) as Player
		if p == null:
			continue
		var personal := [_last_run.get(id, 0), p.get_state(), p.health, p.grenades.snapshot(), p.weapons.snapshot()]
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
	for c in _pending:
		local_player.simulate(c, delta)
		_history[c.seq] = local_player.get_state()
	local_player.apply_look()


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
	_show_grenade.rpc(id, type, pos, vel)


@rpc("authority", "call_remote", "reliable")
func _show_grenade(id: int, type: int, pos: Vector3, vel: Vector3) -> void:
	var g := Grenade.create(type as Grenade.Type, 0.0, null, id)
	_projectiles[id] = g
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
	_explosion.rpc(grenade_id, type, origin, radius)


@rpc("authority", "call_local", "reliable")
func _explosion(grenade_id: int, type: int, origin: Vector3, radius: float) -> void:
	var g: Node = _projectiles.get(grenade_id)
	if is_instance_valid(g):
		g.queue_free()
	_projectiles.erase(grenade_id)
	if radius > 0.0:
		GrenadeThrower.spawn_effect(get_parent(), type as Grenade.Type, origin, radius)


# --- Rockets -------------------------------------------------------------------

## Server: fire a real rocket and tell clients to show a look-alike.
func spawn_rocket(shooter: Player, pos: Vector3, vel: Vector3) -> void:
	var id := _new_projectile_id()
	var r := Rocket.create(shooter, vel, id)
	r.position = pos
	get_parent().add_child(r)
	_show_rocket.rpc(id, pos, vel)


@rpc("authority", "call_remote", "reliable")
func _show_rocket(id: int, pos: Vector3, vel: Vector3) -> void:
	var r := Rocket.create(null, vel, id)
	r.position = pos
	_projectiles[id] = r
	get_parent().add_child(r)


# --- Hitscan with lag compensation ---------------------------------------------

## Server, every tick: remember where every player's hull was.
func _record_positions() -> void:
	var now := {}
	for p: Player in players_root.get_children():
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
			if p == shooter:
				continue
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
		p.launch(p.velocity + dir * damage[p] * knockback)
		p.take_damage(damage[p])
	_tracers.rpc(origin, ends)


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
