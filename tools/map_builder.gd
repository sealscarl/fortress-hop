@tool
class_name MapBuilder
extends RefCounted
## Turns a Quake/QWTF .map from maps/source/ into a Godot scene with
## func_godot, using our dev textures. Run it from the editor with
## tools/build_maps.gd (Script editor → File → Run), or headless.
##
##   maps/source/<name>.map   →   maps/<name>/<name>_geometry.scn
##
## What it does:
## - 32 Quake units = 1 m (the same scale as our movement code).
## - Every texture becomes the world-space grid dev texture, team-tinted
##   toward each base. Original texture names are kept in the .map, so new
##   textures can replace them one by one later (see maps/<name>/textures.md).
## - Special Quake textures: SKIP = not drawn; clip = invisible wall; sky =
##   sky-colored; liquids (*name) = see-through and not solid; ~lights glow.
## - QWTF entities (spawns, flags, goals, buttons, lifts, lights...) become
##   markers with all their original settings, for maps/map_logic.gd to read.

const SOURCE_DIR := "res://maps/source/"
const MAT_DIR := "res://maps/materials/"

## Point entities kept as markers with their settings (map_logic reads them).
const POINT_CLASSES := ["info_player_teamspawn", "info_player_start", "item_tfgoal", "info_tfgoal",
	"info_tfdetect", "info_intermission", "light", "info_notnull", "trigger_relay"]
## Brush entities that move or can be touched: own nodes with collision.
const SOLID_CLASSES := ["func_button", "func_plat", "func_door", "func_train", "func_wall"]


static func build(map_name: String) -> Error:
	var src := SOURCE_DIR + map_name + ".map"
	if not FileAccess.file_exists(src):
		push_error("MapBuilder: no %s" % src)
		return ERR_FILE_NOT_FOUND
	var out_dir := "res://maps/%s/" % map_name
	DirAccess.make_dir_recursive_absolute(out_dir)
	_ensure_materials()

	# Liquids out of the world so they don't collide.
	var prepared := out_dir + ".build_" + map_name + ".map"
	var report := _prepare_map(src, prepared)
	write_special_materials(report.textures.keys())
	_write_texture_report(out_dir + "textures.md", map_name, report)

	var settings := FuncGodotMapSettings.new()
	settings.inverse_scale_factor = 32.0
	settings.entity_fgd = _make_fgd()
	settings.base_texture_dir = "res://maps/textures"
	settings.base_material_dir = MAT_DIR
	settings.default_material = load(MAT_DIR + "dev_grid.tres")
	settings.save_generated_materials = false
	settings.clip_texture = "clip"
	settings.skip_texture = "skip"

	var map := FuncGodotMap.new()
	map.name = "Geometry"
	map.local_map_file = prepared
	map.map_settings = settings
	var ok := [true]
	map.build_failed.connect(func(): ok[0] = false)
	map.build()
	if not ok[0] or map.get_child_count() == 0:
		push_error("MapBuilder: func_godot build failed for %s" % map_name)
		map.free()
		return FAILED

	# Point the saved scene at the real source (not the temp copy), so the
	# editor's own "Build Map" button still finds it.
	map.local_map_file = src
	var packed := PackedScene.new()
	var err := packed.pack(map)
	map.free()
	if err != OK:
		return err
	err = ResourceSaver.save(packed, out_dir + map_name + "_geometry.scn")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prepared))
	print("MapBuilder: built %s (%d textures, %d liquid brushes)" % [map_name, report.textures.size(), report.liquids])
	return err


# --- .map preprocessing -----------------------------------------------------------

## Copies the .map, moving liquid brushes (texture starting with *) out of
## worldspawn into a non-solid func_liquid entity. Returns texture counts.
static func _prepare_map(src: String, dst: String) -> Dictionary:
	# Quake's "gold" text uses bytes 128-255 (same letters + 128): fold them
	# back to plain ASCII so messages read normally.
	var bytes := FileAccess.get_file_as_bytes(src)
	for i in bytes.size():
		if bytes[i] >= 128:
			bytes[i] = bytes[i] & 127
	var text := bytes.get_string_from_ascii().replace("\r", "")
	var textures := {}
	var lines := text.split("\n")
	var out := PackedStringArray()
	var liquid_brushes := PackedStringArray()
	var depth := 0
	var entity_index := -1
	var brush := PackedStringArray()
	var brush_is_liquid := false
	for line in lines:
		var s := line.strip_edges()
		if s == "{":
			depth += 1
			if depth == 1:
				entity_index += 1
			elif depth == 2:
				brush = PackedStringArray([line])
				brush_is_liquid = false
				continue
		elif s == "}":
			depth -= 1
			if depth == 1:
				brush.append(line)
				if entity_index == 0 and brush_is_liquid:
					liquid_brushes.append("\n".join(brush))
				else:
					out.append("\n".join(brush))
				continue
		elif depth == 2:
			brush.append(line)
			if s.begins_with("("):
				var tex := _face_texture(s)
				textures[tex] = textures.get(tex, 0) + 1
				if tex.begins_with("*"):
					brush_is_liquid = true
			continue
		out.append(line)
	if liquid_brushes.size():
		out.append('{\n"classname" "func_liquid"\n' + "\n".join(liquid_brushes) + "\n}")
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	return {"textures": textures, "liquids": liquid_brushes.size()}


