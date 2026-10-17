shader_type spatial;
// Cel shading for everything in the world: flat color, two hard light bands
// and a rim light. Shadows are tinted instead of black so scenes stay bright
// and readable at speed.
//
// Base color comes from `base_color`, times the mesh's vertex colors when
// `use_vertex_color` is on (the runner paints its regions that way).
// `grid_strength` > 0 overlays the graybox meter grid, used on blockout
// geometry so distances stay readable.

render_mode specular_disabled;

#include "res://art/shaders/toon_light.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.82, 1.0);
uniform bool use_vertex_color = false;
uniform float grid_strength = 0.0;

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
	vec3 col = base_color.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	if (grid_strength > 0.0) {
		vec3 n = abs(world_normal);
		vec2 uv = n.y > max(n.x, n.z) ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
		float lines = max(grid(uv, 1.0, 0.012) * 0.5, grid(uv, 4.0, 0.03));
		col = mix(col, col * 0.55, lines * grid_strength);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
