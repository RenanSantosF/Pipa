shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, shadows_disabled;
// Pipa de papel de seda (losango, 3 varetas). A forma envergada é aplicada aqui,
// a partir do diedro ATUAL de cada meia-vela (o mesmo da física): no desbico a
// vareta de um lado fecha e o jogador vê a vela flexionar.
//   z(x) = −tan(diedro do lado) · x² / meia_envergadura   (curva da travessa)
// + barriga do papel entre as varetas + tremulação proporcional ao vento.

uniform float dihedral_l = 0.18;
uniform float dihedral_r = 0.18;
uniform float half_w = 0.275;
uniform float kite_h = 0.65;
uniform float cross_at = 0.32;
uniform float lower_at = 0.66;
uniform float airspeed = 6.0;
uniform float phase = 0.0;
uniform vec3 color_a : source_color = vec3(0.95, 0.78, 0.15);
uniform vec3 color_b : source_color = vec3(0.88, 0.2, 0.18);
uniform int pattern = 0;
// 0 = papel (vela) · 1 = vareta de bambu / linha do cabresto (cor do vértice).
uniform int kind = 0;

varying vec2 kite_xy;   // x (m) e distância a partir do nariz (m)

float bow_z(float x) {
	float d = x < 0.0 ? dihedral_l : dihedral_r;
	return -tan(d) * x * x / max(half_w, 0.01);
}

float row_half_w(float yn) {
	float c = cross_at * kite_h;
	return yn < c ? half_w * yn / max(c, 0.001) : half_w * (kite_h - yn) / max(kite_h - c, 0.001);
}

void vertex() {
	float x = VERTEX.x;
	float yn = UV.y * kite_h;
	kite_xy = vec2(x, yn);
	float z = bow_z(x);
	float dzdx = -2.0 * tan(x < 0.0 ? dihedral_l : dihedral_r) * x / max(half_w, 0.01);
	if (kind == 0) {
		// Barriga do papel entre as varetas (o vento empurra a seda para trás).
		float hw = max(row_half_w(yn), 0.001);
		float across = clamp(abs(x) / hw, 0.0, 1.0);
		float c = cross_at * kite_h;
		float l = lower_at * kite_h;
		float between = yn < c ? sin(3.14159 * yn / max(c, 0.001))
			: (yn < l ? sin(3.14159 * (yn - c) / max(l - c, 0.001)) : sin(3.14159 * (yn - l) / max(kite_h - l, 0.001)));
		float bulge = sin(3.14159 * across) * between;
		float wind = clamp(airspeed / 8.0, 0.0, 1.6);
		z -= 0.012 * kite_h * bulge * (0.4 + 0.6 * wind);
		// Tremulação: maior longe das varetas (pontas e parte de baixo).
		float edge = across * across + max(yn - l, 0.0) / max(kite_h - l, 0.001);
		float t = TIME * (9.0 + 4.0 * wind) + phase;
		z += 0.004 * kite_h * wind * edge * sin(t + yn * 11.0 + x * 7.0);
	}
	VERTEX.z += z;
	if (kind == 0) {
		NORMAL = normalize(vec3(-dzdx, 0.0, 1.0));
	}
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = n;
	if (kind == 1) {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = 0.6;
		SPECULAR = 0.3;
	} else {
		float x = kite_xy.x;
		float yn = kite_xy.y;
		float u = x / (2.0 * half_w) + 0.5;
		float v = yn / kite_h;
		vec3 col = color_a;
		if (pattern == 0) {
			// Dividida na diagonal (clássica de duas cores).
			col = (u - 0.5) > (v - cross_at) * 0.9 ? color_b : color_a;
		} else if (pattern == 1) {
			// Faixas horizontais.
			col = mod(floor(v * 6.0), 2.0) < 1.0 ? color_a : color_b;
		} else if (pattern == 2) {
			// Olho: círculo no centro.
			vec2 p = vec2((u - 0.5) * 2.0 * half_w, yn - cross_at * kite_h * 1.15);
			float r = length(p) / kite_h;
			col = r < 0.13 ? color_b : (r < 0.16 ? vec3(0.96, 0.95, 0.9) : color_a);
		} else {
			// Xadrez de 4 quadrantes.
			col = ((u < 0.5) != (v < cross_at)) ? color_b : color_a;
		}
		float hw = row_half_w(yn);
		float edge = hw - abs(x);
		// Bainha dobrada (papel duplo, mais opaco) e cola por cima das varetas.
		float hem = 1.0 - smoothstep(0.004, 0.009, edge);
		float glue = 1.0 - smoothstep(0.0025, 0.006, abs(x));
		glue = max(glue, 1.0 - smoothstep(0.003, 0.007, abs(yn - cross_at * kite_h)));
		glue = max(glue, (1.0 - smoothstep(0.003, 0.006, abs(yn - lower_at * kite_h))) * step(abs(x), hw));
		col = mix(col, col * 0.78, max(hem * 0.7, glue * 0.55));
		ALBEDO = col;
		ROUGHNESS = 0.78;
		SPECULAR = 0.2;
		// Papel de seda: a luz atravessa (menos na bainha e nas varetas).
		BACKLIGHT = col * (0.55 - 0.35 * max(hem, glue));
	}
}
