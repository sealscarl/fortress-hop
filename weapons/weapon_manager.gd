class_name WeaponManager
extends Node
## Lives on the player. Holds the current class's weapons, their clips and
## ammo, and handles firing, TFC/TF2-style reloading and switching. Runs on
## the server from the player's commands; clients get the state from
## snapshots. Weapon numbers live in weapons/weapon_stats.gd.
##
## Reload rules (every weapon with a clip):
## - Reloads one round at a time: the first round takes reload_first, each
##   one after that takes reload_each.
## - Starts automatically when the clip is empty, or press Reload to top up.
## - Holding Fire with at least one round loaded cancels the reload and fires.
## - Switching weapons cancels the reload. Each weapon keeps its loaded rounds.

const K := WeaponStats.Kind

const RELOAD_SOUND := preload("res://sounds/reload.wav")
const DRY_SOUND := preload("res://sounds/dry_fire.wav")
const SWITCH_SOUND := preload("res://sounds/weapon_switch.wav")
const ROCKET_SOUND := preload("res://sounds/rocket_fire.wav")
const SHOTGUN_SOUND := preload("res://sounds/shotgun_fire.wav")

## Seconds after switching before you can fire.
@export var switch_time := 0.3

## The current class's weapons (WeaponStats.Kind), by slot.
var kinds: Array[int] = []
var clip: Array[int] = []
var reserve: Array[int] = []
var current := 0            ## Slot index into kinds.
var reloading := false
var reload_left := 0.0
var cooldown := 0.0
var switching := 0.0
var _reload_queued := false

@onready var player: Player = get_parent()
## Your own weapon: a plain (non-positional) sound at full volume. Other
## players' weapons: a 3D sound at their position.
var _sound   ## AudioStreamPlayer or AudioStreamPlayer3D


func _ready() -> void:
	if player.is_local:
		_sound = AudioStreamPlayer.new()
		_sound.max_polyphony = 4
		add_child(_sound)
		_build_view_model()
	else:
		var s3 := AudioStreamPlayer3D.new()
		s3.unit_size = 10.0
		s3.max_polyphony = 4
		s3.position.y = 1.4
		_sound = s3
		player.add_child.call_deferred(s3)   # Must sit on the player (a 3D node) to have a position.


func stat(slot: int, key: String) -> Variant:
	return WeaponStats.get_stat(kinds[slot], key)


func current_kind() -> int:
	return kinds[current] if current < kinds.size() else -1


## New class: replace the loadout, full ammo, first slot.
func set_loadout(p_kinds: Array) -> void:
	kinds.assign(p_kinds)
	clip.resize(kinds.size())
	reserve.resize(kinds.size())
	current = 0
	cooldown = 0.0
	switching = 0.0
	refill()


## Full clips and ammo, stop any reload. On spawn and resupply.
func refill() -> void:
	for i in kinds.size():
		clip[i] = stat(i, "clip")
		reserve[i] = stat(i, "reserve")
	reloading = false
	_reload_queued = false


func reset() -> void:
	set_loadout(kinds)


# --- Server tick ---------------------------------------------------------------

