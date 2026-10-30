class_name MapLogic
extends Node3D
## Reads the QWTF (TeamFortress) entities that MapBuilder kept from a .map,
## and runs that map's rules: team spawns, capture-the-flag, security
## buttons and laser gates, spawn protection, supply packs, lifts and lights.
##
## Everything is decided on the server; clients get the state through RPCs
## (send_full_state on join, _state on every change and once a second).
##
## TF conventions: team_no 1 = Blue, 2 = Red (ours: 0 = Red, 1 = Blue).
## Goals use Quake coordinates; 32 units = 1 m; Godot = (y, z, x) / 32.

static var instance: MapLogic

const U := 32.0
const DEFAULT_GOAL_MIN := Vector3(-16, -16, -24)   ## TF default touch box.
const DEFAULT_GOAL_MAX := Vector3(16, 16, 32)

const SND := {
	"taken": preload("res://sounds/flag_taken.wav"),
	"capture": preload("res://sounds/flag_capture.wav"),
	"return": preload("res://sounds/flag_return.wav"),
	"drop": preload("res://sounds/flag_drop.wav"),
	"sec_down": preload("res://sounds/security_down.wav"),
	"sec_up": preload("res://sounds/security_up.wav"),
	"zap": preload("res://sounds/laser_zap.wav"),
	"pickup": preload("res://sounds/pickup.wav"),
}

enum FlagState { HOME, CARRIED, DROPPED }

## Path to the instanced geometry scene (func_godot output).
@export var geometry_path: NodePath = ^"../Geometry"

var team_scores := [0, 0]
var flags: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var lasers: Array[Dictionary] = []
var securities: Array[Dictionary] = []
var kill_zones: Array[Dictionary] = []
var packs: Array[Dictionary] = []
var plats: Array[Dictionary] = []

var _sync_timer := 0.0
var _sound: AudioStreamPlayer


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.volume_db = -4.0
	add_child(_sound)
	var geo := get_node_or_null(geometry_path)
	if geo == null:
		push_error("MapLogic: no geometry at %s" % geometry_path)
		return
	var ents: Array[Node] = []
	for n in geo.get_children():
		if n.has_meta("func_godot_properties"):
			ents.append(n)
	_build_spawns(ents)
	_build_lights(ents)
	_build_flags_and_captures(ents)
	_build_security(ents)
	_build_spawn_protection(ents)
	_build_packs(ents)
	_build_plats(ents)
	_tint_world()


# --- TF helpers ------------------------------------------------------------------

static func props(n: Node) -> Dictionary:
	return n.get_meta("func_godot_properties", {})


static func tf_team(n: Variant) -> int:
	match str(n).to_int():
		1: return 1     # Blue
		2: return 0     # Red
	return -1           # Anyone


static func qvec(s: Variant) -> Vector3:
	var c := str(s).split_floats(" ")
	return Vector3(c[0], c[1], c[2]) if c.size() >= 3 else Vector3.ZERO


static func q2g(q: Vector3) -> Vector3:
	return Vector3(q.y, q.z, q.x) / U


## A goal's touch box in Godot space: origin + goal_min..goal_max (Quake).
static func goal_box(p: Dictionary) -> AABB:
	var o := qvec(p.get("origin", "0 0 0"))
	var mn: Vector3 = qvec(p.goal_min) if p.has("goal_min") else DEFAULT_GOAL_MIN
	var mx: Vector3 = qvec(p.goal_max) if p.has("goal_max") else DEFAULT_GOAL_MAX
	var a := q2g(o + mn)
	var b := q2g(o + mx)
	return AABB(a.min(b), (a - b).abs())


static func text(s: Variant) -> String:
	return str(s).replace("\\n", "\n").strip_edges()


## Quake yaw (degrees) to our player rotation.y.
static func yaw_from_angle(a: Variant) -> float:
	return deg_to_rad(str(a).to_float() + 180.0)


