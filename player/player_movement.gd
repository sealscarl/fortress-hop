class_name Player
extends CharacterBody3D
## Quake / TFC-style player movement: ground friction, ground acceleration,
## air strafing, auto-hop and crouch-jumping.
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

@export_group("Mouse")
## Degrees of turn per pixel of mouse movement (like Quake's m_yaw 0.022 x sens).
@export var mouse_sensitivity := 0.1

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var speed_label: Label = $HUD/Speed

var crouched := false
var spawn_transform: Transform3D


func _ready() -> void:
	spawn_transform = global_transform
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_hull(stand_height)
	head.position.y = stand_eye_height


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotation.x = clampf(
			head.rotation.x - deg_to_rad(event.relative.y * mouse_sensitivity),
			deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_update_crouch()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input.x, 0.0, input.y))
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized()
	var wish_speed := max_speed * (crouch_speed_scale if crouched and is_on_floor() else 1.0)
	if input == Vector2.ZERO:
		wish_speed = 0.0

	if is_on_floor() and _wants_jump():
		# Jump before friction is applied: landing and jumping on the same
		# tick keeps all your speed. This is what makes bhopping possible.
		velocity.y = jump_velocity
		_air_move(wish_dir, wish_speed, delta)
	elif is_on_floor():
		_apply_friction(delta)
		_accelerate(wish_dir, wish_speed, ground_accelerate, delta)
		velocity.y = 0.0
	else:
		_air_move(wish_dir, wish_speed, delta)
		velocity.y -= gravity * delta

	_cap_horizontal_speed()
	move_and_slide()

	if global_position.y < -50.0:
		respawn()

	_update_hud()


func _process(delta: float) -> void:
	var target := crouch_eye_height if crouched else stand_eye_height
	head.position.y = move_toward(head.position.y, target, delta * 6.0)


func _wants_jump() -> bool:
	if auto_hop:
		return Input.is_action_pressed("jump")
	return Input.is_action_just_pressed("jump")


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
func _update_crouch() -> void:
	var diff := stand_height - crouch_height
	var want := Input.is_action_pressed("crouch")
	if want and not crouched:
		crouched = true
		_apply_hull(crouch_height)
		if not is_on_floor():
			global_position.y += diff
			head.position.y -= diff
	elif not want and crouched:
		if is_on_floor():
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


func respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO


func _update_hud() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "%d ups\n%.1f m/s%s" % [
		roundi(speed * QUAKE_UNITS_PER_METER), speed,
		"\nAUTO-HOP" if auto_hop else ""]
