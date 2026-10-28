class_name GrenadeThrower
extends Node
## Lives on the player. Handles double-tap grenades (tap to prime, tap again
## to throw), the fuse countdown (HUD + beeps), and explosion physics.
##
## Conc numbers come from Team Fortress Classic, as reverse-engineered by
## Momentum Mod (accurate to about 0.1% of TFC), converted to meters
## (1 m = 32 Quake units).

const TICK_SOUND := preload("res://sounds/grenade_tick.wav")
const TICK_FINAL_SOUND := preload("res://sounds/grenade_tick_final.wav")
const FRAG_SOUND := preload("res://sounds/explode_frag.wav")
const CONC_SOUND := preload("res://sounds/explode_conc.wav")

@export_group("Priming and throwing")
## Seconds from priming to explosion. Hold past this and it goes off in your hand.
## TFC conc fuse: 3.81 s.
@export var fuse_time := 3.0
@export var max_frags := 4
@export var max_concs := 4
## TFC/Momentum: 660 ups.
@export var throw_speed := 20.625
## Grenades leave at your aim angle tilted up by this much. TFC/Momentum: 18.5 deg.
@export var throw_pitch_up_deg := 18.5
## Fraction of your own velocity added to the throw. TFC: 0 (none).
@export var inherit_velocity := 0.0

@export_group("Frag")
@export var frag_damage := 100.0
## TFC: about 220 units.
@export var frag_radius := 6.875
## Knockback speed (m/s) per point of damage. Quake: 8 ups per point = 0.25 m/s.
@export var frag_knockback := 0.25
## Your own frags hurt you this much (grenade jumps cost health, not a life).
@export var self_damage_scale := 0.5

@export_group("Conc (thrown)")
## TFC: 280 units.
@export var conc_radius := 8.75
## Inside this distance, a thrown conc acts like a handheld. TFC: 16 units.
@export var conc_handheld_distance := 0.5

@export_group("Conc (handheld)")
## Handheld concs multiply your current horizontal velocity. TFC: 2.74.
@export var hh_lateral_power := 2.74
## ...and your current vertical velocity. TFC: 4.1.
@export var hh_vertical_power := 4.1
## Fortress Forever-style assist: a handheld always sends you up at least
## this fast, even if you were standing still or falling. TFC: none (0),
## so a mistimed handheld could slam you into the floor.
@export var hh_min_up_speed := 4.0

signal changed  ## Counts, prime state or timer changed (for the HUD).

var frags := 0
var concs := 0
var held_type := -1          ## Grenade.Type in hand, or -1.
var timer_type := -1         ## Type shown on the HUD timer (keeps running after a throw).
var timer_left := 0.0
var _last_tick_step := -1

@onready var player: Player = get_parent()
@onready var _beep := AudioStreamPlayer.new()


func _ready() -> void:
	add_child(_beep)
	_beep.volume_db = -6.0
	refill()


func refill() -> void:
	frags = max_frags
	concs = max_concs
	changed.emit()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("grenade_1"):
		_press(Grenade.Type.FRAG)
	if Input.is_action_just_pressed("grenade_2"):
		_press(Grenade.Type.CONC)

	if timer_type == -1:
		return
	timer_left -= delta
	_play_ticks()
	if timer_left <= 0.0:
		if held_type != -1:
			# Held too long: it goes off in your hand.
			var t := held_type
			held_type = -1
			detonate(t, player.center(), true)
		timer_type = -1
	changed.emit()


func _press(type: Grenade.Type) -> void:
	if held_type == -1:
		_prime(type)
	elif held_type == type:
		_throw()
	# Pressing the other grenade key while one is primed does nothing (TFC).


func _prime(type: Grenade.Type) -> void:
	if type == Grenade.Type.FRAG:
		if frags <= 0: return
		frags -= 1
	else:
		if concs <= 0: return
		concs -= 1
	held_type = type
	timer_type = type
	timer_left = fuse_time
	_last_tick_step = -1
	changed.emit()


func _throw() -> void:
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var aim := -cam.global_basis.z
	# Tilt the throw upward around the camera's right axis.
	aim = aim.rotated(cam.global_basis.x.normalized(), deg_to_rad(throw_pitch_up_deg)).normalized()
	var vel := aim * throw_speed + player.velocity * inherit_velocity
	Grenade.spawn(self, held_type, player.center(), vel, timer_left)
	held_type = -1
	changed.emit()


