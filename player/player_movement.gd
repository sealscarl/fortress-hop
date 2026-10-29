class_name Player
extends CharacterBody3D
## Quake / TFC-style player movement: ground friction, ground acceleration,
## air strafing, auto-hop and crouch-jumping.
##
## Movement runs from PlayerCmd input commands via simulate(), so the exact
## same code runs on your machine (prediction) and on the server (authority).
## Game (maps/game.gd) drives the ticks; this node never reads input on its own
## except mouse look for the local player.
##
## Units: 1 Godot unit = 1 meter. Classic Quake values are converted with
## 1 m = 32 Quake units (so 320 ups = 10 m/s). Every value below is exported,
## so you can tune it live in the Inspector while the game runs.

const QUAKE_UNITS_PER_METER := 32.0

@export_group("Jumping")
## Hold jump to keep hopping the instant you land. Off = classic tap-to-jump
## (you must release and press again for every hop).
@export var auto_hop := true
## Upward speed of a jump. Quake: 270 ups.
@export var jump_velocity := 8.4375
## Quake: sv_gravity 800.
@export var gravity := 25.0

@export_group("Ground")
## Top running speed. Quake/TFC: 320 ups.
@export var max_speed := 10.0
## Quake: sv_accelerate 10.
@export var ground_accelerate := 10.0
## Quake: sv_friction 4.
@export var friction := 4.0
## Below this speed, friction acts as if you were moving this fast, so you
## stop crisply instead of sliding forever. Quake: sv_stopspeed 100.
@export var stop_speed := 3.125

@export_group("Air")
## How strongly you can steer in the air. Quake/TFC: sv_airaccelerate 10.
@export var air_accelerate := 10.0
## Max speed you can add along your wish direction in one air tick.
## This small cap is what makes strafe-jumping work. Quake: 30 ups.
@export var air_wish_speed_cap := 0.9375
## Hard cap on horizontal speed while hopping. 0 = no cap (QuakeWorld TF).
## TFC used about 1.7 x max_speed.
@export var max_bhop_speed := 0.0

@export_group("Crouch")
@export var stand_height := 1.8
@export var crouch_height := 1.1
## Speed multiplier while crouched on the ground. TFC: 1/3.
@export var crouch_speed_scale := 0.333
@export var stand_eye_height := 1.6
@export var crouch_eye_height := 0.95

@export_group("Health")
@export var max_health := 100.0

@export_group("Mouse")
## Degrees of turn per pixel of mouse movement (like Quake's m_yaw 0.022 x sens).
@export var mouse_sensitivity := 0.1

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var hud: CanvasLayer = $HUD
@onready var speed_label: Label = $HUD/Speed
@onready var grenades: GrenadeThrower = $Grenades

var peer_id := 1
## True for the player this machine controls.
var is_local := false

var crouched := false
var health := 100.0
## Floor contact from the last simulated tick (part of the predicted state,
## so a replay starts from exactly what the server saw).
var on_floor := false
var _prev_jump := false
## Set by explosions so the next tick treats you as airborne, even if you
## were standing on the floor when the blast hit.
var _launched := false

## Where the local player is looking right now (mouse look is applied
## instantly, every frame; commands sample it each tick).
var look_yaw := 0.0
var look_pitch := 0.0


func _ready() -> void:
	health = max_health
	_apply_hull(stand_height)
	head.position.y = stand_eye_height
	look_yaw = rotation.y
	if is_local:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false
		hud.visible = false
		_add_body_mesh()


func _add_body_mesh() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = stand_height
	mesh.mesh = capsule
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.6, 0.9)
	mesh.material_override = m
	add_child(mesh)
	mesh.position.y = stand_height * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= deg_to_rad(event.relative.x * mouse_sensitivity)
		look_pitch = clampf(look_pitch - deg_to_rad(event.relative.y * mouse_sensitivity),
			deg_to_rad(-89.0), deg_to_rad(89.0))
		apply_look()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func apply_look() -> void:
	rotation.y = look_yaw
	head.rotation.x = look_pitch


## Samples this tick's input for the local player. Call from a physics tick.
func build_cmd(seq: int) -> PlayerCmd:
	var c := PlayerCmd.new()
	c.seq = seq
	c.yaw = look_yaw
	c.pitch = look_pitch
	# Ignore game keys while the mouse is freed (Esc), e.g. typing in a menu.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		or DisplayServer.get_name() == "headless"
	if captured:
		c.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_pressed("jump"): c.flags |= PlayerCmd.JUMP
		if Input.is_action_pressed("crouch"): c.flags |= PlayerCmd.CROUCH
		if Input.is_action_just_pressed("grenade_1"): c.flags |= PlayerCmd.GRENADE_1
		if Input.is_action_just_pressed("grenade_2"): c.flags |= PlayerCmd.GRENADE_2
	if auto_hop: c.flags |= PlayerCmd.AUTO_HOP
	return c


