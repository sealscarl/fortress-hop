class_name GrenadeThrower
extends Node
## Lives on the player. Handles double-tap grenades (tap to prime, tap again
## to throw), the fuse countdown (HUD + beeps), and explosion physics.
## Grenade logic and explosions run on the server only; clients get counts
## and the fuse timer from snapshots and play effects when told to.
##
## Conc numbers come from Team Fortress Classic, as reverse-engineered by
## Momentum Mod (accurate to about 0.1% of TFC), converted to meters
## (1 m = 32 Quake units).

const TICK_SOUND := preload("res://sounds/grenade_tick.wav")
const TICK_FINAL_SOUND := preload("res://sounds/grenade_tick_final.wav")
const PIN_SOUND := preload("res://sounds/pin_pull.wav")
const FRAG_SOUND := preload("res://sounds/explode_frag.wav")
const CONC_SOUND := preload("res://sounds/explode_conc.wav")

@export_group("Priming and throwing")
## The countdown shown on the HUD, after the prime delay. Hold past it and
## the grenade goes off in your hand. TFC conc fuse: 3.81 s.
@export var fuse_time := 3.0
## Buffer between priming and the start of the countdown. Total time from
## prime to explosion = prime_delay + fuse_time (1 + 3 = 4 s).
@export var prime_delay := 1.0
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
## Handheld frag push (m/s), aimed along the way you're already moving
## rather than straight up. 31.25 m/s = 1000 ups.
@export var hh_frag_push := 31.25

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
## so a mistimed handheld could slam you into the floor. 10 m/s = 320 ups.
@export var hh_min_up_speed := 10.0

@export_group("Conc (both)")
## Horizontal speed cap after any conc, so chained handhelds can't snowball.
## 31.25 m/s = 1000 ups (what the speedometer shows). 0 = no cap (TFC).
@export var conc_max_horizontal_speed := 31.25

signal changed  ## Counts, prime state or timer changed (for the HUD).

## On the server these are authoritative. On a client they're copied from
## server snapshots (and the timer counts down locally in between).
var frags := 0
var concs := 0
var held_type := -1          ## Grenade.Type in hand, or -1.
var timer_type := -1         ## Type shown on the HUD timer (keeps running after a throw).
var timer_left := 0.0
var _last_tick_step := -1
var _last_timer_seen := 0.0

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


## Server only: one tick of grenade logic, driven by the player's command.
func tick(cmd: PlayerCmd, delta: float) -> void:
	if cmd.has(PlayerCmd.GRENADE_1):
		_press(Grenade.Type.FRAG)
	elif cmd.has(PlayerCmd.GRENADE_2):
		_press(Grenade.Type.CONC)

	if timer_type == -1:
		return
	timer_left -= delta
	if timer_left <= 0.0:
		if held_type != -1:
			# Held too long: it goes off in your hand.
			var t := held_type as Grenade.Type
			held_type = -1
			detonate(t, player.center(), true)
		timer_type = -1
	changed.emit()


## Client: copy the server's view of our grenades from a snapshot.
func apply_snapshot(s: Array) -> void:
	frags = s[0]
	concs = s[1]
	held_type = s[2]
	timer_type = s[3]
	timer_left = s[4]
	changed.emit()


func snapshot() -> Array:
	return [frags, concs, held_type, timer_type, timer_left]


func _process(delta: float) -> void:
	if not multiplayer.is_server() and timer_type != -1:
		timer_left = maxf(timer_left - delta, 0.0)  # Smooth between snapshots.
	if player.is_local:
		_play_ticks()


## Either grenade key throws whatever you're holding; with nothing in hand,
## the key primes its own grenade type.
func _press(type: Grenade.Type) -> void:
	if held_type == -1:
		_prime(type)
	else:
		_throw()


func _prime(type: Grenade.Type) -> void:
	if type == Grenade.Type.FRAG:
		if frags <= 0: return
		frags -= 1
	else:
		if concs <= 0: return
		concs -= 1
	held_type = type
	timer_type = type
	timer_left = prime_delay + fuse_time
	changed.emit()


