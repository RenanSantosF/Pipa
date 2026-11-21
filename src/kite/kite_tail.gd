class_name KiteTail
extends MeshInstance3D
## Rabiola: cadeia Verlet curta presa na ponta de baixo da pipa, com gravidade
## e arrasto do vento. Desenhada como tiras de plástico coloridas voltadas para a câmera.

@export var drag: float = 3.0
@export var width: float = 0.06
@export var iterations: int = 4

var _visual: KiteVisual
var _profile: KiteProfile
var _points: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_physics_priority = 10  # depois da pipa
	var body := get_parent() as KiteBody
	_profile = body.profile if body and body.profile else KiteProfile.new()
	_visual = get_parent().get_node_or_null("KiteVisual") as KiteVisual
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _anchor() -> Vector3:
	if _visual:
		return _visual.get_tail_anchor_global()
	return get_parent().global_position if get_parent() is Node3D else Vector3.ZERO


func _reset_points(anchor: Vector3, count: int) -> void:
	_points.resize(count)
	_prev.resize(count)
	var seg := _profile.tail_length / float(count - 1)
	for i in count:
		_points[i] = anchor + Vector3.DOWN * seg * i
		_prev[i] = _points[i]


func _physics_process(delta: float) -> void:
	var count := GameConfig.tail_points()
	var anchor := _anchor()
	if _points.size() != count or _points[0].distance_to(anchor) > 5.0:
		_reset_points(anchor, count)
	var seg := _profile.tail_length / float(count - 1)
	var wind := Wind.sample(anchor)
	var gravity := Vector3(0.0, -9.8, 0.0)
	_points[0] = anchor
	_prev[0] = anchor
	for i in range(1, count):
		var p := _points[i]
		var v := (p - _prev[i]) / delta
		var acc := gravity + (wind - v) * drag
		_prev[i] = p
		_points[i] = p + v * delta * 0.99 + acc * delta * delta
	for _it in iterations:
		for i in range(1, count):
			var a := _points[i - 1]
			var b := _points[i]
			var d := b - a
			var l := d.length()
			if l < 0.0001:
				continue
			var corr := d * ((l - seg) / l)
			if i == 1:
				_points[i] = b - corr
			else:
				_points[i - 1] = a + corr * 0.5
				_points[i] = b - corr * 0.5


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	var count := _points.size()
	if count < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	for i in range(count - 1):
		var a := _points[i]
		var b := _points[i + 1]
		var tangent := b - a
		if tangent.length_squared() < 1e-8:
			continue
		var to_cam := cam_pos - (a + b) * 0.5
		var side := tangent.cross(to_cam).normalized() * (width * 0.5)
		var color := _profile.tail_color_a if i % 2 == 0 else _profile.tail_color_b
		# Cada tira ocupa 85% do segmento (dá a impressão de tiras amarradas num barbante).
		var b2 := a + tangent * 0.85
		_quad(a - side, a + side, b2 + side, b2 - side, color)
	_im.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for v in [a, b, c, a, c, d]:
		_im.surface_set_color(color)
		_im.surface_add_vertex(v)
