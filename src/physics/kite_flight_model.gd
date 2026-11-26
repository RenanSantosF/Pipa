class_name KiteFlightModel
extends RefCounted
## MODELO DE VOO da pipa de combate (pipa do jogador), separado do controle.
##
## Base física: pipa de linha única voando na "esfera" da linha (modelo de ponto dos
## simuladores de pipa — KiteModels/FreeKiteSim — e a lei de curva de Erhard &
## Strauch: giro ∝ velocidade × comando do cabresto), mais o comportamento da pipa
## de combate: LINHA ESTICADA = estável, voa reto para onde o bico aponta; LINHA
## FROUXA = instável, o bico gira. O desbico é a alternância dos dois:
##
##  * Cada TOQUE é uma puxadinha: o tranco estica a linha (o giro que estava
##    acontecendo PARA na hora) e dá uma arrancada para onde o bico aponta; quando a
##    linha volta a folgar, o bico BALANÇA para um lado. Os lados alternam sozinhos
##    (1º esquerda, 2º direita, ...). O balanço é giro com inércia (velocidade de
##    giro que decai), não uma animação.
##  * RITMO constante: cada balanço é cortado pelo tranco seguinte antes de render,
##    e os dois lados se anulam: ela segue para onde aponta, balançando e subindo um
##    pouco a cada arrancada (sem chegar mais perto: a linha não é recolhida).
##  * PAUSA depois de um toque: aquele balanço rende inteiro e ela vira para aquele
##    lado. 1 ou 3 toques e pausa = esquerda; 2 toques e pausa = direita.
##  * PIPÃO balança mais devagar e mais (forte); PIPINHA mais rápido e curto.
##  * PUXÃO: linha encurtando soma ao vento aparente — ela acelera reto pelo bico,
##    sobe e chega mais perto; a linha esticada trava o giro (não desbica).
##  * GUIAR (arrastar o dedo): comando de cabresto → inclinação → curva.
##
## A pipa gira em volta do PONTO DE APOIO da linha mais perto dela: a mão, ou o fio /
## galho / telhado / linha de outro em que a linha está encostada. Ela não atravessa
## poste, fio, galho nem casa (movimento contínuo, escorrega na superfície), e a
## translação participa das restrições da linha (KiteRigidBody.kinematic).
##
## Os parâmetros são estáticos para a área de testes ajustar ao vivo.

## Eficiência da vela (sustentação/arrasto) e peso equivalente (m/s).
static var E := 2.1
static var G := 3.0
## Guiar: ganho da curva, velocidade somada, inclinação máxima do cabresto (rad).
static var TURN_K := 0.5
static var TURN_V0 := 6.0
static var BANK_MAX := 0.62
## Tempos de resposta (s) para a pipa M; P × 0,7 e G × 1,5.
static var SPEED_TAU := 0.28
static var BANK_TAU := 0.16
## Parou de mexer: a rabiola endireita o bico (rad/s por sen do erro) e a pipa volta
## para o meio da janela, depois de RESTORE_DELAY s sem comando.
static var UP_RESTORE := 1.2
static var RESTORE_DELAY := 0.6
## Força do puxão (quanto a velocidade de recolher soma ao vento aparente).
static var PULL_GAIN := 2.4
## DESBICO (pipa M): giro de um balanço que rende inteiro (rad), tempo do balanço (s),
## arrancada de cada puxadinha (m/s) e pausa que recomeça a sequência pela esquerda.
static var SWING_AMP := 1.15
static var SWING_TAU := 0.28
static var TUG_DV := 3.2
static var TAP_RESET := 0.45
## Quanto o primeiro balanço da sequência rende (centra o vaivém no rumo).
static var FIRST_SWING := 0.6
## Folga da linha em relação ao comprimento (a linha faz barriga).
const SAG := 0.985
const SIZE_SCALE := [0.7, 1.0, 1.5]
const SIZE_TURN := [1.3, 1.0, 0.75]
const SIZE_SWING_AMP := [0.75, 1.0, 1.25]
const SIZE_SWING_TAU := [0.7, 1.0, 1.45]
const SIZE_TUG := [0.85, 1.0, 1.15]
## Tranco: o giro anterior para em LOCK_TIME (linha esticada).
const LOCK_TIME := 0.045
## Inclinação por velocidade de giro do balanço (rad por rad/s).
const ROLL_PER_W := 0.13
## Tremida do vento: oscilador do bico/inclinação (rad/s de frequência natural,
## amortecimento) forçado pelas rajadas laterais — a pipa nunca fica "dura".
const WOB_W := 6.5
const WOB_Z := 0.22
const WOB_GAIN := 0.14
## Mola da inclinação (frequência natural rad/s, amortecimento).
const ROLL_W := 13.0
const ROLL_Z := 0.45
## Dando linha, a pipa se afasta no máximo a esta velocidade (m/s).
const V_OUT_MAX := 4.0

