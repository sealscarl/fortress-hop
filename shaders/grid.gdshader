// World-space grid for grey-box maps: thin lines every 1 m, bold every 4 m.
// Lets you judge speed and distance while testing movement.
// Optional team tint: surfaces toward red_center turn reddish, toward
// blue_center bluish, so you always know whose half you're in.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.45, 0.47, 0.5);
uniform vec3 line_color : source_color = vec3(0.25, 0.26, 0.28);
uniform vec3 major_color : source_color = vec3(0.9, 0.55, 0.15);
uniform float tint_strength = 0.0;
uniform vec3 red_center = vec3(0.0);
uniform vec3 blue_center = vec3(0.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(width) - fw, vec2(width) + fw, g);
	return max(l.x, l.y);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	float minor = grid(p, 1.0, 0.02);
	float major = grid(p, 4.0, 0.04);
	vec3 base = base_color;
	if (tint_strength > 0.0) {
		// -1 at the red center, +1 at the blue center, measured along the line between them.
		vec3 axis = blue_center - red_center;
		float t = dot(world_pos - (red_center + blue_center) * 0.5, axis) / (0.5 * dot(axis, axis));
		float side = smoothstep(0.15, 0.6, abs(t));
		vec3 team = t < 0.0 ? vec3(0.62, 0.38, 0.36) : vec3(0.36, 0.44, 0.62);
		base = mix(base, team, side * tint_strength);
	}
	vec3 c = mix(base, line_color, minor);
	c = mix(c, major_color, major);
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