func _player_box(p: Player) -> AABB:
	var h := p.hull_half_segment() + Player.HULL_RADIUS
	return AABB(p.center() - Vector3(Player.HULL_RADIUS, h, Player.HULL_RADIUS),
		Vector3(Player.HULL_RADIUS * 2, h * 2, Player.HULL_RADIUS * 2))


func _living_players() -> Array[Player]:
	var out: Array[Player] = []
	if Game.instance:
		for p: Player in Game.instance.players_root.get_children():
			if p.alive and not p.is_queued_for_deletion():
				out.append(p)
	return out


# --- Building ----------------------------------------------------------------------

func _build_spawns(ents: Array[Node]) -> void:
	for n in ents:
		var p := props(n)
		if p.classname != "info_player_teamspawn":
			continue
		var team := tf_team(p.get("team_no", 0))
		var m := Marker3D.new()
		# Quake spawn origins are at the hull center (24 units above the feet).
		m.position = n.position - Vector3(0, 24.0 / U, 0)
		m.rotation.y = yaw_from_angle(p.get("angle", 0))
		for t in ([0, 1] if team == -1 else [team]):
			m.add_to_group("spawn_team%d" % t)
		add_child(m)


func _build_lights(ents: Array[Node]) -> void:
	for n in ents:
		var p := props(n)
		if p.classname != "light":
			continue
		var l := OmniLight3D.new()
		var value := str(p.get("light", "300")).to_float()
		l.omni_range = clampf(value / U, 2.0, 30.0)
		l.light_energy = 0.9
		l.omni_attenuation = 0.8
		l.shadow_enabled = false
		if p.has("_color"):
			var c := qvec(p._color)
			if c.length() > 1.5: c /= 255.0
			l.light_color = Color(c.x, c.y, c.z)
		l.position = n.position
		add_child(l)


func _build_flags_and_captures(ents: Array[Node]) -> void:
	for n in ents:
		var p := props(n)
		if p.classname == "item_tfgoal" and p.has("owned_by"):
			var owner_team := tf_team(p.owned_by)
			var f := {
				"goal_no": str(p.get("goal_no", "0")).to_int(),
				"owner": owner_team,
				"takers": tf_team(p.get("team_no", 0)),
				"name": str(p.get("netname", PlayerClasses.TEAM_NAMES[owner_team] + " flag")),
				"home": n.position - Vector3(0, 24.0 / U, 0),
				"return_time": str(p.get("pausetime", "30")).to_float(),
				"state": FlagState.HOME, "carrier": null, "pos": Vector3.ZERO, "return_left": 0.0,
				# A thrown or dropped flag flies (vel) until it lands. The
				# thrower can't grab it back for a moment (teammates can).
				"vel": Vector3.ZERO, "moving": false, "lock_peer": 0, "lock_left": 0.0,
				"msg_taken": text(p.get("message", "")),
			}
			f.pos = f.home
			f.node = MapVisuals.flag(PlayerClasses.TEAM_COLORS[owner_team])
			add_child(f.node)
			f.node.position = f.home
			var stand := MapVisuals.flag_stand(PlayerClasses.TEAM_COLORS[owner_team])
			add_child(stand)
			stand.position = f.home
			flags.append(f)
	for n in ents:
		var p := props(n)
		if p.classname == "info_tfgoal" and p.has("items_allowed"):
			var box := goal_box(p).grow(0.25)
			var team := tf_team(p.get("team_no", 0))
			var c := {
				"team": team, "box": box, "flag_goal": str(p.items_allowed).to_int(),
				"score": maxi(str(p.get("increase_team1", p.get("increase_team2", "10"))).to_int(), 1),
				"refill": str(p.get("target", "")) != "",
			}
			captures.append(c)
			var pad := MapVisuals.capture_pad(PlayerClasses.TEAM_COLORS[team], box.size)
			add_child(pad)
			pad.position = Vector3(box.get_center().x, box.position.y + 0.02, box.get_center().z)


