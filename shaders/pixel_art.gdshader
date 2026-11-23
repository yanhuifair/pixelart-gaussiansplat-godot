// The pixel pass: turns a small render of hard-edged splats into pixel art.
//
// Port of src/render/post.js, running at screen resolution on a ColorRect that covers the window.
//
//   1. Supersample (ss = 2): the splats were drawn at twice the art resolution, so every art pixel
//      has four samples.
//   2. Coverage: a sample is solid when an opaque splat covers it. An art pixel with at least half
//      of its samples solid belongs to the object.
//   3. Palette by vote: each solid sample snaps to its nearest palette colour and the pixel takes
//      the colour most of them chose, so no pixel is an average of two materials.
//   4. Outline: a solid pixel next to the background takes a darker ink of its own colour, kept
//      bright enough to stay visible on a dark background.
//   5. Translucent light (beams, halos, smoke) is blended over the background and the result
//      snapped to the palette in its own hue, so a light beam becomes a flat band of muted colour.
//
// With dither above 0, colours are instead averaged and dithered between the two nearest palette
// colours with an ordered (Bayer) pattern. crisp off draws classic soft Gaussians, blended.
shader_type canvas_item;

uniform sampler2D splat_tex : filter_nearest, repeat_disable;

uniform vec2 src_size = vec2(640.0, 360.0);   // the small render, in texels
uniform vec2 art_size = vec2(320.0, 180.0);   // art pixels
uniform float pixel_size = 5.0;               // screen pixels per art pixel
uniform float ss = 2.0;                       // source texels per art pixel, per side
uniform vec3 palette[64];
uniform int palette_count = 12;
uniform int surface_count = 12;               // entries before this may colour surfaces
uniform vec3 background = vec3(0.0392157, 0.0392157, 0.0941176);
uniform float outline_on = 1.0;
uniform float quantise_on = 1.0;
uniform float dither = 0.0;
uniform float crisp = 1.0;
uniform float debug_raw = 0.0;

const float SOLID_ALPHA = 0.95;

// 4x4 ordered dither matrix, in (0.5, 15.5) / 16
const float PS_BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };

float ps_bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	return (PS_BAYER[x + y * 4] + 0.5) / 16.0;
}

// The buffer holds light that was blended in linear space and then stored sRGB-encoded, so a
// premultiplied texel is srgb(a * linear(c)). Undo it in linear, not in display space: dividing the
// stored value by alpha overshoots, and a faint gold beam would snap to the wrong colour.
vec3 ps_srgb_to_linear(vec3 c) {
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
	return mix(lo, hi, step(vec3(0.04045), c));
}

vec3 ps_linear_to_srgb(vec3 c) {
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(lo, hi, step(vec3(0.0031308), c));
}

// the colour the light had before it was premultiplied, back in display space
vec3 ps_unpre(vec3 c, float a) {
	return ps_linear_to_srgb(ps_srgb_to_linear(c) / max(a, 1e-4));
}

vec4 ps_texel(vec2 t) {
	vec2 c = clamp(t, vec2(0.0), src_size - 1.0);
	return texture(splat_tex, (c + 0.5) / src_size);
}

// share of an art pixel's samples covered by something opaque
float ps_coverage(vec2 cell) {
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= art_size.x || cell.y >= art_size.y) {
		return 1.0; // the screen edge is not an outline
	}
	if (ss < 1.5) {
		return step(SOLID_ALPHA, ps_texel(cell).a);
	}
	vec2 t = cell * 2.0;
	return 0.25 * (step(SOLID_ALPHA, ps_texel(t).a)
		+ step(SOLID_ALPHA, ps_texel(t + vec2(1.0, 0.0)).a)
		+ step(SOLID_ALPHA, ps_texel(t + vec2(0.0, 1.0)).a)
		+ step(SOLID_ALPHA, ps_texel(t + vec2(1.0, 1.0)).a));
}

bool ps_is_background(vec3 c) {
	return length(c - background) < 0.004;
}

// nearest palette entry; solid pixels never take the background colour
int ps_nearest(vec3 c, bool solid) {
	int best = 0;
	float bd = 1e9;
	for (int i = 0; i < 64; i++) {
		if (i >= surface_count) break;
		vec3 p = palette[i];
		if (solid && palette_count > 1 && ps_is_background(p)) continue;
		vec3 e = c - p;
		vec3 w = e * vec3(0.30, 0.59, 0.11); // weigh by how bright each channel looks
		float d = dot(w, w) + 0.25 * dot(e, e);
		if (d < bd) {
			bd = d;
			best = i;
		}
	}
	return best;
}

vec3 ps_oklab(vec3 c) {
	c = pow(max(c, vec3(0.0)), vec3(2.2));
	vec3 lms = pow(vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b) + 1e-9, vec3(1.0 / 3.0));
	return vec3(
		0.2104542553 * lms.x + 0.793617785 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.428592205 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.808675766 * lms.z);
}

vec2 ps_hue_dir(vec3 lab) {
	return lab.yz / (length(lab.yz) + 0.035);
}

