shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Waving cloth banner. Pinned along the pole edge (UV.x = 0).

uniform vec3 field_col : source_color = vec3(0.16, 0.30, 0.58);
uniform vec3 charge_col : source_color = vec3(0.95, 0.86, 0.45);

void vertex() {
	float free_end = UV.x;
	float wave = sin(UV.x * 7.0 - TIME * 5.5) * 0.06 + sin(UV.x * 3.1 - TIME * 3.3 + UV.y * 2.0) * 0.04;
	VERTEX.z += wave * free_end;
	VERTEX.y -= free_end * free_end * 0.05;
}

void fragment() {
	// Simple heraldry: a pale stripe with a swallow-tail notch.
	vec2 uv = UV;
	float notch = step(0.82, uv.x) * step(abs(uv.y - 0.5), (uv.x - 0.82) * 1.6);
	if (notch > 0.5) {
		discard;
	}
	float stripe = step(abs(uv.y - 0.5), 0.11);
	vec3 col = mix(field_col, charge_col, stripe);
	ALBEDO = col * (FRONT_FACING ? 1.0 : 0.82);
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.35;
}
