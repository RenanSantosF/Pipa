class_name LineHand
extends RefCounted
## A MÃO do pipeiro na física de verdade (v0.18): ela só mexe na LINHA.
## Nada aqui empurra, gira ou posiciona a pipa — o que a pipa faz vem da linha
## (tração/folga transmitidas pela corrente XPBD e pelo cabresto), do vento, do
## peso e da rabiola.
##
## Saídas escritas na KiteRig a cada tick:
##   stroke  — posição do braço ao longo da linha (m): + = mão puxada para o peito,
##             − = braço esticado para a frente (dá folga)
##   grip    — pegada (1 = mão fechada; 0 = aberta: a linha corre com a tração)
##   reel_rate — enrolando na lata (m/s): APARAR
##   shorten_on_return — quando o braço volta, a outra mão segura a linha (o trecho
##             puxado fica na mão/no chão): é assim que a braçada RECOLHE linha
##
## Gestos → mão:
##   toque         — PUXADINHA (desbico): o braço dá um tranco curto e devolve a
##                   linha; a tração sobe por um instante e depois volta a folgar
##   puxão         — BRAÇADA: o braço puxa ~0,6 m e volta com a outra mão segurando
##   puxada contínua — braçadas em série (mão sobre mão), ritmo pelo dedo
##   arrastar ↑/↓  — braço para a frente (folga) ou para trás (estica), contínuo
##   dar linha     — mão aberta: a linha corre da lata com a tração da pipa
##   aparar        — enrolar na lata

## DESBICO = "dá e puxa": o braço vai à frente e a mão abre um instante (folga: a
## linha sem tração, a vareta desenverga, o bico fica solto) e logo puxa curto (a
## linha estica de novo e a pipa sai para onde o bico estiver apontando).
## Folga: braço à frente (m), tempo (s), pegada aberta durante a folga.
## Folga curta com a mão firme (a linha não corre a cada toque: frouxa e correndo,
## ela cruzava mais com as outras nos testes).
static var TAP_SLACK := 0.06
static var TAP_SLACK_T := 0.08
static var TAP_GIVE := 0.6
## Pipa longe: o pipeiro aumenta o braço (a linha comprida estica e faz barriga e
## engole um tranco curto). Ganho por metro de linha acima de FAR_FROM e o máximo.
static var FAR_GAIN := 0.012
const FAR_FROM := 25.0
const FAR_MAX := 1.6
## Puxadinha: curso (m), subida e volta (s).
static var TUG_LEN := 0.04
static var TUG_UP := 0.07
static var TUG_DOWN := 0.2
## Braçada do puxão: curso (m), arranque, segurada e volta do braço (s).
const STROKE_LEN := 0.6
const STROKE_UP := 0.12
const STROKE_HOLD := 0.03
const STROKE_BACK := 0.32
## Braço esticado para a frente no máximo (m) e o quanto ele vai para trás (m).
const ARM_FWD := 0.45
const ARM_BACK := 0.3
## Puxada contínua: intervalo entre braçadas (s), do ritmo lento ao rápido.
const REPEAT_SLOW := 0.5
const REPEAT_FAST := 0.24

var rig: KiteRig
## Tamanho da puxadinha (0..1,5), escrito pelo gesto.
var tug_strength: float = 1.0
## Braço contínuo pelo arrasto (−1 = todo à frente / folga … +1 = para trás).
var arm: float = 0.0
## Puxada contínua (dedo segurando para baixo) e ritmo (0..1).
var pull_held: bool = false
var pull_rate: float = 0.0
## Contadores (sondas/HUD).
var tap_count: int = 0
var stroke_count: int = 0

var _clock := 0.0
## Tamanho do braço do toque atual (1 = perto).
var _amp := 1.0
var _tug_t := -1.0
var _tug_from := 0.0
var _pending_taps: Array[float] = []
var _stroke_t := -1.0
var _stroke_from := 0.0
var _stroke_queue := 0
var _repeat_t := 0.0
var _arm_pos := 0.0
var _stroke := 0.0
## Linha puxada pelo dedo esperando entrar (m) e velocidade máxima da mão (m/s).
var _line_pending := 0.0
## Velocidade máxima da mão puxando (m/s) com um dedo; dois dedos (uma mão de cada
## lado da tela) puxam quase o dobro.
const PULL_SPEED_ONE := 1.6
const PULL_SPEED_TWO := 2.6
var pull_fingers: int = 1
## Braço visual da puxada mão-sobre-mão (só desenho: a linha já entrou pela mão).
var visual_pull := 0.0


func _init(p_rig: KiteRig) -> void:
	rig = p_rig


## Desbico: uma puxadinha. `delay` = atraso dentro do tick (ritmo exato dos toques).
func tap(delay: float = 0.0) -> void:
	_pending_taps.append(_clock + maxf(delay, 0.0))
	tap_count += 1
	_release_hold()


## Puxão: uma braçada (as que chegarem durante uma braçada emendam em seguida).
func pull() -> void:
	if _stroke_t >= 0.0:
		_stroke_queue = mini(_stroke_queue + 1, 2)
	else:
		_start_stroke()
	_release_hold()


## Dedo puxando a linha: `m` metros entram na velocidade do dedo (mão sobre mão).
func pull_line(m: float) -> void:
	if m <= 0.0:
		return
	_line_pending += m
	_release_hold()
	rig.desbico_keep()


func is_pulling() -> bool:
	return _stroke_t >= 0.0 or pull_held


