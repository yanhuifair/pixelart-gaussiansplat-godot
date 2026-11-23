// Shared by the solid and the glow splat shaders.
//
// A splat is drawn as one instanced quad: the MultiMesh instance transform carries the surfel's two
// wide axes in its basis and its centre in its origin, so applying the transform to the quad's four
// corners gives the splat's own footprint on screen. The disc test and everything else happens on
// the quad's own (u, v).
//
// Colours here are DISPLAY space, the space the palette is authored in. The 3D viewport encodes
// what it writes into sRGB, so writing srgb_to_linear(colour) makes the pixel pass read exactly
// `colour` back out.
//
// Built-ins (COLOR, MODEL_MATRIX, POSITION, ...) are only visible inside vertex() and fragment(),
// so everything here takes them as arguments.

uniform vec2 ps_low_res = vec2(640.0, 360.0);   // the buffer being drawn into, in texels
uniform float ps_min_texels = 0.9;              // grow tiny distant splats
uniform float ps_falloff = 0.0;                 // 0 = hard disc (pixel art), 1 = soft Gaussian
uniform float ps_bands = 0.0;                   // flat light steps for live lighting, 0 = smooth
uniform float ps_cull = 1.0;                    // hide splats facing away
uniform float ps_fog_start = 6.2;
uniform float ps_fog_end = 9.0;
uniform float ps_exposure = 1.0;
uniform vec3 ps_sun_dir = vec3(0.45, 0.8, 0.4);
uniform vec3 ps_point_pos[4];
uniform vec3 ps_point_color[4];
uniform int ps_point_count = 0;
uniform float ps_time = 0.0;
uniform float ps_base = 0.0;   // index of the first instance in this buffer, for the motion's hash

// what the renderer animates, in flags bits 16..23 (see tools/dio_to_bytes.py)
#define PS_M_RISE 1
#define PS_M_FLOAT 2
#define PS_M_BLINK 3
#define PS_M_TWINKLE 4
#define PS_M_DRIFT 5
#define PS_M_LEAF 6
#define PS_M_SMOKE 7
#define PS_M_FOG 8
#define PS_M_SHAFT 9
#define PS_M_RAY 10
#define PS_M_PULSE 11
#define PS_M_BEAM 12

#define PS_EMISSIVE 1
#define PS_TWO_SIDED 2
#define PS_GLOW 4
#define PS_BAKED 8
#define PS_UP_NORMAL 16
#define PS_SWAY 32

// brightness = ambient (darker from below, lighter from above) + key light
#define AMBIENT_LOW 0.36
#define AMBIENT_HIGH 0.58
#define DIFFUSE 0.62

varying vec2 v_uv;
varying vec3 v_color;
varying float v_alpha;

vec3 ps_srgb_to_linear(vec3 c) {
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
	return mix(lo, hi, step(vec3(0.04045), c));
}

