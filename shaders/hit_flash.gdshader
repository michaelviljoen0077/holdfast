shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

// Additive overlay used briefly when a character takes a hit.

instance uniform float flash = 0.0;

void fragment() {
	ALBEDO = vec3(1.0, 0.92, 0.82) * flash * 0.9;
	ALPHA = flash;
}
