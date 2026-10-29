class_name WeaponManager
extends Node
## Lives on the player. Owns the weapons, their clips and ammo, firing,
## TFC/TF2-style reloading and switching. Runs on the server from the
## player's commands; clients get the state from snapshots.
##
## Reload rules (for every weapon with a clip):
## - Reloads one round at a time: the first round takes reload_first, each
##   one after that takes reload_each.
## - Starts automatically when the clip is empty, or press Reload to top up.
## - Holding Fire with at least one round loaded cancels the reload and fires.
## - Switching weapons cancels the reload. Each weapon keeps its loaded rounds.
##
## Values are TF2/TFC-style starting points. 1 m = 32 units.

enum Kind { ROCKET_LAUNCHER, SHOTGUN }

const FIRE_SOUNDS := {
	Kind.ROCKET_LAUNCHER: preload("res://sounds/rocket_fire.wav"),
	Kind.SHOTGUN: preload("res://sounds/shotgun_fire.wav"),
}
const RELOAD_SOUND := preload("res://sounds/reload.wav")
const DRY_SOUND := preload("res://sounds/dry_fire.wav")
const SWITCH_SOUND := preload("res://sounds/weapon_switch.wav")

@export_group("Switching")
## Seconds after switching before you can fire.
@export var switch_time := 0.3

@export_group("Rocket launcher")
@export var rl_clip_size := 4
@export var rl_max_reserve := 20
@export var rl_fire_interval := 0.8
@export var rl_reload_first := 0.92
@export var rl_reload_each := 0.8
## 1000 ups (TFC: 900).
@export var rocket_speed := 31.25
@export var rocket_damage := 100.0
## Quake: damage + 40 units = 160 units.
@export var rocket_radius := 5.0
## Knockback m/s per damage point. Quake: 8 ups per point.
@export var rocket_knockback := 0.25
## Your own rockets hurt you this much (rocket jumps cost health).
@export var rocket_self_damage_scale := 0.5

@export_group("Shotgun")
@export var sg_clip_size := 8
@export var sg_max_reserve := 40
@export var sg_fire_interval := 0.5
@export var sg_reload_first := 0.75
@export var sg_reload_each := 0.5
@export var sg_pellets := 6
@export var sg_pellet_damage := 6.0
@export var sg_spread_deg := 4.0
@export var sg_range := 100.0
@export var sg_knockback := 0.25

## Per weapon (index = Kind). Server-authoritative; copied to clients.
var clip: Array[int] = [0, 0]
var reserve: Array[int] = [0, 0]
var current := Kind.ROCKET_LAUNCHER
var reloading := false
var reload_left := 0.0
var cooldown := 0.0
var switching := 0.0
var _reload_queued := false

@onready var player: Player = get_parent()
var _sound: AudioStreamPlayer3D
var _view: Node3D
var _view_meshes := {}


func _ready() -> void:
	_sound = AudioStreamPlayer3D.new()
	add_child(_sound)
	refill()
	if player.is_local:
		_build_view_model()


func count() -> int:
	return Kind.size()


func clip_size(k: int) -> int:
	return rl_clip_size if k == Kind.ROCKET_LAUNCHER else sg_clip_size


func max_reserve(k: int) -> int:
	return rl_max_reserve if k == Kind.ROCKET_LAUNCHER else sg_max_reserve


func weapon_name(k: int) -> String:
	return "ROCKETS" if k == Kind.ROCKET_LAUNCHER else "SHOTGUN"


## Full clips and ammo, stop any reload. On spawn, death and resupply.
func refill() -> void:
	for k in count():
		clip[k] = clip_size(k)
		reserve[k] = max_reserve(k)
	reloading = false
	_reload_queued = false


func reset() -> void:
	refill()
	current = Kind.ROCKET_LAUNCHER
	cooldown = 0.0
	switching = 0.0


# --- Server tick ---------------------------------------------------------------

