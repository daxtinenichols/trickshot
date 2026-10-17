shader_type canvas_item;
// Streaks rushing in from the screen edges at high speed. `intensity` 0..1
// comes from how far above run speed the player is; `tint` follows the same
// blue -> yellow -> red speed colors as the motion trails.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float aspect = 1.777;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float lanes = 140.0;
	float lane = floor((ang / TAU + 0.5) * lanes);
	float rnd = hash(lane);
	// Each lane has a streak that slides inward at its own speed.
	float t = fract(TIME * (0.8 + rnd * 1.6) + rnd * 7.0);
	float head = mix(1.1, 0.35, t);
	float streak = smoothstep(head - 0.18 - rnd * 0.15, head, r) * (1.0 - smoothstep(head, head + 0.02, r));
	float thin = 1.0 - abs(fract((ang / TAU + 0.5) * lanes) - 0.5) * 2.0;
	streak *= smoothstep(0.55, 1.0, thin) * step(0.55, rnd);
	float edge = smoothstep(0.32, 0.75, r);
	COLOR = vec4(mix(vec3(1.0), tint.rgb, 0.5), streak * edge * intensity * 0.55);
}
