class_name TailRenderer
extends MeshInstance3D
## Desenha a rabiola simulada (TailChain) como rabiola de sacolinha: barbante fino
## (curva lisa entre os nós da simulação) com TIRINHAS de plástico amarradas pelo
## meio a cada ~7,5 cm. As duas pontas de cada tirinha vão para trás (a favor do
## vento ao longo da rabiola), abertas em V e tremulando; cores em blocos.

## Tirinhas (pipa M; escala com o tamanho): espaçamento, comprimento, largura.
const KNOT_STEP := 0.11
const STRIP_LEN := 0.14
const STRIP_W := 0.022
## Fita: ângulo para o lado (rad) e trechos (para ondular).
const STRIP_ANGLE := 0.32
const STRIP_SEGS := 4
## Ondulação da fita com o vento (rad).
const FLUTTER := 0.55
## Tirinhas da mesma cor seguidas.
const BLOCK := 4
## Barbante sem tirinhas entre a pipa e o começo da rabiola (m, pipa M).
const GAP := 0.3
## Tamanho mínimo de uma tirinha na tela (px) e o quanto ela pode crescer longe.
const MIN_STRIP_PX := 10.0
const MIN_STRIP_W_PX := 2.5
const MAX_EXAGGERATION := 4.0

var rig: KiteRig
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _mat_far := ShaderMaterial.new()
const FAR_SHADER := preload("res://src/kite/tail_far.gdshader")
var _pts := PackedVector3Array()
var _curve := PackedVector3Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	_mat_far.shader = FAR_SHADER
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
	var k := prof.height / 0.65 * rig.visual_scale
	_pts.resize(0)
	# Interpolado entre os ticks da física (liso a 60 quadros/s).
	var fr := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	_pts.append(rig.visual_pose() * rig.body.tail_local)
	if tail.tick_prev.size() == tail.pos.size():
		for i in tail.pos.size():
			_pts.append(tail.tick_prev[i].lerp(tail.pos[i], fr))
	else:
		_pts.append_array(tail.pos)
	# Pipa desenhada maior (longe): a rabiola sai do desenho da pipa e volta para a
	# posição da física ao longo do primeiro terço.
	var off := rig.visual_tail_offset
	if off.length_squared() > 1e-6:
		var np := _pts.size()
		for i in np:
			var w := clampf(1.0 - float(i) / maxf(float(np - 1) * 0.35, 1.0), 0.0, 1.0)
			_pts[i] += off * w
	# Detalhe pelo TAMANHO NA TELA (v0.22): as TIRINHAS aparecem em qualquer distância.
	# Longe, cada tirinha fica com pelo menos MIN_STRIP_PX de comprimento e ~2 px de
	# largura (cresce até MAX_EXAGGERATION×) e o espaço entre elas cresce junto (menos
	# tirinhas, maiores) — de longe se vê a rabiola de fitas tremulando, não uma faixa.
	var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var px_ang := deg_to_rad(cam.fov) / (vp_h * get_viewport().scaling_3d_scale)
	var dist0 := cam_pos.distance_to(_pts[0])
	var px_m := maxf(dist0 * px_ang, 1e-6)          # metros por pixel na rabiola
	var strip_px := STRIP_LEN * k / px_m
	var ex := clampf(MIN_STRIP_PX / maxf(strip_px, 0.01), 1.0, MAX_EXAGGERATION)
	var far := strip_px * ex < 14.0                 # pequena na tela: menos detalhe
	var pxs := 1.5 if GameConfig.quality == GameConfig.Quality.LOW else 1.0
	# Curva lisa (Catmull-Rom) entre os nós: a rabiola é maleável, não um serrote.
	_curve.resize(0)
	var n := _pts.size()
	var sub := 2 if far else 3
	for i in n - 1:
		var p0 := _pts[maxi(i - 1, 0)]
		var p1 := _pts[i]
		var p2 := _pts[i + 1]
		var p3 := _pts[mini(i + 2, n - 1)]
		for s in sub:
			_curve.append(_catmull(p0, p1, p2, p3, float(s) / float(sub)))
	_curve.append(_pts[n - 1])

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_far)
	# Triângulo vazio: a superfície nunca fica sem vértices (rabiola cortada curtinha).
	_soft_tri(_pts[0], _pts[0], _pts[0], Color(0, 0, 0, 0), -1.0, 1.0, 1.0)
	# Barbante: fino, com ~1 px de largura no mínimo (borda suave).
	var string_col := Color(0.92, 0.9, 0.84, 0.9)
	for i in _curve.size() - 1:
		var a := _curve[i]
		var b := _curve[i + 1]
		var hw := maxf(0.0009, cam_pos.distance_to(a) * px_ang * 0.6 * pxs)
		var side := (b - a).cross(cam_pos - a).normalized() * hw
		var e := maxf(hw * 2.0 / maxf(cam_pos.distance_to(a) * px_ang, 1e-6) / 1.5, 1.0)
		_soft_quad(a - side, a + side, b + side, b - side, string_col, e)
	var t_now := Time.get_ticks_msec() / 1000.0
	var wind := clampf(Wind.get_reference_speed() / 6.0, 0.4, 1.8)
	# Longe o espaço entre fitas cresce MAIS que o tamanho delas: poucas fitas maiores
	# (antes de longe pareciam "mil fitas").
	var step := KNOT_STEP * k * pow(ex, 1.6)
	var segs := 2 if far else STRIP_SEGS
	# Primeiras tirinhas só depois de um pedaço de barbante (como na rabiola de verdade).
	var acc := GAP * k
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
			# Blocos de cor: longe (tirinhas maiores e mais espaçadas) o bloco tem menos
			# tirinhas, para a mesma quantidade de cor ao longo da rabiola.
			var blk := maxi(int(round(float(BLOCK) / ex)), 1)
			var color := prof.tail_color_a if (knot / blk) % 2 == 0 else prof.tail_color_b
			# Uma fita fina de sacola, amarrada de UM lado do barbante, indo para trás
			# e ondulando com o vento (a onda corre da amarração para a ponta).
			var ph := t_now * (9.0 + 5.0 * wind) + float(knot) * 0.9
			var dir := (t * cos(STRIP_ANGLE) + s * sin(STRIP_ANGLE)).normalized()
			var seg_len := STRIP_LEN * k * ex / float(segs)
			var px_here := maxf(cam_pos.distance_to(c) * px_ang, 1e-6)
			var half_w := maxf(STRIP_W * k * ex * 0.5, px_here * MIN_STRIP_W_PX * 0.5 * pxs)
			var edge := maxf(half_w * 2.0 / px_here / 1.5, 1.0)
			var p0 := c
			var w0 := s.cross(dir).cross(dir).normalized() * half_w
			for j in segs:
				var bend := FLUTTER * wind * sin(ph - float(j) * (1.6 * float(STRIP_SEGS) / float(segs))) * (0.4 + float(j) / float(segs))
				var dj := dir.rotated(to_cam, bend)
				var p1 := p0 + dj * seg_len
				var w1 := s.cross(dj).cross(dj).normalized() * half_w * (1.0 - 0.25 * float(j + 1) / float(segs))
				w1 = w1.rotated(dj, 0.6 * sin(ph * 1.3 - float(j)))   # torce um pouco
				var col := color if j % 2 == 0 else color.darkened(0.1)
				_soft_quad(p0 - w0, p0 + w0, p1 + w1, p1 - w1, col, edge)
				p0 = p1
				w0 = w1
			acc += step
			knot += 1
		acc -= l
	_im.surface_end()


## Quadrilátero com borda suave: a–b na largura do começo, c–d na do fim (a e d do
## lado −1; b e c do lado +1). `edge` = largura em px / 1,5 (borda de ~1,5 px).
func _soft_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, edge: float) -> void:
	_soft_tri(a, b, c, col, -1.0, 1.0, edge, 1.0)
	_soft_tri(a, c, d, col, -1.0, 1.0, edge, -1.0)


func _soft_tri(p: Vector3, q: Vector3, r: Vector3, col: Color, u_p: float, u_q: float, edge: float, u_r: float = 1.0) -> void:
	_im.surface_set_color(col)
	_im.surface_set_uv(Vector2(u_p, edge))
	_im.surface_add_vertex(p)
	_im.surface_set_color(col)
	_im.surface_set_uv(Vector2(u_q, edge))
	_im.surface_add_vertex(q)
	_im.surface_set_color(col)
	_im.surface_set_uv(Vector2(u_r, edge))
	_im.surface_add_vertex(r)


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
