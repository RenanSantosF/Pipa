class_name HouseBuilder
extends RefCounted
## Casa de bairro brasileiro (autoconstrução), montada num referencial local:
## a rua corre em Z, a casa cresce para +X, y = 0 é o nível da calçada.
## Variações: colada na calçada ou recuada com muro e portão, 1 a 3 andares
## (andares de cima menores, às vezes em tijolo aparente), laje com caixa d'água
## ou telhado de barro, porta de enrolar de garagem, janelas com grade e muro de
## arrimo quando o terreno desce atrás.

const WALL_COLORS := [
	Color(0.25, 0.50, 0.85), Color(0.20, 0.68, 0.70), Color(0.98, 0.82, 0.22), Color(0.95, 0.55, 0.22),
	Color(0.95, 0.52, 0.62), Color(0.42, 0.75, 0.36), Color(0.62, 0.46, 0.80), Color(0.95, 0.95, 0.92),
	Color(0.82, 0.28, 0.22), Color(0.76, 0.86, 0.32), Color(0.98, 0.70, 0.45), Color(0.55, 0.80, 0.95),
]
const MURO_COLORS := [Color(0.92, 0.91, 0.87), Color(0.63, 0.63, 0.61), Color(0.88, 0.82, 0.62), Color(0.75, 0.72, 0.68)]
const GATE_COLORS := [Color(0.16, 0.32, 0.22), Color(0.36, 0.36, 0.38), Color(0.16, 0.22, 0.45), Color(0.45, 0.26, 0.16), Color(0.55, 0.12, 0.1)]
const ROOF_COLORS := [Color(0.68, 0.33, 0.21), Color(0.60, 0.29, 0.19), Color(0.72, 0.40, 0.26), Color(0.62, 0.62, 0.60)]
const BRICK := Color(0.72, 0.40, 0.26)
const WATER_TANK := Color(0.22, 0.42, 0.72)
const GLASS := Color(0.12, 0.15, 0.18)
const FRAME := Color(0.93, 0.93, 0.9)
const BARS := Color(0.2, 0.2, 0.22)
const STORY_H := 2.7

var _sb: StreetBuilder
var _rng: RandomNumberGenerator
var frame := Transform3D.IDENTITY
var _z: float = 0.0  # z do mundo (fatia de malha)


func _init(street_builder: StreetBuilder, rng: RandomNumberGenerator) -> void:
	_sb = street_builder
	_rng = rng


func _pick(arr: Array) -> Color:
	var c: Color = arr[_rng.randi() % arr.size()]
	return c.darkened(_rng.randf_range(0.0, 0.12))


func _b(surface: String) -> MeshBatch:
	return _sb.batch_for(_z, surface)


func _box(surface: String, c: Vector3, size: Vector3, color: Color, collide: bool = false) -> void:
	var xf := frame * Transform3D(Basis.IDENTITY, c)
	_sb.batch_for(_z, surface).add_box(xf, size, color)
	if collide:
		_sb.add_collider(xf, size)


