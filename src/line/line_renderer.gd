class_name LineRenderer
extends MeshInstance3D
## Desenha uma linha simulada (Rope) como fita fina voltada para a câmera.
## * Curva: Catmull-Rom CENTRÍPETA entre os nós (sem bicos nem laços quando os
##   trechos têm tamanhos diferentes), subdividida conforme o tamanho na tela —
##   perto da câmera a curva é bem fina e contínua; longe, poucos pontos bastam.
## * Espessura: ~1 px com bordas suaves (shader), mais opaca perto e esmaecendo
##   com a distância — linha de pipa é mais fina que um pixel a dezenas de metros.
## A forma é 100% a da simulação: barriga, ondas da braçada, linha caindo.

const SHADER := preload("res://src/line/line.gdshader")
## Pixels de tela entre pontos da curva desenhada.
const PX_PER_POINT := 10.0
const MAX_SUB := 10
## Esmaecimento: opaca até NEAR m, mínimo FAR_ALPHA a partir de FAR m.
const NEAR := 3.0
const FAR := 32.0
const FAR_ALPHA := 0.04

var rope: Rope
var _im := ImmediateMesh.new()
var _mat := ShaderMaterial.new()
var _pts: PackedVector3Array = PackedVector3Array()
var _smooth: PackedVector3Array = PackedVector3Array()
var _diameter := 0.0006
var _px_scale := 1.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0
	_mat.shader = SHADER


func bind(p_rope, line_type: LineType) -> void:
	rope = p_rope
	var c := line_type.color if line_type else Color(0.96, 0.95, 0.9)
	_mat.set_shader_parameter("line_color", c)
	_diameter = line_type.diameter if line_type else 0.0006
	if rope == null:
		_im.clear_surfaces()


