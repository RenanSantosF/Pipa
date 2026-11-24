class_name KiteRigidBody
extends RefCounted
## Pipa como corpo rígido 6DOF (posição + orientação), integrada com XPBD.
##
## Eixos locais: X = lateral (direita de quem empina), Y = espinha (nariz),
## Z = normal da face voltada ao jogador. Origem = centro de massa.
##
## Aerodinâmica (docs/REVISAO_V5.md §2): cada meia-vela (triângulo do losango) é
## uma placa de baixo alongamento com SEU diedro e SUA velocidade local (v + ω×r):
##  - sustentação CL(α) = Kp·sen α·cos²α + Kv·cos α·sen²α (Polhamus) → placa
##    descolada após o estol;  arrasto CD = CD0 + CL·tan α (induzido + normal);
##  - força = q·A·(CL·l̂ + CD·v̂), l̂ ⟂ vento no plano da normal;
##  - centro de pressão desliza de ¼ da corda até o centro conforme α cresce.
##
## Atuadores do desbico (escritos pela KiteRig a cada tick, NÃO giram a pipa):
##  - sail_asym: flexão assimétrica das varetas (rad): diedro + num lado, − no outro
##    → desloca o centro de sustentação e cria força lateral;
##  - o deslocamento do ponto de tração (perna do cabresto carregada) fica na Rope
##    (end_local), então o torque vem da própria tensão da linha.

const RHO := 1.225
const GRAVITY := Vector3(0.0, -9.8, 0.0)
static var RELAX_DIHEDRAL := 0.0

var profile: KiteProfile
var mass: float = 0.03
var inertia := Vector3.ONE
var inv_inertia := Vector3.ONE

var x := Vector3.ZERO           ## centro de massa (mundo)
var v := Vector3.ZERO
var q := Quaternion.IDENTITY
var w := Vector3.ZERO           ## velocidade angular (mundo)

## Cantos do losango (local): nariz, direita, ponta de baixo, esquerda.
var corners: PackedVector3Array = PackedVector3Array()
var tow_local := Vector3.ZERO
var tail_local := Vector3.ZERO
## Diedro de repouso (envergadura) e flexão assimétrica atual (desbico).
var dihedral: float = 0.17
var sail_asym: float = 0.0
## Vareta RELAXADA na folga (0 = linha esticada, 1 = sem tensão) e o viés da
## relaxação para um lado (−1 esquerda … +1 direita), dado pelo jeito de soltar.
## Vareta envergada sob carga fica simétrica; sem carga ela relaxa torta e o vento
## na vela torta gira a pipa em torno da normal ("a pipa roda / vira o bico").
var relax: float = 0.0
var spin_bias: float = 0.0

# Meias-velas: [esquerda, direita] — pontos locais planos, área.
var _half_pts: Array[PackedVector3Array] = []
var _half_area: PackedFloat32Array = PackedFloat32Array()
var _half_center_flat: PackedVector3Array = PackedVector3Array()

# Estado aerodinâmico (para HUD/sons/rede).
var angle_of_attack: float = 0.0
var airspeed: float = 0.0
var lift: float = 0.0
var drag: float = 0.0
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
	# Losango: a maior parte da massa está nas varetas (espinha + 2 travessas).
	inertia = Vector3(mass * h * h / 18.0 + 0.00008, mass * wd * wd / 16.0 + 0.00008, mass * (h * h / 18.0 + wd * wd / 16.0) + 0.0001)
	inv_inertia = Vector3(1.0 / inertia.x, 1.0 / inertia.y, 1.0 / inertia.z)
	# Pipa brasileira (foto de referência): a vareta passa ACIMA do papel (cabeça),
	# a travessa envergada é a borda de cima do papel, os lados descem quase retos
	# até os "ombros" e fecham em V na ponta de baixo. Da cabeça saem linhas até as
	# pontas da travessa (sem papel no triângulo de cima).
	#   cantos: 0 cabeça · 1 travessa dir · 2 ombro dir · 3 ponta · 4 ombro esq · 5 travessa esq
	var yc := -p.cross_at * h
	var ys := -p.lower_at * h
	var ws := wd * 0.5 * p.shoulder
	var raw := [Vector2(0, 0), Vector2(wd * 0.5, yc), Vector2(ws, ys), Vector2(0, -h), Vector2(-ws, ys), Vector2(-wd * 0.5, yc)]
	# Centro de massa: papel (pentágono) + a cabeça da vareta acima dele.
	var paper := [raw[5], raw[1], raw[2], raw[3], raw[4]]
	var cen: Vector2 = _poly_centroid(paper) * 0.88 + Vector2(0, yc * 0.5) * 0.12
	corners = PackedVector3Array()
	for v2 in raw:
		corners.append(Vector3(v2.x - cen.x, v2.y - cen.y, 0.0))
	var top_paper_y := corners[1].y
	tow_local = Vector3(0, corners[0].y - p.tow_fraction * h, p.bridle_length)
	tail_local = corners[3]
	dihedral = p.dihedral()
	for side in [-1.0, 1.0]:
		var top_mid := Vector3(0, top_paper_y, 0)
		var pts := PackedVector3Array([top_mid, corners[5], corners[4], corners[3]]) if side < 0.0 \
			else PackedVector3Array([top_mid, corners[1], corners[2], corners[3]])
		# Contorno da meia-vela para o centro de pressão: inclui a cabeça (vareta +
		# linhas da cabeça às pontas da travessa formam a borda de ataque da armação).
		var outline := pts.duplicate()
		outline.append(corners[0])
		_half_pts.append(outline)
		var area := 0.0
		var c := Vector3.ZERO
		for k in range(1, pts.size() - 1):
			var ta := 0.5 * (pts[k] - pts[0]).cross(pts[k + 1] - pts[0]).length()
			area += ta
			c += (pts[0] + pts[k] + pts[k + 1]) / 3.0 * ta
		_half_area.append(area)
		_half_center_flat.append(c / maxf(area, 1e-6))


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


