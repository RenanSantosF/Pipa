class_name KiteVisual
extends Node3D
## Malha da pipa (vela em losango, varetas e cabresto) + tremulação com o vento.
## Filho de KiteBody. A origem é o ponto do cabresto; a vela fica atrás dele.

const SAIL_OFFSET := 0.2  # distância do cabresto até a vela (m)
const BILLOW := 0.03      # "barriga" da vela

@export var flutter_degrees: float = 1.8

var _body: KiteBody
var _sail_pivot: Node3D
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _tail_anchor_local := Vector3.ZERO


func _ready() -> void:
	_body = get_parent() as KiteBody
	_noise.frequency = 1.0
	_noise.seed = randi()
	_build()


func get_tail_anchor_global() -> Vector3:
	return _sail_pivot.to_global(_tail_anchor_local)


func _process(delta: float) -> void:
	if _body == null:
		return
	_t += delta
	var amt := clampf(_body.airspeed / 14.0, 0.0, 1.0) * deg_to_rad(flutter_degrees)
	_sail_pivot.rotation = Vector3(
		_noise.get_noise_2d(_t * 9.0, 0.0) * amt,
		0.0,
		_noise.get_noise_2d(0.0, _t * 7.0) * amt)


func _build() -> void:
	var profile := _body.profile if _body and _body.profile else KiteProfile.new()
	var w := profile.size.x
	var h := profile.size.y

	_sail_pivot = Node3D.new()
	_sail_pivot.name = "SailPivot"
	_sail_pivot.position = Vector3(0, 0, -SAIL_OFFSET)
	add_child(_sail_pivot)

	var top := Vector3(0, h * 0.38, 0)
	var bottom := Vector3(0, -h * 0.62, 0)
	var left := Vector3(-w * 0.5, 0, 0)
	var right := Vector3(w * 0.5, 0, 0)
	var center := Vector3(0, -h * 0.05, -BILLOW)
	_tail_anchor_local = bottom

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, center, top, right, profile.color_a)
	_tri(st, center, right, bottom, profile.color_b)
	_tri(st, center, bottom, left, profile.color_a)
	_tri(st, center, left, top, profile.color_b)
	var sail := MeshInstance3D.new()
	sail.name = "Sail"
	sail.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	sail.material_override = mat
	_sail_pivot.add_child(sail)

	# Varetas de bambu.
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.45, 0.32, 0.18)
	stick_mat.roughness = 0.9
	_stick(Vector3(0, (top.y + bottom.y) * 0.5, 0.006), Vector3(0.007, h, 0.007), stick_mat)
	_stick(Vector3(0, 0, 0.006), Vector3(w, 0.007, 0.007), stick_mat)

	# Cabresto: duas pernas do ponto de amarração até a vareta central.
	var im := ImmediateMesh.new()
	var bridle_mat := StandardMaterial3D.new()
	bridle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bridle_mat.albedo_color = Color(0.95, 0.93, 0.86)
	im.surface_begin(Mesh.PRIMITIVE_LINES, bridle_mat)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3(0, h * 0.28, -SAIL_OFFSET))
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3(0, -h * 0.45, -SAIL_OFFSET))
	im.surface_end()
	var bridle := MeshInstance3D.new()
	bridle.name = "Bridle"
	bridle.mesh = im
	bridle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bridle)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(n)
		st.add_vertex(v)


func _stick(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_sail_pivot.add_child(mi)
