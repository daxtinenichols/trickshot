shader_type spatial;
// World-space grid for graybox geometry: thin lines every meter, bold lines
// every 4 m, so distances and heights can be read at a glance.

uniform vec4 base_color : source_color = vec4(0.72, 0.73, 0.77, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float line_strength = 0.18;
uniform float roughness_value = 0.85;

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
	vec2 uv = n.y > max(n.x, n.z) ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	float lines = max(grid(uv, 1.0, 0.012) * 0.5, grid(uv, 4.0, 0.03));
	vec3 col = mix(base_color.rgb, line_color.rgb, lines * line_strength);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
