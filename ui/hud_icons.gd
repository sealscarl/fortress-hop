class_name HudIcons
## Placeholder HUD icons, drawn in code (no image files): a team flag and a
## security button. Drawn large and scaled down, so the edges come out smooth.

const SIZE := 96   ## Drawing size; the texture is half this.

static var _cache := {}


## A flag on a pole, waving, in the team color.
static func flag(color: Color) -> Texture2D:
	var key := "flag" + color.to_html()
	if not _cache.has(key):
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var outline := color.darkened(0.55)
		# Pennant: a wavy band from the pole to the right.
		for x in range(20, 88):
			var u := (x - 20) / 68.0
			var top := 12.0 + 5.0 * sin(u * TAU)
			var height := 42.0 - u * 6.0
			for y in range(int(top) - 2, int(top + height) + 3):
				if y < 0 or y >= SIZE:
					continue
				var inside := y >= top and y <= top + height and x < 86
				var shade := color.lerp(color.darkened(0.25), (y - top) / height)
				shade = shade.lightened(0.12 * (0.5 + 0.5 * sin(u * TAU + 1.2)))
				img.set_pixel(x, y, shade if inside else outline)
		# Pole and knob.
		_rect(img, 13, 6, 8, 86, Color(0.2, 0.2, 0.22))
		_rect(img, 15, 6, 4, 86, Color(0.88, 0.88, 0.9))
		_circle(img, 17, 7, 6, Color(0.2, 0.2, 0.22))
		_circle(img, 17, 7, 4, Color(0.95, 0.8, 0.3))
		_cache[key] = _finish(img)
	return _cache[key]


## A round push button on a base plate, in the team color.
static func button(color: Color) -> Texture2D:
	var key := "button" + color.to_html()
	if not _cache.has(key):
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		# Base plate.
		_round_rect(img, 6, 58, 84, 30, 8, Color(0.12, 0.12, 0.14))
		_round_rect(img, 9, 60, 78, 25, 6, Color(0.32, 0.33, 0.36))
		_rect(img, 12, 62, 72, 3, Color(0.45, 0.46, 0.5))
		# Dome: outline, then shaded fill with a highlight up and to the left.
		var c := Vector2(48, 60)
		for y in range(20, 64):
			for x in range(10, 87):
				var d := Vector2((x - c.x) / 36.0, (y - c.y) / 38.0)
				var r := d.length()
				if y > 62 or r > 1.0:
					continue
				var col := color.darkened(0.6)
				if r < 0.92:
					var light := clampf(1.0 - Vector2(d.x + 0.35, d.y + 0.55).length(), 0.0, 1.0)
					col = color.darkened(0.2 * r).lerp(color.lightened(0.6), light * 0.8)
				img.set_pixel(x, y, col)
		_cache[key] = _finish(img)
	return _cache[key]


static func _finish(img: Image) -> Texture2D:
	img.resize(SIZE >> 1, SIZE >> 1, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), col)


static func _circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < SIZE and y < SIZE and Vector2(x - cx, y - cy).length() <= r:
				img.set_pixel(x, y, col)


