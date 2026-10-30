class_name Rocket
extends Node3D
## Straight-flying projectiles (no gravity): rockets and nails. Rockets
## explode on the first wall or player they touch; nails just hit. Like
## grenades, the server owns the real one and clients show a look-alike.

const LIFETIME := 6.0
const HIT_MASK := 1 | 4   ## World + players.

var kind: int             ## WeaponStats.Kind
var velocity := Vector3.ZERO
var shooter: Player       ## Null on a client look-alike.
var is_real := false
var net_id := 0
var _age := 0.0
var _trail: GPUParticles3D
const TRAIL_DELAY := 0.04   ## Don't puff smoke right in the shooter's face.


static func create(p_shooter: Player, p_kind: int, p_vel: Vector3, p_id: int) -> Rocket:
	var r := Rocket.new()
	r.shooter = p_shooter
	r.is_real = p_shooter != null
	r.kind = p_kind
	r.velocity = p_vel
	r.net_id = p_id
	r.name = "Projectile%d" % p_id
	return r


func _is_nail() -> bool:
	return kind != WeaponStats.Kind.ROCKET_LAUNCHER


func _ready() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.02 if _is_nail() else 0.06
	capsule.height = 0.18 if _is_nail() else 0.4
	body.mesh = capsule
	body.rotation.x = deg_to_rad(90)   # Capsule along -Z (the flight direction).
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.75, 0.7) if _is_nail() else Color(0.3, 0.3, 0.3)
	m.metallic = 0.8 if _is_nail() else 0.0
	body.material_override = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	if not _is_nail():
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.25)
		glow.light_energy = 2.0
		glow.omni_range = 3.0
		add_child(glow)
		glow.position = Vector3(0, 0, 0.25)
		_trail = Effects.rocket_trail(self)
		_trail.emitting = false
		tree_exiting.connect(_end_trail)
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)


func _process(delta: float) -> void:
	if _trail == null:
		return
	if not _trail.is_inside_tree():
		get_parent().add_child(_trail)
	# Cover the stretch flown since last frame (see Effects.rocket_trail).
	var half := maxf(velocity.length() * delta * 0.5, 0.05)
	_trail.global_transform = Transform3D(global_basis, global_position + global_basis.z * (0.25 + half))
	(_trail.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.04, 0.04, half)
	_trail.emitting = _age > TRAIL_DELAY


## The rocket is gone: its smoke stops and drifts away.
func _end_trail() -> void:
	if _trail and _trail.is_inside_tree():
		_trail.emitting = false
		var t := _trail
		_trail.get_tree().create_timer(_trail.lifetime + 0.2).timeout.connect(t.queue_free)
	elif _trail:
		_trail.free()
	_trail = null


func _physics_process(delta: float) -> void:
	_age += delta
	var step := velocity * delta
	if not is_real:
		global_position += step
		# Outlive the server's copy a little; normally the server removes us.
		if _age > LIFETIME + 1.0:
			queue_free()
		return

	if not is_instance_valid(shooter) or _age > LIFETIME:
		Game.instance.announce_explosion(net_id, Grenade.Type.FRAG, global_position, 0.0)
		queue_free()
		return

	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, HIT_MASK, [shooter.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return

	var d: Dictionary = WeaponStats.DATA[kind]
	if _is_nail():
		if hit.collider is Player:
			var victim: Player = hit.collider
			victim.hurt(d.damage, shooter, velocity.normalized() * d.damage * d.knockback, WeaponStats.icon(kind))
		Game.instance.announce_explosion(net_id, Grenade.Type.FRAG, hit.position, 0.0)
	else:
		# Explode just in front of the surface so the blast isn't inside the wall.
		var at: Vector3 = hit.position + hit.normal * 0.05
		Game.instance.announce_explosion(net_id, Grenade.Type.FRAG, at, d.radius)
		Explosions.radial(get_tree(), at, d.damage, d.radius, d.knockback, shooter,
			Console.sv("tf_rocket_selfdamage"), Console.sv("tf_rocket_selfpush"), "rocket")
	queue_free()