// translucent light over the background: the palette colour nearest the blend in OKLab, kept in
// the light's own hue (a faint gold beam becomes a muted gold, not a green that happens to be close)
vec3 ps_haze(vec3 light, float a) {
	if (a < 0.3) return background;
	vec3 t = ps_oklab(mix(background, light, min(1.0, a * 1.6)));
	vec2 h = ps_hue_dir(ps_oklab(light));
	vec3 best = background;
	float bd = 1e9;
	for (int i = 0; i < 64; i++) {
		if (i >= palette_count) break;
		vec3 pc = palette[i];
		vec3 p = ps_oklab(pc);
		vec3 e = t - p;
		vec2 dh = ps_hue_dir(p) - h;
		bool bg = ps_is_background(pc);
		float d = 1.4 * e.x * e.x + dot(e.yz, e.yz) + (bg ? 0.0 : 0.12 * dot(dh, dh));
		if (d < bd) {
			bd = d;
			best = pc;
		}
	}
	return best;
}

vec3 ps_snap_dither(vec3 col, vec2 cell, bool solid) {
	vec3 c1 = col;
	vec3 c2 = col;
	float d1 = 1e9;
	float d2 = 1e9;
	for (int i = 0; i < 64; i++) {
		if (i >= surface_count) break;
		vec3 p = palette[i];
		if (solid && palette_count > 1 && ps_is_background(p)) continue;
		vec3 e = col - p;
		vec3 w = e * vec3(0.30, 0.59, 0.11);
		float d = dot(w, w) + 0.25 * dot(e, e);
		if (d < d1) {
			d2 = d1;
			c2 = c1;
			d1 = d;
			c1 = p;
		} else if (d < d2) {
			d2 = d;
			c2 = p;
		}
	}
	vec3 axis = c2 - c1;
	float t = clamp(dot(col - c1, axis) / max(dot(axis, axis), 1e-5), 0.0, 0.5);
	return ps_bayer(cell) < t * dither ? c2 : c1;
}

// a darker shade of a colour, never so dark that it vanishes into the background
vec3 ps_ink(vec3 body) {
	vec3 tone = body * 0.64;
	tone = min(vec3(1.0), tone * max(1.0, 0.12 / max(dot(tone, vec3(0.30, 0.55, 0.15)), 0.001)));
	return mix(body, tone, 0.65);
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / pixel_size); // which art pixel
	vec3 col;
	if (debug_raw > 0.5) {
		col = ps_texel(cell * vec2(ss, ss)).rgb;
	} else {
	int N = ss < 1.5 ? 1 : 4;

	vec4 smp[4];
	vec4 sum = vec4(0.0);
	vec4 solid_sum = vec4(0.0);
	for (int i = 0; i < 4; i++) {
		if (i >= N) break;
		smp[i] = (N == 1) ? ps_texel(cell) : ps_texel(cell * 2.0 + vec2(float(i - (i / 2) * 2), float(i / 2)));
		sum += smp[i];
		if (smp[i].a > SOLID_ALPHA) {
			solid_sum += vec4(ps_unpre(smp[i].rgb, smp[i].a), 1.0);
		}
	}
	sum /= float(N);
	float cov = solid_sum.a / float(N);

	bool quantise = quantise_on > 0.5;
	bool use_dither = dither > 0.0;

	if (crisp < 0.5) {
		// soft Gaussians: plain blending over the background
		col = sum.rgb + background * (1.0 - clamp(sum.a, 0.0, 1.0));
		if (quantise) {
			col = use_dither ? ps_snap_dither(col, cell, false) : palette[ps_nearest(col, false)];
		}
	} else if (cov >= 0.5) {
		// the object. Its colour: the palette colour most samples snap to
		vec3 body = solid_sum.rgb / max(solid_sum.a, 1e-4);
		bool edge = false;
		if (outline_on > 0.5) {
			float n = step(0.5, ps_coverage(cell + vec2(1.0, 0.0)))
				+ step(0.5, ps_coverage(cell - vec2(1.0, 0.0)))
				+ step(0.5, ps_coverage(cell + vec2(0.0, 1.0)))
				+ step(0.5, ps_coverage(cell - vec2(0.0, 1.0)));
			edge = n > 0.5 && n < 3.5; // isolated dots (embers, fireflies) keep their colour
		}

		if (quantise && !use_dither) {
			int lab[4] = { -1, -1, -1, -1 };
			for (int a = 0; a < 4; a++) {
				if (a < N && smp[a].a > SOLID_ALPHA) {
					lab[a] = ps_nearest(ps_unpre(smp[a].rgb, smp[a].a), true);
				}
			}
			int best = 0;
			int score = 0;
			for (int a = 0; a < 4; a++) {
				if (lab[a] < 0) continue;
				int repeats = 0;
				for (int b = 0; b < 4; b++) {
					if (lab[b] == lab[a]) repeats++;
				}
				if (repeats > score) {
					score = repeats;
					best = lab[a];
				}
			}
			col = palette[best];
			if (edge) col = palette[ps_nearest(ps_ink(col), true)];
		} else {
			if (edge) body = ps_ink(body);
			if (quantise) {
				col = edge ? palette[ps_nearest(body, true)] : ps_snap_dither(body, cell, true);
			} else {
				col = body;
			}
		}
	} else {
		// background, with whatever translucent light lies over it
		float a = clamp(sum.a, 0.0, 1.0);
		col = background * (1.0 - a) + sum.rgb;
		if (quantise) {
			col = use_dither ? ps_snap_dither(col, cell, false) : ps_haze(ps_unpre(sum.rgb, a), a);
		}
	}

	}
	COLOR = vec4(col, 1.0);
}