func tick(cmd: PlayerCmd, delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	switching = maxf(switching - delta, 0.0)

	var want := current
	if cmd.weapon_slot > 0 and cmd.weapon_slot <= count():
		want = cmd.weapon_slot - 1
	elif cmd.has(PlayerCmd.NEXT_WEAPON):
		want = (current + 1) % count()
	elif cmd.has(PlayerCmd.PREV_WEAPON):
		want = (current + count() - 1) % count()
	if want != current:
		current = want
		reloading = false           # Switching cancels a reload.
		_reload_queued = false
		switching = switch_time
		_play_fx.rpc(_FX_SWITCH)
	if switching > 0.0:
		return

	var k := current
	var firing := cmd.has(PlayerCmd.FIRE)

	if cmd.has(PlayerCmd.RELOAD) and clip[k] < clip_size(k) and reserve[k] > 0:
		_reload_queued = true

	if reloading:
		if firing and clip[k] > 0:
			reloading = false       # Fire cancels the reload.
		else:
			reload_left -= delta
			if reload_left <= 0.0:
				clip[k] += 1
				reserve[k] -= 1
				_play_fx.rpc(_FX_RELOAD)
				if clip[k] >= clip_size(k) or reserve[k] <= 0:
					reloading = false
				else:
					reload_left += rl_reload_each if k == Kind.ROCKET_LAUNCHER else sg_reload_each
			return

	if firing and cooldown <= 0.0:
		if clip[k] > 0:
			clip[k] -= 1
			cooldown = rl_fire_interval if k == Kind.ROCKET_LAUNCHER else sg_fire_interval
			_reload_queued = false
			_fire(k, cmd)
		elif reserve[k] <= 0:
			cooldown = 0.3          # Completely out: click.
			_play_fx.rpc(_FX_DRY)

	# Auto-reload when empty, or a requested reload, once the shot is done.
	if cooldown <= 0.0 and not reloading and reserve[k] > 0 \
			and (clip[k] == 0 or _reload_queued) and clip[k] < clip_size(k):
		_reload_queued = false
		reloading = true
		reload_left = rl_reload_first if k == Kind.ROCKET_LAUNCHER else sg_reload_first


func _fire(k: int, cmd: PlayerCmd) -> void:
	var eye := player.camera.global_position
	var aim := -player.camera.global_basis.z
	_play_fx.rpc(k)
	if k == Kind.ROCKET_LAUNCHER:
		Game.instance.spawn_rocket(player, eye + aim * 0.5, aim * rocket_speed)
	else:
		var dirs: Array[Vector3] = []
		var basis := player.camera.global_basis
		for i in sg_pellets:
			# Even spread inside a cone, pellet 0 dead center.
			var ang := randf() * TAU
			var r := deg_to_rad(sg_spread_deg) * sqrt(randf()) if i > 0 else 0.0
			var d := -basis.z + basis.x * tan(r) * cos(ang) + basis.y * tan(r) * sin(ang)
			dirs.append(d.normalized())
		Game.instance.hitscan(player, eye, dirs, sg_range, sg_pellet_damage, sg_knockback, cmd.view_tick)


## Server: a rocket exploded. Quake-style radius damage and knockback.
func rocket_explode(origin: Vector3) -> void:
	Explosions.radial(get_tree(), origin, rocket_damage, rocket_radius,
		rocket_knockback, player, rocket_self_damage_scale)


# --- Snapshots and client-side feedback --------------------------------------

func snapshot() -> Array:
	return [current, clip[0], clip[1], reserve[0], reserve[1], reloading, switching > 0.0]


func apply_snapshot(s: Array) -> void:
	current = s[0] as Kind
	clip[0] = s[1]
	clip[1] = s[2]
	reserve[0] = s[3]
	reserve[1] = s[4]
	reloading = s[5]
	switching = switch_time if s[6] else 0.0


const _FX_RELOAD := 10
const _FX_DRY := 11
const _FX_SWITCH := 12


## Sounds for this player's weapon, heard by everyone nearby.
@rpc("authority", "call_local", "unreliable")
func _play_fx(which: int) -> void:
	match which:
		Kind.ROCKET_LAUNCHER, Kind.SHOTGUN:
			_sound.stream = FIRE_SOUNDS[which]
			_sound.volume_db = 0.0
			if player.is_local:
				_kick = 1.0
		_FX_RELOAD:
			_sound.stream = RELOAD_SOUND
			_sound.volume_db = -4.0
		_FX_DRY:
			_sound.stream = DRY_SOUND
			_sound.volume_db = -4.0
		_FX_SWITCH:
			_sound.stream = SWITCH_SOUND
			_sound.volume_db = -6.0
	_sound.play()


# --- Placeholder view model (local player only) -------------------------------

var _kick := 0.0
var _shown := -1
var _dip := 0.0


func _build_view_model() -> void:
	_view = Node3D.new()
	player.get_node("Head/Camera3D").add_child(_view)
	_view.position = Vector3(0.28, -0.26, -0.55)
	var rl := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.07
	tube.bottom_radius = 0.07
	tube.height = 0.75
	rl.mesh = tube
	rl.rotation.x = deg_to_rad(90)
	rl.material_override = _mat(Color(0.25, 0.32, 0.22))
	_view.add_child(rl)
	var sg := MeshInstance3D.new()
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.025
	barrel.bottom_radius = 0.035
	barrel.height = 0.7
	sg.mesh = barrel
	sg.rotation.x = deg_to_rad(90)
	sg.material_override = _mat(Color(0.35, 0.35, 0.38))
	_view.add_child(sg)
	_view_meshes = {Kind.ROCKET_LAUNCHER: rl, Kind.SHOTGUN: sg}
	for m in _view.get_children():
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


func _process(delta: float) -> void:
	if _view == null:
		return
	if _shown != current:
		_shown = current
		for k in _view_meshes:
			_view_meshes[k].visible = k == current
	# Lowered while switching or reloading, kicks back when firing.
	var target_dip := 0.18 if switching > 0.0 else (0.08 if reloading else 0.0)
	_dip = move_toward(_dip, target_dip, delta * 1.5)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_view.position = Vector3(0.28, -0.26 - _dip, -0.55 + _kick * 0.08)
	_view.rotation.x = _kick * 0.12 - _dip * 1.5
	if not multiplayer.is_server():
		switching = maxf(switching - delta, 0.0)