## Security: each func_button targets an "off" goal that removes a group of
## lasers and starts an "on" goal that restores them after delay_time.
func _build_security(ents: Array[Node]) -> void:
	var by_target := {}
	var by_goal_no := {}
	for n in ents:
		var p := props(n)
		if p.has("targetname"): by_target[p.targetname] = p
		if p.has("goal_no"): by_goal_no[str(p.goal_no)] = p
	for n in ents:
		var p := props(n)
		if p.classname != "func_button" or not by_target.has(p.get("target", "")):
			continue
		var off: Dictionary = by_target[p.target]
		var on: Dictionary = by_goal_no.get(str(off.get("activate_goal_no", "")), {})
		var group := str(off.get("remove_group_no", ""))
		var owner_team := tf_team(on.get("owned_by", "0"))
		var presser := tf_team(p.get("team_no", 0))
		if owner_team == -1 and presser != -1:
			owner_team = 1 - presser
		var sec := {
			"owner": owner_team, "presser": presser, "group": group,
			"name": str(on.get("netname", PlayerClasses.TEAM_NAMES[owner_team] + " Security")),
			"duration": str(on.get("delay_time", "30")).to_float(),
			"cooldown": str(p.get("wait", "30")).to_float(),
			"offline_left": 0.0, "button": n, "button_box": _node_box(n).grow(0.35),
			"msg_down_team": text(p.get("non_team_broadcast", "Your security is offline!")),
			"msg_down_enemy": text(p.get("team_broadcast", "Enemy security is offline!")),
			"msg_up": text(on.get("broadcast", "%s is back online!" % str(on.get("netname", "Security")))),
		}
		securities.append(sec)
	# Lasers: goals with a 3lasers model and a kill effect, in a group.
	for n in ents:
		var p := props(n)
		if p.classname != "info_tfgoal" or not str(p.get("mdl", "")).contains("laser"):
			continue
		if not p.has("group_no"):
			continue   # Spawn-door lasers are handled by spawn protection.
		var box := goal_box(p)
		var kill_team := tf_team(p.get("team_no", 0))
		var owner_team := 1 - kill_team if kill_team != -1 else -1
		var vis := MapVisuals.laser(box, PlayerClasses.TEAM_COLORS[owner_team if owner_team != -1 else 0])
		add_child(vis)
		lasers.append({"box": box, "kill_team": kill_team, "group": str(p.group_no), "node": vis,
			"msg": text(p.get("n_b", " was laser'd"))})


func _security_for_group(group: String) -> Dictionary:
	for s in securities:
		if s.group == group:
			return s
	return {}


## Spawn protection: the laser doorways at spawn exits kill enemies, and so
## do the small "camper" goals next to them.
func _build_spawn_protection(ents: Array[Node]) -> void:
	for n in ents:
		var p := props(n)
		if p.classname != "info_tfgoal":
			continue
		var is_door_laser: bool = str(p.get("mdl", "")).contains("laser") and not p.has("group_no")
		var is_kill: bool = str(p.get("netname", "")) == "kill" and str(p.get("health", "0")).to_float() <= -100
		if not (is_door_laser or is_kill):
			continue
		var box := goal_box(p)
		# Door lasers list the team they protect against in team_no.
		var kill_team := tf_team(p.get("team_no", 0))
		if is_door_laser:
			var vis := MapVisuals.laser(box, PlayerClasses.TEAM_COLORS[1 - kill_team if kill_team != -1 else 0])
			add_child(vis)
		kill_zones.append({"box": box, "kill_team": kill_team, "msg": text(p.get("n_b", " is a camper!"))})