## Diedro de cada meia-vela agora (0 = esquerda, 1 = direita), com a flexão do desbico.
## sail_asym > 0: a meia-vela DIREITA fecha (vai para trás), a esquerda abre.
func half_dihedral(i: int) -> float:
	# Folga: a vareta relaxa (menos envergada) e fica torta para o lado do desbico.
	var a := sail_asym - spin_bias * relax * 0.1
	var s := a if i == 1 else -a
	var base := dihedral * (1.0 - RELAX_DIHEDRAL * relax)
	return clampf(base + (s if s > 0.0 else s * 0.6), 0.0, 0.8)


## Normal local da meia-vela i (as pontas vão para trás = −Z).
func half_normal(i: int) -> Vector3:
	var d := half_dihedral(i)
	var side := 1.0 if i == 1 else -1.0
	return Vector3(side * sin(d), 0.0, cos(d))


## Ponto local da meia-vela i dobrado pelo diedro (ponta lateral vai para trás).
func half_point(i: int, p: Vector3) -> Vector3:
	var d := half_dihedral(i)
	var xx := absf(p.x)
	return Vector3(p.x * cos(d), p.y, -xx * sin(d))


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


## Coeficientes de baixo alongamento: [CL, CD] para o ângulo de ataque α (rad, com sinal).
func coefficients(alpha: float) -> Vector2:
	var a := absf(alpha)
	var sa := sin(a)
	var ca := cos(a)
	var cl_att := profile.lift_kp * sa * ca * ca + profile.lift_kv * ca * sa * sa
	var cd_att := cl_att * sa / maxf(ca, 0.05)
	var cn_sep := profile.cn_separated * sa
	var t := clampf((rad_to_deg(a) - profile.stall_start_deg) / maxf(profile.stall_end_deg - profile.stall_start_deg, 0.1), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var cl := lerpf(cl_att, cn_sep * ca, t)
	var cd := lerpf(cd_att, cn_sep * sa, t) + profile.cd0
	return Vector2(cl * signf(alpha), cd)


## Calcula força e torque (gravidade + aerodinâmica) para o vento atual.
func compute_forces() -> void:
	_force = GRAVITY * mass
	_torque = Vector3.ZERO
	var alpha_sum := 0.0
	var sp_sum := 0.0
	var lift_sum := 0.0
	var drag_sum := 0.0
	for i in 2:
		var n: Vector3 = q * half_normal(i)
		var cw: Vector3 = q * half_point(i, _half_center_flat[i])
		var vel := v + w.cross(cw)
		var vrel: Vector3 = Wind.sample(x + cw) - vel
		var sp := vrel.length()
		sp_sum += sp
		if sp < 0.05:
			continue
		var vd := vrel / sp
		var qd := 0.5 * RHO * sp * sp
		# α > 0: o vento bate na face da frente (voltada ao jogador).
		var sina := clampf(-vd.dot(n), -1.0, 1.0)
		var al := asin(sina)
		alpha_sum += al
		var co := coefficients(al)
		var area: float = _half_area[i]
		# Direção da sustentação: ⟂ ao vento, do lado de −n.
		var perp := -n + vd * n.dot(vd)
		var pl := perp.length()
		var f := vd * (qd * area * co.y)
		var lmag := 0.0
		if pl > 0.0005:
			f += perp / pl * (qd * area * co.x)
			lmag = qd * area * co.x
		lift_sum += lmag
		drag_sum += qd * area * co.y
		# Centro de pressão ao longo do escoamento no plano da meia-vela.
		var cop := cw
		var flow := vd - n * vd.dot(n)
		var fl := flow.length()
		if fl > 0.001:
			var fdir := flow / fl
			var pts: PackedVector3Array = _half_pts[i]
			var lead := INF
			var far := -INF
			for pt in pts:
				var pr := (q * half_point(i, pt)).dot(fdir)
				lead = minf(lead, pr)
				far = maxf(far, pr)
			var chord := far - lead
			cop = cw + fdir * ((lead - cw.dot(fdir)) + chord * (0.25 + 0.25 * sin(absf(al))))
		_force += f
		_torque += cop.cross(f)
	angle_of_attack = alpha_sum * 0.5
	airspeed = sp_sum * 0.5
	lift = lift_sum
	drag = drag_sum
	# Vela torta na folga: momento em torno da normal (gira o BICO, sem força lateral).
	if spin_bias != 0.0 and relax > 0.0:
		var qa := 0.5 * RHO * airspeed * airspeed * (_half_area[0] + _half_area[1]) * profile.height
		_torque += (q * Vector3.BACK) * (-spin_bias * profile.spin_coef * qa * relax)
	var span := profile.width * profile.height * 0.5 * profile.height * profile.height
	_torque -= w * (profile.rotational_damping * 0.5 * RHO * maxf(airspeed, 1.0) * span)


func add_torque(t: Vector3) -> void:
	_torque += t


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
