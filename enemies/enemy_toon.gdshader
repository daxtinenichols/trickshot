shader_type spatial;
// Enemy bodies: the world's cel lighting (toon_light) on vertex-painted
// models, plus a white hit flash and the attack telegraph glow, so the
// "about to attack" read is the same as on the old placeholder bodies.
// `glow_part` marks the lit parts (eyes, lenses, visor strips): they stay
// bright in any light and flare with the telegraph.

render_mode specular_disabled;

#include "res://art/shaders/toon_light.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform float flash = 0.0;
uniform vec3 telegraph = vec3(0.0);
uniform bool glow_part = false;
uniform float glow_level = 1.5;

void fragment() {
	vec3 col = base_color.rgb * COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 e = vec3(flash) + telegraph * 0.3;
	if (glow_part) {
		e += col * (glow_level + length(telegraph) * 3.0);
	}
	EMISSION = e;
}
