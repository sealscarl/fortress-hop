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
const HULL_RADIUS := 0.4

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

@export_group("Steps")
## Tallest step you walk up without jumping. Quake: 18 units.
@export var step_height := 0.5625
## FTEQW / QWTF Live "pm_airstep": the same step-up works in the air, so you
## can bhop up stairs without losing (or gaining) speed.
@export var air_step := true

@export_group("Crouch")
@export var stand_height := 1.8
@export var crouch_height := 1.1
## Speed multiplier while crouched on the ground. TFC: 1/3.
@export var crouch_speed_scale := 0.333
@export var stand_eye_height := 1.6
@export var crouch_eye_height := 0.95

@export_group("Health")
@export var max_health := 100.0

## Mouse sensitivity, FOV and auto-hop come from the Settings autoload (Options menu).

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var hud: CanvasLayer = $HUD
@onready var speed_label: Label = $HUD/Speed
@onready var grenades: GrenadeThrower = $Grenades
@onready var weapons: WeaponManager = $Weapons

var peer_id := 1
## True for the player this machine controls.
var is_local := false

var team := 0                 ## 0 = Red, 1 = Blue.
var class_id := -1            ## PlayerClasses.Id, or -1 before picking one.
var pending_class := -1       ## Class to switch to at the next respawn.
var alive := false            ## False until a class is picked (and while dead).
var display_name := ""
## Set just before a non-player death ("was laser'd") for the kill feed.
var death_msg := ""

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
## Mouse-wheel weapon switches arrive as instant press+release events, so
## they're caught here and handed to the next command.
var _wheel_flags := 0


func _ready() -> void:
	health = max_health
	_apply_hull(stand_height)
	head.position.y = stand_eye_height
	look_yaw = rotation.y
	Console.apply_server_vars(self)   # sv_gravity, sv_airaccelerate, pm_airstep...
	if is_local:
		camera.current = true
		Settings.changed.connect(_apply_settings)
		_apply_settings()
	else:
		camera.current = false
		hud.visible = false
		_add_body_mesh()
	set_alive(alive)


## Options that affect the local player (FOV, auto-hop, speedometer).
func _apply_settings() -> void:
	camera.fov = Settings.vertical_fov()
	auto_hop = Settings.get_option("auto_hop")
	speed_label.visible = Settings.get_option("show_speed")


func _add_body_mesh() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = HULL_RADIUS
	capsule.height = stand_height
	mesh.mesh = capsule
	mesh.material_override = StandardMaterial3D.new()
	add_child(mesh)
	mesh.position.y = stand_height * 0.5
	_update_team_color()


func _update_team_color() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body:
		(body.material_override as StandardMaterial3D).albedo_color = PlayerClasses.TEAM_COLORS[team]


# --- Class, team, life -----------------------------------------------------------

## Sets health, speed, weapons and grenades from the class table.
func apply_class(id: int) -> void:
	class_id = id
	max_health = PlayerClasses.stat(id, "health")
	max_speed = PlayerClasses.stat(id, "speed_ups") / QUAKE_UNITS_PER_METER
	weapons.set_loadout(PlayerClasses.stat(id, "weapons"))
	grenades.max_frags = PlayerClasses.stat(id, "frags")
	grenades.max_concs = PlayerClasses.stat(id, "concs")
	grenades.refill()


func set_team(t: int) -> void:
	team = t
	_update_team_color()


func set_alive(value: bool) -> void:
	alive = value
	collision.disabled = not value
	var body := get_node_or_null("Body")
	if body:
		body.visible = value


## Server only: hurt by someone (or something, if attacker is null), with a
## knockback push. No friendly fire: teammates can't hurt or push you.
func hurt(amount: float, attacker: Player, push: Vector3) -> void:
	if not alive:
		return
	if attacker and attacker != self and attacker.team == team:
		return
	launch(velocity + push)
	take_damage(amount, attacker)


## Server only. Returns how much health was actually restored.
func heal(amount: float, healer: Player) -> float:
	if not alive or health >= max_health:
		return 0.0
	var gained := minf(amount, max_health - health)
	health += gained
	Game.instance.report_damage(healer, self, -gained)
	return gained


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var deg := Settings.degrees_per_count()
		var dy: float = -event.relative.y if Settings.get_option("invert_y") else event.relative.y
		look_yaw -= deg_to_rad(event.relative.x * deg)
		look_pitch = clampf(look_pitch - deg_to_rad(dy * deg),
			deg_to_rad(-89.0), deg_to_rad(89.0))
		apply_look()
	elif event.is_action_pressed("weapon_next"):
		_wheel_flags |= PlayerCmd.NEXT_WEAPON
	elif event.is_action_pressed("weapon_prev"):
		_wheel_flags |= PlayerCmd.PREV_WEAPON
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameUI.menu_open():
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
		if Input.is_action_pressed("fire"): c.flags |= PlayerCmd.FIRE
		if Input.is_action_just_pressed("reload"): c.flags |= PlayerCmd.RELOAD
		if Input.is_action_just_pressed("weapon_1"): c.weapon_slot = 1
		if Input.is_action_just_pressed("weapon_2"): c.weapon_slot = 2
		if Input.is_action_just_pressed("weapon_3"): c.weapon_slot = 3
		if Input.is_action_just_pressed("detonate_pipes"): c.flags |= PlayerCmd.DETONATE
		c.flags |= _wheel_flags
	_wheel_flags = 0
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
	_step_slide_move(not on_ground or wants_jump)

	if global_position.y < -50.0 and multiplayer.is_server():
		die(null)


