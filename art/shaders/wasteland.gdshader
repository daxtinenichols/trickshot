shader_type spatial;
// Post-apocalyptic world surfaces, cel shaded. Procedural, world-space
// textures (no UVs, no image files): weathered concrete, rusted metal,
// cracked asphalt and worn paint, plus dust that settles on top faces and
// grime that streaks down walls. Texture detail is posterized into a few
// flat steps so it sits inside the cel bands instead of fighting them.
//
// `surface` picks the material:
//   0 plain   1 concrete   2 rusted metal   3 asphalt / ground
//   4 painted metal (the paint is base_color; chips show rust underneath)
//   5 painted concrete (chips show concrete)
//   6 building facade (concrete with a grid of dark, some broken, windows)
//   7 floor tiles (60 cm, grout, cracked and missing tiles)
//   8 brick (running bond, mortar, spalled bricks; base_color = brick)
//   9 corrugated sheet metal (vertical ribs, painted base_color over rust)
//   10 wood planks (boards with gaps and grain, base_color = timber)

render_mode specular_disabled;

#include "res://art/shaders/toon_light.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.72, 0.69, 0.64, 1.0);
uniform int surface = 1;
// Meters per texture tile (bigger = coarser detail).
uniform float tex_scale = 1.0;
// How much the texture darkens/lightens the base (0 = flat color).
uniform float tex_strength = 1.0;
uniform vec4 dust_color : source_color = vec4(0.70, 0.63, 0.53, 1.0);
uniform float dust_amount = 0.45;
uniform vec4 rust_color : source_color = vec4(0.52, 0.28, 0.16, 1.0);
uniform vec4 under_color : source_color = vec4(0.62, 0.6, 0.56, 1.0);
// Faint meter grid, kept from the blockout so distances still read.
uniform float grid_strength = 0.0;
// How dark concrete cracks are.
uniform float crack_strength = 0.4;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// ---------------------------------------------------------------- noise

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return v;
}

// Distance to the nearest Voronoi cell edge: thin lines = cracks.
float crack_lines(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

float grid(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(width) - fw, vec2(width) + fw, g);
	return max(l.x, l.y);
}

// A few flat steps, so detail reads as cel shapes, not noise.
float steps(float v, float n) {
	return floor(clamp(v, 0.0, 0.999) * n) / (n - 1.0);
}

// Hard-edged mask from a noise value, anti-aliased by its screen rate.
float cut(float v, float edge) {
	float w = max(fwidth(v), 0.0005);
	return smoothstep(edge - w, edge + w, v);
}

// ---------------------------------------------------------------- materials

vec3 concrete(vec2 p, vec3 col) {
	float blotch = steps(fbm(p * 0.35), 3.0);
	col *= mix(0.86, 1.04, blotch);
	// Aggregate speckle.
	float speck = cut(hash12(floor(p * 22.0)), 0.93);
	col *= 1.0 - speck * 0.12;
	// Cracks, only in some areas.
	float zone = cut(fbm(p * 0.18 + 5.0), 0.6);
	float c = 1.0 - cut(crack_lines(p * 0.9), 0.025);
	col *= 1.0 - c * zone * crack_strength;
	return col;
}

vec3 rusted(vec2 p, vec3 col, vec3 n) {
	// Panel seams every 1 m and rivets along them.
	float seam = grid(p, 1.0, 0.012);
	col *= 1.0 - seam * 0.35;
	vec2 cell = fract(p);
	vec2 rv = abs(cell - vec2(0.06));
	float rivet = 1.0 - cut(length(min(rv, abs(cell - vec2(0.94)))), 0.025);
	col *= 1.0 + rivet * 0.25;
	// Rust patches, worse toward the bottom of each panel.
	float r = fbm(p * 0.8 + 11.0) + (0.5 - cell.y) * 0.25;
	float rust = cut(r, 0.52);
	col = mix(col, rust_color.rgb * mix(0.9, 1.1, steps(fbm(p * 3.0), 3.0)), rust * 0.85);
	return col;
}

