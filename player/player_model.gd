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
## Every class uses the Soldier model until the others are made.

const MODELS := {
	"default": preload("res://player/models/soldier.glb"),
}
const SHADER := preload("res://player/team_swap.gdshader")
const ROCKET_LAUNCHER := preload("res://weapons/models/rocket_launcher.glb")
const K := WeaponStats.Kind

var player: Player
var _model: Node3D
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _aim: AimModifier
var _mats: Array[ShaderMaterial] = []
var _hand: BoneAttachment3D
var _weapon: Node3D
var _weapon_kind := -2
var _team := -1
var _last_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _air_time := 0.0
var _playing := ""


func _ready() -> void:
	player = get_parent() as Player
	_model = (MODELS["default"] as PackedScene).instantiate()
	_model.rotation.y = PI   # The models face +Z; players face -Z.
	add_child(_model)
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["idle", "run", "walk", "crouch", "crouch_walk", "jump"]:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	_aim = AimModifier.new()
	_skel.add_child(_aim)
	_hand = BoneAttachment3D.new()
	_hand.bone_name = "mixamorig_RightHand"
	_skel.add_child(_hand)
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
	_last_pos = player.global_position
	_play("idle")


func _process(delta: float) -> void:
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


## The class's main weapon in the right hand, pointing where the player aims.
func _update_weapon() -> void:
	var kinds: Array = PlayerClasses.stat(player.class_id, "weapons") if player.class_id != -1 else []
	var kind: int = kinds[0] if kinds.size() else -1
	if kind != _weapon_kind:
		_weapon_kind = kind
		if _weapon:
			_weapon.queue_free()
			_weapon = null
		if kind == K.ROCKET_LAUNCHER:
			_weapon = ROCKET_LAUNCHER.instantiate()
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
		if _weapon:
			add_child(_weapon)
	if _weapon:
		var aim := Basis.from_euler(Vector3(player.head.rotation.x, player.rotation.y, 0.0))
		_weapon.global_transform = Transform3D(aim, _hand.global_position + aim * Vector3(-0.04, 0.03, -0.08))
