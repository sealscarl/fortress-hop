class_name Rocket
extends Node3D
## A rocket flies in a straight line (no gravity) and explodes on the first
## thing it touches: the world or another player. Like grenades, the server
## owns the real one and clients show a look-alike.

const LIFETIME := 10.0
const HIT_MASK := 1 | 4   ## World + players.

var velocity := Vector3.ZERO
var shooter: Player       ## Null on a client look-alike.
var is_real := false
var net_id := 0
var _age := 0.0


static func create(p_shooter: Player, p_vel: Vector3, p_id: int) -> Rocket:
	var r := Rocket.new()
	r.shooter = p_shooter
	r.is_real = p_shooter != null
	r.velocity = p_vel
	r.net_id = p_id
	r.name = "Rocket%d" % p_id
	return r


func _ready() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.06
	capsule.height = 0.4
	body.mesh = capsule
	body.rotation.x = deg_to_rad(90)   # Capsule along -Z (the flight direction).
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.3, 0.3)
	body.material_override = m
	add_child(body)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 2.0
	glow.omni_range = 3.0
	add_child(glow)
	glow.position = Vector3(0, 0, 0.25)
	_face_velocity()


func _face_velocity() -> void:
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	_age += delta
	var step := velocity * delta
	if not is_real:
		global_position += step
		if _age > LIFETIME:
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
	# Explode just in front of the surface so the blast isn't inside the wall.
	var at: Vector3 = hit.position + hit.normal * 0.05
	var radius := shooter.weapons.rocket_radius
	Game.instance.announce_explosion(net_id, Grenade.Type.FRAG, at, radius)
	shooter.weapons.rocket_explode(at)
	queue_free()