vec3 asphalt(vec2 p, vec3 col) {
	col *= mix(0.88, 1.02, steps(fbm(p * 0.25), 3.0));
	float c = 1.0 - cut(crack_lines(p * 0.35), 0.02);
	float zone = cut(fbm(p * 0.12 + 2.0), 0.58);
	col *= 1.0 - c * zone * 0.45;
	// Patched repairs: darker, newer rectangles of tar.
	vec2 pid = floor(p / vec2(3.0, 2.0));
	vec2 pf = fract(p / vec2(3.0, 2.0));
	float patch_ = step(0.88, hash12(pid + 9.0)) * cut(pf.x, 0.1) * (1.0 - cut(pf.x, 0.9)) * cut(pf.y, 0.15) * (1.0 - cut(pf.y, 0.85));
	col *= 1.0 - patch_ * 0.22;
	// Loose gravel dots.
	float g = cut(hash12(floor(p * 9.0)), 0.97);
	col *= 1.0 - g * 0.18;
	return col;
}

vec3 painted(vec2 p, vec3 paint, vec3 under) {
	// Faded paint with chipped-off patches and edges.
	vec3 col = paint * mix(0.88, 1.0, steps(fbm(p * 0.6), 3.0));
	float chip = cut(fbm(p * 1.6 + 7.0), 0.66);
	return mix(col, under, chip);
}

vec3 facade(vec2 p, vec3 col, vec3 n) {
	col = concrete(p * 0.5, col) * 0.6 + col * 0.4;
	if (abs(n.y) > 0.6) {
		return col;
	}
	// 3 m floors, 2.5 m bays; windows dark, some boarded or blown out.
	vec2 cell = vec2(p.x / 2.5, p.y / 3.0);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float win = cut(f.x, 0.22) * (1.0 - cut(f.x, 0.78)) * cut(f.y, 0.3) * (1.0 - cut(f.y, 0.82));
	float h = hash12(id + 3.0);
	vec3 glass = h < 0.15 ? col * 0.8 : vec3(0.1, 0.1, 0.12);
	col = mix(col, glass, win);
	// Soot above blown-out windows.
	float soot = (h > 0.8 ? 1.0 : 0.0) * cut(f.y, 0.82) * cut(fbm(p * 1.3), 0.45) * cut(f.x, 0.22) * (1.0 - cut(f.x, 0.78));
	col *= 1.0 - soot * 0.45;
	return col;
}

// 60 cm tiles in two faded tones, dark grout, some cracked, some gone
// (bare screed underneath).
vec3 tiles(vec2 p, vec3 col) {
	vec2 cell = p / 0.6;
	vec2 id = floor(cell);
	float h = hash12(id + 21.0);
	vec3 t = col * mix(0.9, 1.04, steps(h, 3.0));
	t *= mix(0.94, 1.0, steps(fbm(p * 0.5), 3.0));
	float grout = grid(p, 0.6, 0.012);
	t = mix(t, col * 0.55, grout);
	float c = 1.0 - cut(crack_lines(p * 1.4), 0.02);
	t *= 1.0 - c * step(0.7, h) * 0.35;
	// Missing tiles cluster in patches.
	float gone = step(0.82, hash12(id + 5.0)) * cut(fbm(p * 0.2 + 3.0), 0.5);
	return mix(t, concrete(p, under_color.rgb * 0.75), gone);
}

// Running-bond brick: 24 x 7 cm bricks (times tex_scale), mortar, a few
// spalled or darker bricks, and soot.
vec3 brick(vec2 p, vec3 col) {
	vec2 size = vec2(0.24, 0.075);
	vec2 cell = p / size;
	float row = floor(cell.y);
	cell.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float h = hash12(id + 13.0);
	vec3 b = col * mix(0.82, 1.08, steps(h, 4.0));
	b *= mix(0.92, 1.0, steps(fbm(p * 0.7), 3.0));
	// Spalled bricks show the paler core.
	b = mix(b, col * 1.25 + 0.05, step(0.94, h) * 0.6);
	vec2 mw = vec2(0.012) / size;
	float mortar = 1.0 - cut(f.x, mw.x) * (1.0 - cut(f.x, 1.0 - mw.x)) * cut(f.y, mw.y * 1.6) * (1.0 - cut(f.y, 1.0 - mw.y * 1.6));
	b = mix(b, under_color.rgb * 0.9, mortar);
	// Patches where the brick has been rendered over with concrete.
	float render_ = cut(fbm(p * 0.25 + 41.0), 0.68);
	return mix(b, concrete(p, under_color.rgb * 0.95), render_);
}

// Ribs every 15 cm (times tex_scale) across the horizontal axis of a wall.
float corrugation(float x) {
	return sin(x / (0.15 * max(tex_scale, 0.01)) * 6.2832);
}

