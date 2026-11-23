class_name MeshBatch
extends RefCounted
## Acumula geometria simples (caixas, cilindros, esferas) com cor por vértice
## em UMA malha. Todo o cenário estático vira poucas malhas → poucas draw calls,
## essencial no celular. Opcionalmente grava UV = (peso do balanço, fase) para
## o shader de vento das árvores.

const _FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
]

var _st := SurfaceTool.new()
var _with_uv: bool = false
var _vertex_count: int = 0
## Quanto da cor de vértice tinge a textura (0 = textura pura, 1 = cor cheia).
var tint: float = 1.0
## Gera UV por projeção no mundo + tangentes (para materiais com textura).
var textured: bool = false


func _init(with_uv: bool = false, p_tint: float = 1.0, p_textured: bool = false) -> void:
	_with_uv = with_uv
	tint = p_tint
	textured = p_textured
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func is_empty() -> bool:
	return _vertex_count == 0


## Caixa centrada em xf.origin com tamanho `size` (no espaço local de xf).
func add_box(xf: Transform3D, size: Vector3, color: Color, uv: Vector2 = Vector2.ZERO, skip_bottom: bool = true) -> void:
	var h := size * 0.5
	for f in _FACES:
		var n: Vector3 = f[0]
		if skip_bottom and n.y < -0.5:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var uu := u * h
		var vv := v * h
		var wn := (xf.basis * n).normalized()
		add_quad(xf * (c - uu - vv), xf * (c + uu - vv), xf * (c + uu + vv), xf * (c - uu + vv), wn, color, uv)


## Quadrilátero plano (a, b, c, d em sequência) com normal n.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color, uv: Vector2 = Vector2.ZERO) -> void:
	add_triangle(a, b, c, n, color, uv)
	add_triangle(a, c, d, n, color, uv)


## Triângulo com normal plana. A ordem dos vértices é corrigida automaticamente
## (o Godot usa ordem horária para faces frontais).
func add_triangle(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color, uv: Vector2 = Vector2.ZERO) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	_vertex(a, n, color, uv)
	_vertex(b, n, color, uv)
	_vertex(c, n, color, uv)


## Cilindro vertical (eixo Y local de xf), com tampa superior.
func add_cylinder(xf: Transform3D, radius: float, height: float, segments: int, color: Color, uv: Vector2 = Vector2.ZERO) -> void:
	var hh := height * 0.5
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := (xf.basis * (d0 + d1).normalized()).normalized()
		var p0 := xf * (d0 * radius + Vector3(0, -hh, 0))
		var p1 := xf * (d1 * radius + Vector3(0, -hh, 0))
		var p2 := xf * (d1 * radius + Vector3(0, hh, 0))
		var p3 := xf * (d0 * radius + Vector3(0, hh, 0))
		add_quad(p0, p1, p2, p3, n, color, uv)
		var top := xf * Vector3(0, hh, 0)
		add_triangle(top, p3, p2, (xf.basis * Vector3.UP).normalized(), color, uv)


## Esfera de baixa resolução com normais suaves (copas de árvore, arbustos).
func add_sphere(center: Vector3, radius: Vector3, segments: int, rings: int, color: Color, uv: Vector2 = Vector2.ZERO) -> void:
	for r in rings:
		var t0 := PI * float(r) / float(rings)
		var t1 := PI * float(r + 1) / float(rings)
		for s in segments:
			var p0 := TAU * float(s) / float(segments)
			var p1 := TAU * float(s + 1) / float(segments)
			var d00 := _sph(t0, p0)
			var d01 := _sph(t0, p1)
			var d10 := _sph(t1, p0)
			var d11 := _sph(t1, p1)
			_smooth_tri(center, radius, d00, d10, d11, color, uv)
			_smooth_tri(center, radius, d00, d11, d01, color, uv)


## Cartão de folhagem (quad duplo-face). `up` aponta da base do galho (UV y=1) para a ponta.
func add_card(center: Vector3, right: Vector3, up: Vector3, size: float, n: Vector3, color: Color, sway: Vector2) -> void:
	var r := right * (size * 0.5)
	var u := up * (size * 0.5)
	var p := [center - r - u, center + r - u, center + r + u, center - r + u]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		_st.set_color(color)
		_st.set_normal(n)
		_st.set_uv(uvs[idx])
		_st.set_uv2(sway)
		_st.add_vertex(p[idx])
		_vertex_count += 1


## Cartão retangular (folha de coqueiro/bananeira): largura × comprimento.
func add_card_rect(center: Vector3, right: Vector3, up: Vector3, width: float, length: float, n: Vector3, color: Color, sway: Vector2) -> void:
	var r := right * (width * 0.5)
	var u := up * (length * 0.5)
	var p := [center - r - u, center + r - u, center + r + u, center - r + u]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		_st.set_color(color)
		_st.set_normal(n)
		_st.set_uv(uvs[idx])
		_st.set_uv2(sway)
		_st.add_vertex(p[idx])
		_vertex_count += 1


func _sph(theta: float, phi: float) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))


func _smooth_tri(center: Vector3, radius: Vector3, da: Vector3, db: Vector3, dc: Vector3, color: Color, uv: Vector2) -> void:
	var a := center + da * radius
	var b := center + db * radius
	var c := center + dc * radius
	var face_n := (da + db + dc)
	if (b - a).cross(c - a).dot(face_n) > 0.0:
		var tb := b
		b = c
		c = tb
		var tdb := db
		db = dc
		dc = tdb
	_vertex(a, (da / radius).normalized(), color, uv)
	_vertex(b, (db / radius).normalized(), color, uv)
	_vertex(c, (dc / radius).normalized(), color, uv)


func _vertex(p: Vector3, n: Vector3, color: Color, uv: Vector2) -> void:
	_st.set_color(Color.WHITE.lerp(color, tint) if tint < 1.0 else color)
	_st.set_normal(n)
	if _with_uv:
		_st.set_uv2(uv)
	elif textured:
		# Projeção pelo eixo dominante da normal (tiling contínuo entre peças).
		var an := n.abs()
		if an.y >= an.x and an.y >= an.z:
			_st.set_uv(Vector2(p.x, p.z))
		elif an.x >= an.z:
			_st.set_uv(Vector2(p.z * signf(n.x), -p.y))
		else:
			_st.set_uv(Vector2(-p.x * signf(n.z), -p.y))
	_st.add_vertex(p)
	_vertex_count += 1


func commit() -> ArrayMesh:
	if _vertex_count == 0:
		return null
	if textured:
		_st.generate_tangents()
	return _st.commit()