## Casa num lote: width ao longo da rua (z de -width/2 a +width/2), depth para +X,
## front = distância do eixo da rua até o alinhamento, drop = quanto o terreno
## desce (+) ou sobe (−) no fundo do lote em relação à calçada.
func build(lot_frame: Transform3D, width: float, front: float, depth: float, drop: float, detail: bool = true) -> void:
	frame = lot_frame
	_z = lot_frame.origin.z
	var z0 := -width * 0.5
	var setback := 0.0 if _rng.randf() < 0.4 else _rng.randf_range(1.5, 4.0)
	var hd := clampf(_rng.randf_range(6.0, 10.0), 4.0, depth - setback - 0.5)
	var hw := width - _rng.randf_range(0.0, 1.2)
	var house_z := z0 + 0.1 + hw * 0.5 if _rng.randf() < 0.5 else z0 + width - 0.1 - hw * 0.5
	var r := _rng.randf()
	var stories := 1 if r < 0.45 else (2 if r < 0.87 else 3)
	var fx := front + setback
	var cx := fx + hd * 0.5
	var color := _pick(WALL_COLORS)

	# Muro de arrimo / embasamento quando o terreno desce.
	if drop > 0.3:
		_box("muro", Vector3(front + depth * 0.5, -drop * 0.5, 0.0), Vector3(depth, drop, width), Color(0.7, 0.7, 0.68), true)
	# Quintal/garagem.
	_box("laje" if _rng.randf() < 0.6 else "ground", Vector3(front + depth * 0.5, 0.01, 0.0), Vector3(depth, 0.02, width), Color(0.6, 0.6, 0.58))

	# Muro da frente com portão (só se recuada).
	if setback > 1.0:
		var muro_h := _rng.randf_range(1.4, 2.0)
		var gate_w := 2.6
		var gz := _rng.randf_range(z0 + 0.4 + gate_w * 0.5, z0 + width - 0.4 - gate_w * 0.5)
		var mc := _pick(MURO_COLORS)
		_wall_z(front + 0.08, z0, gz - gate_w * 0.5, muro_h, mc)
		_wall_z(front + 0.08, gz + gate_w * 0.5, z0 + width, muro_h, mc)
		_box("metal", Vector3(front + 0.08, (muro_h - 0.1) * 0.5, gz), Vector3(0.06, muro_h - 0.1, gate_w), _pick(GATE_COLORS), true)

	# Andares (os de cima podem ser menores e em tijolo aparente).
	var y := 0.0
	var w_cur := hw
	var d_cur := hd
	var top_brick := false
	for s in stories:
		var brick := s > 0 and _rng.randf() < 0.06   # casas mais acabadas (v0.22)
		var surface := "brick" if brick else "plaster"
		var col := BRICK if brick else (color if s == 0 or _rng.randf() < 0.6 else _pick(WALL_COLORS))
		_box(surface, Vector3(fx + d_cur * 0.5, y + STORY_H * 0.5, house_z), Vector3(d_cur, STORY_H, w_cur), col, true)
		if not brick:
			_box(surface, Vector3(fx - 0.01, y + 0.3, house_z), Vector3(0.04, 0.6, w_cur + 0.02), col.darkened(0.3))
		# Laje entre andares (beiral).
		_box("laje", Vector3(fx + d_cur * 0.5 - 0.1, y + STORY_H + 0.06, house_z), Vector3(d_cur + 0.3, 0.12, w_cur + 0.3), Color(0.75, 0.74, 0.72))
		if detail:
			_facade(fx, y, house_z, w_cur, s == 0)
		y += STORY_H + 0.12
		top_brick = brick
		if s < stories - 1:
			w_cur = maxf(w_cur - _rng.randf_range(0.0, 2.0), 3.5)
			d_cur = maxf(d_cur - _rng.randf_range(0.0, 2.5), 3.5)

	# Cobertura.
	if not top_brick and _rng.randf() < 0.5:
		_gable_roof(fx + d_cur * 0.5, y, d_cur, w_cur, house_z, color)
	else:
		_slab_roof(fx + d_cur * 0.5, y, d_cur, w_cur, house_z, color)

	# Árvore no quintal.
	if detail and _rng.randf() < 0.07 and depth - setback - hd > 2.5:   # menos árvores (v0.22)
		var tp := frame * Vector3(front + depth - 1.8, 0.0, _rng.randf_range(z0 + 1.5, z0 + width - 1.5))
		_sb.add_tree(Vector3(tp.x, Ground.height_at(tp.x, tp.z), tp.z), "")


func _wall_z(x: float, za: float, zb: float, h: float, color: Color) -> void:
	var length := zb - za
	if length < 0.05:
		return
	var zc := (za + zb) * 0.5
	_box("muro", Vector3(x, h * 0.5, zc), Vector3(0.15, h, length), color, true)
	_box("muro", Vector3(x, 0.2, zc), Vector3(0.17, 0.4, length), color.darkened(0.3))