func tug_amount() -> float:
	return clampf(_tug_shape(), 0.0, 1.0)


func _release_hold() -> void:
	if rig != null and rig.held:
		rig.release_hold()


func _start_stroke() -> void:
	_stroke_t = 0.0
	_stroke_from = _stroke
	stroke_count += 1


## Posição do braço na puxadinha (m, + = puxado): folga à frente, depois tranco, depois volta.
func _tug_pos(t: float) -> float:
	if t < 0.0:
		return 0.0
	var slack := TAP_SLACK * _amp
	var tug := TUG_LEN * tug_strength * _amp
	if t < TAP_SLACK_T:
		return -slack * _smooth(t / TAP_SLACK_T)
	var t2 := t - TAP_SLACK_T
	if t2 < TUG_UP:
		return lerpf(-slack, tug, _smooth(t2 / TUG_UP))
	return tug * (1.0 - _smooth((t2 - TUG_UP) / TUG_DOWN))


func _tug_total() -> float:
	return TAP_SLACK_T + TUG_UP + TUG_DOWN


func _tug_shape() -> float:
	if _tug_t < 0.0:
		return 0.0
	return clampf(_tug_pos(_tug_t) / maxf(TUG_LEN, 0.01), -1.0, 1.0)


static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Um tick da mão. `grip_in` = pegada pedida (1 fechada … 0 aberta = dar linha),
## `reel` = aparar (m/s).
func update(delta: float, grip_in: float, reel: float) -> void:
	_clock += delta
	if rig == null:
		return
	# Puxada contínua: braçadas em série.
	if pull_held:
		_repeat_t += delta
		if _repeat_t >= lerpf(REPEAT_SLOW, REPEAT_FAST, clampf(pull_rate, 0.0, 1.0)):
			_repeat_t = 0.0
			pull()
	else:
		_repeat_t = 1.0
	# Toques que venceram neste tick: a puxadinha recomeça de onde o braço está.
	while not _pending_taps.is_empty() and _pending_taps[0] <= _clock:
		var t0: float = _pending_taps.pop_front()
		_tug_from = _tug_pos(_tug_t) if _tug_t >= 0.0 else 0.0
		_tug_t = maxf(_clock - t0, 0.0)
		var ln := rig.flying_length() if rig.rope != null else 0.0
		_amp = clampf(1.0 + FAR_GAIN * (ln - FAR_FROM), 1.0, FAR_MAX)
		rig.desbico_tap()
	var keep_line := false
	# Braço contínuo (arrasto): à frente dá folga, atrás estica.
	var arm_target := -ARM_FWD * maxf(-arm, 0.0) + ARM_BACK * maxf(arm, 0.0)
	_arm_pos = move_toward(_arm_pos, arm_target, 2.5 * delta)
	var s := _arm_pos
	# Braçada.
	if _stroke_t >= 0.0:
		_stroke_t += delta
		var t1 := STROKE_UP
		var t2 := t1 + STROKE_HOLD
		var t3 := t2 + STROKE_BACK
		var st := 0.0
		if _stroke_t < t1:
			st = lerpf(_stroke_from, STROKE_LEN, _smooth(_stroke_t / t1))
		elif _stroke_t < t2:
			st = STROKE_LEN
			if _stroke_queue > 0:
				_stroke_queue -= 1
				_start_stroke()
				st = STROKE_LEN
		elif _stroke_t < t3:
			st = lerpf(STROKE_LEN, 0.0, _smooth((_stroke_t - t2) / STROKE_BACK))
			keep_line = true   # a outra mão segura: o trecho puxado fica recolhido
			if _stroke_queue > 0:
				_stroke_queue -= 1
				_stroke_from = st
				_stroke_t = 0.0
				stroke_count += 1
		else:
			_stroke_t = -1.0
		s += st
	# Puxadinha (por cima de tudo; a linha volta para a pipa — não recolhe).
	var grip := clampf(grip_in, 0.0, 1.0)
	if _tug_t >= 0.0:
		_tug_t += delta
		var tp := _tug_pos(_tug_t)
		# Um toque emendado no anterior começa de onde o braço estava.
		if _tug_t < TAP_SLACK_T and _tug_from != 0.0:
			tp = lerpf(_tug_from, -TAP_SLACK * _amp, _smooth(_tug_t / TAP_SLACK_T))
		s += tp
		if _tug_t < TAP_SLACK_T:
			grip = minf(grip, TAP_GIVE)
		rig.tap_slack = _tug_t < TAP_SLACK_T + 0.05
		if _tug_t >= _tug_total():
			_tug_t = -1.0
			_tug_from = 0.0
	# Linha puxada pelo dedo: entra na velocidade dele (a outra mão segura o que entrou).
	if _line_pending > 0.0 and rig.rope != null:
		var cap := PULL_SPEED_TWO if pull_fingers >= 2 else PULL_SPEED_ONE
		var take := minf(_line_pending, cap * delta)
		_line_pending -= take
		rig.regrip(take)
		visual_pull += take
		if visual_pull > 0.45:
			visual_pull -= 0.45
	else:
		_line_pending = 0.0
		visual_pull = move_toward(visual_pull, 0.0, 1.2 * delta)
	if _tug_t < 0.0:
		rig.tap_slack = false
	_stroke = s
	rig.stroke = s
	rig.grip = grip
	rig.reel_rate = maxf(reel, 0.0)
	rig.shorten_on_return = keep_line
	if grip_in < 0.95 or reel > 0.0 or arm != 0.0:
		_release_hold()
