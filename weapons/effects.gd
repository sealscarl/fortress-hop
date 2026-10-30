class_name Effects
extends RefCounted
## Explosion and rocket-trail visuals (particles). Everything is made in code:
## the soft puff texture is generated once, no image files.
##
## - explosion(): rockets, frag grenades, Demoman grenades and pipes. A white
##   flash, a rolling fireball, sparks thrown out with gravity, dark smoke
##   that rises and spreads for a couple of seconds, and a flickering light.
## - concussion(): conc grenades. Not fire: a quick blue flash and a
##   shockwave ring that spreads to the blast radius.
## - rocket_trail(): a hot exhaust flame plus a smoke trail that hangs in the
##   air and fades after the rocket has gone.
## Sizes scale with the blast radius (rocket 5 m).

static var _puff: Texture2D
static var _spark: Texture2D
static var _ring: Texture2D


## Soft round smoke/fire puff, with some lumpy noise so it doesn't look like a
## perfect circle.
static func puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var size := 64
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size / 2.0 + 0.5, y - size / 2.0 + 0.5).length() / (size / 2.0)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.4) * lerpf(0.55, 1.0, n)
			var shade := lerpf(0.75, 1.0, n)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	_puff = ImageTexture.create_from_image(img)
	return _puff


## Small bright dot with a soft edge (sparks, flame core).
static func spark_texture() -> Texture2D:
	if _spark:
		return _spark
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.8))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	_spark = t
	return _spark


## Thin glowing ring (conc shockwave).
static func ring_texture() -> Texture2D:
	if _ring:
		return _ring
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.72, 0.86, 0.94, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	_ring = t
	return _ring


static func _ramp(stops: Array) -> GradientTexture1D:
	## stops: [[offset, Color], ...]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 4.0   # (Curves stop at 1 by default.)
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


## Billboard particle material. additive = glowing fire/sparks; otherwise
## alpha-blended (smoke). lit smoke picks up the map's light and shadow.
static func _draw_mat(tex: Texture2D, additive: bool, lit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


static func _particles(amount: int, lifetime: float, size: float, tex: Texture2D, additive: bool, lit := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 18, 24))
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _draw_mat(tex, additive, lit)
	p.draw_pass_1 = q
	return p


## Adds a one-shot particle burst at origin and frees it when it's done.
static func _burst(scene: Node, p: GPUParticles3D, origin: Vector3) -> void:
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	scene.add_child(p)
	p.global_position = origin
	p.emitting = true
	p.finished.connect(p.queue_free)


static func explosion(scene: Node, origin: Vector3, radius: float) -> void:
	var s := clampf(radius / 5.0, 0.4, 1.6)   # Size relative to a rocket.

	# 1. Flash: one big white-yellow pop, gone in a tenth of a second.
	var flash := _particles(1, 0.12, 4.0 * s, spark_texture(), true)
	var fm := ParticleProcessMaterial.new()
	fm.gravity = Vector3.ZERO
	fm.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.8, 1.0)], [1.0, Color(1.0, 0.7, 0.3, 0.0)]])
	fm.scale_curve = _curve([Vector2(0, 0.6), Vector2(1, 1.3)])
	flash.process_material = fm
	_burst(scene, flash, origin)

	# 2. Fireball: puffs pushed out from the center, white-hot to orange to
	#    dark red to soot, growing as they cool.
	var fire := _particles(26, 0.7, 2.3 * s, puff_texture(), false)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5 * s
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0 * s
	pm.initial_velocity_max = 9.0 * s
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.gravity = Vector3(0, 1.5, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 0.45), Vector2(0.35, 1.0), Vector2(1, 1.25)])
	pm.color_ramp = _ramp([
		[0.0, Color(1.0, 0.92, 0.6, 1.0)], [0.12, Color(1.0, 0.62, 0.18, 1.0)],
		[0.35, Color(0.9, 0.32, 0.06, 0.9)], [0.65, Color(0.35, 0.12, 0.05, 0.7)],
		[1.0, Color(0.12, 0.1, 0.09, 0.0)]])
	fire.process_material = pm
	_burst(scene, fire, origin)

	# 3. Sparks: small hot bits thrown out fast; gravity brings them down.
	var sparks := _particles(28, 0.8, 0.09 * s, spark_texture(), true)
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3.UP
	sm.spread = 180.0
	sm.initial_velocity_min = 7.0 * s
	sm.initial_velocity_max = 16.0 * s
	sm.gravity = Vector3(0, -14, 0)
	sm.damping_min = 1.0
	sm.damping_max = 3.0
	sm.lifetime_randomness = 0.5
	sm.color_ramp = _ramp([[0.0, Color(1.0, 0.9, 0.6, 1.0)], [0.6, Color(1.0, 0.5, 0.1, 1.0)], [1.0, Color(0.8, 0.2, 0.0, 0.0)]])
	sparks.process_material = sm
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	(sparks.draw_pass_1 as QuadMesh).size = Vector2(0.06, 0.35) * s
	(sparks.draw_pass_1 as QuadMesh).material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_burst(scene, sparks, origin)

	# 4. Smoke: starts a moment later, dark, rises and spreads, then thins out.
	var smoke := _particles(20, 3.2, 2.8 * s, puff_texture(), false, true)
	var km := ParticleProcessMaterial.new()
	km.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	km.emission_sphere_radius = 0.6 * s
	km.direction = Vector3.UP
	km.spread = 70.0
	km.initial_velocity_min = 0.6
	km.initial_velocity_max = 2.6 * s
	km.damping_min = 0.6
	km.damping_max = 1.2
	km.gravity = Vector3(0, 0.55, 0)
	km.angle_min = -180.0
	km.angle_max = 180.0
	km.angular_velocity_min = -25.0
	km.angular_velocity_max = 25.0
	km.lifetime_randomness = 0.35
	km.scale_min = 0.8
	km.scale_max = 1.3
	km.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.6)])
	km.color_ramp = _ramp([
		[0.0, Color(0.12, 0.1, 0.09, 0.0)], [0.08, Color(0.14, 0.12, 0.11, 0.9)],
		[0.45, Color(0.24, 0.23, 0.22, 0.6)], [1.0, Color(0.35, 0.35, 0.35, 0.0)]])
	smoke.process_material = km
	_burst(scene, smoke, origin)
	smoke.explosiveness = 0.8

	# 5. Light: bright orange that flickers down over ~0.4 s.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 9.0
	light.omni_range = radius * 1.8
	light.shadow_enabled = false
	scene.add_child(light)
	light.global_position = origin
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 4.0, 0.06)
	tw.tween_property(light, "light_energy", 6.0, 0.05)
	tw.tween_property(light, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)


