class_name KiteVisual
extends Node3D
## Pipa de combate brasileira: losango de papel de seda com 3 varetas de bambu
## (espinha + travessa principal envergada + travessa inferior), bainha, cola sobre
## as varetas, cabresto de 3 pernas. Segue o corpo rígido simulado (origem = CM).
##
## A envergadura e a flexão do desbico vêm da FÍSICA (diedro de cada meia-vela),
## aplicadas no shader: o que se vê é o que a aerodinâmica está usando.

const PAPER_SHADER := preload("res://src/kite/kite_paper.gdshader")
const BAMBOO := Color(0.80, 0.64, 0.40)
const BRIDLE := Color(0.95, 0.94, 0.9)
const GRID_V := 16
const GRID_U := 12
## Distância (m) a partir da qual a pipa é desenhada maior, e o máximo.
const VIS_SCALE_DIST := 12.0
## 1,0 = tamanho real (escala 1:1, como pediu o jogador).
const VIS_SCALE_MAX := 1.0

var rig: KiteRig
var _paper: ShaderMaterial
var _sticks: ShaderMaterial
var _bridle: ImmediateMesh
var _bridle_mat: StandardMaterial3D
var _profile: KiteProfile
var _corners: PackedVector3Array


func _ready() -> void:
	top_level = true


func bind(p_rig: KiteRig) -> void:
	rig = p_rig
	for c in get_children():
		c.queue_free()
	_build(rig.body, rig.profile)


func unbind() -> void:
	rig = null
	for c in get_children():
		c.queue_free()


func _process(_delta: float) -> void:
	if rig == null or rig.body == null or _paper == null:
		return
	var b := rig.body
	# Pose INTERPOLADA entre os ticks da física (lisa a 60 quadros/s).
	var pose := rig.visual_pose()
	# Inclinação do desbico: a pipa deita em volta da vareta (só o desenho; a física
	# do balanço já está no giro do bico).
	var basis := pose.basis * Basis(Vector3.UP, rig.bank)
	# Longe da câmera a pipa é DESENHADA maior (até 3×), em volta do nó do cabresto
	# (a linha continua presa no mesmo ponto): no celular uma pipa de 65 cm a 40 m
	# vira um pontinho e o balanço do desbico some.
	# v0.23+: tamanho REAL em qualquer distância (desenhada maior, de longe ela parecia
	# grande demais para a distância).
	var k := 1.0
	rig.visual_scale = k
	var kl := _knot_local()
	var knot := pose.origin + pose.basis * kl
	var bs := basis.scaled(Vector3(k, k, k))
	global_transform = Transform3D(bs, knot - bs * kl)
	rig.visual_tail_offset = (global_transform * b.tail_local) - b.world_point(b.tail_local)
	# Desbico: as asas batem juntas, como um pássaro (as varetas fecham e abrem).
	var fl := rig.flap * 0.38
	var dl := b.half_dihedral(0) + fl
	var dr := b.half_dihedral(1) + fl
	for m in [_paper, _sticks]:
		m.set_shader_parameter("dihedral_l", dl)
		m.set_shader_parameter("dihedral_r", dr)
	_paper.set_shader_parameter("airspeed", b.airspeed)
	_update_bridle(dl, dr)


## Nó do cabresto no sistema da pipa: o nó de verdade (partícula) quando há cabresto
## de linha; senão o ponto de tração fixo.
func _knot_local() -> Vector3:
	var b := rig.body
	var br := _bridle_of()
	if br != null:
		return rig.rope.end_local
	if not rig.loose:
		return b.tow_local + Vector3(rig.bridle_offset.x, rig.bridle_offset.y, 0.0)
	return b.tow_local


func _bridle_of() -> Bridle:
	if rig == null or rig.rope == null or rig.rope.bridle == null or rig.rope.end_body != rig.body:
		return null
	return rig.rope.bridle


func _bow_z(x: float, dl: float, dr: float) -> float:
	var d := dl if x < 0.0 else dr
	return -tan(d) * x * x / maxf(_profile.width * 0.5, 0.01)


