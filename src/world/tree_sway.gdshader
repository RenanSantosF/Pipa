shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
// Copas de árvore com cartões de folhagem real (atlas de folhas Poly Haven, CC0).
// UV  = coordenadas da textura de galho com folhas.
// UV2 = (peso do balanço, fase própria da árvore). Balanço todo na GPU.

uniform sampler2D leaves : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 wind_direction = vec3(0.0, 0.0, -1.0);
uniform float wind_strength = 0.25;
uniform float gust = 1.0;

void vertex() {
	float w = UV2.x;
	float phase = UV2.y;
	float t = TIME;
	float sway = sin(t * 1.6 + phase) * 0.6 + sin(t * 2.9 + phase * 1.7) * 0.3;
	float flutter = sin(t * 7.0 + phase * 3.0 + VERTEX.x * 2.0 + VERTEX.z * 2.0) * 0.08;
	vec3 offset = wind_direction * (wind_strength * gust * w * (0.7 + 0.5 * sway));
	offset += vec3(flutter, flutter * 0.5, -flutter) * w * wind_strength;
	VERTEX += offset;
}

void fragment() {
	vec4 tex = texture(leaves, UV);
	if (tex.a < 0.45) {
		discard;
	}
	ALBEDO = tex.rgb * pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.35, 0.4, 0.15);
}