// three stable random numbers per splat, the same hash the browser uses
vec3 ps_hash31(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// The moving things: port of src/render/particles.js. `param` is the byte above the motion id,
// 0..4 spread over 0..255 — the height of a smoke column, or the radius sand wraps around.
// `pivot` is the splat's third axis, except for leaf and beam: those turn around a point, which the
// importer leaves in that slot instead (both are translucent, and a translucent splat's normal is
// never read). See tools/dio_to_bytes.py.
void ps_animate(inout vec3 centre, inout vec3 axis1, inout vec3 axis2, inout float alpha,
		int mode, float par, vec3 pivot, float index, float t) {
	if (mode == 0) {
		return;
	}
	vec3 r = ps_hash31(index + 3.0);
	float k;
	float s;

	if (mode == PS_M_RISE) {
		k = fract(t * 0.22 * (0.6 + r.x) + r.y);
		centre.y += k * par;
		centre.x += 0.07 * sin(k * 9.0 + r.z * 40.0) * k;
		centre.z += 0.07 * cos(k * 7.0 + r.x * 40.0) * k;
		s = 1.0 - 0.6 * k;
		axis1 *= s;
		axis2 *= s;
		alpha *= smoothstep(0.0, 0.05, k) * (1.0 - smoothstep(0.55, 1.0, k));
	} else if (mode == PS_M_SMOKE) {
		k = fract(t * 0.09 * (0.6 + r.x) + r.y);
		centre.y += k * par;
		centre.x += 0.12 * k * sin(k * 6.0 + r.z * 40.0) + 0.12 * k * k;
		centre.z += 0.1 * k * cos(k * 5.0 + r.x * 40.0);
		s = 1.0 + 3.0 * k;
		axis1 *= s;
		axis2 *= s;
		alpha *= smoothstep(0.0, 0.08, k) * (1.0 - smoothstep(0.3, 1.0, k)) * 0.6;
	} else if (mode == PS_M_BLINK) {
		centre += 0.12 * vec3(sin(t * 0.5 + r.x * 40.0), 0.6 * sin(t * 0.4 + r.y * 40.0),
				cos(t * 0.45 + r.z * 40.0));
		alpha *= smoothstep(0.55, 0.95, sin(t * (0.9 + r.z) + r.x * 60.0));
	} else if (mode == PS_M_DRIFT) {
		float radius = par;
		centre.x = mod(centre.x + t * 0.16 * (0.5 + r.x) + radius, 2.0 * radius) - radius;
		centre.y += 0.03 * sin(t * 1.3 + r.y * 30.0);
		alpha *= smoothstep(0.0, 0.25, radius - abs(centre.x));
	} else if (mode == PS_M_TWINKLE) {
		alpha *= smoothstep(0.6, 0.98, sin(t * (0.7 + r.z * 1.3) + r.x * 60.0));
	} else if (mode == PS_M_PULSE) {
		s = 0.93 + 0.07 * sin(t * 7.0 + r.x * 20.0);
		axis1 *= s;
		axis2 *= s;
	} else if (mode == PS_M_FLOAT) {
		centre += 0.07 * vec3(sin(t * 0.3 + r.x * 40.0), sin(t * 0.22 + r.y * 40.0),
				cos(t * 0.27 + r.z * 40.0));
		alpha *= 0.35 + 0.65 * smoothstep(0.2, 0.9, sin(t * (0.3 + r.z * 0.4) + r.x * 60.0) * 0.5 + 0.5);
	} else if (mode == PS_M_FOG) {
		centre.x += 0.25 * sin(t * 0.12 + r.x * 40.0);
		centre.z += 0.25 * cos(t * 0.1 + r.y * 40.0);
		centre.y += 0.04 * sin(t * 0.3 + r.z * 30.0);
		alpha *= 0.55 + 0.45 * sin(t * 0.25 + r.z * 50.0);
	} else if (mode == PS_M_SHAFT) {
		centre.x += 0.08 * sin(t * 0.15 + r.x * 20.0);
		alpha *= 0.5 + 0.5 * sin(t * 0.4 + r.y * 50.0);
	} else if (mode == PS_M_RAY) {
		centre.x += 0.025 * sin(t * 0.21 + r.x * 6.0);
		centre.z += 0.02 * cos(t * 0.17 + r.x * 6.0);
		alpha *= 0.8 + 0.2 * sin(t * 0.5 + r.y * 50.0);
	} else if (mode == PS_M_LEAF) {
		// fall through a column of height `par` above the pivot, tumbling as it goes
		float h = max(par, 0.01);
		centre.y = pivot.y + mod(centre.y - pivot.y - t * 0.14 * (0.6 + r.x), h);
		float d = centre.y - pivot.y;
		centre.x += 0.13 * sin(t * 0.9 + r.y * 40.0 + centre.y * 3.0);
		centre.z += 0.11 * cos(t * 0.7 + r.z * 40.0 + centre.y * 2.5);
		alpha *= smoothstep(0.0, 0.1, d) * (1.0 - smoothstep(h - 0.3, h, d));
	} else if (mode == PS_M_BEAM) {
		// sweep around the vertical through the pivot, and turn the beam with it
		float ang = t * 0.7;
		float cs = cos(ang);
		float sn = sin(ang);
		vec3 d = centre - pivot;
		centre = pivot + vec3(cs * d.x + sn * d.z, d.y, -sn * d.x + cs * d.z);
		axis1 = vec3(cs * axis1.x + sn * axis1.z, axis1.y, -sn * axis1.x + cs * axis1.z);
		axis2 = vec3(cs * axis2.x + sn * axis2.z, axis2.y, -sn * axis2.x + cs * axis2.z);
	}
}

vec3 ps_sway(vec3 centre) {
	// a whole blade leans, the way the original particles lean one splat
	return vec3(0.016 * sin(ps_time * 1.6 + centre.x * 5.0 + centre.z * 3.0), 0.0,
				0.011 * cos(ps_time * 1.3 + centre.z * 4.0 - centre.x * 2.0));
}

// Per-splat light. Baked clouds already carry their colour; everything else is lit here, once per
// splat, because it is the same for the whole disc.
vec3 ps_shade(vec3 albedo, float alpha, int flags, vec3 p, vec3 centre, vec3 n, vec3 cam_pos) {
	vec3 to_cam = cam_pos - centre;
	float dist = max(length(to_cam), 1e-4);
	float facing = dot(n, to_cam / dist);

	bool emissive = (flags & PS_EMISSIVE) != 0;
	bool baked = (flags & PS_BAKED) != 0;
	bool two_sided = (flags & PS_TWO_SIDED) != 0;
	bool up_normal = (flags & PS_UP_NORMAL) != 0;

	vec3 col = albedo;
	if ((flags & PS_GLOW) == 0) {
		if (two_sided && facing < 0.0) n = -n;
		if (up_normal) n = normalize(n * 0.3 + vec3(0.0, 1.0, 0.0));

		if (baked) {
			col = albedo * ps_exposure;
		} else {
			float ndl = dot(n, normalize(ps_sun_dir));
			float light = mix(AMBIENT_LOW, AMBIENT_HIGH, n.y * 0.5 + 0.5)
				+ DIFFUSE * max(ndl, 0.0) + 0.22 * max(facing, 0.0);
			if (ps_bands > 0.5) light = (floor(light * ps_bands) + 0.5) / ps_bands;

			col = albedo * light * ps_exposure;
			// a blade or a leaflet is lit as if it faced up, and a little dimmer for it
			if (up_normal) col *= 0.74;
			col *= mix(vec3(0.92, 0.95, 1.05), vec3(1.04, 1.0, 0.95), step(0.0, ndl));

			for (int k = 0; k < 4; k++) {
				if (k >= ps_point_count) break;
				vec3 to_light = ps_point_pos[k] - p;
				float d = length(to_light);
				float w = (max(dot(n, to_light / max(d, 1e-4)), 0.0) * 0.85 + 0.15) / (1.0 + d * d * 9.0);
				col += (albedo * 0.85 + 0.1) * ps_point_color[k] * w;
			}
		}

		if (emissive) col = albedo * 1.15;
		else col = mix(col, vec3(0.03, 0.035, 0.05), 0.75 * smoothstep(ps_fog_start, ps_fog_end, dist));
	}
	return col;
}

// Where the quad's corners go, and whether the splat is worth drawing at all.
bool ps_project(vec3 centre, vec3 axis1, vec3 axis2, vec2 uv, mat4 proj, mat4 view, out vec4 clip) {
	vec4 clip_c = proj * view * vec4(centre, 1.0);
	clip = vec4(0.0, 0.0, -2.0, 1.0);
	if (clip_c.w <= 0.0001) {
		return false;
	}

	vec3 p_ws = centre + uv.x * axis1 + uv.y * axis2;
	vec4 clip_p = proj * view * vec4(p_ws, 1.0);

	vec2 ndc_c = clip_c.xy / clip_c.w;
	vec2 ndc_p = clip_p.xy / max(clip_p.w, 1e-5);
	vec2 d = ndc_p - ndc_c;

	// do not let a splat fall below a texel: distant surfaces would get holes
	vec2 texels = abs(d) * ps_low_res * 0.5;
	float biggest = max(texels.x, texels.y);
	float grow = (biggest > 1e-4) ? max(1.0, ps_min_texels / biggest) : 1.0;

	vec2 ndc = ndc_c + d * grow;
	clip = vec4(ndc * clip_p.w, clip_p.z, clip_p.w);
	return true;
}

// Everything vertex() does, with the built-ins handed in.
void ps_vertex(vec2 uv, mat4 model, vec4 colour, vec4 custom, vec3 cam_pos, mat4 proj, mat4 view,
		float index, out vec4 clip, out vec3 out_colour, out float out_alpha) {
	vec3 axis1 = model[0].xyz;
	vec3 axis2 = model[1].xyz;
	vec3 axis3 = model[2].xyz;   // the thin axis, or the pivot for leaf and beam
	vec3 centre = model[3].xyz;
	vec3 n = normalize(axis3 + vec3(0.0, 0.0, 1e-6));

	int flags = int(custom.x);
	float alpha = 1.0;
	ps_animate(centre, axis1, axis2, alpha, int(custom.y), custom.z * (4.0 / 255.0), axis3,
			index + ps_base, ps_time);

	if ((flags & PS_SWAY) != 0) {
		centre += ps_sway(centre);
	}

	out_alpha = colour.a * alpha;
	out_colour = ps_shade(colour.rgb, out_alpha, flags, centre, centre, n, cam_pos);

	vec3 to_cam = cam_pos - centre;
	float facing = dot(n, to_cam / max(length(to_cam), 1e-4));
	bool two_sided = (flags & PS_TWO_SIDED) != 0;
	bool glow = (flags & PS_GLOW) != 0;

	// hide splats facing away
	if (ps_cull > 0.5 && !two_sided && !glow && facing < -0.08) {
		clip = vec4(0.0, 0.0, -2.0, 1.0);
		return;
	}
	if (!ps_project(centre, axis1, axis2, uv, proj, view, clip)) {
		clip = vec4(0.0, 0.0, -2.0, 1.0);
	}
}

// 0 outside the disc, 1 on it, and a soft edge between when falloff is on.
float ps_disc(vec2 uv) {
	float d2 = dot(uv, uv);
	if (d2 > 1.0) {
		discard;
	}
	if (ps_falloff <= 0.001) {
		return 1.0;
	}
	return clamp((exp(-3.0 * d2) - 0.0497870684) / 0.9502129316, 0.0, 1.0);
}
