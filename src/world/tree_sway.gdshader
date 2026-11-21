shader_type spatial;
// Balanço das copas das árvores pelo vento, todo na GPU (custo zero de CPU).
// UV.x = peso do balanço (0 = parado), UV.y = fase própria de cada árvore.
// Cores de vértice gravadas em sRGB.

uniform vec3 wind_direction = vec3(0.0, 0.0, -1.0);
uniform float wind_strength = 0.25;
uniform float gust = 1.0;

void vertex() {
	float w = UV.x;
	float phase = UV.y;
	float t = TIME;
	float sway = sin(t * 1.6 + phase) * 0.6 + sin(t * 2.9 + phase * 1.7) * 0.3;
	float flutter = sin(t * 7.0 + phase * 3.0 + VERTEX.x * 2.0 + VERTEX.z * 2.0) * 0.08;
	vec3 offset = wind_direction * (wind_strength * gust * w * (0.7 + 0.5 * sway));
	offset += vec3(flutter, flutter * 0.5, -flutter) * w * wind_strength;
	VERTEX += offset;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
