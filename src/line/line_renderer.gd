class_name LineRenderer
extends MeshInstance3D
## Desenha uma linha simulada (Rope) como fita voltada para a câmera, com
## largura mínima em pixels e curva suavizada (Catmull-Rom entre os nós).
## A forma é 100% a da simulação: barriga, ondas da braçada, linha caindo.

@export var subdivisions: int = 3

var rope: Rope
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _pts: PackedVector3Array = PackedVector3Array()
var _smooth: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func bind(p_rope, line_type: LineType) -> void:
	rope = p_rope
	_mat.albedo_color = line_type.color if line_type else Color(0.96, 0.95, 0.9)


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if rope == null or rope.pos.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_pts.resize(0)
	_pts.append_array(rope.pos)
	if rope.end_body != null:
		_pts.append(rope.end_point())
	var n := _pts.size()
	var sub := maxi(1, subdivisions if GameConfig.quality > 0 else 1)
	_smooth.resize(0)
	for i in n - 1:
		var p0 := _pts[maxi(i - 1, 0)]
		var p1 := _pts[i]
		var p2 := _pts[i + 1]
		var p3 := _pts[mini(i + 2, n - 1)]
		for k in sub:
			var t := float(k) / float(sub)
			_smooth.append(_catmull(p0, p1, p2, p3, t))
	_smooth.append(_pts[n - 1])

	var cam_pos := cam.global_position
	var px := deg_to_rad(cam.fov) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var m := _smooth.size()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	for i in m:
		var p := _smooth[i]
		var tangent := _smooth[mini(i + 1, m - 1)] - _smooth[maxi(i - 1, 0)]
		var to_cam := cam_pos - p
		var side := tangent.cross(to_cam)
		if side.length_squared() < 1e-12:
			side = cam.global_basis.x
		var half := maxf(0.0005, to_cam.length() * px * 0.6)
		side = side.normalized() * half
		_im.surface_add_vertex(p - side)
		_im.surface_add_vertex(p + side)
	_im.surface_end()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
