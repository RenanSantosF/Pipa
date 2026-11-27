class_name FallingRibbon
extends Node3D
## Pedaço de rabiola cortado: cai sozinho com o vento, tremulando, e some depois de um
## tempo. Física simples de partículas (peso, arrasto do vento, barbante inextensível,
## chão) e desenho em fita virada para a câmera.

const RHO := 1.225
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const LIFE := 14.0
const WIDTH := 0.035

var pts: PackedVector3Array = PackedVector3Array()
var prev: PackedVector3Array = PackedVector3Array()
var seg: float = 0.3
var k_drag: float = 0.6   # 1/s por m/s de vento relativo (tiras de plástico leves)
var col_a := Color.WHITE
var col_b := Color(0.2, 0.45, 0.9)
var _age := 0.0
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D


func setup(p_pts: PackedVector3Array, p_vel: PackedVector3Array, profile: KiteProfile, segment: float) -> void:
	pts = p_pts.duplicate()
	prev = pts.duplicate()
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for i in pts.size():
		if i < p_vel.size():
			prev[i] = pts[i] - p_vel[i] * dt
	seg = segment
	if profile != null:
		col_a = profile.tail_color_a
		col_b = profile.tail_color_b


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(dt: float) -> void:
	_age += dt
	if _age > LIFE or pts.size() < 2:
		queue_free()
		return
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var v := (p - prev[i]) / dt
		var wind := Wind.sample(p)
		var rel := wind - v
		v += (GRAVITY * 0.35 + rel * (k_drag * minf(rel.length(), 8.0)) * 0.25) * dt
		# Tremulação das tiras.
		v += Vector3(sin(_age * 9.0 + i * 1.3), 0.0, cos(_age * 7.0 + i)) * (1.5 * dt)
		prev[i] = p
		p += v * dt
		var gy := Ground.height_at(p.x, p.z) + 0.01
		if p.y < gy:
			p.y = gy
			prev[i] = Vector3(lerpf(prev[i].x, p.x, 0.5), gy, lerpf(prev[i].z, p.z, 0.5))
		pts[i] = p
	for _it in 2:
		for i in range(1, n):
			var d := pts[i] - pts[i - 1]
			var l := d.length()
			if l > seg and l > 1e-5:
				var c := d * ((l - seg) / l * 0.5)
				pts[i] -= c
				pts[i - 1] += c


func _process(_delta: float) -> void:
	if _mesh == null or pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fade := clampf((LIFE - _age) / 2.0, 0.0, 1.0)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	for i in pts.size():
		var p := pts[i]
		var tng := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tng.cross((cam.global_position - p).normalized()).normalized() * WIDTH
		var c := (col_a if (i / 2) % 2 == 0 else col_b)
		c.a = fade
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side)
	_mesh.surface_end()