## Backpacks: health, ammo and grenades, team-restricted, with respawn.
func _build_packs(ents: Array[Node]) -> void:
	for n in ents:
		var p := props(n)
		if p.classname != "info_tfgoal" or not str(p.get("mdl", "")).contains("backpack"):
			continue
		var full: bool = str(p.get("ammo_rockets", "0")).to_int() >= 999
		var grenades: bool = p.has("no_grenades_1") and not p.has("ammo_rockets")
		var kind := "full" if full else ("grenades" if grenades else "ammo")
		var pos: Vector3 = (n as Node3D).position - Vector3(0, 24.0 / U, 0)
		var vis := MapVisuals.pack(kind)
		add_child(vis)
		vis.position = pos
		packs.append({
			"kind": kind, "team": tf_team(p.get("team_no", 0)), "pos": pos,
			"box": AABB(pos - Vector3(0.6, 0.0, 0.6), Vector3(1.2, 1.2, 1.2)),
			"wait": maxf(str(p.get("wait", "10")).to_float(), 1.0),
			"health": str(p.get("health", "0")).to_float(),
			"grenades": str(p.get("no_grenades_1", "0")).to_int(),
			"respawn_left": 0.0, "node": vis,
		})


## Quake func_plat: rests at the bottom, rises "height" units when someone
## stands on it, waits at the top, comes back down. Moves at "speed" (150).
func _build_plats(ents: Array[Node]) -> void:
	for n in ents:
		var p := props(n)
		if p.classname != "func_plat" or not n is AnimatableBody3D:
			continue
		var body := n as AnimatableBody3D
		body.sync_to_physics = true
		var box := _node_box(n)
		var height := str(p.get("height", str(box.size.y * U))).to_float() / U
		var plat := {
			"body": body, "top": body.position, "bottom": body.position - Vector3(0, height, 0),
			"speed": str(p.get("speed", "150")).to_float() / U,
			"wait": maxf(str(p.get("wait", "3")).to_float(), 1.0),
			"phase": 0, "phase_start": 0.0,   # 0 bottom, 1 rising, 2 top, 3 lowering
			"half": Vector2(box.size.x * 0.5, box.size.z * 0.5), "top_offset": box.end.y - body.position.y,
		}
		body.position = plat.bottom
		plats.append(plat)


## World-space AABB of a func_godot brush entity's mesh.
func _node_box(n: Node) -> AABB:
	for c in n.get_children():
		if c is MeshInstance3D:
			return (n as Node3D).transform * c.transform * (c as MeshInstance3D).get_aabb()
	return AABB((n as Node3D).position - Vector3.ONE * 0.5, Vector3.ONE)


## Tint the dev grid red/blue toward each team's spawns.
func _tint_world() -> void:
	var centers := [Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0]
	for t in 2:
		for s in get_tree().get_nodes_in_group("spawn_team%d" % t):
			centers[t] += s.global_position
			counts[t] += 1
	if counts[0] == 0 or counts[1] == 0:
		return
	var mat: ShaderMaterial = load("res://maps/materials/dev_grid.tres")
	mat.set_shader_parameter("tint_strength", 0.9)
	mat.set_shader_parameter("red_center", centers[0] / counts[0])
	mat.set_shader_parameter("blue_center", centers[1] / counts[1])


