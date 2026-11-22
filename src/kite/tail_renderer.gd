class_name TailRenderer
extends MeshInstance3D
## Desenha a rabiola simulada (TailChain) como tiras de plástico coloridas
## voltadas para a câmera, amarradas num barbante.

@export var width: float = 0.06

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
	var a := tail.attach_point()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	var drawn := 0
	for i in n:
		var b := tail.pos[i]
		var tangent := b - a
		if tangent.length_squared() > 1e-8:
			var side := tangent.cross(cam_pos - (a + b) * 0.5).normalized() * (width * 0.5)
			var color := prof.tail_color_a if i % 2 == 0 else prof.tail_color_b
			var b2 := a + tangent * 0.82
			for v in [a - side, a + side, b2 + side, a - side, b2 + side, b2 - side]:
				_im.surface_set_color(color)
				_im.surface_add_vertex(v)
			drawn += 1
		a = b
	if drawn == 0:
		_im.surface_set_color(Color.WHITE)
		_im.surface_add_vertex(a)
		_im.surface_add_vertex(a)
		_im.surface_add_vertex(a)
	_im.surface_end()
