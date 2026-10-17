shader_type spatial;
// Flames for the burning tower: a camera-facing (around Y) quad with a
// flickering flame shape, added on top of the scene. Visual only.

render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.32, 0.06, 1.0);
uniform float speed = 1.6;
uniform float seed = 0.0;

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

void vertex() {
	// Turn to face the camera around the vertical axis.
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(0.0001));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + right * VERTEX.x * scale.x + vec3(0.0, 1.0, 0.0) * VERTEX.y * scale.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed + seed * 13.0;
	float y = 1.0 - uv.y;  // 0 at the base, 1 at the top
	// Wobble sideways more toward the top.
	float wobble = (vnoise(vec2(y * 3.0 - t * 1.3, seed)) - 0.5) * 0.35 * y;
	float x = abs(uv.x - 0.5 + wobble) * 2.0;
	// Flame body narrows upward; noise eats into the edges.
	float width = mix(0.95, 0.05, pow(y, 0.8));
	float n = vnoise(vec2(uv.x * 5.0, y * 4.0 - t * 2.5)) * 0.6 + vnoise(vec2(uv.x * 11.0, y * 9.0 - t * 4.0)) * 0.4;
	float body = smoothstep(width, width - 0.25, x + (n - 0.5) * 0.5);
	body *= smoothstep(0.0, 0.08, y);
	float core = smoothstep(width * 0.55, width * 0.2, x) * (1.0 - y);
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(core * 1.5, 0.0, 1.0));
	ALBEDO = col * body * 1.6;
	ALPHA = 1.0;
}