static func _round_rect(img: Image, x: int, y: int, w: int, h: int, r: int, col: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			var dx := maxi(maxi(x + r - px, px - (x + w - 1 - r)), 0)
			var dy := maxi(maxi(y + r - py, py - (y + h - 1 - r)), 0)
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(px, py, col)


# --- Kill feed weapon icons -------------------------------------------------------
# Drawn on a 192 x 96 grid as polygons, each with a dark outline, then shrunk to
# 64 x 32. Keys: rocket, shotgun, nailgun, supernail, gl, pipe, frag, medkit,
# laser, skull.

const W_W := 192
const W_H := 96
const W_SCALE := 2.0 / 3.0   ## Drawing canvas is 128 x 64 (2/3 of the grid).
const LIGHT := Color(0.93, 0.93, 0.9)
const DARK := Color(0.07, 0.07, 0.08)


static func weapon(key: String) -> Texture2D:
	var ck := "w_" + key
	if _cache.has(ck):
		return _cache[ck]
	var shapes := _weapon_shapes(key)   # [[polygon, color, outlined], ...]
	var img := Image.create(int(W_W * W_SCALE), int(W_H * W_SCALE), false, Image.FORMAT_RGBA8)
	for s in shapes:
		if s[2]:
			_fill(img, Geometry2D.offset_polygon(s[0], 4.5)[0], DARK)
	for s in shapes:
		_fill(img, s[0], s[1])
	img.resize(64, 32, Image.INTERPOLATE_LANCZOS)
	_cache[ck] = ImageTexture.create_from_image(img)
	return _cache[ck]


static func _weapon_shapes(key: String) -> Array:
	var orange := Color(1.0, 0.55, 0.15)
	match key:
		"rocket":
			return [
				[_box(40, 40, 100, 16), LIGHT, true],
				[_poly([140, 40, 170, 48, 140, 56]), LIGHT, true],
				[_poly([40, 40, 60, 40, 40, 24]), LIGHT, true],
				[_poly([40, 56, 60, 56, 40, 72]), LIGHT, true],
				[_poly([40, 43, 40, 53, 14, 48]), orange, true],
			]
		"shotgun":
			return [
				[_poly([40, 38, 40, 56, 14, 68, 8, 52]), LIGHT, true],
				[_box(40, 36, 38, 20), LIGHT, true],
				[_box(76, 38, 102, 8), LIGHT, true],
				[_box(96, 47, 38, 9), LIGHT, true],
			]
		"nailgun", "supernail":
			var s := [
				[_box(44, 32, 86, 28), LIGHT, true],
				[_poly([62, 60, 84, 60, 76, 84, 56, 84]), LIGHT, true],
			]
			if key == "supernail":
				s.append([_box(130, 34, 50, 8), LIGHT, true])
				s.append([_box(130, 50, 50, 8), LIGHT, true])
			else:
				s.append([_box(130, 42, 46, 8), LIGHT, true])
			s.append([_circle_poly(88, 46, 9), DARK, false])
			return s
		"gl":
			return [
				[_box(18, 42, 48, 12), LIGHT, true],
				[_circle_poly(82, 48, 22), LIGHT, true],
				[_box(98, 36, 74, 24), LIGHT, true],
				[_circle_poly(82, 48, 7), DARK, false],
			]
		"pipe":
			return [
				[_box(56, 34, 80, 28), LIGHT, true],
				[_box(48, 30, 12, 36), LIGHT, true],
				[_box(132, 30, 12, 36), LIGHT, true],
				[_circle_poly(96, 48, 7), Color(0.35, 1.0, 0.45), false],
			]
		"frag":
			return [
				[_circle_poly(90, 56, 28), Color(0.55, 0.65, 0.4), true],
				[_poly([92, 26, 132, 20, 136, 28, 98, 34]), LIGHT, true],
				[_circle_poly(122, 14, 9), LIGHT, true],
				[_circle_poly(122, 14, 4), DARK, false],
				[_box(66, 50, 48, 4), DARK, false],
			]
		"medkit":
			return [
				[_box(84, 16, 24, 12), LIGHT, true],
				[_box(52, 26, 88, 50), LIGHT, true],
				[_box(88, 34, 16, 34), Color(0.85, 0.15, 0.15), false],
				[_box(72, 43, 48, 16), Color(0.85, 0.15, 0.15), false],
			]
		"laser":
			return [[_poly([62, 8, 116, 8, 94, 40, 136, 40, 62, 90, 80, 52, 46, 52]), Color(1.0, 0.85, 0.3), true]]
		_:   # skull: suicide, falls, the world
			return [
				[_circle_poly(96, 40, 30), LIGHT, true],
				[_box(76, 56, 40, 24), LIGHT, true],
				[_circle_poly(84, 40, 8), DARK, false],
				[_circle_poly(108, 40, 8), DARK, false],
				[_poly([96, 50, 91, 60, 101, 60]), DARK, false],
				[_box(88, 68, 3, 12), DARK, false],
				[_box(101, 68, 3, 12), DARK, false],
			]


static func _poly(xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		out.append(Vector2(xy[i], xy[i + 1]))
	return out


static func _box(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


static func _circle_poly(cx: float, cy: float, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 28:
		out.append(Vector2(cx, cy) + Vector2.from_angle(TAU * i / 28.0) * r)
	return out


## Fills a polygon given in grid coordinates (scaled onto the canvas).
static func _fill(img: Image, poly: PackedVector2Array, col: Color) -> void:
	var scaled := PackedVector2Array()
	for v in poly:
		scaled.append(v * W_SCALE)
	var r := Rect2(scaled[0], Vector2.ZERO)
	for v in scaled:
		r = r.expand(v)
	for y in range(maxi(int(r.position.y), 0), mini(int(r.end.y) + 1, img.get_height())):
		for x in range(maxi(int(r.position.x), 0), mini(int(r.end.x) + 1, img.get_width())):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), scaled):
				img.set_pixel(x, y, col)
