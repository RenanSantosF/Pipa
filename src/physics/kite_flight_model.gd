class_name KiteFlightModel
extends RefCounted
## MODELO DE VOO da pipa de combate (pipa do jogador), separado do controle.
##
## Base: modelos de pipa de linha única usados em simulação de pipas (modelo de
## ponto na "esfera" de raio = comprimento da linha, como nos simuladores de energia
## eólica com pipas — KiteModels/FreeKiteSim — e a lei de curva de Erhard & Strauch:
## giro ∝ velocidade × comando do cabresto):
##
##  * A pipa anda TANGENTE à esfera, para onde o bico aponta (rumo ψ). A velocidade
##    de equilíbrio vem do vento que bate de frente na vela (componente do vento ao
##    longo da linha, W_n) vezes a eficiência da vela (sustentação/arrasto, E), mais o
##    vento que corre pela esfera na direção do rumo, menos a gravidade quando ela
##    sobe (e mais quando desce). A borda da janela de vento aparece sozinha: lá em
##    cima W_n → 0 e ela não sobe mais.
##  * Puxar linha (linha encurtando a r m/s) soma r ao vento aparente: ela acelera,
##    sobe e chega mais perto. Dar linha subtrai: ela perde força e se afasta.
##  * CABRESTO: o comando do jogador desloca o ponto de tração para um lado; a pipa
##    INCLINA (rolagem β, com tempo de resposta) e a sustentação inclinada faz a
##    CURVA: dψ/dt = K × (velocidade + v0) × sen β. Corpo e voo sempre ligados: o
##    bico é o rumo, a inclinação é a do cabresto.
##  * Inércia: velocidade e inclinação seguem o equilíbrio com constantes de tempo
##    (pipão mais lento, pipinha mais rápida). Sem comando, a linha esticada deixa a
##    pipa reta e a rabiola puxa o bico devagar para cima.
##
## Os parâmetros são estáticos para a área de testes ajustar ao vivo.

## Eficiência da vela (sustentação/arrasto) e peso equivalente (m/s).
static var E := 1.8
static var G := 3.0
## Curva: ganho, velocidade somada, inclinação máxima do cabresto (rad).
static var TURN_K := 0.5
static var TURN_V0 := 6.0
static var BANK_MAX := 0.62
## Tempos de resposta (s) para a pipa M; P × 0,7 e G × 1,5.
static var SPEED_TAU := 0.35
static var BANK_TAU := 0.16
## A rabiola puxa o bico para cima quando não há comando (rad/s por sen ψ).
static var UP_RESTORE := 0.35
## Força do puxão (quanto a velocidade de recolher soma ao vento aparente).
static var PULL_GAIN := 1.8
## Folga da linha em relação ao comprimento (a linha faz barriga).
const SAG := 0.985
const SIZE_SCALE := [0.7, 1.0, 1.5]
const SIZE_TURN := [1.3, 1.0, 0.75]

var rig: KiteRig
var heading := 0.0       ## rumo do bico (rad): 0 = para cima, + = direita do pipeiro
var speed := 0.0         ## velocidade tangente (m/s), negativa = cai para trás
var bank := 0.0          ## inclinação (rad) imposta pelo cabresto
var steer := 0.0         ## comando do cabresto (−1..1), escrito pelo controle
var tension := 0.0       ## tração na linha (N)
var _radius := 0.0
var _pull_rate := 0.0


func _init(p_rig: KiteRig) -> void:
	rig = p_rig
	var b := rig.body
	var fr := frame()
	var nose: Vector3 = b.q * Vector3.UP
	heading = atan2(nose.dot(fr[2]), nose.dot(fr[1]))
	_radius = (b.world_point(b.tow_local) - _hand()).length()


func _hand() -> Vector3:
	return rig.rope.pos[0] if rig.rope != null and rig.rope.pos.size() > 0 else rig.hand_position()


## [direção da linha (mão→pipa), cima da janela, direita da janela].
func frame() -> Array:
	var b := rig.body
	var ld := b.world_point(b.tow_local) - _hand()
	ld = ld.normalized() if ld.length() > 0.01 else Vector3.UP
	var up_t := Vector3.UP - ld * ld.y
	up_t = up_t.normalized() if up_t.length() > 0.02 else Vector3.FORWARD
	var right_t := ld.cross(up_t).normalized()
	return [ld, up_t, right_t]


func heading_dir() -> Vector3:
	var fr := frame()
	return (fr[1] as Vector3) * cos(heading) + (fr[2] as Vector3) * sin(heading)


