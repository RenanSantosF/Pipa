shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Rabiola de longe: fita com perfil de opacidade triangular através da largura
// (UV.x de -1 a 1) — a borda some suave em vez de virar degraus de pixel (no celular
// a cena é desenhada em resolução menor e ampliada; geometria fina serrilhava).
// A cor do vértice (sRGB) traz as faixas das duas cores da rabiola e o esmaecimento.

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float a = 1.0 - abs(UV.x);
	ALBEDO = to_linear(COLOR.rgb);
	ALPHA = clamp(a * COLOR.a * 1.4, 0.0, 1.0);
}