## Beeps once per second, then four quick beeps in the final second.
func _play_ticks() -> void:
	var step: int
	if timer_left > 1.0:
		step = int(ceil(timer_left))           # 3, 2 -> one beep per second
	else:
		step = -int(ceil(timer_left / 0.25))   # -4..-1 -> beep every 0.25 s
	if step != _last_tick_step and timer_left > 0.0:
		_last_tick_step = step
		_beep.stream = TICK_SOUND if step > 0 else TICK_FINAL_SOUND
		_beep.play()


## Called when the player dies: a primed grenade drops where you stand.
func drop_held() -> void:
	if held_type == -1:
		return
	Grenade.spawn(self, held_type, player.center(), Vector3.ZERO, timer_left)
	held_type = -1
	changed.emit()


func detonate(type: Grenade.Type, origin: Vector3, handheld: bool) -> void:
	_spawn_effect(type, origin)
	if type == Grenade.Type.FRAG:
		_frag_explode(origin)
	else:
		_conc_explode(origin, handheld)


func _frag_explode(origin: Vector3) -> void:
	for p: Player in get_tree().get_nodes_in_group("player"):
		var offset := p.center() - origin
		var dist := offset.length()
		if dist > frag_radius:
			continue
		var points := frag_damage * (1.0 - dist / frag_radius)
		var dir := offset / dist if dist > 0.05 else Vector3.UP
		p.launch(p.velocity + dir * points * frag_knockback)
		p.take_damage(points * (self_damage_scale if p == player else 1.0))


func _conc_explode(origin: Vector3, handheld: bool) -> void:
	for p: Player in get_tree().get_nodes_in_group("player"):
		var offset := p.center() - origin
		var dist := offset.length()
		if dist > conc_radius:
			continue
		# A conc that went off in someone's hand only moves that person.
		if handheld and p != player:
			continue
		if (handheld and p == player) or dist < conc_handheld_distance:
			p.launch(_handheld_velocity(p.velocity))
		else:
			p.launch(_thrown_conc_velocity(offset))


## TFC drop/thrown conc. Push grows with distance, peaking near the edge of
## the blast. In Quake units the formula is:
##   horizontal = h * (8.4 - 0.015 * d),  vertical = z * (12.6 - 0.0225 * d)
## where h/z are your horizontal/vertical offset from the conc and d the total
## distance. In meters the constants become 0.48 and 0.72.
## Note it SETS your velocity rather than adding to it.
func _thrown_conc_velocity(offset: Vector3) -> Vector3:
	var dist := offset.length()
	var horizontal := Vector3(offset.x, 0.0, offset.z) * (8.4 - 0.48 * dist)
	var vertical := offset.y * (12.6 - 0.72 * dist)
	return Vector3(horizontal.x, vertical, horizontal.z)


## TFC handheld: multiplies the velocity you already had, so a good handheld
## means jumping (and moving) at the instant it pops. Plus FF-style lift.
func _handheld_velocity(v: Vector3) -> Vector3:
	return Vector3(
		v.x * hh_lateral_power,
		maxf(v.y * hh_vertical_power, hh_min_up_speed),
		v.z * hh_lateral_power)


func _spawn_effect(type: Grenade.Type, origin: Vector3) -> void:
	var scene := get_tree().current_scene
	var radius := frag_radius if type == Grenade.Type.FRAG else conc_radius
	var color := Color(1.0, 0.55, 0.15) if type == Grenade.Type.FRAG else Color(0.5, 0.8, 1.0)

	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	flash.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, 0.35)
	flash.material_override = m
	scene.add_child(flash)
	flash.global_position = origin

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius * 1.5
	scene.add_child(light)
	light.global_position = origin

	var sound := AudioStreamPlayer3D.new()
	sound.stream = FRAG_SOUND if type == Grenade.Type.FRAG else CONC_SOUND
	sound.unit_size = 20.0
	scene.add_child(sound)
	sound.global_position = origin
	sound.play()
	sound.finished.connect(sound.queue_free)

	# Sphere grows to the blast radius and fades: shows exactly how far it reaches.
	var tw := scene.create_tween().set_parallel()
	flash.scale = Vector3.ONE * 0.2
	tw.tween_property(flash, "scale", Vector3.ONE * radius, 0.18)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.chain().tween_callback(flash.queue_free)
	tw.tween_callback(light.queue_free)
