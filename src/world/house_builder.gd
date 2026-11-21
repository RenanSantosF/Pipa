class_name HouseBuilder
extends RefCounted
## Monta uma casa de bairro brasileiro dentro de um lote: muro com portão e barrado,
## casa térrea ou sobrado, telhado de telha ou laje com caixa d'água, janelas com grade.
## Escreve geometria nos MeshBatch do StreetBuilder e registra colisões.

const WALL_COLORS := [
	Color(0.93, 0.85, 0.55), Color(0.62, 0.80, 0.74), Color(0.92, 0.72, 0.70),
	Color(0.66, 0.76, 0.88), Color(0.92, 0.90, 0.84), Color(0.95, 0.72, 0.48),
	Color(0.76, 0.85, 0.60), Color(0.86, 0.80, 0.70), Color(0.80, 0.66, 0.80),
]
const MURO_COLORS := [
	Color(0.92, 0.91, 0.87), Color(0.63, 0.63, 0.61), Color(0.88, 0.82, 0.62), Color(0.75, 0.72, 0.68),
]
const GATE_COLORS := [
	Color(0.16, 0.32, 0.22), Color(0.36, 0.36, 0.38), Color(0.16, 0.22, 0.38), Color(0.40, 0.26, 0.16),
]
const ROOF_COLORS := [
	Color(0.68, 0.33, 0.21), Color(0.60, 0.29, 0.19), Color(0.72, 0.40, 0.26), Color(0.62, 0.62, 0.60),
]
const BRICK := Color(0.70, 0.38, 0.25)
const WATER_TANK := Color(0.22, 0.42, 0.72)
const GLASS := Color(0.12, 0.15, 0.18)
const FRAME := Color(0.93, 0.93, 0.9)
const BARS := Color(0.2, 0.2, 0.22)

var _sb: StreetBuilder
var _rng: RandomNumberGenerator


func _init(street_builder: StreetBuilder, rng: RandomNumberGenerator) -> void:
	_sb = street_builder
	_rng = rng


func _pick(arr: Array) -> Color:
	var c: Color = arr[_rng.randi() % arr.size()]
	return c.darkened(_rng.randf_range(0.0, 0.12))