# --- Server rules ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_move_plats()
	if not multiplayer.is_server():
		_client_tick(delta)
		return
	var changed := false
	var living := _living_players()
	for p in living:
		var pbox := _player_box(p)
		# Lasers and spawn protection (harmless in match prematch).
		var deadly := _rules() == null or _rules().lasers_kill()
		for l in lasers:
			if deadly and l.node.visible and p.team == l.kill_team and pbox.intersects(l.box):
				_laser_kill(p, l.msg)
		for z in kill_zones:
			if deadly and p.alive and p.team == z.kill_team and pbox.intersects(z.box):
				_laser_kill(p, z.msg)
		if not p.alive:
			continue
		# Flags.
		for f in flags:
			if f.state != FlagState.CARRIED and p.team == f.takers and _flags_open(p.team) \
					and not (f.lock_left > 0.0 and f.lock_peer == p.peer_id) \
					and pbox.intersects(AABB(f.pos - Vector3(0.6, 0, 0.6), Vector3(1.2, 1.8, 1.2))):
				_take_flag(f, p)
				changed = true
		for f in flags:
			if f.carrier == p and _flags_open(p.team):
				for c in captures:
					if c.team == p.team and c.flag_goal == f.goal_no and pbox.intersects(c.box):
						_capture(f, p, c)
						changed = true
		# Security buttons.
		for s in securities:
			if s.offline_left <= 0.0 and p.team == s.presser and pbox.intersects(s.button_box):
				_security_down(s, p)
				changed = true
		# Packs.
		for k in packs:
			if k.respawn_left <= 0.0 and (k.team == -1 or k.team == p.team) and pbox.intersects(k.box):
				if _use_pack(k, p):
					changed = true
	# Timers.
	for f in flags:
		if f.state == FlagState.CARRIED and is_instance_valid(f.carrier):
			f.pos = f.carrier.global_position
			Game.instance.add_stat(f.carrier.peer_id, "carry", delta)
		elif f.state == FlagState.DROPPED:
			f.lock_left = maxf(f.lock_left - delta, 0.0)
			if f.moving and _move_flag(f, delta):
				changed = true   # Landed: tell everyone where.
			f.return_left -= delta
			if f.return_left <= 0.0 or f.pos.y < -40.0:
				_return_flag(f, "%s returned." % f.name)
				changed = true
	for s in securities:
		if s.offline_left > 0.0:
			s.offline_left -= delta
			if s.offline_left <= 0.0:
				s.offline_left = 0.0
				_set_lasers(s.group, true)
				send_all("_announce", [s.msg_up, -1, "sec_up"])
				changed = true
	for k in packs:
		if k.respawn_left > 0.0:
			k.respawn_left -= delta
			if k.respawn_left <= 0.0:
				changed = true
	_sync_timer -= delta
	if changed or _sync_timer <= 0.0:
		_sync_timer = 1.0
		send_all("_state", [_state_array()], false)
	_update_visuals()


## The game clock / match rules (net/match_state.gd), if there is a game.
func _rules() -> MatchState:
	return Game.instance.match_state if Game.instance else null


## Whether this team may take and capture flags right now (match mode: only
## the attacking team, and not in prematch).
func _flags_open(team: int) -> bool:
	return _rules() == null or _rules().can_take_flag(team)


## Server: everything back to the start of a game: flags home, security
## online, packs back, and (unless keep_scores) team scores zero.
func reset_objectives(keep_scores := false) -> void:
	for f in flags:
		_return_flag(f, "", false)
	for s in securities:
		s.offline_left = 0.0
		_set_lasers(s.group, true)
	for k in packs:
		k.respawn_left = 0.0
	if not keep_scores:
		team_scores = [0, 0]
	send_all("_state", [_state_array()], false)


func _laser_kill(p: Player, msg: String) -> void:
	send_all("_play_at", ["zap", p.center()])
	p.death_msg = msg.strip_edges()
	p.take_damage(9999.0, null, "laser")


func _take_flag(f: Dictionary, p: Player) -> void:
	f.state = FlagState.CARRIED
	f.carrier = p
	Game.instance.add_stat(p.peer_id, "touches", 1)
	var who: String = _name(p)
	send_all("_announce", [f.msg_taken if f.msg_taken else "You have the %s!" % f.name, p.peer_id, "taken"])
	send_all("_announce_team", ["Your team has the enemy flag!", p.team, "%s has the %s!" % [who, f.name], "taken", p.peer_id])


func _capture(f: Dictionary, p: Player, c: Dictionary) -> void:
	team_scores[p.team] += c.score
	Game.instance.add_stat(p.peer_id, "caps", 1)
	var msg := "%s captured the %s!" % [_name(p), f.name]
	_return_flag(f, "", false)
	if c.refill:
		p.health = p.max_health
		p.grenades.refill()
		p.weapons.refill()
	send_all("_announce", [msg, -1, "capture"])


func _return_flag(f: Dictionary, msg: String, sound := true) -> void:
	f.state = FlagState.HOME
	f.carrier = null
	f.pos = f.home
	f.moving = false
	f.vel = Vector3.ZERO
	if msg:
		send_all("_announce", [msg, -1, "return" if sound else ""])


