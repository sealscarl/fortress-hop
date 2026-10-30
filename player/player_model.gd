class_name PlayerModel
extends Node3D
## The body other players see (player/models/*.glb, prepared with
## tools/models/prepare_player.py).
##
## - Team color: the models are made red; Blue gets the red parts turned
##   blue by player/team_swap.gdshader.
## - Animations follow how the player moves: idle, run (sped up / slowed /
##   played backwards to match), crouch, crouch_walk, jump in the air.
## - Aim and strafe (player/aim_modifier.gd): the spine bends to where the
##   player looks; strafing turns the legs while the chest faces forward.
## - Holds a world version of the class's weapon.
## Each class has its own model (all on the same Mixamo skeleton); a class
## without one uses the Soldier.

## Model per class name (player/classes.gd); others use "default".
const MODELS := {
	"Scout": preload("res://player/models/scout.glb"),
	"Soldier": preload("res://player/models/soldier.glb"),
	"Medic": preload("res://player/models/medic.glb"),
	"Demoman": preload("res://player/models/demoman.glb"),
	"default": preload("res://player/models/soldier.glb"),
}
const SHADER := preload("res://player/team_swap.gdshader")
const K := WeaponStats.Kind

var player: Player
var _model: Node3D
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _aim: AimModifier
var _mats: Array[ShaderMaterial] = []
var _weapon: Node3D
var _weapon_kind := -2
var _team := -1
var _last_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _air_time := 0.0
var _playing := ""
var _model_key := ""


func _ready() -> void:
	player = get_parent() as Player
	_last_pos = player.global_position
	_build(_key_for_class())


func _key_for_class() -> String:
	if player.class_id == -1:
		return "default"
	var n: String = PlayerClasses.stat(player.class_id, "name")
	return n if MODELS.has(n) else "default"


## (Re)builds the body for the given model: animations, aim, hand, materials.
func _build(key: String) -> void:
	_model_key = key
	if _model:
		_model.queue_free()
	if _weapon:
		_weapon.queue_free()
	_weapon = null
	_weapon_kind = -2
	_mats.clear()
	_team = -1
	_playing = ""
	_model = (MODELS[key] as PackedScene).instantiate()
	_model.rotation.y = PI   # The models face +Z; players face -Z.
	add_child(_model)
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["idle", "run", "walk", "crouch", "crouch_walk", "jump"]:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	_aim = AimModifier.new()
	_skel.add_child(_aim)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var std := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if std and std.albedo_texture:
				var m := ShaderMaterial.new()
				m.shader = SHADER
				m.set_shader_parameter("albedo_tex", std.albedo_texture)
				if std.roughness_texture:
					m.set_shader_parameter("orm_tex", std.roughness_texture)
					m.set_shader_parameter("has_orm", true)
				if std.normal_texture:
					m.set_shader_parameter("normal_tex", std.normal_texture)
					m.set_shader_parameter("has_normal", true)
				mi.set_surface_override_material(i, m)
				_mats.append(m)
	_play("idle")


func _process(delta: float) -> void:
	var key := _key_for_class()
	if key != _model_key:
		_build(key)
	if player.team != _team:
		_team = player.team
		for m in _mats:
			m.set_shader_parameter("swap", 1.0 if _team == 1 else 0.0)

	# How the player is moving: measured from where they are drawn, since
	# remote players on a client are only interpolated, not simulated.
	var pos := player.global_position
	if delta > 0.0:
		var v := (pos - _last_pos) / delta
		if v.length() > 80.0:
			v = Vector3.ZERO   # Teleport / respawn.
		_vel = _vel.lerp(v, 1.0 - exp(-delta * 12.0))
	_last_pos = pos
	var hv := Vector2(_vel.x, _vel.z)
	var speed := hv.length()
	var grounded := _on_ground()
	_air_time = 0.0 if grounded else _air_time + delta

	# Movement relative to facing (forward = -Z).
	var local := player.global_basis.inverse() * Vector3(_vel.x, 0, _vel.z)
	var backwards := local.z > 0.3 * speed and speed > 0.6
	var move_angle := atan2(local.x, -local.z) if speed > 0.6 else 0.0
	if backwards:
		move_angle = atan2(-local.x, local.z)
	var yaw_target := clampf(-move_angle, -1.1, 1.1) if grounded else 0.0
	_aim.hips_yaw = lerpf(_aim.hips_yaw, yaw_target, 1.0 - exp(-delta * 10.0))
	_aim.pitch = player.head.rotation.x

	if _air_time > 0.12:
		_play("jump")
		_anim.speed_scale = 1.0
	elif player.crouched:
		_play("crouch_walk" if speed > 0.5 else "crouch")
		_anim.speed_scale = clampf(speed / 3.3, 0.6, 1.6) * (-1.0 if backwards else 1.0) if speed > 0.5 else 1.0
	elif speed > 0.6:
		_play("run")
		_anim.speed_scale = clampf(speed / 7.5, 0.55, 2.2) * (-1.0 if backwards else 1.0)
	else:
		_play("idle")
		_anim.speed_scale = 1.0

	_update_weapon()


func _play(a: String) -> void:
	if a != _playing and _anim.has_animation(a):
		_playing = a
		_anim.play(a, 0.15)


func _on_ground() -> bool:
	if absf(_vel.y) > 2.5:
		return false
	var from := player.global_position + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.35, 1, [player.get_rid()])
	return not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Where the hands hold each weapon, in the weapon's own space (-Z = toward
## the muzzle): [right hand, left hand]. Placeholders get them from their size.
const HANDS := {
	K.ROCKET_LAUNCHER: [Vector3(0.0, -0.08, 0.06), Vector3(0.0, -0.08, -0.16)],
	K.SHOTGUN: [Vector3(0.0, -0.06, 0.12), Vector3(0.0, -0.03, -0.14)],
}


## The class's main weapon, held in both hands, pointing where the player
## aims. AimModifier places it each frame (after the spine has bent to the
## aim) and moves the hands onto it.
func _update_weapon() -> void:
	var kinds: Array = PlayerClasses.stat(player.class_id, "weapons") if player.class_id != -1 else []
	var kind: int = kinds[0] if kinds.size() else -1
	if kind != _weapon_kind:
		_weapon_kind = kind
		if _weapon:
			_weapon.queue_free()
			_weapon = null
		var hands := [Vector3(0.0, -0.04, 0.1), Vector3(0.0, -0.04, -0.14)]
		if ViewModel.MODELS.has(kind):
			_weapon = (ViewModel.MODELS[kind] as PackedScene).instantiate()
			hands = HANDS.get(kind, hands)
		elif kind != -1:
			var v: Array = WeaponStats.get_stat(kind, "view")
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = v[1]
			cm.bottom_radius = v[1]
			cm.height = v[2]
			mi.mesh = cm
			mi.rotation.x = deg_to_rad(90)
			var m := StandardMaterial3D.new()
			m.albedo_color = v[0]
			mi.material_override = m
			_weapon = Node3D.new()
			_weapon.add_child(mi)
			var r := float(v[1])
			var half := float(v[2]) * 0.5
			hands = [Vector3(0.0, -r, minf(0.1, half - 0.02)), Vector3(0.0, -r, -minf(0.14, half - 0.02))]
		if _weapon:
			add_child(_weapon)
		_aim.weapon = _weapon
		_aim.grip = hands[0]
		_aim.support = hands[1]
	_aim.aim_basis = Basis.from_euler(Vector3(player.head.rotation.x, player.rotation.y, 0.0))
