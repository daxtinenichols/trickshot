shader_type spatial;
// Screen-space ink outlines, drawn by a full-screen quad in front of the
// camera (see ArtLook). Edges come from the depth buffer only, so they work
// on every mesh and in both the Forward+ and Compatibility renderers.
//
// The trick: 1/depth is linear across any flat surface on screen, so its
// second difference is ~0 on planes, and spikes at silhouettes (depth jumps)
// and at creases (where the plane changes). One measure catches both.

render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 line_color : source_color = vec4(0.06, 0.06, 0.1, 1.0);
// Line half-width in pixels at 1080p; scales with resolution.
uniform float thickness = 1.2;
// Edge sensitivity for creases (bigger = fewer lines).
uniform float crease_threshold = 0.012;
// Silhouette sensitivity: relative depth jump that counts as an outline.
uniform float silhouette_threshold = 0.04;
// Lines fade out between these distances (meters).
uniform float fade_start = 45.0;
uniform float fade_end = 110.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_texture, uv).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = thickness * max(VIEWPORT_SIZE.y / 1080.0, 1.0) / VIEWPORT_SIZE;
	float c = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float l = view_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = view_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float u = view_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d = view_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);

	// Silhouettes: the nearer side of a big relative depth jump draws the line,
	// so outlines sit on the object, not on whatever is behind it.
	float nearest = min(min(l, r), min(u, d));
	float far_jump = (max(max(l, r), max(u, d)) - c) / c;
	float sil = step(silhouette_threshold, far_jump) * step(c, nearest + 0.0001);

	// Creases: second difference of inverse depth, relative to the center.
	float ic = 1.0 / c;
	float lap = abs(1.0 / l + 1.0 / r - 2.0 * ic) + abs(1.0 / u + 1.0 / d - 2.0 * ic);
	float crease = smoothstep(crease_threshold, crease_threshold * 2.0, lap / ic);
	// Crease detection only inside one surface's neighborhood, not across gaps.
	crease *= 1.0 - step(silhouette_threshold, abs(far_jump));

	float edge = max(sil, crease);
	edge *= 1.0 - smoothstep(fade_start, fade_end, c);
	ALBEDO = line_color.rgb;
	ALPHA = edge * line_color.a;
}