var rig: KiteRig
var heading := 0.0       ## rumo do bico (rad): 0 = para cima, + = direita do pipeiro
var yaw_rate := 0.0      ## velocidade de giro do bico (rad/s) — o balanço do desbico
var speed := 0.0         ## velocidade tangente (m/s), negativa = cai para trás
var bank := 0.0          ## inclinação total (rad): cabresto + balanço
var steer := 0.0         ## comando do cabresto (−1..1), escrito pelo controle
var steer_bank := 0.0
var tension := 0.0       ## tração na linha (N)
## Sequência de toques: quantos desde a última pausa e lado do balanço atual.
var taps := 0
var swing_side := 0.0
## Total de toques desde o lançamento (testes).
var tap_count := 0
## Ponto de apoio atual (mão, obstáculo ou linha de outro) e comprimento até a pipa.
var pivot := Vector3.ZERO
var pivot_len := 0.0
## Folga da linha (m): quanto a linha está mais comprida do que a distância até o apoio.
var slack := 0.0
var _pull_rate := 0.0
var _since_tap := 10.0
var _since_input := 10.0
var _lock := 0.0
var _pending := 0.0
var _pending_dv := 0.0
var _tug := 0.0
var _x_set := Vector3.ZERO
var _hd_last := Vector3.ZERO
var _pivot_key := -2
var _tap_queue: Array[float] = []
var _pivot_blend := 0.0
var _wob := 0.0
var _wob_v := 0.0
var _w_lat_avg := 0.0
var _roll_v := 0.0
var _pitch := -0.22


func _init(p_rig: KiteRig) -> void:
	rig = p_rig
	var b := rig.body
	var fr := frame()
	var nose: Vector3 = b.q * Vector3.UP
	heading = atan2(nose.dot(fr[2]), nose.dot(fr[1]))


func _size() -> int:
	return clampi(rig.profile.size_class, 0, 2) if rig.profile else 1


## Ponto de apoio da linha mais perto da pipa: [ponto, comprimento até a pipa, chave].
func _pivot() -> Array:
	var r := rig.rope
	if r == null or r.pos.is_empty():
		return [rig.hand_position(), (rig.body.world_point(rig.body.tow_local) - rig.hand_position()).length(), -1]
	var best_s := r._rest_total if r._rest_total > 0.0 else r.length()
	var best_p := r.pos[0]
	var key := -1
	# Nós encostados em fio/galho/telhado (ou presos).
	# A chave é o OBSTÁCULO (o índice do nó muda quando a mão recolhe linha e nós
	# saem perto dela — trocar a chave à toa cortava o efeito do puxão).
	for k in range(1, r.pos.size()):
		if r.pin_obstacle[k] >= 0 or r.pinned[k] == 1:
			var s: float = r.mat_s[k]
			if s > 0.3 and s < best_s:
				best_s = s
				best_p = r.pos[k]
				key = 10 + maxi(r.pin_obstacle[k], 0)
	# Linha de outra pipa encostada (cruzou): a pipa gira em volta do cruzamento.
	var segs := r.segment_count()
	for lp in rig.line_pivots:
		var ia: int = lp[0]
		if ia < 0 or ia >= segs:
			continue
		var ta: float = lp[1]
		var s2 := r.material_at(ia, ta)
		if s2 > 0.3 and s2 < best_s:
			var sp := r.segment_points(ia)
			best_s = s2
			best_p = sp[0].lerp(sp[1], ta)
			key = 2000000 + (int(lp[2]) % 1000000 if lp.size() > 2 else 0)
	return [best_p, best_s, key]


