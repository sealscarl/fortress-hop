class_name ViewModel
extends Node
## Your first-person weapon (local player only), Quake style: centered, no
## visible arms. While reloading, the weapon drops out of view (the reload
## sound plays for each round) and comes back up when it's done or you fire.
##
## Drawn by its own camera on a render layer the world camera skips, then
## laid over the world. So it never pokes through walls, and it always uses
## the same field of view (fov 90) whatever your FOV setting is, so it never
## looks stretched. It's in the same 3D world, so map lights still light it.
##
## Weapons with a model (weapons/models/*.glb) play its draw, idle and fire
## animations. Others show a simple placeholder.

const K := WeaponStats.Kind
const LAYER := 1 << 19          ## Render layer 20: first-person weapon only.
const FOV := 73.74              ## Vertical, = "fov 90".
const DROP := 0.45              ## How far the weapon drops while reloading (m).
const DROP_TIME := 0.12         ## Seconds to drop out of view / come back.

const MODELS := {
	K.ROCKET_LAUNCHER: preload("res://weapons/models/rocket_launcher.glb"),
}
## Where each weapon sits: [position, rotation in degrees], centered.
const PLACE_MODEL := {
	K.ROCKET_LAUNCHER: [Vector3(0.0, -0.27, -0.24), Vector3(-2, 0, 0)],
}
const PLACE_PLACEHOLDER := [Vector3(0.0, -0.32, -0.55), Vector3.ZERO]

var weapons: WeaponManager
var player: Player

var _world_cam: Camera3D
var _holder: Node3D            ## Follows the world camera; the weapon hangs off it.
var _cam: Camera3D             ## The weapon camera.
var _viewport: SubViewport
var _model: Node3D
var _anim: AnimationPlayer
var _placeholder: MeshInstance3D
var _shown := -2
var _kick := 0.0
var _down := 0.0               ## 0 = in view, 1 = dropped out of view.


func setup(p_weapons: WeaponManager) -> void:
	weapons = p_weapons
	player = weapons.player
	var world_cam := player.get_node("Head/Camera3D") as Camera3D   # (player.camera isn't set up yet)
	_world_cam = world_cam
	world_cam.cull_mask &= ~LAYER
	_holder = Node3D.new()
	_holder.name = "ViewModel"
	world_cam.add_child(_holder)

	var layer := CanvasLayer.new()
	layer.layer = -1   # Under the HUD.
	add_child(layer)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = get_viewport().msaa_3d
	_viewport.size = get_window().size
	layer.add_child(_viewport)
	var screen := TextureRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture = _viewport.get_texture()
	layer.add_child(screen)
	_cam = Camera3D.new()
	_cam.cull_mask = LAYER
	_cam.fov = FOV
	_cam.near = 0.02
	_cam.far = 5.0
	_viewport.add_child(_cam)
	_cam.current = true


func _process(delta: float) -> void:
	if _holder == null:
		return
	# Full resolution even though the UI is scaled.
	var win := get_window().size
	if _viewport.size != win and win.x > 0:
		_viewport.size = win
	_cam.global_transform = _world_cam.global_transform

	var kind := weapons.current_kind()
	if kind != _shown:
		_show(kind)
	if _anim and not _anim.is_playing():
		_anim.play("idle", 0.15)
	_place(delta)


func _show(kind: int) -> void:
	_shown = kind
	for c in _holder.get_children():
		c.queue_free()
	_model = null
	_anim = null
	_placeholder = null
	if kind == -1:
		return
	if MODELS.has(kind):
		_model = (MODELS[kind] as PackedScene).instantiate()
		_holder.add_child(_model)
		_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
		_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		_set_layers(_model)
		_anim.play("draw")
		_anim.queue("idle")
	else:
		var v: Array = WeaponStats.get_stat(kind, "view")
		_placeholder = MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = v[1]
		mesh.bottom_radius = v[1]
		mesh.height = v[2]
		_placeholder.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = v[0]
		m.roughness = 0.6
		_placeholder.material_override = m
		_placeholder.rotation.x = deg_to_rad(90)
		_holder.add_child(_placeholder)
		_set_layers(_placeholder)


static func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		n.layers = LAYER
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_layers(c)


## Called when you fire (any weapon).
func fired(kind: int) -> void:
	if _anim and kind == _shown:
		_anim.stop()
		_anim.play("fire")
		_anim.queue("idle")
		if kind == K.ROCKET_LAUNCHER:
			_rocket_flash()
	else:
		_kick = 1.0 if kind != K.NAILGUN and kind != K.SUPER_NAILGUN else 0.3


func _place(delta: float) -> void:
	var p: Array = PLACE_MODEL.get(_shown, PLACE_PLACEHOLDER) if _model else PLACE_PLACEHOLDER
	var pos: Vector3 = p[0]
	var rot: Vector3 = p[1]
	# Out of view while reloading or switching; slides back when done.
	var want_down := 1.0 if weapons.reloading or weapons.switching > 0.0 else 0.0
	_down = move_toward(_down, want_down, delta / DROP_TIME)
	_holder.visible = _down < 0.999
	pos.y -= DROP * _down
	rot.x -= 25.0 * _down
	if _placeholder:
		_kick = move_toward(_kick, 0.0, delta * 6.0)
		pos.z += _kick * 0.08
		rot.x += rad_to_deg(_kick * 0.12)
	_holder.position = pos
	_holder.rotation_degrees = rot


## Muzzle flash, backblast and a smoke puff (drawn with the weapon).
func _rocket_flash() -> void:
	var muzzle := _model.global_transform * Vector3(0, 0, -0.44)
	var rear := _model.global_transform * Vector3(0, 0, 0.42)
	for spot in [[muzzle, Color(1.0, 0.75, 0.35), 0.06, 4.0], [rear, Color(1.0, 0.55, 0.2), 0.1, 2.0]]:
		var light := OmniLight3D.new()
		light.light_color = spot[1]
		light.light_energy = spot[3]
		light.omni_range = 2.5
		_holder.add_child(light)
		light.global_position = spot[0]
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = spot[2]
		sm.height = spot[2] * 2.0
		ball.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = spot[1]
		ball.material_override = m
		ball.layers = LAYER
		_holder.add_child(ball)
		ball.global_position = spot[0]
		var tw := create_tween().set_parallel()
		tw.tween_property(light, "light_energy", 0.0, 0.12)
		tw.tween_property(ball, "scale", Vector3.ONE * 1.8, 0.1)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.1)
		tw.chain().tween_callback(light.queue_free)
		tw.tween_callback(ball.queue_free)