func _process(_delta: float) -> void:
	if rope == null or rope.pos.size() < 2:
		_im.clear_surfaces()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Linha toda longe (vizinhos): redesenha a cada 2 quadros (metade da CPU). A sua
	# linha (que sai da sua mão) é sempre redesenhada — senão ela "trepidava".
	var mid_pt := rope.pos[rope.pos.size() / 2]
	var near_pt := minf(cam.global_position.distance_to(rope.pos[0]), cam.global_position.distance_to(mid_pt))
	# Linha perto de outra (tem contato) é redesenhada SEMPRE: uma desenhada um quadro
	# atrasada da outra parecia atravessar no cruzamento.
	if near_pt > 45.0 and rope.render_kinks.is_empty() and (Engine.get_process_frames() + get_instance_id()) % 2 == 0:
		return
	_im.clear_surfaces()
	_pts.resize(0)
	# Interpolado entre os ticks da física (liso a 60 quadros/s, sem trepidar).
	var fr := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	if rope.frame_pos.size() == rope.pos.size():
		for i in rope.pos.size():
			_pts.append(rope.frame_pos[i].lerp(rope.pos[i], fr))
	else:
		_pts.append_array(rope.pos)
	if rope.end_body != null:
		_pts.append(rope.frame_end.lerp(rope.end_point(), fr) if rope.frame_end != Vector3.ZERO else rope.end_point())
	# Linha no chão: desenhada um pouco acima dele (não some dentro da terra).
	for i in _pts.size():
		var gp := _pts[i]
		var gy := Ground.height_at(gp.x, gp.z) + 0.05
		if gp.y < gy:
			_pts[i] = Vector3(gp.x, gy, gp.z)
	var n := _pts.size()
	_px_scale = 1.5 if GameConfig.quality == GameConfig.Quality.LOW else 1.0
	var cam_pos := cam.global_position
	var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	# Ângulo de 1 pixel do buffer 3D (com a escala de renderização do celular).
	var px := deg_to_rad(cam.fov) / (vp_h * get_viewport().scaling_3d_scale)

	_smooth.resize(0)
	var kinks := rope.render_kinks
	for i in n - 1:
		var p1 := _pts[i]
		var p2 := _pts[i + 1]
		if not kinks.is_empty():
			if _segment_kinks(kinks, i, p1, p2):
				continue
			if _has_kink(kinks, i - 1) or _has_kink(kinks, i + 1):
				_smooth.append(p1)   # vizinho de um cruzamento: reto (sem estufar)
				continue
		var p0 := _pts[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := _pts[i + 2] if i + 2 < n else p2 * 2.0 - p1
		var mid := (p1 + p2) * 0.5
		var seg_px := p1.distance_to(p2) / maxf(mid.distance_to(cam_pos) * px, 1e-5)
		var sub := clampi(int(seg_px / (PX_PER_POINT * _px_scale)) + 1, 1, MAX_SUB)
		for k in sub:
			_smooth.append(_centripetal(p0, p1, p2, p3, float(k) / float(sub)))
	_smooth.append(_pts[n - 1])

	var m := _smooth.size()
	var vis_d := maxf(_diameter * 1.6, 0.001)
	var to_sun := _sun_dir()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	for i in m:
		var p := _smooth[i]
		var tangent := _smooth[mini(i + 1, m - 1)] - _smooth[maxi(i - 1, 0)]
		var to_cam := cam_pos - p
		var dist := to_cam.length()
		var side := tangent.cross(to_cam)
		if side.length_squared() < 1e-12:
			side = cam.global_basis.x
		# Fita de 2 px (perfil triangular no shader = 1 px); perto da mão, a largura real.
		var half := maxf(dist * px * 0.75, vis_d * 0.5)
		side = side.normalized() * half
		var fade := clampf(1.0 - (dist - NEAR) / (FAR - NEAR), 0.0, 1.0)
		var alpha := lerpf(FAR_ALPHA, 0.85, fade * fade)
		# Brilho do sol: linha de pipa (fio encerado/cerol) reflete onde ela fica
		# perpendicular à bissetriz sol–olho — um trecho que acende e corre pela linha
		# quando ela balança (de longe é o que mais denuncia a linha no céu).
		var tn := tangent.normalized() if tangent.length_squared() > 1e-10 else Vector3.UP
		var hv := (to_sun + to_cam / maxf(dist, 0.001)).normalized()
		var g := pow(clampf(1.0 - absf(tn.dot(hv)), 0.0, 1.0), 6.0) * 0.5
		alpha = maxf(alpha, g * 0.7)
		var col := Color(1.0 + 0.5 * g, 1.0 + 0.45 * g, 1.0 + 0.35 * g, alpha)
		_im.surface_set_color(col)
		_im.surface_set_uv(Vector2(-1.0, 0.0))
		_im.surface_add_vertex(p - side)
		_im.surface_set_color(col)
		_im.surface_set_uv(Vector2(1.0, 0.0))
		_im.surface_add_vertex(p + side)
	_im.surface_end()


var _sun_cache := Vector3.ZERO


func _sun_dir() -> Vector3:
	if _sun_cache == Vector3.ZERO:
		_sun_cache = Vector3(0.3, 0.8, 0.5).normalized()
		var lights := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			_sun_cache = (lights[0] as DirectionalLight3D).global_basis.z.normalized()
	return _sun_cache


## Trecho encostado em outra linha: desenha reto passando pelos pontos de contato
## (como a física: a linha é reta entre os nós e a outra encosta nessa reta).
func _segment_kinks(kinks: PackedVector2Array, i: int, p1: Vector3, p2: Vector3) -> bool:
	var ts: Array[float] = []
	for k in kinks:
		if int(k.x) == i:
			ts.append(k.y)
	if ts.is_empty():
		return false
	ts.sort()
	_smooth.append(p1)
	for t in ts:
		if t > 0.001 and t < 0.999:
			_smooth.append(p1.lerp(p2, t))
	return true


static func _has_kink(kinks: PackedVector2Array, i: int) -> bool:
	for k in kinks:
		if int(k.x) == i:
			return true
	return false


## Catmull-Rom centrípeta (Barry–Goldman), t em [0, 1] entre p1 e p2.
static func _centripetal(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 1e-4)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