func _throw() -> void:
	var cam := player.camera
	var aim := -cam.global_basis.z
	# Tilt the throw upward around the camera's right axis.
	aim = aim.rotated(cam.global_basis.x.normalized(), deg_to_rad(throw_pitch_up_deg)).normalized()
	var vel := aim * throw_speed + player.velocity * inherit_velocity
	Game.instance.spawn_grenade(self, held_type, player.center(), vel, timer_left)
	held_type = -1
	changed.emit()


## Beeps once per second, then four quick beeps in the final second.
## Local player only.
func _play_ticks() -> void:
	if timer_type == -1:
		_last_timer_seen = 0.0
		return
	if timer_left > _last_timer_seen + 0.5:
		_last_tick_step = -1  # A new grenade was primed: pin-pull click.
		_beep.stream = PIN_SOUND
		_beep.play()
	_last_timer_seen = timer_left
	if timer_left > fuse_time:
		_last_tick_step = 0   # Still in the prime delay: no beeps yet.
		return
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
	Game.instance.spawn_grenade(self, held_type, player.center(), Vector3.ZERO, timer_left)
	held_type = -1
	changed.emit()


## Server only. grenade_id is 0 for a grenade that went off in a hand.
func detonate(type: Grenade.Type, origin: Vector3, handheld: bool, grenade_id := 0) -> void:
	var radius := frag_radius if type == Grenade.Type.FRAG else conc_radius
	Game.instance.announce_explosion(grenade_id, type, origin, radius)
	if type == Grenade.Type.FRAG:
		_frag_explode(origin, handheld)
	else:
		_conc_explode(origin, handheld)


func _frag_explode(origin: Vector3, handheld: bool) -> void:
	if not handheld:
		Explosions.radial(get_tree(), origin, frag_damage, frag_radius, frag_knockback,
			player, self_damage_scale, 1.0, "frag")
		return
	# In your hand: you get the directional handheld push and half damage;
	# everyone else around you gets the normal blast (teammates only with
	# friendly fire on).
	for p: Player in get_tree().get_nodes_in_group("player"):
		if not p.alive or p.center().distance_to(origin) > frag_radius:
			continue
		if p == player:
			p.launch(p.velocity + _handheld_frag_dir(p.velocity) * hh_frag_push)
			p.take_damage(frag_damage * self_damage_scale, player, "frag")
		else:
			var offset := p.center() - origin
			var points := frag_damage * (1.0 - offset.length() / frag_radius)
			p.hurt(points, player, offset.normalized() * points * frag_knockback, "frag")


## A frag in your hand pushes you the way you're already going. Upward
## motion counts (so jump first if you want height); falling doesn't, so it
## never drives you into the floor. Standing still: straight up.
func _handheld_frag_dir(v: Vector3) -> Vector3:
	var dir := Vector3(v.x, maxf(v.y, 0.0), v.z)
	return dir.normalized() if dir.length() > 0.5 else Vector3.UP


## Concs push everyone in range, teammates included (as in TFC), but never
## do damage.
func _conc_explode(origin: Vector3, handheld: bool) -> void:
	for p: Player in get_tree().get_nodes_in_group("player"):
		if not p.alive:
			continue
		var offset := p.center() - origin
		var dist := offset.length()
		if dist > conc_radius:
			continue
		# A conc that went off in someone's hand only moves that person.
		if handheld and p != player:
			continue
		var v: Vector3
		if (handheld and p == player) or dist < conc_handheld_distance:
			v = _handheld_velocity(p.velocity)
		else:
			v = _thrown_conc_velocity(offset)
		p.launch(_cap_horizontal(v, conc_max_horizontal_speed))


func _cap_horizontal(v: Vector3, cap: float) -> Vector3:
	var h := Vector2(v.x, v.z)
	if cap <= 0.0 or h.length() <= cap:
		return v
	h = h.normalized() * cap
	return Vector3(h.x, v.y, h.y)


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


## Flash, light and sound. Runs on every machine for every explosion.
static func spawn_effect(scene: Node, type: Grenade.Type, origin: Vector3, radius: float) -> void:
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
