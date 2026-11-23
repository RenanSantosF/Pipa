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
	global_transform = Transform3D(Basis(b.q), b.x)
	var dl := b.half_dihedral(0)
	var dr := b.half_dihedral(1)
	for m in [_paper, _sticks]:
		m.set_shader_parameter("dihedral_l", dl)
		m.set_shader_parameter("dihedral_r", dr)
	_paper.set_shader_parameter("airspeed", b.airspeed)
	_update_bridle(dl, dr)


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
	var rows: Array[float] = []
	for i in GRID_V + 1:
		rows.append(float(i) / float(GRID_V))
	# Garante linhas exatamente nas travessas (dobra limpa).
	rows.append(profile.cross_at)
	rows.append(profile.lower_at)
	rows.sort()
	var verts: Array = []
	for v in rows:
		var yn := v * h
		var rw := _row_half_w(yn, hw, h, profile.cross_at)
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
	_tube(sk, nose + Vector3(0, 0.004, back), _corners[2] + Vector3(0, -0.004, back), r_spine, 2, BAMBOO)
	var yc := nose.y - profile.cross_at * h
	_tube(sk, Vector3(-hw - 0.006, yc, back - r_spine * 2.0), Vector3(hw + 0.006, yc, back - r_spine * 2.0), r_cross, 14, BAMBOO)
	var yl := nose.y - profile.lower_at * h
	var lw := _row_half_w(profile.lower_at * h, hw, h, profile.cross_at)
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
	var yl := nose.y - _profile.lower_at * h
	var lw := _row_half_w(_profile.lower_at * h, hw, h, _profile.cross_at)
	var knot := rig.body.tow_local + Vector3(rig.bridle_offset.x, rig.bridle_offset.y, 0.0) if rig and not rig.loose else rig.body.tow_local
	var anchors := [nose + Vector3(0, -0.07 * h, 0), Vector3(-lw, yl, _bow_z(-lw, dl, dr)), Vector3(lw, yl, _bow_z(lw, dl, dr))]
	_bridle.clear_surfaces()
	_bridle.surface_begin(Mesh.PRIMITIVE_LINES, _bridle_mat)
	for a in anchors:
		_bridle.surface_add_vertex(knot)
		_bridle.surface_add_vertex(a)
	_bridle.surface_end()


static func _row_half_w(yn: float, hw: float, h: float, cross_at: float) -> float:
	var c := cross_at * h
	return hw * yn / maxf(c, 0.001) if yn < c else hw * (h - yn) / maxf(h - c, 0.001)


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