## [direção da linha (apoio→pipa), cima da janela, direita da janela].
func frame() -> Array:
	var b := rig.body
	var pv := _pivot()
	var ld: Vector3 = b.world_point(b.tow_local) - (pv[0] as Vector3)
	ld = ld.normalized() if ld.length() > 0.01 else Vector3.UP
	var up_t := Vector3.UP - ld * ld.y
	up_t = up_t.normalized() if up_t.length() > 0.02 else Vector3.FORWARD
	var right_t := ld.cross(up_t).normalized()
	return [ld, up_t, right_t]


func heading_dir() -> Vector3:
	var fr := frame()
	return (fr[1] as Vector3) * cos(heading) + (fr[2] as Vector3) * sin(heading)


## DESBICO com atraso (s) dentro do tick: o toque chega na hora certa do subpasso
## (a física roda a 30 Hz; sem isso o ritmo dos toques ficava desigual e o rumo ia
## escorregando para um lado).
func tap_at(delay: float) -> void:
	if delay <= 0.0005:
		tap()
	else:
		_tap_queue.append(delay)


## DESBICO: um toque = uma puxadinha (tranco + balanço para o próximo lado).
func tap() -> void:
	var sz := _size()
	if _since_tap > TAP_RESET:
		taps = 0
	taps += 1
	tap_count += 1
	swing_side = -1.0 if taps % 2 == 1 else 1.0
	var amp := SWING_AMP * float(SIZE_SWING_AMP[sz]) * (FIRST_SWING if taps == 1 else 1.0)
	_pending = swing_side * amp / (SWING_TAU * float(SIZE_SWING_TAU[sz]))
	_pending_dv = TUG_DV * float(SIZE_TUG[sz])
	_lock = LOCK_TIME
	_since_tap = 0.0
	_since_input = 0.0
	_tug = 1.0


## Raio da pipa para bater em poste/fio/galho/casa (m).
func kite_radius() -> float:
	return maxf(rig.profile.height * 0.32, 0.14)


## Pulso do braço na puxadinha (0..1), só para o visual da mão.
func tug_visual() -> float:
	return sin(PI * (1.0 - _tug)) if _tug > 0.0 else 0.0


