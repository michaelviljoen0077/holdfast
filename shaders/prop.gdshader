shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Shared shader for faceted vertex-coloured props.
// Vertex alpha is a wind sway weight (0 = rigid, 1 = fully swaying canopy).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float wind_strength = 0.06;
uniform float roughness = 0.85;
uniform float translucency = 0.0;

void vertex() {
	float sway = COLOR.a;
	if (sway > 0.0) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float n = texture(noise_tex, origin.xz * 0.04 + TIME * vec2(0.025, 0.018)).r;
		float phase = TIME * 1.6 + origin.x * 0.7 + origin.z * 0.4;
		vec2 dir = vec2(1.0, 0.45) * (n - 0.35) + vec2(sin(phase), cos(phase * 1.3)) * 0.25;
		VERTEX.xz += (inverse(mat3(MODEL_MATRIX)) * vec3(dir.x, 0.0, dir.y)).xz * wind_strength * sway * VERTEX.y;
	}
}

void fragment() {
	// Vertex colours are authored in sRGB; lighting needs linear.
	vec3 c = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	ALBEDO = c;
	ROUGHNESS = roughness;
	BACKLIGHT = c * translucency * COLOR.a;
}