func _drop_flag(f: Dictionary, at: Vector3, vel := Vector3.ZERO, msg := "") -> void:
	f.state = FlagState.DROPPED
	f.carrier = null
	f.pos = at
	f.vel = vel
	f.moving = true   # Falls to the floor (or flies, if thrown).
	f.return_left = f.return_time
	if at.y < -40.0:
		_return_flag(f, "%s returned." % f.name)
	else:
		send_all("_announce", [msg if msg else "The %s was dropped!" % f.name, -1, "drop"])
	send_all("_state", [_state_array()], false)


## Server: the carrier pressed Throw flag (A).
func throw_flag(p: Player) -> void:
	for f in flags:
		if f.carrier == p and f.state == FlagState.CARRIED:
			var aim := -p.camera.global_basis.z
			var vel := aim * Console.sv("tf_flagthrow_speed") / U + Vector3.UP * Console.sv("tf_flagthrow_up") / U
			f.lock_peer = p.peer_id
			f.lock_left = 1.0
			_drop_flag(f, p.global_position + Vector3.UP * 0.6, vel, "%s threw the %s!" % [_name(p), f.name])
			return


## Moves a flying flag one tick: gravity, stops against walls, lands on
## floors. Same code on the server and on clients (for a smooth arc).
## Returns true when it lands.
func _move_flag(f: Dictionary, delta: float) -> bool:
	var space := get_world_3d().direct_space_state
	f.vel.y -= Console.sv("sv_gravity") / U * delta
	var motion: Vector3 = f.vel * delta
	# Walls and ceilings, checked a little above the flag's base.
	var lift := Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(f.pos + lift, f.pos + lift + motion, 1)
	var hit := space.intersect_ray(q)
	if hit and hit.normal.y < 0.7:
		var n: Vector3 = hit.normal
		f.vel -= n * minf(f.vel.dot(n), 0.0)   # Lose the speed into the wall.
		motion = f.vel * delta
	# The floor, at the flag's base.
	q = PhysicsRayQueryParameters3D.create(f.pos + Vector3.UP * 0.05, f.pos + motion, 1)
	hit = space.intersect_ray(q)
	if hit and hit.normal.y >= 0.7 and f.vel.y <= 0.0:
		f.pos = hit.position
		f.vel = Vector3.ZERO
		f.moving = false
		return true
	f.pos += motion
	return false


## Called by Player.die() before respawning, and when a player leaves or
## switches team: drop whatever flag they carry where they stand.
func on_player_died(p: Player) -> void:
	if not multiplayer.is_server():
		return
	for f in flags:
		if f.carrier == p:
			_drop_flag(f, p.global_position)


func on_player_gone(p: Player) -> void:
	on_player_died(p)


func _security_down(s: Dictionary, _presser: Player) -> void:
	s.offline_left = s.duration
	_set_lasers(s.group, false)
	send_all("_announce_team", [s.msg_down_team, s.owner, s.msg_down_enemy, "sec_down"])


func _use_pack(k: Dictionary, p: Player) -> bool:
	var used := false
	if k.kind == "full":
		used = true
		p.health = p.max_health
		p.weapons.refill()
		p.grenades.refill()
	elif k.kind == "grenades":
		used = p.grenades.frags < p.grenades.max_frags or p.grenades.concs < p.grenades.max_concs
		p.grenades.refill()
	else:
		# Ammo pack: half of each weapon's reserve back.
		for i in p.weapons.kinds.size():
			var mx: int = p.weapons.stat(i, "reserve")
			if mx > 0 and p.weapons.reserve[i] < mx:
				p.weapons.reserve[i] = mini(mx, p.weapons.reserve[i] + ceili(mx * 0.5))
				used = true
	if used:
		k.respawn_left = k.wait
		send_all("_play_at", ["pickup", k.pos], true)
	return used


func _set_lasers(group: String, on: bool) -> void:
	for l in lasers:
		if l.group == group:
			l.node.visible = on


