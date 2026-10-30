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