func tick(cmd: PlayerCmd, delta: float) -> void:
	if kinds.is_empty():
		return
	cooldown = maxf(cooldown - delta, 0.0)
	switching = maxf(switching - delta, 0.0)
	var n := kinds.size()

	var want := current
	if cmd.weapon_slot > 0 and cmd.weapon_slot <= n:
		want = cmd.weapon_slot - 1
	elif cmd.has(PlayerCmd.NEXT_WEAPON):
		want = (current + 1) % n
	elif cmd.has(PlayerCmd.PREV_WEAPON):
		want = (current + n - 1) % n
	if want != current:
		current = want
		reloading = false           # Switching cancels a reload.
		_reload_queued = false
		switching = switch_time
		Game.instance.send_all(self, "_play_fx", [_FX_SWITCH])

	if cmd.has(PlayerCmd.DETONATE):
		Game.instance.detonate_pipes(player)

	if switching > 0.0:
		return

	var s := current
	var size: int = stat(s, "clip")
	var firing := cmd.has(PlayerCmd.FIRE)

	if size > 0 and cmd.has(PlayerCmd.RELOAD) and clip[s] < size and reserve[s] > 0:
		_reload_queued = true

	if reloading:
		if firing and clip[s] > 0:
			reloading = false       # Fire cancels the reload.
		else:
			reload_left -= delta
			if reload_left <= 0.0:
				clip[s] += 1
				reserve[s] -= 1
				Game.instance.send_all(self, "_play_fx", [_FX_RELOAD])
				if clip[s] >= size or reserve[s] <= 0:
					reloading = false
				else:
					reload_left += stat(s, "reload_each")
			return

	if firing and cooldown <= 0.0:
		if _has_round(s):
			_use_round(s)
			cooldown = stat(s, "interval")
			_reload_queued = false
			_fire(kinds[s], cmd)
		elif size == 0 or reserve[s] == 0:
			cooldown = 0.3          # Completely out: click.
			Game.instance.send_all(self, "_play_fx", [_FX_DRY])

	# Auto-reload when empty, or a requested reload, once the shot is done.
	if size > 0 and cooldown <= 0.0 and not reloading and reserve[s] > 0 \
			and (clip[s] == 0 or _reload_queued) and clip[s] < size:
		_reload_queued = false
		reloading = true
		reload_left = stat(s, "reload_first")


func _has_round(s: int) -> bool:
	if stat(s, "clip") > 0:
		return clip[s] > 0
	return reserve[s] != 0          # -1 = unlimited.


func _use_round(s: int) -> void:
	if stat(s, "clip") > 0:
		clip[s] -= 1
	elif reserve[s] > 0:
		reserve[s] -= 1


func _fire(kind: int, cmd: PlayerCmd) -> void:
	var cam := player.camera
	var eye := player.eye_position()
	var aim := -cam.global_basis.z
	var d: Dictionary = WeaponStats.DATA[kind]
	Game.instance.send_all(self, "_play_fx", [kind])
	match kind:
		K.ROCKET_LAUNCHER:
			Game.instance.spawn_projectile(player, kind, eye + aim * 0.5, aim * d.speed)
		K.NAILGUN, K.SUPER_NAILGUN:
			# From the center of the view like every weapon, so the weapon
			# position option (cl_hand) is purely visual.
			Game.instance.spawn_projectile(player, kind, eye + aim * 0.5 - cam.global_basis.y * 0.1, aim * d.speed)
		K.GRENADE_LAUNCHER, K.PIPEBOMB_LAUNCHER:
			var up_aim := aim.rotated(cam.global_basis.x.normalized(), deg_to_rad(d.pitch_up_deg))
			Game.instance.spawn_bomb(player, kind, eye + aim * 0.5, up_aim * d.speed)
		K.SHOTGUN:
			var dirs: Array[Vector3] = []
			var basis := cam.global_basis
			for i in d.pellets:
				# Even spread inside a cone, pellet 0 dead center.
				var ang := randf() * TAU
				var r := deg_to_rad(d.spread_deg) * sqrt(randf()) if i > 0 else 0.0
				var dir := -basis.z + basis.x * tan(r) * cos(ang) + basis.y * tan(r) * sin(ang)
				dirs.append(dir.normalized())
			Game.instance.hitscan(player, eye, dirs, d.range, d.damage, d.knockback, cmd.view_tick)
		K.MEDKIT:
			Game.instance.medkit(player, eye, aim, d.range, d.heal, d.damage, cmd.view_tick)


# --- Snapshots and client-side feedback --------------------------------------

func snapshot() -> Array:
	return [current, clip.duplicate(), reserve.duplicate(), reloading, switching > 0.0]