static func concussion(scene: Node, origin: Vector3, radius: float) -> void:
	var color := Color(0.55, 0.8, 1.0)
	var flash := _particles(1, 0.15, 2.0, spark_texture(), true)
	var fm := ParticleProcessMaterial.new()
	fm.gravity = Vector3.ZERO
	fm.color_ramp = _ramp([[0.0, Color(0.9, 0.97, 1.0, 1.0)], [1.0, Color(color, 0.0)]])
	flash.process_material = fm
	_burst(scene, flash, origin)

	# Shockwave: a glowing ring that faces you, spreading to the blast radius.
	var ring := _particles(1, 0.35, radius * 2.0, ring_texture(), true)
	var rm := ParticleProcessMaterial.new()
	rm.gravity = Vector3.ZERO
	rm.scale_curve = _curve([Vector2(0, 0.1), Vector2(1, 1.0)])
	rm.color_ramp = _ramp([[0.0, Color(color, 0.9)], [1.0, Color(color, 0.0)]])
	ring.process_material = rm
	_burst(scene, ring, origin)

	# A light puff of dust.
	var dust := _particles(10, 1.0, 1.4, puff_texture(), false, true)
	var dm := ParticleProcessMaterial.new()
	dm.direction = Vector3.UP
	dm.spread = 180.0
	dm.initial_velocity_min = 2.0
	dm.initial_velocity_max = 4.0
	dm.damping_min = 4.0
	dm.damping_max = 6.0
	dm.gravity = Vector3(0, 0.3, 0)
	dm.angle_min = -180.0
	dm.angle_max = 180.0
	dm.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.4)])
	dm.color_ramp = _ramp([[0.0, Color(0.7, 0.75, 0.8, 0.0)], [0.15, Color(0.7, 0.75, 0.8, 0.35)], [1.0, Color(0.7, 0.75, 0.8, 0.0)]])
	dust.process_material = dm
	_burst(scene, dust, origin)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = radius * 1.5
	scene.add_child(light)
	light.global_position = origin
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.tween_callback(light.queue_free)


## Rocket exhaust. Adds the flame to the rocket and returns the smoke trail,
## which the rocket adds to the world (so puffs stay where they were left)
## and moves along with itself; when the rocket is gone the trail stops and
## fades out.
static func rocket_trail(rocket: Node3D) -> GPUParticles3D:
	# Smoke trail: puffs left behind in the air, grey, spreading and fading.
	var smoke := _particles(320, 2.0, 0.45, puff_texture(), false, true)
	var m := ParticleProcessMaterial.new()
	# A thin box the rocket stretches each frame over the distance it just
	# flew, so the trail is continuous at any frame rate.
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.04, 0.04, 0.1)
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.5
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.gravity = Vector3(0, 0.35, 0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -40.0
	m.angular_velocity_max = 40.0
	m.lifetime_randomness = 0.3
	m.scale_curve = _curve([Vector2(0, 0.6), Vector2(1, 3.2)])
	m.color_ramp = _ramp([
		[0.0, Color(1.0, 0.75, 0.45, 1.0)], [0.05, Color(0.5, 0.48, 0.46, 0.9)],
		[0.4, Color(0.42, 0.42, 0.42, 0.6)], [1.0, Color(0.5, 0.5, 0.5, 0.0)]])
	smoke.process_material = m
	smoke.local_coords = false
	smoke.fixed_fps = 0
	smoke.interpolate = false
	smoke.name = "RocketSmoke"

	# Flame: a bright flickering core at the back of the rocket.
	var flame := _particles(12, 0.08, 0.32, spark_texture(), true)
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, 0, 1)
	fm.spread = 8.0
	fm.initial_velocity_min = 1.0
	fm.initial_velocity_max = 2.5
	fm.gravity = Vector3.ZERO
	fm.scale_min = 0.6
	fm.scale_max = 1.1
	fm.scale_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.3)])
	fm.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.75, 1.0)], [0.5, Color(1.0, 0.6, 0.2, 0.8)], [1.0, Color(1.0, 0.3, 0.05, 0.0)]])
	flame.process_material = fm
	flame.local_coords = true
	rocket.add_child(flame)
	flame.position = Vector3(0, 0, 0.24)
	return smoke