## Um subpasso de voo: escreve a posição/orientação PREVISTAS da pipa (as restrições
## da linha e os contatos ainda corrigem a posição depois).
func step(h: float) -> void:
	var b := rig.body
	var prof := rig.profile
	var sz := _size()
	var tsc: float = SIZE_SCALE[sz]
	var p := b.world_point(b.tow_local)
	# Empurrada pela linha/contato desde o último subpasso: contra o movimento = freou.
	if _x_set != Vector3.ZERO:
		# (Só empurrões de verdade — linha presa, contato com outra linha; o vaivém
		# miúdo da linha não freia.)
		var push := p - _x_set
		var along := push.dot(_hd_last)
		if along < -0.006:
			speed = maxf(speed + (along + 0.006) / h * 0.5, minf(speed, 0.0))
	var pv := _pivot()
	pivot = pv[0]
	pivot_len = pv[1]
	var key: int = pv[2]
	var ld := p - pivot
	var d0 := ld.length()
	ld = ld / d0 if d0 > 0.01 else Vector3.UP
	var up_t := Vector3.UP - ld * ld.y
	up_t = up_t.normalized() if up_t.length() > 0.02 else Vector3.FORWARD
	var right_t := ld.cross(up_t).normalized()
	if key != _pivot_key:
		# Mudou o ponto de apoio: o rumo é remedido no novo referencial (o bico não pula)
		# e o raio novo chega aos poucos — sem isso a troca virava um "puxão" fantasma
		# (a tração disparava e a linha arrebentava sozinha com a pipa longe).
		var nose: Vector3 = b.q * Vector3.UP
		heading = atan2(nose.dot(right_t), nose.dot(up_t))
		if _pivot_key != -2:
			_pivot_blend = 0.35
		_pivot_key = key
	_pivot_blend = maxf(_pivot_blend - h, 0.0)
	var r_t := maxf(pivot_len * SAG, 0.8)
	# Velocidade com que a linha puxa a pipa (mão indo para trás, linha recolhida);
	# negativa = linha saindo (dando linha).
	var u := 0.0 if _pivot_blend > 0.0 else (d0 - r_t) / h
	_pull_rate = lerpf(_pull_rate, clampf(u, -8.0, 12.0), minf(1.0, h / 0.1))
	# Vento.
	var wind := Wind.sample(p)
	var w_n := wind.dot(ld)
	var w_t := wind - ld * w_n
	var hd := up_t * cos(heading) + right_t * sin(heading)
	var w_eff := maxf(w_n + _pull_rate * PULL_GAIN, 0.0)
	var mass_k := (prof.mass + prof.tail_mass * 0.5) / 0.05
	var s_eq := E * w_eff + w_t.dot(hd) - G * mass_k * Vector3.UP.dot(hd)
	s_eq = maxf(s_eq, -3.0)
	speed += (s_eq - speed) * minf(1.0, h / (SPEED_TAU * tsc))
	# --- DESBICO: tranco trava o giro, depois balança para o lado da vez. ---
	var qi := 0
	while qi < _tap_queue.size():
		_tap_queue[qi] -= h
		if _tap_queue[qi] <= 0.0:
			_tap_queue.remove_at(qi)
			tap()
		else:
			qi += 1
	_since_tap += h
	_since_input += h
	if _lock > 0.0:
		_lock -= h
		yaw_rate *= exp(-h / 0.012)
		if _lock <= 0.0:
			yaw_rate += _pending
			# A arrancada vem do vento na vela: lá no alto da janela (bem em cima da
			# cabeça) quase não há vento de frente e o tranco quase não empurra.
			speed += _pending_dv * clampf(w_n / 3.0, 0.15, 1.2)
			_pending = 0.0
			_pending_dv = 0.0
	var tau := SWING_TAU * float(SIZE_SWING_TAU[sz])
	if _pull_rate > 0.6:
		tau = minf(tau, 0.07)      # puxando: linha esticada, vai reta
	elif _pull_rate < -0.8:
		tau *= 1.5                 # dando linha: frouxa, o bico gira mais solto
	yaw_rate *= exp(-h / tau)
	# --- GUIAR: cabresto → inclinação → curva. ---
	steer_bank += (steer * BANK_MAX - steer_bank) * minf(1.0, h / (BANK_TAU * tsc))
	var turn := TURN_K * float(SIZE_TURN[sz]) * (maxf(speed, 0.0) + TURN_V0) * sin(steer_bank)
	if absf(steer) > 0.05:
		_since_input = 0.0
	# Parado (sem toque, sem guiar, sem puxar): a rabiola endireita o bico — para cima
	# e um pouco para o meio da janela (a pipa volta para a posição normal, reta,
	# a favor do vento).
	var restore := 0.0
	if _since_input > RESTORE_DELAY and _pull_rate < 0.6:
		var ramp := minf((_since_input - RESTORE_DELAY) / 0.5, 1.0)
		var wd := Vector3(wind.x, 0.0, wind.z)
		var lat := 0.0
		if wd.length() > 0.1:
			lat = ld.dot(wd.normalized().cross(Vector3.UP))
		var target := clampf(-lat * 1.3, -0.7, 0.7)
		restore = -UP_RESTORE * sin(heading - target) * clampf(prof.tail_length / 2.6, 0.6, 1.5) * ramp
	# Tremida do vento (rajada lateral força um oscilador leve no bico).
	var w_lat := w_t.dot(right_t)
	_w_lat_avg = lerpf(_w_lat_avg, w_lat, minf(1.0, h / 1.2))
	var force := (w_lat - _w_lat_avg) * WOB_GAIN * WOB_W * WOB_W
	_wob_v += (force - WOB_W * WOB_W * _wob - 2.0 * WOB_Z * WOB_W * _wob_v) * h
	_wob += _wob_v * h
	heading = wrapf(heading + (yaw_rate + turn + restore) * h, -PI, PI)
	hd = up_t * cos(heading) + right_t * sin(heading)
	# --- Movimento na esfera em volta do apoio. ---
	var np := p + hd * speed * h
	var r_new := r_t
	if _pivot_blend > 0.0:
		r_new = move_toward(d0, r_t, 2.5 * h)
	elif d0 < r_t:
		# Linha saindo (descarregando): a pipa vai para trás COM O VENTO (perde um pouco
		# de altura e afasta), não reto ao longo da linha.
		var wh := Vector3(wind.x, 0.0, wind.z)
		var out_dir := ld
		if wh.length() > 0.3:
			out_dir = (ld + wh.normalized() * 0.6).normalized()
		np += out_dir * minf(V_OUT_MAX * h, r_t - d0)
		r_new = minf(r_t, (np - pivot).length())
	var rel := np - pivot
	var rl := rel.length()
	if rl > 0.01:
		np = pivot + rel / rl * r_new
	# Poste, fio, galho, casa: não atravessa (para no toque e escorrega). O teste é
	# no CENTRO da vela (o nó do cabresto fica uns 20–30 cm à frente dela).
	var obs: WorldObstacles = rig.rope.obstacles if rig.rope != null else null
	if obs != null:
		var off := b.x - p
		var sw := obs.kite_sweep(p + off, np + off, kite_radius())
		var n: Vector3 = sw[1]
		if n != Vector3.ZERO:
			np = (sw[0] as Vector3) - off
			var vn := hd.dot(n)
			if vn < 0.0:
				speed *= 1.0 + vn
	var g_y := Ground.height_at(np.x, np.z) + 0.4
	if np.y < g_y:
		np.y = g_y
		speed = minf(speed, 0.0) * 0.3
	# Orientação: frente da vela voltada para o apoio, bico = rumo, inclinação =
	# cabresto + balanço do desbico (deita para o lado em que gira).
	var ld2 := (np - pivot).normalized()
	var y_axis := hd - ld2 * hd.dot(ld2)
	y_axis = y_axis.normalized() if y_axis.length() > 0.01 else up_t
	var z_axis := -ld2
	var x_axis := y_axis.cross(z_axis).normalized()
	# Inclinação com mola (passa um pouco e volta: viva, não dura) e a tremida.
	var bank_target := clampf(steer_bank + yaw_rate * ROLL_PER_W + _wob * 1.6, -1.0, 1.0)
	_roll_v += ((bank_target - bank) * ROLL_W * ROLL_W - 2.0 * ROLL_Z * ROLL_W * _roll_v) * h
	bank = clampf(bank + _roll_v * h, -1.1, 1.1)
	# Ângulo da vela com a linha: em voo o topo deita para trás (contra o vento);
	# na arrancada/puxão ela "abaixa a cabeça" para frente, devagar, ela levanta.
	var pitch_target := clampf(-0.32 + 0.035 * speed - 0.025 * maxf(w_eff - speed, 0.0), -0.45, 0.05)
	_pitch = lerpf(_pitch, pitch_target, minf(1.0, h / 0.12))
	var basis := Basis(x_axis, y_axis, z_axis).rotated(z_axis, _wob) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.UP, bank)
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
	_x_set = np
	_hd_last = hd
	# Asas batendo na puxadinha (as varetas envergam com o tranco).
	_tug = maxf(_tug - h / 0.16, 0.0)
	rig.flap = tug_visual()
	rig.bank = 0.0
	# Tração na linha: pressão dinâmica do vento aparente × área × coeficiente da vela
	# (~10 N para a M com 8 m/s). Voando parada ela NUNCA chega perto de arrebentar a
	# linha (no máximo metade do que a linha aguenta); só puxão, tranco e combate.
	var area := b._half_area[0] + b._half_area[1]
	var w_air := maxf(w_n, 0.0) + 0.3 * w_t.length()
	var base := 0.5 * KiteRigidBody.RHO * (w_air * w_air + 0.35 * speed * speed) * area * 1.1
	var brk := rig.line_type.break_tension if rig.line_type else 40.0
	base = minf(base, 0.5 * brk)
	var pull_extra := 0.5 * KiteRigidBody.RHO * maxf(_pull_rate, 0.0) * (2.0 * w_air + maxf(_pull_rate, 0.0)) * area * 1.1
	tension = minf(base + pull_extra, 0.9 * brk) + tug_visual() * (2.5 + 1.5 * float(sz))
	# Linha frouxa (saindo mais rápido do que a pipa se afasta) quase não puxa: é isso
	# que limita o "descarregar" à velocidade com que o vento leva a pipa.
	slack = maxf(r_t - d0, 0.0)
	tension *= clampf(1.0 - slack / maxf(0.02 * r_t, 0.15), 0.08, 1.0)


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
		"SWING_AMP": return SWING_AMP
		"SWING_TAU": return SWING_TAU
		"TUG_DV": return TUG_DV
		"TAP_RESET": return TAP_RESET
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
		"SWING_AMP": SWING_AMP = v
		"SWING_TAU": SWING_TAU = v
		"TUG_DV": TUG_DV = v
		"TAP_RESET": TAP_RESET = v