## Runs one tick of movement from a command.
func simulate(cmd: PlayerCmd, delta: float) -> void:
	rotation.y = cmd.yaw
	head.rotation.x = cmd.pitch
	_update_crouch(cmd.has(PlayerCmd.CROUCH))

	var wish_dir := transform.basis * Vector3(cmd.move.x, 0.0, cmd.move.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized()
	var wish_speed := max_speed * (crouch_speed_scale if crouched and on_floor else 1.0)
	if cmd.move == Vector2.ZERO:
		wish_speed = 0.0

	var on_ground := on_floor and not _launched
	_launched = false

	var jump_held := cmd.has(PlayerCmd.JUMP)
	var wants_jump := jump_held if cmd.has(PlayerCmd.AUTO_HOP) else (jump_held and not _prev_jump)
	_prev_jump = jump_held

	if on_ground and wants_jump:
		# Jump before friction is applied: landing and jumping on the same
		# tick keeps all your speed. This is what makes bhopping possible.
		velocity.y = jump_velocity
		_air_move(wish_dir, wish_speed, delta)
	elif on_ground:
		_apply_friction(delta)
		_accelerate(wish_dir, wish_speed, ground_accelerate, delta)
		velocity.y = 0.0
	else:
		_air_move(wish_dir, wish_speed, delta)
		velocity.y -= gravity * delta

	_cap_horizontal_speed()
	move_and_slide()
	on_floor = is_on_floor()

	if global_position.y < -50.0 and multiplayer.is_server():
		respawn()


## Everything a replay needs to restart from a server-confirmed tick.
func get_state() -> Array:
	return [global_position, velocity, crouched, on_floor, _prev_jump, _launched]


func set_state(s: Array) -> void:
	global_position = s[0]
	velocity = s[1]
	if s[2] != crouched:
		crouched = s[2]
		_apply_hull(crouch_height if crouched else stand_height)
	on_floor = s[3]
	_prev_jump = s[4]
	_launched = s[5]


func _process(delta: float) -> void:
	var target := crouch_eye_height if crouched else stand_eye_height
	head.position.y = move_toward(head.position.y, target, delta * 6.0)
	if is_local:
		_update_hud()


## Quake PM_Friction.
func _apply_friction(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control := maxf(speed, stop_speed)
	var new_speed := maxf(speed - control * friction * delta, 0.0)
	var scale := new_speed / speed
	velocity.x *= scale
	velocity.z *= scale


## Quake PM_Accelerate: only adds speed along wish_dir up to wish_speed.
func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current := velocity.dot(wish_dir)
	var add := wish_speed - current
	if add <= 0.0:
		return
	var accel_speed := minf(accel * wish_speed * delta, add)
	velocity += wish_dir * accel_speed


## Quake PM_AirAccelerate. The wish speed is capped very low, but the
## acceleration still uses the full wish speed. Turning the mouse smoothly
## while holding a strafe key keeps current speed along wish_dir below the
## cap, so every tick adds a little speed: strafe-jumping.
func _air_move(wish_dir: Vector3, wish_speed: float, delta: float) -> void:
	var capped := minf(wish_speed, air_wish_speed_cap)
	var current := velocity.dot(wish_dir)
	var add := capped - current
	if add <= 0.0:
		return
	var accel_speed := minf(air_accelerate * wish_speed * delta, add)
	velocity += wish_dir * accel_speed


func _cap_horizontal_speed() -> void:
	if max_bhop_speed <= 0.0:
		return
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > max_bhop_speed:
		horizontal = horizontal.normalized() * max_bhop_speed
		velocity.x = horizontal.x
		velocity.z = horizontal.y


## Crouching on the ground lowers your head. Crouching in the air pulls your
## feet up instead (head stays put), so crouch-jumping clears higher ledges.
func _update_crouch(want: bool) -> void:
	var diff := stand_height - crouch_height
	if want and not crouched:
		crouched = true
		_apply_hull(crouch_height)
		if not on_floor:
			global_position.y += diff
			head.position.y -= diff
	elif not want and crouched:
		if on_floor:
			if test_move(global_transform, Vector3.UP * diff):
				return  # Something overhead; stay crouched.
			crouched = false
			_apply_hull(stand_height)
		else:
			if test_move(global_transform, Vector3.DOWN * diff):
				# Too close to the ground to drop the feet; stand from the top.
				if test_move(global_transform, Vector3.UP * diff):
					return
				crouched = false
				_apply_hull(stand_height)
			else:
				crouched = false
				global_position.y -= diff
				head.position.y += diff
				_apply_hull(stand_height)


func _apply_hull(height: float) -> void:
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = height
	collision.position.y = height * 0.5
	if has_node("Body"):
		var body := $Body as MeshInstance3D
		(body.mesh as CapsuleMesh).height = height
		body.position.y = height * 0.5


## Remote players on a client aren't simulated; Game moves them from
## snapshots and calls this to show crouching.
func set_remote_crouched(value: bool) -> void:
	if value != crouched:
		crouched = value
		_apply_hull(crouch_height if crouched else stand_height)


## Middle of the player's hull, which is what explosions measure distance to.
func center() -> Vector3:
	return global_position + Vector3.UP * collision.position.y


## Explosions call this to replace your velocity.
func launch(new_velocity: Vector3) -> void:
	velocity = new_velocity
	_launched = true


## Server only.
func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		grenades.drop_held()
		respawn()


## Server only: back to a random spawn point with full health and grenades.
## The owning client snaps to it on the next snapshot.
func respawn() -> void:
	var spawns := get_tree().get_nodes_in_group("spawn_point")
	var at: Node3D = spawns.pick_random() if spawns.size() else null
	global_position = at.global_position if at else Vector3(0, 0.1, 60)
	rotation.y = at.rotation.y if at else 0.0
	velocity = Vector3.ZERO
	health = max_health
	_launched = false
	grenades.refill()


func _update_hud() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "%d ups\n%.1f m/s%s" % [
		roundi(speed * QUAKE_UNITS_PER_METER), speed,
		"\nAUTO-HOP" if auto_hop else ""]
