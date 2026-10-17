// Shared cel lighting for the toon shaders: two hard light bands, shadows as
// their own hard band, optional rim. Include after declaring nothing else
// named like these uniforms.

// Light band thresholds on N.L (after shadows) and their softness.
uniform float band_high = 0.55;
uniform float band_low = 0.08;
uniform float band_soft = 0.07;
// How bright the middle band is, between shadow (0) and full light (1).
uniform float mid_level = 0.55;
// Blend from pure bands (0) toward smooth Lambert light (1): a little keeps
// the stylized read while surfaces round off more naturally.
uniform float realism = 0.35;
// Rim light reads well on characters but makes flat floors glow at grazing
// angles, so it is off unless a material turns it on.
uniform float rim_strength = 0.0;
uniform float rim_width = 0.28;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float hi = smoothstep(band_high - band_soft, band_high + band_soft, ndl);
	float lo = smoothstep(band_low - band_soft, band_low + band_soft, ndl);
	// Shadows are their own hard band, so soft shadow edges and the shadow
	// fade-out distance don't smear the bands.
	float lit = smoothstep(0.1, 0.45, ATTENUATION);
	float bands = mix(lo * mid_level, 1.0, hi);
	float level = mix(bands, clamp(ndl, 0.0, 1.0), realism) * lit;
	// Unlit areas get the tint via ambient (environment); lit areas add on top.
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * level;
	// Rim: thin bright edge on the side facing the light.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_mask = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.04, rim) * smoothstep(-0.1, 0.3, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * rim_mask * rim_strength * lit;
}
