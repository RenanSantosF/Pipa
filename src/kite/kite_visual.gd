class_name KiteVisual
extends Node3D
## Malha da pipa (vela em losango com "barriga", varetas, cabresto) que segue o
## corpo rígido simulado. Origem = centro de massa (como KiteRigidBody).

@export var flutter_degrees: float = 1.5

var rig: KiteRig
var _sail_pivot: Node3D
var _noise := FastNoiseLite.new()
var _t: float = 0.0


func _ready() -> void:
	top_level = true
	_noise.frequency = 1.0
	_noise.seed = randi()


func bind(p_rig: KiteRig) -> void:
	rig = p_rig
	for c in get_children():
		c.queue_free()
	_build(rig.body, rig.profile)


func unbind() -> void:
	rig = null
	for c in get_children():
		c.queue_free()


func _process(delta: float) -> void:
	if rig == null or rig.body == null:
		return
	var b := rig.body
	global_transform = Transform3D(Basis(b.q), b.x)
	_t += delta
	var amt := clampf(b.airspeed / 12.0, 0.0, 1.0) * deg_to_rad(flutter_degrees)
	_sail_pivot.rotation = Vector3(_noise.get_noise_2d(_t * 11.0, 0.0) * amt, 0.0, _noise.get_noise_2d(0.0, _t * 9.0) * amt)


func _build(body: KiteRigidBody, profile: KiteProfile) -> void:
	_sail_pivot = Node3D.new()
	_sail_pivot.name = "SailPivot"
	add_child(_sail_pivot)
	var c := body.corners
	var top := c[0]
	var right := c[1]
	var bottom := c[2]
	var left := c[3]
	var center := (top + bottom) * 0.5 + Vector3(0, 0, -0.03)
	var d := deg_to_rad(profile.dihedral_deg)
	right.z = -sin(d) * profile.width * 0.5
	left.z = right.z

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, center, top, right, profile.color_a)
	_tri(st, center, right, bottom, profile.color_b)
	_tri(st, center, bottom, left, profile.color_a)
	_tri(st, center, left, top, profile.color_b)
	var sail := MeshInstance3D.new()
	sail.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	# Papel de seda: deixa passar um pouco de luz.
	mat.backlight_enabled = true
	mat.backlight = Color(0.35, 0.3, 0.25)
	sail.material_override = mat
	_sail_pivot.add_child(sail)

	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.45, 0.32, 0.18)
	_stick(top, bottom, stick_mat)
	_stick(left, right, stick_mat)

	# Cabresto: do nó até dois pontos da vareta central.
	var im := ImmediateMesh.new()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.95, 0.93, 0.86)
	im.surface_begin(Mesh.PRIMITIVE_LINES, bm)
	var tow := body.tow_local
	im.surface_add_vertex(tow)
	im.surface_add_vertex(top.lerp(bottom, 0.1))
	im.surface_add_vertex(tow)
	im.surface_add_vertex(top.lerp(bottom, 0.65))
	im.surface_end()
	var bridle := MeshInstance3D.new()
	bridle.mesh = im
	bridle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bridle)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, cc: Vector3, color: Color) -> void:
	var n := (b - a).cross(cc - a).normalized()
	for v in [a, b, cc]:
		st.set_color(color)
		st.set_normal(n)
		st.add_vertex(v)


func _stick(a: Vector3, b: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var l := a.distance_to(b)
	bm.size = Vector3(0.007, 0.007, l)
	mi.mesh = bm
	mi.material_override = mat
	var mid := (a + b) * 0.5 + Vector3(0, 0, 0.006)
	mi.transform = Transform3D(Basis.looking_at(b - a, Vector3.BACK if absf((b - a).normalized().y) > 0.9 else Vector3.UP), mid)
	_sail_pivot.add_child(mi)
