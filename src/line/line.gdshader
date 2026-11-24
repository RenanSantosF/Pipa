shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Linha de pipa fina: a fita tem ~2 px de largura e a opacidade cai do centro para
// as bordas (perfil triangular = ~1 px de peso, sem serrilhado). A cor do vértice
// traz o esmaecimento pela distância (linha real é mais fina que um pixel).

uniform vec4 line_color : source_color = vec4(0.96, 0.95, 0.9, 1.0);

void fragment() {
	float a = 1.0 - abs(UV.x);
	ALBEDO = line_color.rgb;
	ALPHA = clamp(a * COLOR.a * 1.15, 0.0, 1.0);
}