func _build(body: KiteRigidBody, profile: KiteProfile) -> void:
	_profile = profile
	_corners = body.corners
	var nose := _corners[0]
	var hw := profile.width * 0.5
	var h := profile.height
	_paper = ShaderMaterial.new()
	_paper.shader = PAPER_SHADER
	_paper.set_shader_parameter("half_w", hw)
	_paper.set_shader_parameter("kite_h", h)
	_paper.set_shader_parameter("cross_at", profile.cross_at)
	_paper.set_shader_parameter("lower_at", profile.lower_at)
	_paper.set_shader_parameter("shoulder", profile.shoulder)
	_paper.set_shader_parameter("color_c", profile.color_c)
	_paper.set_shader_parameter("color_a", profile.color_a)
	_paper.set_shader_parameter("color_b", profile.color_b)
	_paper.set_shader_parameter("pattern", profile.pattern)
	_paper.set_shader_parameter("phase", randf() * TAU)
	_paper.set_shader_parameter("kind", 0)
	_sticks = _paper.duplicate() as ShaderMaterial
	_sticks.set_shader_parameter("kind", 1)

	# Vela: grade sobre o losango (linhas ao longo da espinha, colunas na largura).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Só a parte de papel: da travessa até a ponta de baixo (a cabeça é só vareta).
	var rows: Array[float] = []
	for i in GRID_V + 1:
		rows.append(lerpf(profile.cross_at, 1.0, float(i) / float(GRID_V)))
	rows.append(profile.lower_at)
	rows.sort()
	var verts: Array = []
	for v in rows:
		var yn := v * h
		var rw := _row_half_w(yn, hw, h, profile)
		var row := []
		for j in GRID_U + 1:
			var u := float(j) / float(GRID_U) * 2.0 - 1.0
			row.append(Vector3(u * rw, nose.y - yn, 0.0))
		verts.append([row, v])
	for i in verts.size() - 1:
		var r0: Array = verts[i][0]
		var r1: Array = verts[i + 1][0]
		var v0: float = verts[i][1]
		var v1: float = verts[i + 1][1]
		for j in GRID_U:
			_quad(st, r0[j], r0[j + 1], r1[j + 1], r1[j], v0, v1)
	var sail := MeshInstance3D.new()
	sail.name = "Sail"
	sail.mesh = st.commit()
	sail.material_override = _paper
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sail)

	# Varetas (atrás do papel; a curva da envergadura é aplicada no shader).
	var sk := SurfaceTool.new()
	sk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_spine := 0.0028 * h / 0.65
	var r_cross := 0.0022 * h / 0.65
	var back := -0.004
	_tube(sk, nose + Vector3(0, 0.006, back), _corners[3] + Vector3(0, -0.004, back), r_spine, 2, BAMBOO)
	var yc := nose.y - profile.cross_at * h
	_tube(sk, Vector3(-hw - 0.006, yc, back - r_spine * 2.0), Vector3(hw + 0.006, yc, back - r_spine * 2.0), r_cross, 14, BAMBOO)
	var yl := nose.y - profile.lower_at * h
	var lw := _row_half_w(profile.lower_at * h, hw, h, profile)
	_tube(sk, Vector3(-lw, yl, back - r_spine * 2.0), Vector3(lw, yl, back - r_spine * 2.0), r_cross * 0.9, 10, BAMBOO.darkened(0.05))
	# Amarração (linha) no cruzamento das varetas.
	for yy in [yc, yl]:
		_tube(sk, Vector3(-0.008, yy, back), Vector3(0.008, yy, back), r_spine * 1.7, 1, Color(0.92, 0.9, 0.85))
	var sticks := MeshInstance3D.new()
	sticks.name = "Sticks"
	sticks.mesh = sk.commit()
	sticks.material_override = _sticks
	add_child(sticks)

	# Cabresto: 3 pernas do nó até a espinha (perto do nariz) e às pontas da travessa de baixo.
	_bridle = ImmediateMesh.new()
	_bridle_mat = StandardMaterial3D.new()
	_bridle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bridle_mat.albedo_color = BRIDLE
	var bm := MeshInstance3D.new()
	bm.name = "Bridle"
	bm.mesh = _bridle
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bm)
	_update_bridle(body.dihedral, body.dihedral)


