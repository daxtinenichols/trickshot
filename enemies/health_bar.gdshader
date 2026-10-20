shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
// A small camera-facing health bar over an enemy's head.

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.35, 0.25, 1.0);
uniform vec4 back_color : source_color = vec4(0.05, 0.05, 0.07, 0.75);

void vertex() {
	// Billboard, keeping the mesh's own size.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 px = UV * vec2(80.0, 8.0);
	bool border = px.x < 1.0 || px.x > 79.0 || px.y < 1.0 || px.y > 7.0;
	vec4 c = (UV.x <= fill && !border) ? fill_color : back_color;
	ALBEDO = c.rgb;
	ALPHA = c.a * alpha;
}