## side: +1 = lado direito (x > 0), -1 = esquerdo. front: distância do eixo da rua até o muro.
func build(side: float, z0: float, width: float, front: float, depth: float) -> void:
	var s := side
	var zc := z0 + width * 0.5
	var b := _sb.batch_for(zc)
	var muro_color := _pick(MURO_COLORS)
	var wall_color := _pick(WALL_COLORS)

	# Piso do lote (cimento ou terra/grama).
	var yard := Color(0.55, 0.54, 0.5) if _rng.randf() < 0.5 else Color(0.48, 0.47, 0.30)
	b.add_box(_xf(Vector3(s * (front + depth * 0.5), 0.01, zc)), Vector3(depth, 0.02, width), yard.darkened(_rng.randf() * 0.1))

	# Muro da frente com portão.
	var muro_h := _rng.randf_range(1.5, 2.0)
	var gate_w := 2.6
	var gate_z := _rng.randf_range(z0 + 0.4 + gate_w * 0.5, z0 + width - 0.4 - gate_w * 0.5)
	var mx := s * (front + 0.08)
	_wall_z(b, mx, z0, gate_z - gate_w * 0.5, muro_h, 0.15, muro_color, true)
	_wall_z(b, mx, gate_z + gate_w * 0.5, z0 + width, muro_h, 0.15, muro_color, true)
	b.add_box(_xf(Vector3(mx, (muro_h - 0.1) * 0.5, gate_z)), Vector3(0.06, muro_h - 0.1, gate_w), _pick(GATE_COLORS))
	_sb.add_collider(_xf(Vector3(mx, muro_h * 0.5, gate_z)), Vector3(0.1, muro_h, gate_w))

	# Muros laterais e de fundo.
	var side_h := 1.8
	b.add_box(_xf(Vector3(s * (front + depth * 0.5), side_h * 0.5, z0)), Vector3(depth, side_h, 0.12), muro_color)
	_sb.add_collider(_xf(Vector3(s * (front + depth * 0.5), side_h * 0.5, z0)), Vector3(depth, side_h, 0.12))
	b.add_box(_xf(Vector3(s * (front + depth), side_h * 0.5, zc)), Vector3(0.12, side_h, width), muro_color)
	_sb.add_collider(_xf(Vector3(s * (front + depth), side_h * 0.5, zc)), Vector3(0.12, side_h, width))

	# Casa.
	var setback := _rng.randf_range(2.5, 4.5)
	var hd := minf(_rng.randf_range(6.5, 9.0), depth - setback - 1.0)
	var hw := width - _rng.randf_range(1.2, 2.6)
	var house_z := z0 + 0.3 + hw * 0.5 if _rng.randf() < 0.5 else z0 + width - 0.3 - hw * 0.5
	var stories := 2 if _rng.randf() < 0.25 else 1
	var h := 2.9 * stories
	var cx := s * (front + setback + hd * 0.5)
	b.add_box(_xf(Vector3(cx, h * 0.5, house_z)), Vector3(hd, h, hw), wall_color)
	_sb.add_collider(_xf(Vector3(cx, h * 0.5, house_z)), Vector3(hd, h, hw))
	# Barrado (faixa escura embaixo da fachada).
	var fx := s * (front + setback)
	b.add_box(_xf(Vector3(fx - s * 0.01, 0.3, house_z)), Vector3(0.04, 0.6, hw + 0.02), wall_color.darkened(0.35))

	# Porta e janelas na fachada.
	var door_z := house_z + _rng.randf_range(-hw * 0.3, hw * 0.3)
	b.add_box(_xf(Vector3(fx - s * 0.03, 1.05, door_z)), Vector3(0.08, 2.1, 0.9), _pick(GATE_COLORS).lightened(0.1))
	for story in stories:
		var wy := 1.55 + 2.9 * story
		var slots := [house_z - hw * 0.28, house_z + hw * 0.28]
		for wz in slots:
			if story == 0 and absf(float(wz) - door_z) < 1.3:
				continue
			_window(b, fx, s, wy, float(wz))

	# Telhado.
	if _rng.randf() < 0.5:
		_gable_roof(b, cx, s, h, hd, hw, house_z, wall_color)
	else:
		_slab_roof(b, cx, s, h, hd, hw, house_z, wall_color)

	# Árvore no quintal (mangueira/goiabeira).
	if _rng.randf() < 0.45:
		var tx := s * (front + depth - 2.2)
		var tz := z0 + _rng.randf_range(2.0, width - 2.0)
		_sb.add_tree(Vector3(tx, 0, tz), _rng.randf_range(1.6, 2.4), _rng.randf_range(3.0, 4.2))


func _wall_z(b: MeshBatch, x: float, za: float, zb: float, h: float, t: float, color: Color, stripe: bool) -> void:
	var length := zb - za
	if length < 0.05:
		return
	var c := Vector3(x, h * 0.5, (za + zb) * 0.5)
	b.add_box(_xf(c), Vector3(t, h, length), color)
	if stripe:
		b.add_box(_xf(Vector3(x, 0.2, c.z)), Vector3(t + 0.02, 0.4, length), color.darkened(0.3))
	b.add_box(_xf(Vector3(x, h + 0.03, c.z)), Vector3(t + 0.06, 0.06, length), color.lightened(0.15))
	_sb.add_collider(_xf(c), Vector3(t, h, length))