func _facade(fx: float, y: float, z: float, w: float, ground_floor: bool) -> void:
	var slots := 1 if w < 5.0 else (2 if w < 8.0 else 3)
	var garage := ground_floor and w > 5.5 and _rng.randf() < 0.35
	var used_z := -999.0
	if ground_floor:
		if garage:
			used_z = z - w * 0.5 + 1.6
			_box("metal", Vector3(fx - 0.04, 1.2, used_z), Vector3(0.08, 2.4, 2.8), _pick(GATE_COLORS))
		else:
			used_z = z + _rng.randf_range(-w * 0.3, w * 0.3)
			_box("metal", Vector3(fx - 0.03, 1.05, used_z), Vector3(0.08, 2.1, 0.9), _pick(GATE_COLORS).lightened(0.1))
	for i in slots:
		var wz := z - w * 0.5 + w * (float(i) + 0.5) / float(slots)
		if absf(wz - used_z) < 1.6:
			continue
		_window(fx, y + 1.55, wz)


func _window(fx: float, y: float, z: float) -> void:
	_box("plain", Vector3(fx - 0.02, y, z), Vector3(0.05, 1.2, 1.3), FRAME)
	_box("plain", Vector3(fx - 0.04, y, z), Vector3(0.04, 1.0, 1.1), GLASS)
	for i in 4:
		_box("plain", Vector3(fx - 0.09, y, z - 0.45 + 0.3 * i), Vector3(0.025, 1.0, 0.025), BARS)


func _gable_roof(cx: float, h: float, hd: float, hw: float, z: float, wall_color: Color) -> void:
	var angle := deg_to_rad(_rng.randf_range(14.0, 18.0))
	var a := hd * 0.5 + 0.45
	var slab_len := a / cos(angle)
	var rise := a * tan(angle)
	var color := _pick(ROOF_COLORS)
	var size := Vector3(slab_len, 0.08, hw + 0.6)
	for dir in [-1.0, 1.0]:
		var center := Vector3(cx + dir * a * 0.5, h + rise * 0.5 - 0.05, z)
		var xf := frame * Transform3D(Basis(Vector3(0, 0, 1), -angle * dir), center)
		_b("roof").add_box(xf, size, color.darkened(0.08 if dir > 0.0 else 0.0), Vector2.ZERO, false)
		_sb.add_collider(xf, size)
	var peak := h + (hd * 0.5) * tan(angle)
	for zend in [z - hw * 0.5, z + hw * 0.5]:
		var ze := float(zend)
		var n := frame.basis * Vector3(0, 0, signf(ze - z))
		_b("plaster").add_triangle(frame * Vector3(cx - hd * 0.5, h, ze), frame * Vector3(cx + hd * 0.5, h, ze), frame * Vector3(cx, peak, ze), n, wall_color)


func _slab_roof(cx: float, h: float, hd: float, hw: float, z: float, wall_color: Color) -> void:
	var ph := 0.45
	var t := 0.12
	var pc := wall_color.lightened(0.05)
	_box("plaster", Vector3(cx, h + ph * 0.5, z - hw * 0.5 + t * 0.5), Vector3(hd, ph, t), pc)
	_box("plaster", Vector3(cx, h + ph * 0.5, z + hw * 0.5 - t * 0.5), Vector3(hd, ph, t), pc)
	_box("plaster", Vector3(cx - hd * 0.5 + t * 0.5, h + ph * 0.5, z), Vector3(t, ph, hw), pc)
	_box("plaster", Vector3(cx + hd * 0.5 - t * 0.5, h + ph * 0.5, z), Vector3(t, ph, hw), pc)
	var tank := Vector3(cx + hd * 0.25, h + 0.45, z + _rng.randf_range(-hw * 0.3, hw * 0.3))
	var txf := frame * Transform3D(Basis.IDENTITY, tank)
	_b("plain").add_cylinder(txf, 0.55, 0.9, 12, WATER_TANK)
	_b("plain").add_cylinder(frame * Transform3D(Basis.IDENTITY, tank + Vector3(0, 0.5, 0)), 0.58, 0.1, 12, WATER_TANK.darkened(0.2))
	_sb.add_collider(txf, Vector3(1.1, 0.9, 1.1))
	if _rng.randf() < 0.3:
		var bh := _rng.randf_range(0.8, 1.6)
		_box("brick", Vector3(cx - hd * 0.2, h + bh * 0.5, z), Vector3(hd * 0.4, bh, hw * 0.5), BRICK.darkened(_rng.randf() * 0.15), true)