vec3 corrugated(vec2 p, vec3 paint, vec3 n, float rib) {
	vec3 col = paint * mix(0.9, 1.0, steps(fbm(p * 0.5), 3.0));
	// Rib light and shade, posterized so it stays in the cel style.
	col *= mix(0.86, 1.06, steps(rib * 0.5 + 0.5, 3.0));
	// Paint gone to rust in big patches, worse near the bottom.
	float r = fbm(vec2(p.x * 0.6, p.y * 0.9) + 23.0) - p.y * 0.02;
	col = mix(col, rust_color.rgb * mix(0.85, 1.1, steps(fbm(p * 2.5), 3.0)), cut(r, 0.6) * 0.9);
	// Sheet joins every 0.9 m along the wall, with bolt heads.
	float join = grid(vec2(p.x, 0.0), 0.9, 0.01);
	col *= 1.0 - join * 0.3;
	return col;
}

vec3 planks(vec2 p, vec3 col, bool along_x) {
	vec2 q = along_x ? p : p.yx;
	float w = 0.16;
	float id = floor(q.y / w);
	float f = fract(q.y / w);
	float h = hash12(vec2(id, 7.0));
	vec3 c = col * mix(0.78, 1.08, steps(h, 4.0));
	// Grain: noise stretched along the board.
	float g = fbm(vec2(q.x * 0.8, q.y * 14.0) + id * 3.1);
	c *= mix(0.86, 1.04, steps(g, 3.0));
	// Board ends staggered every 1.2-2.4 m.
	float len = mix(1.2, 2.4, h);
	float e = fract((q.x + h * 7.0) / len);
	float gap = 1.0 - cut(f, 0.06) * (1.0 - cut(f, 0.94)) * cut(e, 0.008) * (1.0 - cut(e, 0.992));
	c = mix(c, col * 0.3, gap);
	// Weathered grey where the sun has bleached it.
	return mix(c, vec3(dot(c, vec3(0.33))) * 1.1, cut(fbm(p * 0.4 + 5.0), 0.6) * 0.5);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	bool top = an.y > max(an.x, an.z);
	// Planar projection on the dominant axis: cheap, no UVs needed.
	vec2 uv = top ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
	vec2 p = uv / max(tex_scale, 0.01);
	vec3 col = base_color.rgb;
	vec3 tex = col;
	if (surface == 1) {
		tex = concrete(p, col);
	} else if (surface == 2) {
		tex = rusted(p, col, n);
	} else if (surface == 3) {
		tex = asphalt(p, col);
	} else if (surface == 4) {
		tex = painted(p, col, rusted(p, rust_color.rgb, n));
	} else if (surface == 5) {
		tex = painted(p, col, concrete(p, under_color.rgb));
	} else if (surface == 6) {
		tex = facade(uv, col, n);
	} else if (surface == 7) {
		tex = tiles(p, col);
	} else if (surface == 8) {
		tex = brick(p, col);
	} else if (surface == 9) {
		// Ribs fade out where they get finer than a few pixels, so distant
		// sheets don't shimmer into moire.
		float ribs_px = fwidth(uv.x) / (0.15 * max(tex_scale, 0.01));
		float rib_fade = 1.0 - smoothstep(0.15, 0.45, ribs_px);
		float rib = top ? 0.0 : corrugation(uv.x) * rib_fade;
		tex = corrugated(p, col, n, rib);
		if (!top && rib_fade > 0.0) {
			// Bend the normal across the ribs so the light catches them.
			vec3 t = an.x > an.z ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
			float slope = cos(uv.x / (0.15 * max(tex_scale, 0.01)) * 6.2832) * rib_fade;
			vec3 wn = normalize(n + t * slope * 0.45);
			NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		}
	} else if (surface == 10) {
		tex = planks(p, col, true);
	}
	col = mix(col, tex, tex_strength);
	if (!top && surface != 0) {
		// Grime streaks running down walls.
		float streak = fbm(vec2(uv.x * 2.2, uv.y * 0.12));
		col *= 1.0 - cut(streak, 0.62) * 0.14 * tex_strength;
	}
	if (top && dust_amount > 0.0) {
		// Dust and sand settled on top faces, in drifts.
		float d = fbm(uv * 0.3 + 31.0);
		col = mix(col, dust_color.rgb, cut(d, 1.0 - dust_amount * 0.6) * 0.45);
	}
	if (grid_strength > 0.0) {
		float lines = max(grid(uv, 1.0, 0.012) * 0.5, grid(uv, 4.0, 0.03));
		col = mix(col, col * 0.6, lines * grid_strength);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