## Um subpasso de voo.
func step(h: float) -> void:
	var b := rig.body
	var prof := rig.profile
	var sz := clampi(prof.size_class, 0, 2)
	var tsc: float = SIZE_SCALE[sz]
	var hand := _hand()
	var fr := frame()
	var ld: Vector3 = fr[0]
	var up_t: Vector3 = fr[1]
	var right_t: Vector3 = fr[2]
	# Raio = comprimento da linha (com barriga). Encurtando = puxando.
	var target_r := maxf(rig.rope._rest_total * SAG, 1.0) if rig.rope != null else _radius
	var dr := target_r - _radius
	_pull_rate = lerpf(_pull_rate, -dr / h, minf(1.0, h / 0.12))
	_radius = target_r
	# Vento.
	var p := b.world_point(b.tow_local)
	var wind := Wind.sample(p)
	var w_n := wind.dot(ld)
	var w_t := wind - ld * w_n
	var hd := up_t * cos(heading) + right_t * sin(heading)
	var w_eff := maxf(w_n + _pull_rate * PULL_GAIN, 0.0)
	var mass_k := (prof.mass + prof.tail_mass * 0.5) / 0.05
	var s_eq := E * w_eff + w_t.dot(hd) - G * mass_k * Vector3.UP.dot(hd)
	s_eq = maxf(s_eq, -3.0)
	speed += (s_eq - speed) * minf(1.0, h / (SPEED_TAU * tsc))
	# Cabresto → inclinação → curva.
	bank += (steer * BANK_MAX - bank) * minf(1.0, h / (BANK_TAU * tsc))
	var turn := TURN_K * float(SIZE_TURN[sz]) * (maxf(speed, 0.0) + TURN_V0) * sin(bank)
	var restore := -UP_RESTORE * sin(heading) * (1.0 - absf(steer)) * clampf(prof.tail_length / 2.6, 0.5, 1.6)
	heading = wrapf(heading + (turn + restore) * h, -PI, PI)
	hd = up_t * cos(heading) + right_t * sin(heading)
	# Anda na esfera.
	var np := p + hd * speed * h
	var g_y := Ground.height_at(np.x, np.z) + 0.4
	if np.y < g_y:
		np.y = g_y
		speed = minf(speed, 0.0) * 0.3
	var rel := np - hand
	if rel.length() > 0.01:
		np = hand + rel.normalized() * _radius
	# Orientação: frente da vela voltada para a mão, bico = rumo, inclinação = cabresto.
	var ld2 := (np - hand).normalized()
	var y_axis := (hd - ld2 * hd.dot(ld2)).normalized()
	var z_axis := -ld2
	var x_axis := y_axis.cross(z_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis) * Basis(Vector3.UP, bank)
	var q_new := basis.get_rotation_quaternion()
	var x_new := np - q_new * b.tow_local
	var inv_h := 1.0 / h
	var dq := q_new * b.q.inverse()
	if dq.w < 0.0:
		dq = -dq
	b.w = Vector3(dq.x, dq.y, dq.z) * (2.0 * inv_h)
	b.v = (x_new - b.x) * inv_h
	b.x = x_new
	b.q = q_new
	b.airspeed = sqrt(w_eff * w_eff + speed * speed)
	b.angle_of_attack = atan2(w_eff, maxf(absf(speed), 0.1))
	# Tração na linha (pressão dinâmica × área × coeficiente).
	var w_line := maxf(w_n + _pull_rate, 0.0)
	tension = 0.5 * KiteRigidBody.RHO * (w_line * w_line + 0.5 * speed * speed) * (b._half_area[0] + b._half_area[1]) * 2.2


## Área de testes: ler/escrever parâmetro pelo nome.
static func param(key: String) -> float:
	match key:
		"E": return E
		"G": return G
		"TURN_K": return TURN_K
		"TURN_V0": return TURN_V0
		"BANK_MAX": return BANK_MAX
		"SPEED_TAU": return SPEED_TAU
		"BANK_TAU": return BANK_TAU
		"UP_RESTORE": return UP_RESTORE
		"PULL_GAIN": return PULL_GAIN
	return 0.0


static func set_param(key: String, v: float) -> void:
	match key:
		"E": E = v
		"G": G = v
		"TURN_K": TURN_K = v
		"TURN_V0": TURN_V0 = v
		"BANK_MAX": BANK_MAX = v
		"SPEED_TAU": SPEED_TAU = v
		"BANK_TAU": BANK_TAU = v
		"UP_RESTORE": UP_RESTORE = v
		"PULL_GAIN": PULL_GAIN = v
