shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Stylised water: depth-based absorption, screen-space refraction,
// animated shoreline foam bands and wind-driven surface normals.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_a : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_b : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D foam_noise : repeat_enable, filter_linear_mipmap;

uniform vec3 shallow_col : source_color = vec3(0.30, 0.82, 0.78);
uniform vec3 mid_col : source_color = vec3(0.06, 0.48, 0.60);
uniform vec3 deep_col : source_color = vec3(0.02, 0.20, 0.36);
uniform vec3 foam_col : source_color = vec3(0.97, 0.99, 1.0);
uniform float clarity = 1.1;
uniform float refraction = 0.025;
uniform float foam_width = 0.55;
uniform float swell = 0.025;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Very gentle swell; kept small so the shoreline depth test stays stable.
	float s = sin(wpos.x * 0.35 + TIME * 0.9) * cos(wpos.z * 0.29 + TIME * 0.7);
	s += sin(wpos.x * 0.11 - wpos.z * 0.07 + TIME * 0.6) * 0.8;
	// Calm near the island so the shoreline depth test stays stable.
	float open_sea = smoothstep(18.0, 40.0, length(wpos.xz));
	float amp = mix(min(swell, 0.03), swell, open_sea);
	VERTEX.y += s * amp;
	wpos.y += s * amp;
}

float scene_world_y(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	float d = texture(depth_tex, uv).r;
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
	vec4 view = inv_proj * ndc;
	view.xyz /= view.w;
	return (inv_view * vec4(view.xyz, 1.0)).y;
}

void fragment() {
	vec2 flow = vec2(TIME * 0.018, TIME * 0.011);
	vec3 na = texture(normal_a, wpos.xz * 0.11 + flow).xyz;
	vec3 nb = texture(normal_b, wpos.xz * 0.07 - flow * 1.3).xyz;
	vec3 nmap = normalize(mix(na, nb, 0.5));
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 0.55;

	vec2 distort = (nmap.xy - 0.5) * refraction;
	float depth = wpos.y - scene_world_y(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	// Only refract where the offset sample is also below the surface.
	vec2 ruv = SCREEN_UV + distort * clamp(depth, 0.0, 1.0);
	float rdepth = wpos.y - scene_world_y(ruv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	if (rdepth < 0.0) {
		ruv = SCREEN_UV;
		rdepth = depth;
	}
	rdepth = max(rdepth, 0.0);
	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;

	// Absorption: transmit the seabed in the shallows, fade to deep blue.
	float t_shallow = exp(-rdepth * clarity);
	float t_mid = exp(-rdepth * 0.55);
	vec3 water = mix(deep_col, mid_col, t_mid);
	water = mix(water, shallow_col, t_shallow * 0.75);
	vec3 transmitted = below * mix(vec3(1.0), shallow_col * 1.35, 0.55);
	float trans = t_shallow * 0.82;

	// Shoreline foam: a crisp contact line plus outward-travelling bands.
	float fn = texture(foam_noise, wpos.xz * 0.18 + flow * 2.0).r;
	float fn2 = texture(foam_noise, wpos.xz * 0.45 - flow * 3.0).r;
	float edge = 1.0 - smoothstep(0.0, 0.07 + fn * 0.06, depth);
	float band_phase = depth / foam_width * 3.0 - TIME * 0.55 + fn * 1.4;
	float bands = smoothstep(0.86, 0.94, fract(band_phase)) * (1.0 - smoothstep(0.0, foam_width, depth));
	bands *= step(0.42, fn2);
	float foam = clamp(edge + bands, 0.0, 1.0);

	vec3 lit = water * (1.0 - trans);
	ALBEDO = mix(lit, foam_col, foam);
	EMISSION = transmitted * trans * (1.0 - foam);
	ROUGHNESS = mix(0.06, 0.85, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
