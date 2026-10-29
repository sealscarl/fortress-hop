class_name MapVisuals
## Code-built placeholder models for map objects: flags, flag stands, laser
## gates and supply packs. No external model files.

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 color : source_color;
uniform float glow = 0.6;
void vertex() {
	// Wave more toward the free end of the banner (UV.x = 1).
	float w = UV.x;
	VERTEX.z += sin(TIME * 5.0 + VERTEX.x * 6.0) * 0.08 * w;
	VERTEX.y += sin(TIME * 3.0 + VERTEX.x * 4.0) * 0.02 * w;
}
void fragment() {
	ALBEDO = color.rgb;
	EMISSION = color.rgb * glow;
	ROUGHNESS = 0.8;
}
"""


static func flag(team_color: Color) -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.03
	cyl.height = 1.8
	pole.mesh = cyl
	pole.position.y = 0.9
	pole.material_override = _mat(Color(0.8, 0.8, 0.82), 0.0)
	root.add_child(pole)
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	cap.mesh = sphere
	cap.position.y = 1.83
	cap.material_override = _mat(Color(0.95, 0.8, 0.3), 0.5)
	root.add_child(cap)
	var banner := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.9, 0.55)
	plane.subdivide_width = 12
	plane.subdivide_depth = 6
	plane.orientation = PlaneMesh.FACE_Z
	banner.mesh = plane
	banner.position = Vector3(0.47, 1.5, 0)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLAG_SHADER
	sm.shader = sh
	sm.set_shader_parameter("color", team_color)
	banner.material_override = sm
	root.add_child(banner)
	var light := OmniLight3D.new()
	light.light_color = team_color
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position.y = 1.4
	root.add_child(light)
	return root


## Glowing ring on the ground where a flag lives.
static func flag_stand(team_color: Color) -> Node3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.9
	ring.mesh = torus
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.03
	ring.material_override = _mat(team_color, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


## Capture point marker: a glowing square on the floor.
static func capture_pad(team_color: Color, size: Vector3) -> Node3D:
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.04, size.z)
	pad.mesh = box
	var m := _mat(team_color, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.5
	pad.material_override = m
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pad


## A laser gate filling an axis-aligned box: three bright beams along the
## box's long side, plus a faint sheet.
static func laser(box: AABB, team_color: Color) -> Node3D:
	var root := Node3D.new()
	var long_x := box.size.x >= box.size.z
	var length := box.size.x if long_x else box.size.z
	var beam_mat := _mat(team_color.lightened(0.3), 3.0)
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 3:
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.025
		cyl.height = length
		beam.mesh = cyl
		beam.rotation = Vector3(0, 0, deg_to_rad(90)) if long_x else Vector3(deg_to_rad(90), 0, 0)
		beam.position = box.get_center() + Vector3(0, (i - 1) * box.size.y * 0.3, 0)
		beam.material_override = beam_mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
	var sheet := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(box.size.x if long_x else 0.02, box.size.y, 0.02 if long_x else box.size.z)
	sheet.mesh = quad
	sheet.position = box.get_center()
	var sm := _mat(team_color, 0.5)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color.a = 0.12
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheet.material_override = sm
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sheet)
	var light := OmniLight3D.new()
	light.light_color = team_color
	light.light_energy = 1.0
	light.omni_range = maxf(length, 3.0)
	light.position = box.get_center()
	root.add_child(light)
	return root


## Supply pack: a small crate. Kind: "full" (white/green), "ammo" (olive),
## "grenades" (orange).
static func pack(kind: String) -> Node3D:
	var root := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.35, 0.35)
	box.mesh = bm
	var c := Color(0.85, 0.9, 0.85)
	if kind == "ammo": c = Color(0.45, 0.5, 0.25)
	elif kind == "grenades": c = Color(0.9, 0.5, 0.15)
	box.material_override = _mat(c, 0.25)
	box.position.y = 0.3
	root.add_child(box)
	var stripe := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.52, 0.08, 0.37)
	stripe.mesh = sb
	stripe.position.y = 0.3
	stripe.material_override = _mat(Color(0.2, 0.75, 0.3) if kind == "full" else c.darkened(0.4), 0.3)
	root.add_child(stripe)
	return root


static func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m
