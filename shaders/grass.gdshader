shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, world_vertex_coords;

// Instanced grass clumps. Colour matches the terrain shader's meadow pattern
// at the root so blades grow out of the ground instead of sitting on it.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 grass_dark : source_color = vec3(0.24, 0.42, 0.14);
uniform vec3 grass_light : source_color = vec3(0.52, 0.64, 0.22);
uniform vec3 tip_tint : source_color = vec3(0.86, 0.88, 0.48);
uniform float wind_strength = 0.16;
uniform float cloud_shadow = 0.28;

varying float blade_h;
varying vec3 wpos;

void vertex() {
	blade_h = UV.y;
	vec3 root = NODE_POSITION_WORLD;
	float gust = texture(noise_tex, VERTEX.xz * 0.035 - TIME * vec2(0.05, 0.03)).r;
	float flutter = sin(TIME * 3.1 + VERTEX.x * 2.3 + VERTEX.z * 1.7) * 0.25;
	vec2 wind = vec2(0.9, 0.4) * (gust * 1.4 - 0.35 + flutter);
	VERTEX.xz += wind * wind_strength * blade_h * blade_h;
	VERTEX.y -= length(wind) * wind_strength * 0.3 * blade_h * blade_h;
	// Bend normals upward: grass reads as soft volume, not individual cards.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.75));
	wpos = VERTEX;
}

void fragment() {
	float n_big = texture(noise_tex, wpos.xz * 0.018).r;
	float n_mid = texture(noise_tex, wpos.xz * 0.07 + 0.5).r;
	vec3 base = mix(grass_dark, grass_light, smoothstep(0.30, 0.72, n_big * 0.7 + n_mid * 0.3));
	vec3 col = mix(base * 0.86, base * mix(vec3(1.0), tip_tint * 1.3, 0.4), blade_h);
	col *= COLOR.rgb;
	float cloud = texture(noise_tex, wpos.xz * 0.008 + TIME * vec2(0.0035, 0.002)).r;
	col *= 1.0 - cloud_shadow * smoothstep(0.52, 0.72, cloud);
	// Both sides of a blade share the bent-up normal; undo the back-face flip.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.45 * blade_h;
	AO = mix(0.7, 1.0, blade_h);
	AO_LIGHT_AFFECT = 0.4;
}
