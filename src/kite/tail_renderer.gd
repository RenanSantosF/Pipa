class_name TailRenderer
extends MeshInstance3D
## Desenha a rabiola simulada (TailChain) como rabiola de sacolinha: barbante fino
## (curva lisa entre os nós da simulação) com TIRINHAS de plástico amarradas pelo
## meio a cada ~7,5 cm. As duas pontas de cada tirinha vão para trás (a favor do
## vento ao longo da rabiola), abertas em V e tremulando; cores em blocos.

## Tirinhas (pipa M; escala com o tamanho): espaçamento, comprimento, largura.
const KNOT_STEP := 0.075
const STRIP_LEN := 0.095
const STRIP_W := 0.022
## Abertura do V (rad) e tremulação.
const SPREAD := 0.55
const FLUTTER := 0.32
## Tirinhas da mesma cor seguidas.
const BLOCK := 4

var rig: KiteRig
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _pts := PackedVector3Array()
var _curve := PackedVector3Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 20.0
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func bind(p_rig: KiteRig) -> void:
	rig = p_rig
	if rig == null:
		_im.clear_surfaces()


func _process(_delta: float) -> void:
	if rig == null or rig.tail == null or rig.tail.pos.size() < 1:
		_im.clear_surfaces()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var tail := rig.tail
	# Longe: redesenha a cada 2 quadros.
	if cam.global_position.distance_to(tail.pos[0]) > 45.0 and (Engine.get_process_frames() + get_instance_id()) % 2 == 0:
		return
	_im.clear_surfaces()
	var cam_pos := cam.global_position
	var prof := rig.profile
	var k := prof.height / 0.65
	_pts.resize(0)
	_pts.append(tail.attach_point())
	_pts.append_array(tail.pos)
	var far := cam_pos.distance_to(_pts[0]) > 45.0
	# Curva lisa (Catmull-Rom) entre os nós: a rabiola é maleável, não um serrote.
	_curve.resize(0)
	var n := _pts.size()
	var sub := 1 if far else 3
	for i in n - 1:
		var p0 := _pts[maxi(i - 1, 0)]
		var p1 := _pts[i]
		var p2 := _pts[i + 1]
		var p3 := _pts[mini(i + 2, n - 1)]
		for s in sub:
			_curve.append(_catmull(p0, p1, p2, p3, float(s) / float(sub)))
	_curve.append(_pts[n - 1])

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	# Barbante (bem fino).
	var string_col := Color(0.92, 0.9, 0.84)
	for i in _curve.size() - 1:
		var a := _curve[i]
		var b := _curve[i + 1]
		var side := (b - a).cross(cam_pos - a).normalized() * 0.0009
		_tri(a - side, a + side, b + side, string_col)
		_tri(a - side, b + side, b - side, string_col)
	if far:
		# Longe: uma fita colorida fina (mesma silhueta, bem mais barato).
		for i in _curve.size() - 1:
			var a0 := _curve[i]
			var b0 := _curve[i + 1]
			var sd := (b0 - a0).cross(cam_pos - a0).normalized() * STRIP_LEN * k * 0.45
			var col := prof.tail_color_a if (i / 2) % 2 == 0 else prof.tail_color_b
			_tri(a0 - sd, a0 + sd, b0 + sd, col)
			_tri(a0 - sd, b0 + sd, b0 - sd, col)
		_im.surface_end()
		return
	var t_now := Time.get_ticks_msec() / 1000.0
	var step := KNOT_STEP * k
	var acc := step * 0.6
	var knot := 0
	for i in _curve.size() - 1:
		var a := _curve[i]
		var b := _curve[i + 1]
		var seg := b - a
		var l := seg.length()
		if l < 1e-5:
			continue
		var t := seg / l              # para trás, ao longo da rabiola
		while acc < l:
			var c := a + t * acc
			var to_cam := (cam_pos - c).normalized()
			var s := t.cross(to_cam).normalized()
			# Cada nó amarrado de um jeito: o V gira em volta do barbante (às vezes
			# de lado, às vezes de frente), abre e tem tamanho diferentes — e rola
			# devagar com o vento. Nada de "pilha de setas" igualzinha.
			var h1 := fposmod(sin(float(knot) * 12.9898) * 43758.5453, 1.0)
			var h2 := fposmod(sin(float(knot) * 78.233) * 12543.137, 1.0)
			s = s.rotated(t, (h1 - 0.5) * 2.4 + 0.5 * sin(t_now * 2.3 + float(knot)))
			var color := prof.tail_color_a if (knot / BLOCK) % 2 == 0 else prof.tail_color_b
			var ph := t_now * 11.0 + float(knot) * 1.37
			for sd2 in [-1.0, 1.0]:
				var side: float = sd2
				# Cada ponta da tirinha: aberta em V para trás, tremulando sozinha.
				var ang := SPREAD * (0.6 + 0.8 * h2) + FLUTTER * sin(ph + side * 1.9)
				var dir := (t * cos(ang) + s * (side * sin(ang))).normalized()
				var len := STRIP_LEN * k * (0.7 + 0.5 * fposmod(h1 + h2 * side, 1.0)) * (0.9 + 0.1 * sin(ph * 0.7 + side))
				var w := s.cross(dir).cross(dir).normalized() * (STRIP_W * k * 0.5)
				var tip := c + dir * len
				# Torcida: a ponta gira um pouco (plástico ao vento).
				var tw := w.rotated(dir, 0.8 * sin(ph * 1.3 + side * 2.0))
				_tri(c - w, c + w, tip + tw, color)
				_tri(c - w, tip + tw, tip - tw, color.darkened(0.12))
			acc += step
			knot += 1
		acc -= l
	_im.surface_end()


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_im.surface_set_color(col)
	_im.surface_add_vertex(a)
	_im.surface_set_color(col)
	_im.surface_add_vertex(b)
	_im.surface_set_color(col)
	_im.surface_add_vertex(c)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
