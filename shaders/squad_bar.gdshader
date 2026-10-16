shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

// Squad health bar under a banner: billboarded and a constant size on
// screen, so it reads the same zoomed in or out.

instance uniform float fill = 1.0;
instance uniform vec4 bar_color : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform vec2 size = vec2(0.05, 0.006);
uniform float drop = 0.031;

void vertex() {
	// Face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	// Constant screen size: scale by view depth.
	float depth = -MODELVIEW_MATRIX[3].z;
	VERTEX.xy = VERTEX.xy * size * depth;
	VERTEX.y -= drop * depth;
}

void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.15) + step(0.85, uv.y);
	vec3 col = uv.x < fill ? bar_color.rgb : vec3(0.12, 0.1, 0.09);
	col = mix(col, vec3(0.05, 0.04, 0.03), clamp(border, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = 0.92;
}