static func _face_texture(face_line: String) -> String:
	# ( x y z ) ( x y z ) ( x y z ) TEXTURE ...
	var after := face_line.substr(face_line.rfind(")") + 1).strip_edges()
	return after.get_slice(" ", 0)


static func _write_texture_report(path: String, map_name: String, report: Dictionary) -> void:
	var tex: Dictionary = report.textures
	var names := tex.keys()
	names.sort_custom(func(a, b): return tex[a] > tex[b])
	var md := "# %s: texture names\n\nEvery texture name in the source map and how many faces use it. All are drawn with the dev grid for now; to give one a real texture later, add `maps/materials/<name>.tres`.\n\n| Texture | Faces | Drawn as |\n| --- | --- | --- |\n" % map_name
	for n in names:
		md += "| `%s` | %d | %s |\n" % [n, tex[n], _drawn_as(n)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(md)
	f.close()


static func _drawn_as(n: String) -> String:
	var l := n.to_lower()
	if l == "skip": return "not drawn"
	if l == "clip": return "invisible wall"
	if l.begins_with("sky"): return "sky"
	if l.begins_with("*"): return "liquid (not solid)"
	if l.begins_with("~") or l.begins_with("light"): return "glowing grid"
	return "dev grid"


# --- Materials and entity definitions -------------------------------------------

## Writes the dev materials once. Special textures get their own material
## files named after the texture, which func_godot picks up by name.
static func _ensure_materials() -> void:
	DirAccess.make_dir_recursive_absolute(MAT_DIR)
	var grid: Shader = load("res://shaders/grid.gdshader")
	if not ResourceLoader.exists(MAT_DIR + "dev_grid.tres"):
		var m := ShaderMaterial.new()
		m.shader = grid
		ResourceSaver.save(m, MAT_DIR + "dev_grid.tres")


static func _special_material(name: String) -> Material:
	var l := name.to_lower()
	if l.begins_with("sky"):
		var sky := StandardMaterial3D.new()
		sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sky.albedo_color = Color(0.55, 0.7, 0.9)
		return sky
	if l.begins_with("*"):
		var water := StandardMaterial3D.new()
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.albedo_color = Color(0.2, 0.45, 0.6, 0.45)
		water.roughness = 0.1
		water.cull_mode = BaseMaterial3D.CULL_DISABLED
		return water
	if l.begins_with("~") or l.begins_with("light"):
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.95, 0.8)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.92, 0.75)
		glow.emission_energy_multiplier = 1.5
		return glow
	if l.begins_with("+") and "button" in l:
		var btn := StandardMaterial3D.new()
		btn.albedo_color = Color(0.9, 0.75, 0.1)
		btn.emission_enabled = true
		btn.emission = Color(0.9, 0.6, 0.05)
		btn.emission_energy_multiplier = 0.6
		return btn
	return null


static func write_special_materials(texture_names: Array) -> void:
	for n in texture_names:
		var m := _special_material(n)
		if m:
			ResourceSaver.save(m, MAT_DIR + str(n).replace("*", "") + ".tres")


static func _make_fgd() -> FuncGodotFGDFile:
	var fgd := FuncGodotFGDFile.new()
	fgd.fgd_name = "FortressHop"
	var defs: Array[Resource] = []
	defs.append(load("res://addons/func_godot/fgd/worldspawn.tres"))
	for cn in POINT_CLASSES:
		var p := FuncGodotFGDPointClass.new()
		p.classname = cn
		p.node_class = "Marker3D"
		p.add_properties_to_metadata = true
		p.apply_rotation_on_map_build = false   # map_logic reads "angle" itself.
		defs.append(p)
	for cn in SOLID_CLASSES:
		var s := FuncGodotFGDSolidClass.new()
		s.classname = cn
		s.spawn_type = FuncGodotFGDSolidClass.SpawnType.ENTITY
		s.origin_type = FuncGodotFGDSolidClass.OriginType.BOUNDS_CENTER
		s.node_class = "AnimatableBody3D"
		s.collision_shape_type = FuncGodotFGDSolidClass.CollisionShapeType.CONVEX
		s.add_properties_to_metadata = true
		defs.append(s)
	var liquid := FuncGodotFGDSolidClass.new()
	liquid.classname = "func_liquid"
	liquid.spawn_type = FuncGodotFGDSolidClass.SpawnType.ENTITY
	liquid.node_class = "Node3D"
	liquid.collision_shape_type = FuncGodotFGDSolidClass.CollisionShapeType.NONE
	liquid.shadow_casting_setting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	defs.append(liquid)
	fgd.entity_definitions = defs
	return fgd
