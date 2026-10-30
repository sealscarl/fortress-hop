class_name Bomb
extends RigidBody3D
## Demoman projectiles: grenade-launcher grenades and pipe bombs. Both bounce
## like hand grenades.
## - Grenades explode after their fuse, or instantly if they touch an enemy
##   before their first bounce.
## - Pipe bombs never go off on their own: the Demoman detonates them with
##   Mouse 5 once they've armed (arm_time after firing; they start glowing).
##   Only so many can be out at once; the oldest pops first.

var kind: int              ## WeaponStats.Kind
var shooter: Player        ## Null on a client look-alike.
var is_real := false
var net_id := 0
var fuse_left := 0.0
var bounced := false
var age := 0.0
var _glow: StandardMaterial3D


## On clients, pass the shooter too (for team colors) with p_real = false.
static func create(p_shooter: Player, p_kind: int, p_id: int, p_real: bool) -> Bomb:
	var b := Bomb.new()
	b.shooter = p_shooter
	b.is_real = p_real
	b.kind = p_kind
	b.net_id = p_id
	b.name = "Bomb%d" % p_id
	if p_kind == WeaponStats.Kind.GRENADE_LAUNCHER:
		b.fuse_left = WeaponStats.get_stat(p_kind, "fuse")
	return b


func _init() -> void:
	collision_layer = 2
	collision_mask = 1
	gravity_scale = 0.8
	continuous_cd = true
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 1
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.5
	mat.friction = 0.8
	physics_material_override = mat
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.11
	shape.shape = sphere
	add_child(shape)


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.26
	mesh.mesh = cyl
	mesh.rotation.z = deg_to_rad(90)
	var m := StandardMaterial3D.new()
	var pipe := kind == WeaponStats.Kind.PIPEBOMB_LAUNCHER
	var team_color: Color = PlayerClasses.TEAM_COLORS[shooter.team] if is_instance_valid(shooter) else Color(0.4, 0.4, 0.4)
	m.albedo_color = team_color.darkened(0.3) if pipe else Color(0.2, 0.22, 0.3)
	if pipe:
		m.emission_enabled = true
		m.emission = team_color
		m.emission_energy_multiplier = 0.0   # Lights up once armed.
		_glow = m
	mesh.material_override = m
	add_child(mesh)
	body_entered.connect(func(_b): bounced = true)


func is_armed() -> bool:
	return age >= WeaponStats.get_stat(kind, "arm_time")


func _physics_process(delta: float) -> void:
	age += delta
	if _glow and _glow.emission_energy_multiplier == 0.0 and is_armed():
		_glow.emission_energy_multiplier = 0.6
	if not is_real:
		return
	if not is_instance_valid(shooter):
		Game.instance.announce_explosion(net_id, Grenade.Type.FRAG, global_position, 0.0)
		queue_free()
		return
	if kind == WeaponStats.Kind.GRENADE_LAUNCHER:
		fuse_left -= delta
		if fuse_left <= 0.0 or (not bounced and _touching_enemy()):
			explode()


func _touching_enemy() -> bool:
	for p: Player in get_tree().get_nodes_in_group("player"):
		if p.alive and p.team != shooter.team and p.center().distance_to(global_position) < Player.HULL_RADIUS + 0.5:
			return true
	return false


## Server only.
func explode() -> void:
	if is_queued_for_deletion():
		return
	var d: Dictionary = WeaponStats.DATA[kind]
	Game.instance.announce_explosion(net_id, Grenade.Type.FRAG, global_position, d.radius)
	Explosions.radial(get_tree(), global_position, d.damage, d.radius, d.knockback, shooter, d.self_scale,
		1.0, WeaponStats.icon(kind))
	queue_free()
