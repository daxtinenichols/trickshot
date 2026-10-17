shader_type spatial;
// Cel muzzle flash: a hard-edged spiky star (front view) or a flame petal
// (side view), white-hot core banding out to orange. Unshaded and additive,
// drawn on quads; `seed` changes the spikes every shot.

render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.82, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
uniform vec4 edge_color : source_color = vec4(0.95, 0.36, 0.10, 1.0);
// 0 = star (looking down the barrel), 1 = petal (from the side, the barrel
// along +V: the flame shoots toward v = 1).
uniform int shape = 0;
uniform float seed = 0.0;
// 1 at the shot, fading to 0: the flash shrinks and cools as it dies.
uniform float life = 1.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r;
	float reach;
	if (shape == 0) {
		float a = atan(p.y, p.x) / TAU + 0.5;
		// 7 spikes of random length.
		float k = a * 7.0;
		float i = floor(k);
		float f = fract(k);
		float spike = mix(0.45, 1.0, hash(i));
		float tri = 1.0 - abs(f - 0.5) * 2.0;
		reach = 0.18 + 0.32 * spike * pow(tri, 2.5);
		r = length(p);
	} else {
		// Petal: wide at the muzzle (v = 0), tapering to a point, with a
		// ragged edge.
		float v = UV.y;
		float width = 0.5 * (1.0 - v) * (0.55 + 0.45 * sin(v * 3.1416));
		width *= 0.8 + 0.2 * hash(floor(v * 6.0));
		reach = max(width, 0.001);
		r = abs(p.x);
		if (v < 0.02) {
			discard;
		}
	}
	reach *= mix(0.55, 1.0, life);
	float t = r / reach;
	if (t > 1.0) {
		discard;
	}
	// Three hard bands, like the cel lighting.
	vec3 col = t < 0.38 ? core_color.rgb : (t < 0.72 ? mid_color.rgb : edge_color.rgb);
	col = mix(col, edge_color.rgb, (1.0 - life) * 0.6);
	ALBEDO = col * (0.6 + 0.6 * life);
}
