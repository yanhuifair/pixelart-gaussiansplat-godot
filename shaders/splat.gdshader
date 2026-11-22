// Solid splats: written as-is into the small buffer, depth tested against each other.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always, skip_vertex_transform;

#include "res://addons/pixel_art_splats/shaders/splat_common.gdshaderinc"

void vertex() {
	v_uv = UV * 2.0 - 1.0;
	vec4 clip;
	vec3 colour;
	float alpha;
	ps_vertex(v_uv, MODEL_MATRIX, COLOR, INSTANCE_CUSTOM, INV_VIEW_MATRIX[3].xyz,
		PROJECTION_MATRIX, VIEW_MATRIX, clip, colour, alpha);
	POSITION = clip;
	v_color = colour;
	v_alpha = alpha;
}

void fragment() {
	ps_disc(v_uv);
	ALBEDO = ps_srgb_to_linear(v_color);
	// the pixel pass reads coverage back out of the buffer's alpha, so a solid splat has to say so
	ALPHA = 1.0;
}