func _window(b: MeshBatch, fx: float, s: float, y: float, z: float) -> void:
	b.add_box(_xf(Vector3(fx - s * 0.02, y, z)), Vector3(0.05, 1.2, 1.3), FRAME)
	b.add_box(_xf(Vector3(fx - s * 0.04, y, z)), Vector3(0.04, 1.0, 1.1), GLASS)
	for i in 4:
		var bz := z - 0.45 + 0.3 * i
		b.add_box(_xf(Vector3(fx - s * 0.09, y, bz)), Vector3(0.025, 1.0, 0.025), BARS)


func _gable_roof(b: MeshBatch, cx: float, s: float, h: float, hd: float, hw: float, z: float, wall_color: Color) -> void:
	var angle := deg_to_rad(_rng.randf_range(18.0, 26.0))
	var a := hd * 0.5 + 0.45
	var slab_len := a / cos(angle)
	var rise := a * tan(angle)
	var color := _pick(ROOF_COLORS)
	var size := Vector3(slab_len, 0.08, hw + 0.6)
	for dir in [-1.0, 1.0]:
		var center := Vector3(cx + s * dir * a * 0.5, h + rise * 0.5 - 0.05, z)
		var xf := Transform3D(Basis(Vector3(0, 0, 1), -angle * s * dir), center)
		b.add_box(xf, size, color.darkened(0.08 if dir > 0.0 else 0.0), Vector2.ZERO, false)
		_sb.add_collider(xf, size)
	# Oitões (triângulos das pontas).
	var peak := h + (hd * 0.5) * tan(angle)
	for zend in [z - hw * 0.5, z + hw * 0.5]:
		var ze := float(zend)
		var n := Vector3(0, 0, signf(ze - z))
		b.add_triangle(Vector3(cx - hd * 0.5, h, ze), Vector3(cx + hd * 0.5, h, ze), Vector3(cx, peak, ze), n, wall_color)


func _slab_roof(b: MeshBatch, cx: float, s: float, h: float, hd: float, hw: float, z: float, wall_color: Color) -> void:
	var ph := 0.45
	var t := 0.12
	var pc := wall_color.lightened(0.05)
	b.add_box(_xf(Vector3(cx, h + ph * 0.5, z - hw * 0.5 + t * 0.5)), Vector3(hd, ph, t), pc)
	b.add_box(_xf(Vector3(cx, h + ph * 0.5, z + hw * 0.5 - t * 0.5)), Vector3(hd, ph, t), pc)
	b.add_box(_xf(Vector3(cx - hd * 0.5 + t * 0.5, h + ph * 0.5, z)), Vector3(t, ph, hw), pc)
	b.add_box(_xf(Vector3(cx + hd * 0.5 - t * 0.5, h + ph * 0.5, z)), Vector3(t, ph, hw), pc)
	b.add_box(_xf(Vector3(cx, h + 0.005, z)), Vector3(hd - 0.2, 0.01, hw - 0.2), Color(0.55, 0.54, 0.52))
	# Caixa d'água azul.
	var tank := Vector3(cx + s * hd * 0.25, h + 0.45, z + _rng.randf_range(-hw * 0.3, hw * 0.3))
	b.add_cylinder(_xf(tank), 0.55, 0.9, 12, WATER_TANK)
	b.add_cylinder(_xf(tank + Vector3(0, 0.5, 0)), 0.58, 0.1, 12, WATER_TANK.darkened(0.2))
	_sb.add_collider(_xf(tank), Vector3(1.1, 0.9, 1.1))
	# Às vezes, um "puxadinho" de tijolo em construção na laje.
	if _rng.randf() < 0.3:
		var bh := _rng.randf_range(0.8, 1.6)
		var bc := Vector3(cx - s * hd * 0.2, h + bh * 0.5, z)
		b.add_box(_xf(bc), Vector3(hd * 0.4, bh, hw * 0.5), BRICK.darkened(_rng.randf() * 0.15))
		_sb.add_collider(_xf(bc), Vector3(hd * 0.4, bh, hw * 0.5))


static func _xf(origin: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin)