func _name(p: Player) -> String:
	return Game.instance.scores.get(p.peer_id, {}).get("name", "Someone") if Game.instance else "Someone"


# --- Lifts (deterministic from server time, so clients agree) -----------------------

func _now() -> float:
	if Game.instance == null:
		return 0.0
	var ticks: float = float(Game.instance.tick) if multiplayer.is_server() else Game.instance._server_tick
	return ticks / Engine.physics_ticks_per_second


func _move_plats() -> void:
	var now := _now()
	for i in plats.size():
		var pl: Dictionary = plats[i]
		var travel: float = (pl.top - pl.bottom).length() / pl.speed
		var t: float = now - pl.phase_start
		if multiplayer.is_server():
			if pl.phase == 0 and _someone_on(pl):
				_set_plat(i, 1, now)
			elif pl.phase == 1 and t >= travel:
				_set_plat(i, 2, pl.phase_start + travel)
			elif pl.phase == 2 and t >= pl.wait and not _someone_on(pl):
				_set_plat(i, 3, now)
			elif pl.phase == 3 and t >= travel:
				_set_plat(i, 0, pl.phase_start + travel)
		t = now - pl.phase_start
		var k := 0.0
		match pl.phase:
			1: k = clampf(t / travel, 0.0, 1.0)
			2: k = 1.0
			3: k = 1.0 - clampf(t / travel, 0.0, 1.0)
		pl.body.position = pl.bottom.lerp(pl.top, k)


func _set_plat(i: int, phase: int, start: float) -> void:
	plats[i].phase = phase
	plats[i].phase_start = start
	send_all("_plat", [i, phase, start], false)


func _someone_on(pl: Dictionary) -> bool:
	var top_y: float = pl.body.position.y + pl.top_offset
	for p in _living_players():
		var d: Vector3 = p.global_position - pl.body.position
		if absf(d.x) <= pl.half.x + 0.2 and absf(d.z) <= pl.half.y + 0.2 and absf(p.global_position.y - top_y) < 0.3:
			return true
	return false


@rpc("authority", "call_remote", "reliable")
func _plat(i: int, phase: int, start: float) -> void:
	if i < plats.size():
		plats[i].phase = phase
		plats[i].phase_start = start


# --- Replication ----------------------------------------------------------------------

func send_all(method: StringName, args: Array, local := true) -> void:
	if Game.instance:
		Game.instance.send_all(self, method, args, local)
	elif local:
		callv(method, args)


func _state_array() -> Array:
	var fl := []
	for f in flags:
		fl.append([f.state, f.carrier.peer_id if is_instance_valid(f.carrier) else 0, f.pos, f.return_left,
			f.vel, f.moving])
	var sec := []
	for s in securities:
		sec.append(s.offline_left)
	var pk := []
	for k in packs:
		pk.append(k.respawn_left)
	return [team_scores, fl, sec, pk]


## Server: everything a newly-joined client needs.
func send_full_state(peer: int) -> void:
	multiplayer.rpc(peer, self, "_state", [_state_array()])
	for i in plats.size():
		multiplayer.rpc(peer, self, "_plat", [i, plats[i].phase, plats[i].phase_start])


@rpc("authority", "call_remote", "reliable")
func _state(s: Array) -> void:
	team_scores = s[0]
	for i in mini(flags.size(), s[1].size()):
		var e: Array = s[1][i]
		flags[i].state = e[0]
		flags[i].carrier = Game.instance.players_root.get_node_or_null(str(e[1])) if e[1] else null
		flags[i].pos = e[2]
		flags[i].return_left = e[3]
		if e.size() >= 6:
			flags[i].vel = e[4]
			flags[i].moving = e[5]
	for i in mini(securities.size(), s[2].size()):
		securities[i].offline_left = s[2][i]
		_set_lasers(securities[i].group, s[2][i] <= 0.0)
	for i in mini(packs.size(), s[3].size()):
		packs[i].respawn_left = s[3][i]
	_update_visuals()


