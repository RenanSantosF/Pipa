shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Tirinhas e barbante da rabiola com BORDA SUAVE de ~1,5 px em qualquer distância:
// UV.x vai de -1 a 1 através da largura e UV.y é a largura em pixels / 1,5 — a
// opacidade cai só na borda (perto, a tirinha fica nítida; longe, fina, ela não vira
// degrau de pixel nem pisca). Cor do vértice em sRGB (blocos de cor da rabiola).

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float edge = max(UV.y, 1.0);
	float a = clamp((1.0 - abs(UV.x)) * edge, 0.0, 1.0);
	ALBEDO = to_linear(COLOR.rgb);
	ALPHA = a * COLOR.a;
}
