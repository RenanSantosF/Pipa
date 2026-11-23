class_name KiteRigidBody
extends RefCounted
## Pipa como corpo rígido 6DOF (posição + orientação), integrada com XPBD.
##
## Eixos locais: X = lateral, Y = vareta (nariz), Z = normal da face voltada ao
## jogador. Origem = centro de massa.
##
## Aerodinâmica: cada meia-vela (esquerda/direita, com diedro) é uma placa plana:
##  - força normal q·A·Cn(α) com perda de sustentação suave;
##  - centro de pressão que desliza de 1/4 da corda (bordo de ataque) até o centro
##    conforme α cresce — é o que faz a pipa achar o ângulo de equilíbrio com o
##    cabresto e "embicar" para onde o nariz aponta;
##  - velocidade local inclui ω×r (amortecimento natural ao girar).

const RHO := 1.225
const GRAVITY := Vector3(0.0, -9.8, 0.0)

var profile: KiteProfile
var mass: float = 0.045
var inertia := Vector3.ONE
var inv_inertia := Vector3.ONE

var x := Vector3.ZERO           ## centro de massa (mundo)
var v := Vector3.ZERO
var q := Quaternion.IDENTITY
var w := Vector3.ZERO           ## velocidade angular (mundo)

## Pontos locais (contorno sextavado: nariz, sup. dir., inf. dir., baixo, inf. esq., sup. esq.).
var corners: PackedVector3Array = PackedVector3Array()
var tow_local := Vector3.ZERO
var tail_local := Vector3.ZERO

# Meias-velas: centro, normal local, área, índices dos cantos.
var _half_center: PackedVector3Array = PackedVector3Array()
var _half_normal: PackedVector3Array = PackedVector3Array()
var _half_area: PackedFloat32Array = PackedFloat32Array()
var _half_pts: Array[PackedVector3Array] = []

# Estado aerodinâmico (para HUD/sons/rede).
var angle_of_attack: float = 0.0
var airspeed: float = 0.0
var resting: bool = false

var _force := Vector3.ZERO
var _torque := Vector3.ZERO
var _x_prev := Vector3.ZERO
var _q_prev := Quaternion.IDENTITY


func _init(p: KiteProfile) -> void:
	profile = p
	mass = p.mass
	var h := p.height
	var wd := p.width
	inertia = Vector3(mass * h * h / 24.0 + 0.0002, mass * wd * wd / 24.0 + 0.0002, mass * (h * h + wd * wd) / 24.0 + 0.0003)
	inv_inertia = Vector3(1.0 / inertia.x, 1.0 / inertia.y, 1.0 / inertia.z)
	# Pipa de 3 varetas: 1 vertical + 2 horizontais envergadas → vela sextavada.
	var raw := [
		Vector2(0, 0.5 * h), Vector2(wd * 0.5, p.upper_stick * h), Vector2(wd * 0.44, p.lower_stick * h),
		Vector2(0, -0.5 * h), Vector2(-wd * 0.44, p.lower_stick * h), Vector2(-wd * 0.5, p.upper_stick * h)]
	var cen := _poly_centroid(raw)
	corners = PackedVector3Array()
	for v in raw:
		corners.append(Vector3(v.x - cen.x, v.y - cen.y, 0.0))
	tow_local = Vector3(0, corners[0].y - p.tow_fraction * h, p.bridle_length)
	tail_local = corners[3]
	var d := deg_to_rad(p.dihedral_deg)
	for side in [-1.0, 1.0]:
		var idx := [0, 5, 4, 3] if side < 0.0 else [0, 1, 2, 3]
		var pts := PackedVector3Array()
		for k in idx:
			pts.append(corners[k])
		_half_pts.append(pts)
		var area := 0.0
		var c := Vector3.ZERO
		for k in range(1, pts.size() - 1):
			var ta := 0.5 * (pts[k] - pts[0]).cross(pts[k + 1] - pts[0]).length()
			area += ta
			c += (pts[0] + pts[k] + pts[k + 1]) / 3.0 * ta
		_half_center.append(c / maxf(area, 1e-6))
		_half_normal.append(Vector3(side * sin(d), 0.0, cos(d)))
		_half_area.append(area)


