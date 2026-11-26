class_name Bridle
extends RefCounted
## CABRESTO de verdade: duas pernas de LINHA amarradas num NÓ, e a linha de empinar
## amarrada nesse nó.
##
##   perna de cima  — da cabeça da vareta até o nó;
##   perna de baixo — da vareta, perto da ponta de baixo, até o nó.
##
## O nó (e o cabresto) pesa ~1 g, contra ~30 g da pipa: é tratado como nó SEM MASSA
## em equilíbrio, que é exato nesse limite e não amolece a ligação (um nó-partícula
## leve entre a linha e a pipa só transmitia ~20% da tração no passo de física do
## celular). Equilíbrio do nó: tração da linha + trações das pernas = 0, com cada perna
## só PUXANDO (linha frouxa não empurra). A cada subpasso:
##
##  * as duas pernas esticadas: o nó fica no círculo em volta da vareta onde as duas
##    esferas (centro em cada ponto de amarração, raio = perna) se cruzam, GIRADO para
##    o lado de onde vem a linha. A força da linha passa pelo nó; como as duas pernas
##    estão no eixo da vareta, ela NÃO gera torque de rolagem em volta da vareta (a
##    pipa gira livre em volta da vareta; quem segura a rolagem é o diedro e a rabiola);
##  * se a linha puxa por fora do "leque" das pernas, uma perna afrouxa e o nó fica
##    alinhado com a outra perna (a pipa pendurada por uma perna só);
##  * a posição do nó em relação ao centro de massa e ao centro de pressão decide o
##    ângulo de ataque: é a REGULAGEM DO CABRESTO (nó mais para a cabeça = pipa mais
##    deitada, sobe mais e puxa menos; mais para baixo = mais em pé, puxa mais).
##
## Cada força de perna passa pelo nó, então o efeito das duas pernas na pipa (força e
## torque) é igual ao da tração da linha aplicada no nó: a Rope usa `knot_local` como
## ponta da linha no corpo (end_local), atualizado a cada subpasso.

var body: KiteRigidBody
## Pontos de amarração das pernas na vareta (local) e comprimento de cada perna (m).
var anchors: PackedVector3Array = PackedVector3Array()
var legs: PackedFloat32Array = PackedFloat32Array()
## Nó agora (local) e a fração da tração em cada perna.
var knot_local := Vector3.ZERO
var leg_share: PackedFloat32Array = PackedFloat32Array([0.5, 0.5])
## Tração de cada perna no último tick (N).
var leg_tension: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Qual perna está frouxa (-1 = nenhuma).
var slack_leg: int = -1
# Círculo das duas pernas esticadas (centro na vareta, raio) e lado atual do nó.
var _c := Vector3.ZERO
var _rho := 0.0
var _side := Vector3.BACK


## Monta o cabresto: pernas de `top_local` e `bottom_local` até o nó em `p_knot`
## (as duas esticadas).
func setup(p_body: KiteRigidBody, top_local: Vector3, bottom_local: Vector3, p_knot: Vector3) -> void:
	body = p_body
	anchors = PackedVector3Array([top_local, bottom_local])
	legs = PackedFloat32Array([(p_knot - top_local).length(), (p_knot - bottom_local).length()])
	var a := anchors[0]
	var b := anchors[1]
	var d := (b - a).length()
	var x := (legs[0] * legs[0] - legs[1] * legs[1] + d * d) / (2.0 * d)
	_rho = sqrt(maxf(legs[0] * legs[0] - x * x, 0.0))
	_c = a + (b - a) / d * x
	var w := p_knot - _c
	_side = w.normalized() if w.length() > 1e-5 else Vector3.BACK
	knot_local = p_knot


## Pontos padrão: perna de cima na cabeça da vareta, perna de baixo a 1/6 da altura
## acima da ponta, nó em (`knot_y` abaixo da cabeça, `knot_z` à frente do papel),
## em frações da altura.
static func standard_points(b: KiteRigidBody, knot_y: float, knot_z: float) -> Array:
	var h := b.profile.height
	var top := Vector3(0.0, b.corners[0].y - 0.03 * h, 0.0)
	var bottom := Vector3(0.0, b.corners[3].y + h / 6.0, 0.0)
	var k := Vector3(0.0, b.corners[0].y - knot_y * h, knot_z * h)
	return [top, bottom, k]


## Posiciona o nó para a linha que vem do ponto `toward` (mundo: o nó vizinho da
## linha) e devolve o ponto de tração (local).
func update(toward: Vector3) -> Vector3:
	var p := body.q.inverse() * (toward - body.x)
	var spine := Vector3.UP
	# Lado de onde vem a linha, no plano ⟂ à vareta.
	var w := p - _c
	w -= spine * w.dot(spine)
	if w.length() > 1e-4:
		_side = w.normalized()
	var k := _c + _side * _rho
	# Equilíbrio do nó no plano (vareta, lado): T0·u0 + T1·u1 = −l.
	var l := p - k
	var ll := l.length()
	if ll < 1e-5:
		knot_local = k
		return k
	l /= ll
	var u0 := (anchors[0] - k) / legs[0]
	var u1 := (anchors[1] - k) / legs[1]
	var s0 := Vector2(u0.dot(spine), u0.dot(_side))
	var s1 := Vector2(u1.dot(spine), u1.dot(_side))
	var sl := Vector2(l.dot(spine), l.dot(_side))
	var det := s0.x * s1.y - s1.x * s0.y
	var t0 := 0.5
	var t1 := 0.5
	if absf(det) > 1e-6:
		t0 = (-sl.x * s1.y + s1.x * sl.y) / det
		t1 = (-s0.x * sl.y + sl.x * s0.y) / det
	slack_leg = -1
	if t1 < 0.0:
		# Perna de baixo frouxa: pendurada pela de cima, alinhada com a linha.
		slack_leg = 1
		k = anchors[0] + (p - anchors[0]).normalized() * legs[0]
		t0 = 1.0
		t1 = 0.0
	elif t0 < 0.0:
		slack_leg = 0
		k = anchors[1] + (p - anchors[1]).normalized() * legs[1]
		t0 = 0.0
		t1 = 1.0
	leg_share[0] = t0
	leg_share[1] = t1
	knot_local = k
	return k


## Tração das pernas para a tração da linha no nó (N).
func finish_tick(line_tension: float) -> void:
	leg_tension[0] = leg_share[0] * line_tension
	leg_tension[1] = leg_share[1] * line_tension


## Nó no mundo.
func knot_world() -> Vector3:
	return body.world_point(knot_local)