## Client: count timers down between updates.
func _client_tick(delta: float) -> void:
	for f in flags:
		if f.state == FlagState.DROPPED:
			f.return_left = maxf(f.return_left - delta, 0.0)
			if f.moving:
				_move_flag(f, delta)
		elif f.state == FlagState.CARRIED and is_instance_valid(f.carrier):
			f.pos = f.carrier.global_position
	for s in securities:
		s.offline_left = maxf(s.offline_left - delta, 0.0)
	for k in packs:
		k.respawn_left = maxf(k.respawn_left - delta, 0.0)
	_update_visuals()


func _update_visuals() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in flags:
		var node: Node3D = f.node
		var local_carrier: bool = is_instance_valid(f.carrier) and f.carrier.is_local
		node.visible = not local_carrier
		if f.state == FlagState.CARRIED and is_instance_valid(f.carrier):
			# On the carrier's back, leaning a little.
			node.global_position = f.carrier.global_position + f.carrier.global_basis.z * 0.35 + Vector3(0, 0.3, 0)
			node.rotation = Vector3(0.25, f.carrier.rotation.y, 0)
		else:
			node.global_position = f.pos
			node.rotation = Vector3(0, t * (0.0 if f.state == FlagState.HOME else 1.5), 0)
	for k in packs:
		k.node.visible = k.respawn_left <= 0.0
		k.node.rotation.y = t * 1.2
	for s in securities:
		var btn: Node3D = s.button
		for c in btn.get_children():
			if c is MeshInstance3D:
				c.transparency = 0.6 if s.offline_left > 0.0 else 0.0


# --- Messages and sounds ----------------------------------------------------------------

## Show a message to one player (peer), or everyone (-1).
@rpc("authority", "call_remote", "reliable")
func _announce(msg: String, peer: int, sound: String) -> void:
	if peer != -1 and peer != multiplayer.get_unique_id():
		return
	if Game.instance and Game.instance.ui:
		Game.instance.ui.show_message(msg)
	_play(sound)


## team_msg to members of team, other_msg to everyone else. The player
## `skip_peer` (who already got a personal message) gets neither.
@rpc("authority", "call_remote", "reliable")
func _announce_team(team_msg: String, team: int, other_msg: String, sound: String, skip_peer := 0) -> void:
	var me := Game.instance.local_player if Game.instance else null
	if me == null or me.peer_id == skip_peer:
		return
	var msg := team_msg if me.team == team else other_msg
	if msg and Game.instance.ui:
		Game.instance.ui.show_message(msg)
	_play(sound)


@rpc("authority", "call_remote", "unreliable")
func _play_at(sound: String, at: Vector3) -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = SND[sound]
	s.unit_size = 12.0
	add_child(s)
	s.global_position = at
	s.play()
	s.finished.connect(s.queue_free)


func _play(sound: String) -> void:
	if sound and SND.has(sound):
		_sound.stream = SND[sound]
		_sound.play()


## For the HUD: one entry per flag and security system (icon, team, text).
func status_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in flags:
		var line := "Home"
		var col := Color(0.85, 0.9, 0.85)
		if f.state == FlagState.CARRIED:
			line = "Taken by %s" % (_name(f.carrier) if is_instance_valid(f.carrier) else "?")
			col = Color(1.0, 0.8, 0.35)
		elif f.state == FlagState.DROPPED:
			line = "Dropped  ·  returns in %d" % ceili(f.return_left)
			col = Color(1.0, 0.55, 0.4)
		out.append({"icon": "flag", "team": f.owner, "text": line, "color": col, "dim": false})
	for sec in securities:
		var down: bool = sec.offline_left > 0.0
		out.append({"icon": "button", "team": sec.owner,
			"text": "OFFLINE  %d" % ceili(sec.offline_left) if down else "Security online",
			"color": Color(1.0, 0.4, 0.33) if down else Color(0.85, 0.9, 0.85), "dim": down})
	return out
