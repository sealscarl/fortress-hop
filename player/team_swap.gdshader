shader_type spatial;
// Player model material with a team color swap. The models are made red;
// for Blue, strongly red parts of the texture (uniform, trim, markings) are
// turned the same shade of blue, keeping all their shading and detail.
// Skin, olive gear, metal and other colors are left alone (they're either
// not red or not saturated enough). Everything else is a normal PBR material
// (the glTF's color, roughness/metal and normal textures).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;   // G roughness, B metal
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_orm = false;
uniform bool has_normal = false;

uniform float swap : hint_range(0.0, 1.0) = 0.0;    // 0 = red as made, 1 = blue
uniform float target_hue : hint_range(0.0, 1.0) = 0.6;   // Blue
uniform float hue_width = 0.075;     // How far from pure red still counts as red.
uniform float sat_min = 0.4;         // Below this saturation: never swapped (skin).
uniform float sat_full = 0.55;       // Above this: fully swapped.
uniform float value_boost = 1.12;    // Blue reads darker than red; lift it a little.

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 lin = texture(albedo_tex, UV).rgb;
	vec3 col = lin;
	if (swap > 0.0) {
		vec3 srgb = pow(lin, vec3(1.0 / 2.2));
		vec3 hsv = rgb2hsv(srgb);
		float hue_dist = min(hsv.x, 1.0 - hsv.x);   // Distance from red (hue 0).
		float w = (1.0 - smoothstep(hue_width * 0.6, hue_width, hue_dist))
			* smoothstep(sat_min, sat_full, hsv.y) * swap;
		vec3 blue = hsv2rgb(vec3(target_hue, hsv.y, min(hsv.z * value_boost, 1.0)));
		col = pow(mix(srgb, blue, w), vec3(2.2));
	}
	ALBEDO = col;
	if (has_orm) {
		vec4 orm = texture(orm_tex, UV);
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	} else {
		ROUGHNESS = 0.8;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