func _update_bridle(dl: float, dr: float) -> void:
	if _bridle == null:
		return
	var h := _profile.height
	var hw := _profile.width * 0.5
	var nose := _corners[0]
	var yc := nose.y - _profile.cross_at * h
	var yl := nose.y - _profile.lower_at * h
	var knot := _knot_local()
	# Cabresto de 2 pernas: no cruzamento da travessa e mais abaixo na vareta. É
	# LINHA: esticado com a pipa puxando; folgado, faz barriga para baixo e tremula.
	var low_y := lerpf(yl, _corners[3].y, 0.35)
	var anchors := [Vector3(0, yc - 0.01, 0), Vector3(0, low_y, 0)]
	var t_line := rig.tension if rig else 0.0
	var slack := clampf(1.0 - t_line / 3.0, 0.0, 1.0)
	var br := _bridle_of()
	if br != null:
		anchors = [br.anchors[0], br.anchors[1]]
	var g_local: Vector3 = (rig.body.q.inverse() * Vector3.DOWN) if rig and rig.body else Vector3.DOWN
	var t_now := Time.get_ticks_msec() / 1000.0
	_bridle.clear_surfaces()
	_bridle.surface_begin(Mesh.PRIMITIVE_LINES, _bridle_mat)
	for li in anchors.size():
		var a: Vector3 = anchors[li]
		var leg := knot - a
		var ll := leg.length()
		var dirl := leg / maxf(ll, 0.001)
		var sag_dir := g_local - dirl * g_local.dot(dirl)
		sag_dir = sag_dir.normalized() if sag_dir.length() > 0.01 else Vector3.DOWN
		var side := dirl.cross(sag_dir)
		if br != null:
			# Cada perna com a SUA tração (perna frouxa faz barriga; o comprimento é o
			# da perna, a corda até o nó fica mais curta quando ela afrouxa).
			slack = clampf(1.0 - br.leg_tension[li] / 1.2, 0.0, 1.0)
			var extra := maxf(br.legs[li] - ll, 0.0)
			sag_dir = sag_dir * 1.0
			ll = maxf(ll, 0.001)
			slack = maxf(slack, clampf(extra / (0.08 * br.legs[li]), 0.0, 1.0))
		var sag := ll * (0.012 + 0.05 * slack)
		var flick := ll * (0.004 + 0.012 * slack) * sin(t_now * 23.0 + float(li) * 1.7)
		var prev := a
		for k in range(1, 9):
			var u := float(k) / 8.0
			var bump := sin(PI * u)
			var pt := a + leg * u + sag_dir * (sag * bump) + side * (flick * bump)
			_bridle.surface_add_vertex(prev)
			_bridle.surface_add_vertex(pt)
			prev = pt
	# Linha de contorno de cima: da cabeça às pontas (envergadas) da travessa.
	for sx in [-1.0, 1.0]:
		var tip := Vector3(sx * hw, yc, _bow_z(sx * hw, dl, dr))
		_bridle.surface_add_vertex(nose + Vector3(0, -0.005, 0))
		_bridle.surface_add_vertex(tip)
	_bridle.surface_end()


static func _row_half_w(yn: float, hw: float, h: float, p: KiteProfile) -> float:
	var c := p.cross_at * h
	var l := p.lower_at * h
	if yn < c:
		return 0.0
	if yn < l:
		return lerpf(hw, hw * p.shoulder, (yn - c) / maxf(l - c, 0.001))
	return hw * p.shoulder * (h - yn) / maxf(h - l, 0.001)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v0: float, v1: float) -> void:
	for p in [[a, v0], [b, v0], [c, v1], [a, v0], [c, v1], [d, v1]]:
		var pt: Vector3 = p[0]
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.0, p[1]))
		st.add_vertex(pt)


## Tubo poligonal entre a e b (5 lados, `segs` trechos para acompanhar a curva).
func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, segs: int, col: Color) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.BACK if absf(axis.z) < 0.9 else Vector3.UP
	var s1 := axis.cross(ref).normalized()
	var s2 := axis.cross(s1).normalized()
	const SIDES := 5
	for k in segs:
		var p0 := a.lerp(b, float(k) / float(segs))
		var p1 := a.lerp(b, float(k + 1) / float(segs))
		for i in SIDES:
			var a0 := TAU * float(i) / float(SIDES)
			var a1 := TAU * float(i + 1) / float(SIDES)
			var o0 := (s1 * cos(a0) + s2 * sin(a0)) * r
			var o1 := (s1 * cos(a1) + s2 * sin(a1)) * r
			for q in [[p0, o0], [p1, o0], [p1, o1], [p0, o0], [p1, o1], [p0, o1]]:
				var pp: Vector3 = q[0]
				var oo: Vector3 = q[1]
				st.set_color(col.lightened(0.08 * oo.normalized().dot(Vector3.UP)))
				st.set_normal(oo.normalized())
				st.set_uv(Vector2.ZERO)
				st.add_vertex(pp + oo)
