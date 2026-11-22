// Translucent light: halos, beams, smoke. Blended over whatever is behind, no depth write.
// Over the buffer's transparent black this leaves premultiplied colour and accumulated alpha,
// which is exactly what the pixel pass expects.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, skip_vertex_transform;

#include "res://addons/pixel_art_splats/shaders/splat_common.gdshaderinc"

void vertex() {
	v_uv = UV * 2.0 - 1.0;
	vec4 clip;
	vec3 colour;
	float alpha;
	ps_vertex(v_uv, MODEL_MATRIX, COLOR, INSTANCE_CUSTOM, INV_VIEW_MATRIX[3].xyz,
		PROJECTION_MATRIX, VIEW_MATRIX, float(INSTANCE_ID), clip, colour, alpha);
	POSITION = clip;
	v_color = colour;
	v_alpha = alpha;
}

void fragment() {
	float a = ps_disc(v_uv) * v_alpha;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = ps_srgb_to_linear(v_color);
	ALPHA = a;
}