## Quake PM_StepSlideMove, with FTEQW's pm_airstep. Slides normally; if a
## wall stopped us, tries again lifted by a step, then presses back down onto
## it, and keeps whichever got further. Vertical speed always comes from the
## normal slide, so stepping never adds or removes speed.
func _step_slide_move(in_air: bool) -> void:
	var start := global_position
	var start_vel := velocity
	move_and_slide()
	on_floor = is_on_floor()

	var hit_wall := false
	for i in get_slide_collision_count():
		# Anything we can't stand on (walls, step risers, rounded lips).
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.7 and n.y > -0.1:
			hit_wall = true
	if not hit_wall or (in_air and not air_step):
		return
	var down_pos := global_position
	var down_vel := velocity
	var down_floor := on_floor

	var step := step_height
	if in_air:
		# Only a real step: there must be floor within a step below us
		# (where we started if rising, where we ended up if falling), and we
		# can't climb higher than a step above it.
		var org := down_pos if start_vel.y < 0.0 else start
		var probe := KinematicCollision3D.new()
		if not test_move(Transform3D(global_basis, org), Vector3.DOWN * step_height, probe) \
				or is_nan(_floor_height(probe)):
			return
		step = step_height - probe.get_travel().length()
		if step <= 0.001:
			return

	# Retry from the start, lifted up a step (less if there's a ceiling).
	global_position = start
	velocity = start_vel
	move_and_collide(Vector3.UP * step)
	move_and_slide()
	var slide_floor := is_on_floor()
	# Press back down onto the step.
	var land := move_and_collide(Vector3.DOWN * step)
	var up_dist := Vector2(global_position.x - start.x, global_position.z - start.z).length()
	var down_dist := Vector2(down_pos.x - start.x, down_pos.z - start.z).length()
	var floor_y := _floor_height(land) if land else NAN
	if (land and is_nan(floor_y)) or down_dist > up_dist:
		global_position = down_pos
		velocity = down_vel
		on_floor = down_floor
		return
	if not is_nan(floor_y) and floor_y > global_position.y:
		global_position.y = floor_y   # Sit flat on the step, not on its rounded lip.
	velocity.y = down_vel.y
	on_floor = velocity.y <= 0.0 and (slide_floor or land != null)


## Height of the standable ground under a downward hit, or NAN if it's not
## ground. Physics engines round shape edges slightly (Jolt especially), so
## landing on the lip of a step reports a slanted normal. Quake's hull has
## sharp edges and would stand there, so for a slanted hit we look just past
## the contact for flat ground: a step's top is there, a steep slope isn't.
func _floor_height(hit: KinematicCollision3D) -> float:
	var n := hit.get_normal()
	if n.y >= 0.7:
		return hit.get_position().y
	if n.y <= 0.0:
		return NAN
	var out := Vector3(-n.x, 0.0, -n.z).normalized() * 0.05
	var from := hit.get_position() + out + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.2, collision_mask, [get_rid()])
	var ray := get_world_3d().direct_space_state.intersect_ray(q)
	if ray.is_empty() or ray.normal.y < 0.7:
		return NAN
	return ray.position.y


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
	var factor := new_speed / speed
	velocity.x *= factor
	velocity.z *= factor


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
	var hull := collision.shape as CylinderShape3D
	hull.height = height
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


## Half the length of the hull capsule's inner segment (for hitscan checks).
func hull_half_segment() -> float:
	return (collision.shape as CylinderShape3D).height * 0.5 - HULL_RADIUS


## Middle of the player's hull, which is what explosions measure distance to.
func center() -> Vector3:
	return global_position + Vector3.UP * collision.position.y


## Explosions call this to replace your velocity.
func launch(new_velocity: Vector3) -> void:
	velocity = new_velocity
	_launched = true


## Server only. Damage that ignores teams (falling out of the world, your
## own grenade in your hand). Use hurt() for anything a player caused.
func take_damage(amount: float, attacker: Player = null) -> void:
	if not alive:
		return
	health -= amount
	if attacker and attacker != self:
		Game.instance.report_damage(attacker, self, amount)
	if health <= 0.0:
		die(attacker)


## Server only.
func die(killer: Player) -> void:
	grenades.drop_held()
	if MapLogic.instance:
		MapLogic.instance.on_player_died(self)   # Drops a carried flag here.
	Game.instance.on_death(self, killer)
	death_msg = ""
	if pending_class != -1:
		apply_class(pending_class)
		pending_class = -1
	respawn()


## Server only: to a random spawn point of your team, full health and ammo.
## The owning client snaps to it on the next snapshot.
func respawn() -> void:
	var spawns := get_tree().get_nodes_in_group("spawn_team%d" % team)
	var at: Node3D = spawns.pick_random() if spawns.size() else null
	global_position = at.global_position if at else Vector3(0, 0.1, 60)
	rotation.y = at.rotation.y if at else 0.0
	look_yaw = rotation.y
	velocity = Vector3.ZERO
	health = max_health
	_launched = false
	grenades.refill()
	weapons.reset()
	set_alive(true)


func _update_hud() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "%d ups\n%.1f m/s%s" % [
		roundi(speed * QUAKE_UNITS_PER_METER), speed,
		"\nAUTO-HOP" if auto_hop else ""]