func apply_snapshot(s: Array) -> void:
	if (s[1] as Array).size() != kinds.size():
		return  # Class change still on its way; next snapshot will match.
	current = s[0]
	clip.assign(s[1])
	reserve.assign(s[2])
	reloading = s[3]
	switching = switch_time if s[4] else 0.0


const _FX_RELOAD := 100
const _FX_DRY := 101
const _FX_SWITCH := 102


## Sounds for this player's weapon, heard by everyone nearby.
@rpc("authority", "call_local", "unreliable")
func _play_fx(which: int) -> void:
	_sound.volume_db = 0.0
	match which:
		K.ROCKET_LAUNCHER, K.GRENADE_LAUNCHER, K.PIPEBOMB_LAUNCHER:
			_sound.stream = ROCKET_SOUND
			_sound.pitch_scale = 1.0 if which == K.ROCKET_LAUNCHER else 1.5
		K.SHOTGUN:
			_sound.stream = SHOTGUN_SOUND
			_sound.pitch_scale = 1.0
		K.NAILGUN, K.SUPER_NAILGUN:
			_sound.stream = DRY_SOUND   # Short tick per nail.
			_sound.pitch_scale = 2.2 if which == K.NAILGUN else 1.8
			_sound.volume_db = 2.0
		K.MEDKIT:
			_sound.stream = SWITCH_SOUND
			_sound.pitch_scale = 1.6
		_FX_RELOAD:
			_sound.stream = RELOAD_SOUND
			_sound.pitch_scale = 1.0
			_sound.volume_db = -4.0
		_FX_DRY:
			_sound.stream = DRY_SOUND
			_sound.pitch_scale = 1.0
			_sound.volume_db = -4.0
		_FX_SWITCH:
			_sound.stream = SWITCH_SOUND
			_sound.pitch_scale = 1.0
			_sound.volume_db = -6.0
	if which < _FX_RELOAD and player.is_local:
		_kick = 1.0 if which != K.NAILGUN and which != K.SUPER_NAILGUN else 0.3
	_sound.play()


# --- Placeholder view model (local player only) -------------------------------

var _view: Node3D
var _view_mesh: MeshInstance3D
var _kick := 0.0
var _shown := -1
var _dip := 0.0


func _build_view_model() -> void:
	_view = Node3D.new()
	player.get_node("Head/Camera3D").add_child(_view)
	_view_mesh = MeshInstance3D.new()
	_view_mesh.rotation.x = deg_to_rad(90)
	_view_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.add_child(_view_mesh)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		switching = maxf(switching - delta, 0.0)
	if _view == null:
		return
	var kind := current_kind()
	if _shown != kind:
		_shown = kind
		_view.visible = kind != -1
		if kind != -1:
			var v: Array = WeaponStats.get_stat(kind, "view")
			var mesh := CylinderMesh.new()
			mesh.top_radius = v[1]
			mesh.bottom_radius = v[1]
			mesh.height = v[2]
			_view_mesh.mesh = mesh
			var m := StandardMaterial3D.new()
			m.albedo_color = v[0]
			m.roughness = 0.6
			_view_mesh.material_override = m
	# Lowered while switching or reloading, kicks back when firing.
	var target_dip := 0.18 if switching > 0.0 else (0.08 if reloading else 0.0)
	_dip = move_toward(_dip, target_dip, delta * 1.5)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	# Weapon position (Options / cl_hand): centered, right or left. Left is a
	# mirror image, so asymmetric models flip the right way.
	var hand: int = Settings.get_option("hand")
	var side := 0.0 if hand == 0 else (0.28 if hand == 1 else -0.28)
	var base_y := -0.32 if hand == 0 else -0.26
	_view.position = Vector3(side, base_y - _dip, -0.55 + _kick * 0.08)
	_view.rotation.x = _kick * 0.12 - _dip * 1.5
	_view.scale.x = -1.0 if hand == 2 else 1.0
