shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Shared shader for faceted vertex-coloured props.
// Vertex alpha is a wind sway weight (0 = rigid, 1 = fully swaying canopy).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float wind_strength = 0.06;
uniform float roughness = 0.85;
uniform float translucency = 0.0;
instance uniform float flash = 0.0;     // hit flash for units
instance uniform float charred = 0.0;   // burnt buildings

varying float occlusion_fade;

void vertex() {
	occlusion_fade = INSTANCE_CUSTOM.r * step(0.01, COLOR.a);
	float sway = COLOR.a;
	if (sway > 0.0) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float n = texture(noise_tex, origin.xz * 0.04 + TIME * vec2(0.025, 0.018)).r;
		float phase = TIME * 1.6 + origin.x * 0.7 + origin.z * 0.4;
		vec2 dir = vec2(1.0, 0.45) * (n - 0.35) + vec2(sin(phase), cos(phase * 1.3)) * 0.25;
		VERTEX.xz += (inverse(mat3(MODEL_MATRIX)) * vec3(dir.x, 0.0, dir.y)).xz * wind_strength * sway * VERTEX.y;
	}
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	if (occlusion_fade > 0.001 && bayer4(FRAGCOORD.xy) < occlusion_fade) {
		discard;
	}
	// Vertex colours are authored in sRGB; lighting needs linear.
	vec3 c = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	c = mix(c, c * vec3(0.10, 0.09, 0.085), charred);
	ALBEDO = mix(c, vec3(1.0, 0.95, 0.9), flash * 0.85);
	EMISSION = vec3(1.0, 0.9, 0.8) * flash * 0.6;
	ROUGHNESS = roughness;
	BACKLIGHT = c * translucency * COLOR.a;
}
