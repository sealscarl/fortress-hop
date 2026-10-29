class_name Grenade
extends RigidBody3D
## A thrown grenade. Bounces off the world (not players), counts down its
## fuse, then asks its thrower to detonate it at its current position.

enum Type { FRAG, CONC }

const COLORS := {
	Type.FRAG: Color(0.25, 0.35, 0.15),
	Type.CONC: Color(0.75, 0.9, 1.0),
}

var type: Type
var fuse_left: float
var thrower: GrenadeThrower
var _mesh: MeshInstance3D


static func spawn(p_thrower: GrenadeThrower, p_type: Type, pos: Vector3,
		vel: Vector3, fuse: float) -> Grenade:
	var g := Grenade.new()
	g.thrower = p_thrower
	g.type = p_type
	g.fuse_left = fuse
	p_thrower.get_tree().current_scene.add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	return g


func _init() -> void:
	# Layer 2 = grenades. Collide with the world (layer 1) only, so grenades
	# never block players and players never kick grenades around.
	collision_layer = 2
	collision_mask = 1
	gravity_scale = 0.8  # Quake/TFC grenades fall at 0.8 x gravity.
	continuous_cd = true
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.6
	mat.friction = 0.6
	physics_material_override = mat
	# No spinning: a spinning sphere rolls for ages. Locked, it slides and
	# friction stops it quickly, like TFC grenades. Bounce is unchanged.
	lock_rotation = true

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	_mesh.mesh = sm
	add_child(_mesh)


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = COLORS[type]
	if type == Type.CONC:
		m.emission_enabled = true
		m.emission = Color(0.4, 0.7, 1.0)
		m.emission_energy_multiplier = 0.6
	_mesh.set_surface_override_material(0, m)


func _physics_process(delta: float) -> void:
	fuse_left -= delta
	if fuse_left <= 0.0:
		if is_instance_valid(thrower):
			thrower.detonate(type, global_position, false)
		queue_free()
