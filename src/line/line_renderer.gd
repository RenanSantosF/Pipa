class_name LineRenderer
extends MeshInstance3D
## Linha visual entre a mão e a pipa (separada da física).
##
## A forma alvo é uma parábola cuja flecha vem da física real da linha:
##  - esticada: flecha ≈ peso_por_metro · distância² / (8 · tensão)
##  - frouxa:   flecha a partir do excesso de comprimento (comprimento de arco)
## A flecha segue o alvo com uma mola amortecida (ondula quando a tensão muda)
## e cada ponto persegue sua posição com atraso maior no meio da linha.
## Desenhada como uma fita voltada para a câmera, com largura mínima em pixels.

@export var color: Color = Color(0.97, 0.95, 0.9)
@export var sag_stiffness: float = 30.0
@export var sag_damping: float = 6.0

var line: KiteLine
var kite: Node3D

var _points: PackedVector3Array = PackedVector3Array()
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _sag: float = 0.0
var _sag_velocity: float = 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 50.0
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func setup(p_line: KiteLine, p_kite: Node3D) -> void:
	line = p_line
	kite = p_kite
	_points.clear()


func _process(delta: float) -> void:
	_im.clear_surfaces()
	if line == null or kite == null or line.hand == null or line.is_broken:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var a := line.hand.global_position
	var b := kite.global_position
	var chord := b - a
	var dist := chord.length()
	if dist < 0.05:
		return
	var chord_dir := chord / dist

	# Flecha alvo.
	var weight_per_m := line.mass_per_meter * 9.8
	var sag_taut := weight_per_m * dist * dist / (8.0 * maxf(line.tension, 0.15))
	var slack := maxf(line.effective_length() - dist, 0.0)
	var sag_slack := sqrt(3.0 * dist * slack / 8.0)
	var target_sag := clampf(maxf(sag_taut, sag_slack), 0.0, dist * 0.45)
	_sag_velocity += (target_sag - _sag) * sag_stiffness * delta
	_sag_velocity *= exp(-sag_damping * delta)
	_sag = maxf(_sag + _sag_velocity * delta, 0.0)

	# Direção da flecha: gravidade perpendicular à corda + um pouco de vento lateral.
	var sag_dir := Vector3.DOWN - chord_dir * Vector3.DOWN.dot(chord_dir)
	var wind := Wind.sample((a + b) * 0.5)
	var wind_perp := wind - chord_dir * wind.dot(chord_dir)
	sag_dir += wind_perp * 0.05
	if sag_dir.length() < 0.001:
		sag_dir = cam.global_basis.x
	sag_dir = sag_dir.normalized()

	var count := GameConfig.line_points()
	var reset := _points.size() != count
	if reset:
		_points.resize(count)
	for i in count:
		var t := float(i) / float(count - 1)
		var bulge := 4.0 * t * (1.0 - t)
		var target := a + chord * t + sag_dir * (_sag * bulge)
		if reset or i == 0 or i == count - 1:
			_points[i] = target
		else:
			var rate := lerpf(40.0, 9.0, bulge)
			_points[i] = _points[i].lerp(target, 1.0 - exp(-rate * delta))

	# Fita voltada para a câmera.
	var cam_pos := cam.global_position
	var px_angle := deg_to_rad(cam.fov) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	for i in count:
		var p := _points[i]
		var tangent := _points[mini(i + 1, count - 1)] - _points[maxi(i - 1, 0)]
		var to_cam := cam_pos - p
		var dcam := to_cam.length()
		var side := tangent.cross(to_cam)
		if side.length_squared() < 1e-12:
			side = cam.global_basis.x
		var half_width := maxf(0.0006, dcam * px_angle * 0.6)
		side = side.normalized() * half_width
		_im.surface_add_vertex(p - side)
		_im.surface_add_vertex(p + side)
	_im.surface_end()
