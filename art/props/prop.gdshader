shader_type spatial;
// Props from the prop kit (art/source/build_props.py): the mesh's vertex
// colors are the paint, cel lit like the rest of the world, with the same
// dust on top faces and grime low down that the wasteland surfaces get.
// Vertex alpha 0 marks parts that glow (lamps, radio dials).

render_mode specular_disabled;

#include "res://art/shaders/toon_light.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 dust_color : source_color = vec4(0.70, 0.63, 0.53, 1.0);
uniform float dust_amount = 0.22;
uniform float grime_amount = 0.25;
uniform float glow_energy = 2.5;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Hard-edged mask, anti-aliased by its screen rate.
float cut(float v, float edge) {
	float w = max(fwidth(v), 0.0005);
	return smoothstep(edge - w, edge + w, v);
}

void fragment() {
	vec3 col = COLOR.rgb * tint.rgb;
	bool glow = COLOR.a < 0.5;
	if (!glow) {
		vec3 n = normalize(world_normal);
		vec3 an = abs(n);
		vec2 uv = an.y > max(an.x, an.z) ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
		// Posterized blotches, so detail sits inside the cel bands.
		float blotch = floor(vnoise(uv * 2.3) * 3.0) / 2.0;
		col *= mix(0.9, 1.04, blotch);
		// Dust settles on faces that look up.
		float dust = cut(n.y + vnoise(uv * 4.0) * 0.5, 1.05) * dust_amount;
		col = mix(col, dust_color.rgb, dust);
		// Grime streaks low down on the sides.
		float low = 1.0 - clamp(local_pos.y / 0.8, 0.0, 1.0);
		float streak = cut(vnoise(vec2(uv.x * 6.0, uv.y * 0.6)), 0.55);
		col *= 1.0 - grime_amount * low * (0.5 + 0.5 * streak) * (1.0 - an.y);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (glow) {
		EMISSION = col * glow_energy;
	}
}