static func _poly_centroid(pts: Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in pts.size():
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		var cr := p0.cross(p1)
		a += cr
		c += (p0 + p1) * cr
	return c / (3.0 * a) if absf(a) > 1e-6 else Vector2.ZERO


func basis() -> Basis:
	return Basis(q)


func world_point(local: Vector3) -> Vector3:
	return x + q * local


## Velocidade de um ponto do corpo (r = offset em mundo a partir do CM).
func point_velocity(r: Vector3) -> Vector3:
	return v + w.cross(r)


## I⁻¹ no espaço do mundo aplicado a um vetor.
func mul_inv_inertia(vec: Vector3) -> Vector3:
	var local := q.inverse() * vec
	return q * Vector3(local.x * inv_inertia.x, local.y * inv_inertia.y, local.z * inv_inertia.z)


## Massa inversa generalizada de um ponto (offset r) na direção n.
func inverse_mass_at(r: Vector3, n: Vector3) -> float:
	var rn := r.cross(n)
	return 1.0 / mass + rn.dot(mul_inv_inertia(rn))


## Correção posicional XPBD aplicada num ponto do corpo.
func apply_correction(r: Vector3, corr: Vector3) -> void:
	x += corr / mass
	var dw := mul_inv_inertia(r.cross(corr))
	q = (q + Quaternion(dw.x, dw.y, dw.z, 0.0) * q * 0.5).normalized()


## Calcula força e torque (gravidade + aerodinâmica) para o vento dado.
func compute_forces() -> void:
	_force = GRAVITY * mass
	_torque = Vector3.ZERO
	var alpha_sum := 0.0
	var sp_sum := 0.0
	for i in 2:
		var n: Vector3 = q * _half_normal[i]
		var cw: Vector3 = q * _half_center[i]
		var vel := v + w.cross(cw)
		var vrel: Vector3 = Wind.sample(x + cw) - vel
		var sp := vrel.length()
		sp_sum += sp
		if sp < 0.05:
			continue
		var vd := vrel / sp
		var qd := 0.5 * RHO * sp * sp
		var sina := clampf(-vd.dot(n), -1.0, 1.0)
		var al := asin(sina)
		alpha_sum += al
		var cn := normal_coefficient(al)
		# Centro de pressão ao longo do escoamento no plano da vela.
		var cop := cw
		var flow := vd - n * vd.dot(n)
		var fl := flow.length()
		if fl > 0.001:
			var fdir := flow / fl
			var pts: PackedVector3Array = _half_pts[i]
			var lead := INF
			var far := -INF
			for pt in pts:
				var pr := (q * pt).dot(fdir)
				lead = minf(lead, pr)
				far = maxf(far, pr)
			var chord := far - lead
			cop = cw + fdir * ((lead - cw.dot(fdir)) + chord * (0.25 + 0.25 * sin(absf(al))))
		var area: float = _half_area[i]
		var f := -n * (qd * area * cn) + vd * (qd * area * profile.cd0)
		_force += f
		_torque += cop.cross(f)
	angle_of_attack = alpha_sum * 0.5
	airspeed = sp_sum * 0.5
	var span := profile.width * profile.height * 0.5 * profile.height * profile.height
	_torque -= w * (profile.rotational_damping * 0.5 * RHO * maxf(airspeed, 1.0) * span)


func add_torque(t: Vector3) -> void:
	_torque += t


## Coeficiente de força normal de placa plana com perda de sustentação suave.
func normal_coefficient(alpha: float) -> float:
	var a := absf(alpha)
	var attached := profile.cn_attached * sin(a) * cos(a)
	var separated := profile.cn_separated * sin(a)
	var t := clampf((rad_to_deg(a) - profile.stall_start_deg) / maxf(profile.stall_end_deg - profile.stall_start_deg, 0.1), 0.0, 1.0)
	return lerpf(attached, separated, t * t * (3.0 - 2.0 * t)) * signf(alpha)


## Predição do subpasso (integração explícita das forças).
func predict(h: float) -> void:
	_x_prev = x
	_q_prev = q
	v += _force / mass * h
	w += mul_inv_inertia(_torque) * h
	x += v * h
	q = (q + Quaternion(w.x, w.y, w.z, 0.0) * q * (0.5 * h)).normalized()


## Atualiza velocidades a partir das posições corrigidas.
func finalize(h: float) -> void:
	v = (x - _x_prev) / h
	var dq := q * _q_prev.inverse()
	var s := 1.0 if dq.w >= 0.0 else -1.0
	w = Vector3(dq.x, dq.y, dq.z) * (2.0 / h * s)
	if w.length() > 60.0:
		w = w.normalized() * 60.0
	if v.length() > 45.0:
		v = v.normalized() * 45.0


## Orienta a pipa de frente para o ponto `toward` (face +Z para ele), nariz para cima.
func orient_facing(toward_dir: Vector3) -> void:
	var z := toward_dir.normalized()
	var y := (Vector3.UP - z * z.y)
	y = y.normalized() if y.length() > 0.01 else Vector3.FORWARD
	var xa := y.cross(z)
	q = Basis(xa, y, z).get_rotation_quaternion()


func is_valid() -> bool:
	return x.is_finite() and v.is_finite() and w.is_finite() and is_finite(q.x) and is_finite(q.w)
