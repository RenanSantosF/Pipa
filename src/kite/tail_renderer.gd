class_name TailRenderer
extends MeshInstance3D
## Desenha a rabiola simulada (TailChain): barbante com laços de plástico
## ("bandeirinhas" amarradas no meio) em cores alternadas, voltados para a câmera.

## Laços da rabiola: espaçamento e tamanho (pipa M; escala com o tamanho).
const BOW_STEP := 0.085
const BOW_HALF_W := 0.055
const BOW_HALF_H := 0.022

var rig: KiteRig
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


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


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if rig == null or rig.tail == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var tail := rig.tail
	var n := tail.pos.size()
	if n < 1:
		return
	var cam_pos := cam.global_position
	var prof := rig.profile
	var k := prof.height / 0.65
	var t_now := Time.get_ticks_msec() / 1000.0
	# Pontos do barbante: ponta da pipa + nós da simulação.
	var pts := PackedVector3Array([tail.attach_point()])
	pts.append_array(tail.pos)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	# Barbante.
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).cross(cam_pos - a).normalized() * 0.0012
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			_im.surface_set_color(Color(0.9, 0.88, 0.82))
			_im.surface_add_vertex(v)
	# Laços de plástico ("bandeirinhas") a cada BOW_STEP ao longo do barbante
	# (longe não dá para ver os laços: desenha só uma fita colorida, bem mais barato).
	if cam_pos.distance_to(pts[0]) > 45.0:
		for i in pts.size() - 1:
			var a0 := pts[i]
			var b0 := pts[i + 1]
			var sd := (b0 - a0).cross(cam_pos - a0).normalized() * BOW_HALF_W * k * 0.6
			var col := prof.tail_color_a if i % 2 == 0 else prof.tail_color_b
			for v in [a0 - sd, a0 + sd, b0 + sd, a0 - sd, b0 + sd, b0 - sd]:
				_im.surface_set_color(col)
				_im.surface_add_vertex(v)
		_im.surface_end()
		return
	var acc := BOW_STEP * 0.5
	var bow_i := 0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var l := seg.length()
		if l < 1e-5:
			continue
		var t := seg / l
		while acc < l:
			var c := a + t * acc
			var to_cam := (cam_pos - c).normalized()
			var s := t.cross(to_cam).normalized()
			# Cada laço balança um pouco sozinho (plástico ao vento).
			var wob := sin(t_now * 13.0 + float(bow_i) * 1.7) * 0.35
			s = (s * cos(wob) + t * sin(wob)).normalized()
			var wb := BOW_HALF_W * k
			var hb := BOW_HALF_H * k
			var color := prof.tail_color_a if bow_i % 2 == 0 else prof.tail_color_b
			var tip := t * hb
			for v in [c, c + s * wb + tip, c + s * wb - tip, c, c - s * wb - tip, c - s * wb + tip]:
				_im.surface_set_color(color)
				_im.surface_add_vertex(v)
			acc += BOW_STEP * k
			bow_i += 1
		acc -= l
	_im.surface_end()
