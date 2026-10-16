shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Stylised terrain: slope/height driven material layers with painterly noise.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap_anisotropic;

uniform vec3 grass_dark : source_color = vec3(0.24, 0.42, 0.14);
uniform vec3 grass_light : source_color = vec3(0.52, 0.64, 0.22);
uniform vec3 grass_dry : source_color = vec3(0.70, 0.66, 0.34);
uniform vec3 rock_dark : source_color = vec3(0.40, 0.33, 0.27);
uniform vec3 rock_light : source_color = vec3(0.72, 0.63, 0.52);
uniform vec3 sand_col : source_color = vec3(0.86, 0.76, 0.56);
uniform vec3 seabed_col : source_color = vec3(0.70, 0.66, 0.50);
uniform float beach_h = 0.28;
uniform float level_h = 1.25;
uniform float cloud_shadow = 0.28;
uniform sampler2D path_mask : filter_linear_mipmap, repeat_disable;
uniform float path_extent = 30.0;
uniform vec3 dirt_col : source_color = vec3(0.56, 0.44, 0.30);

varying vec3 wpos;
varying vec3 wnorm;

float caustics(vec2 p, float t) {
	float a = texture(detail_tex, p * 0.31 + vec2(t * 0.020, t * 0.013)).r;
	float b = texture(detail_tex, p * 0.27 + vec2(-t * 0.017, t * 0.021) + 0.37).r;
	float c = 1.0 - abs(a - b) * 4.0;
	return pow(clamp(c, 0.0, 1.0), 6.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n_big = texture(noise_tex, wpos.xz * 0.018).r;
	float n_mid = texture(noise_tex, wpos.xz * 0.07 + 0.5).r;
	float n_fine = texture(detail_tex, wpos.xz * 0.6).r;

	// Grass: two-tone meadow patches with dry tufts on high, exposed ground.
	vec3 grass = mix(grass_dark, grass_light, smoothstep(0.30, 0.72, n_big * 0.7 + n_mid * 0.3));
	float dry = smoothstep(0.62, 0.85, n_mid) * smoothstep(beach_h + level_h * 1.5, beach_h + level_h * 2.5, wpos.y);
	grass = mix(grass, grass_dry, dry * 0.6);
	grass *= 0.88 + 0.24 * n_fine;

	// Rock: sedimentary strata, warped by noise so bands don't look ruled.
	float strata_coord = wpos.y * 3.2 + n_mid * 2.5 + n_big * 1.5;
	float band = fract(strata_coord);
	// Uneven ledges: a sharp lip at the top of each band, softer below.
	float strata = smoothstep(0.0, 0.85, band) * smoothstep(1.0, 0.92, band);
	float crack = texture(detail_tex, vec2(atan(wpos.x, wpos.z) * 3.0, wpos.y * 0.15)).r;
	strata = strata * 0.6 + n_fine * 0.25 + crack * 0.15;
	vec3 rock = mix(rock_dark, rock_light, strata);
	// Warmer, iron-stained streaks running down the faces.
	float streak = texture(noise_tex, vec2(wpos.x * 0.35 + wpos.z * 0.35, wpos.y * 0.05)).r;
	rock = mix(rock, rock * vec3(1.08, 0.92, 0.78), smoothstep(0.55, 0.75, streak) * 0.6);
	// Darken the base of each cliff, lighten the lip: fake curvature.
	float in_level = fract((wpos.y - beach_h) / level_h);
	rock *= mix(0.78, 1.08, smoothstep(0.0, 0.9, in_level));

	float slope = 1.0 - wnorm.y;
	float rock_w = smoothstep(0.30, 0.48, slope + (n_fine - 0.5) * 0.16);

	// Sand band along the coast, breaking up into grass with noise.
	float sand_w = 1.0 - smoothstep(beach_h + 0.04, beach_h + 0.22, wpos.y + (n_mid - 0.5) * 0.25);
	vec3 sand = sand_col * (0.92 + 0.12 * n_fine);

	vec3 col = mix(grass, sand, sand_w);
	// Worn dirt paths with a ragged grass edge.
	float path = texture(path_mask, wpos.xz / (path_extent * 2.0) + 0.5).r;
	path = smoothstep(0.35, 0.65, path + (n_fine - 0.5) * 0.35);
	vec3 dirt = dirt_col * (0.85 + 0.25 * n_fine) * mix(0.9, 1.05, n_mid);
	col = mix(col, dirt, path * (1.0 - sand_w));
	col = mix(col, rock, rock_w);

	// Wet sand and seabed.
	float wet = 1.0 - smoothstep(-0.02, 0.10, wpos.y);
	vec3 bed = seabed_col * (0.85 + 0.25 * n_fine);
	col = mix(col, bed, smoothstep(0.0, -0.5, wpos.y));
	col *= mix(1.0, 0.68, wet);

	// Caustics on the seabed, fading with depth.
	float under = smoothstep(0.0, -0.15, wpos.y) * exp(wpos.y * 0.45);
	col += vec3(0.85, 0.95, 1.0) * caustics(wpos.xz, TIME) * under * 0.55;

	// Slow drifting cloud shadows.
	float cloud = texture(noise_tex, wpos.xz * 0.008 + TIME * vec2(0.0035, 0.002)).r;
	col *= 1.0 - cloud_shadow * smoothstep(0.52, 0.72, cloud);

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.35, wet);
	SPECULAR = mix(0.3, 0.6, wet);
}
