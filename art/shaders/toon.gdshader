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

uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.82, 1.0);
uniform bool use_vertex_color = false;
// Light band thresholds on N.L (after shadows) and their softness.
uniform float band_high = 0.55;
uniform float band_low = 0.08;
uniform float band_soft = 0.03;
// How bright the middle band is, between shadow (0) and full light (1).
uniform float mid_level = 0.55;
// Rim light reads well on characters but makes flat floors glow at grazing
// angles, so it is off unless a material turns it on.
uniform float rim_strength = 0.0;
uniform float rim_width = 0.28;
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

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float hi = smoothstep(band_high - band_soft, band_high + band_soft, ndl);
	float lo = smoothstep(band_low - band_soft, band_low + band_soft, ndl);
	// Shadows are their own hard band, so soft shadow edges and the shadow
	// fade-out distance don't smear the bands.
	float lit = smoothstep(0.15, 0.35, ATTENUATION);
	float level = mix(lo * mid_level, 1.0, hi) * lit;
	// Unlit areas get the tint via ambient (environment); lit areas add on top.
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * level;
	// Rim: thin bright edge on the side facing the light.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_mask = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.04, rim) * smoothstep(-0.1, 0.3, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * rim_mask * rim_strength * lit;
}
