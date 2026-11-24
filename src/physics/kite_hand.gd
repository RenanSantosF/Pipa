class_name KiteHand
extends RefCounted
## A mão do pipeiro: transforma comandos em entradas FÍSICAS da KiteRig (posição
## da mão, pegada, carretel). Nada aqui posiciona ou gira a pipa: quem decide o
## movimento é a aerodinâmica + a linha + a rabiola (docs/DESBICO_PUXAO.md).
## Usada pelo jogador e pelos vizinhos (bots).
##
## DESBICO — segurar = DAR LINHA, soltar = RETOMAR:
##   o braço vai para a frente e a mão abre: a linha corre e a tensão some. Sem
##   tensão o cabresto não segura mais o ângulo da vela: a pipa perde sustentação,
##   começa a cair, a rabiola fica para trás (acima) e o NARIZ DESCE — ela mergulha
##   na diagonal para onde o bico aponta. O lado vem do jeito de soltar: no começo
##   a mão puxa de leve para o lado (uma perna do cabresto carrega) e a pipa gira
##   o bico para lá; depois segue por inércia.
##   Soltar o dedo: a mão fecha e o braço volta devagar → a linha estica de novo,
##   o cabresto retoma o ângulo e a pipa sai do mergulho e se estabiliza aos poucos.
##   Toque curto = desbicada curta (folga mínima DESB_MIN), também perto do chão.
##   JOGAR (duplo toque, throw): desbico até o bico apontar para o lado (~0,4 s) e,
##   ao retomar, dois puxões emendados — a pipa dispara para onde o bico aponta.
##
## PUXÃO — arranque do braço (0,5 m em ~0,1 s) com a mão fechada: pico de tensão,
##   a pipa acelera para onde o NARIZ aponta (é a sustentação que cresce com o
##   vento aparente); a outra mão segura a linha enquanto o braço volta (keep_line),
##   então a tensão cai sozinha conforme a pipa desacelera. Toques seguidos =
##   puxões seguidos (mão sobre mão); dedo segurado para baixo = puxada contínua
##   (braçadas em série, ritmo pelo quanto o dedo desceu: recolhe linha, ela sobe).

const DOUBLE_WINDOW := 0.3
## Folga mínima de um toque curto (s).
const DESB_MIN := 0.3
## Braço estendido no desbico (m, negativo = para a frente).
const DESB_ARM := -0.35
const DESB_ARM_TIME := 0.16
## Mão entreaberta no desbico: a linha corre quando a tensão passa de ~grip²·40 N.
## Retomada: a mão fecha e o braço volta.
const RECOVER_GRIP_TIME := 0.18
const RECOVER_ARM_TIME := 0.45
## Puxão: curso, tempo de arranque, segurada e volta do braço.
const PULL_MAX := 0.9
const PULL_HOLD := 0.04
const PULL_RETURN := 0.42
const PULL_REPEAT := 0.3
## Puxada contínua: intervalo entre braçadas (s) do ritmo lento ao rápido.
const PULL_REPEAT_SLOW := 0.42
const PULL_REPEAT_FAST := 0.2
## Jogar para o lado (duplo toque): tempo de desbico antes do puxão (s).
const THROW_DESB := 0.38
## Abaixo desta linha (m) é lançamento: o tranco deixa a linha correr.
const LAUNCH_LEN := 18.0
## …ou com a pipa ainda baixa (m acima da mão), onde o vento é fraco.
const LAUNCH_ALT := 14.0
## Puxão de recolher: abaixo desta linha (m) ainda é o tranco de soltar da mão.
const RECOLHER_LAUNCH_LEN := 8.0
## Desbico por toques: giro de um balanço (rad/s) e quanto tempo ele dura (decaimento),
## quanto tempo sem toque reinicia a sequência, quanto tempo o rumo fica mantido.
## Por tamanho [P, M, G]: pipinha rápida e curta; pipão lento e forte.
const SWING_RATE_BY_SIZE := [3.4, 2.4, 1.75]
const SWING_TAU_BY_SIZE := [0.2, 0.35, 0.58]
## Inclinação (rad) de cada balanço e o tempo de resposta dela, por tamanho.
const BANK_BY_SIZE := [0.48, 0.58, 0.68]
const BANK_TAU_BY_SIZE := [0.05, 0.08, 0.13]
const TAP_SEQ_RESET := 0.45
const TAP_HOLD_TIME := 1.6
## Pulso de tração de cada desbico (braço curto, linha não é recolhida).
const THRUST_LEN := 0.15
## Empurrão de cada batida na direção do bico (m/s).
const DESB_IMPULSE := 4.0
const DESB_PUSH_TIME := 0.2
## Coeficiente de empuxo da batida (× pressão dinâmica × área da vela).
const DESB_THRUST := 0.35
const THRUST_UP := 0.06
const THRUST_DOWN := 0.22

## Força do desbico pedida pelo gesto (0,25..1): quanto mais longe o dedo, mais a
## mão abre e mais a vareta relaxa torta (o bico gira mais rápido).
var desbico_intensity: float = 1.0
## Ajustes do desbico (pegada entreaberta, impulso lateral).
var desb_grip: float = 0.27
## Puxão: curso do braço (m) e tempo do arranque (s).
var pull_len: float = 0.6
var pull_time: float = 0.09
## Preparação do tranco: o braço cede um pouco antes de puxar (m, s). No ar o
## puxão é seco (sem preparação); soltando da mão (linha curta) o pipeiro cede
## antes de cada tranco para a pipa recuar e pegar vento.
var windup: float = 0.0
var windup_time: float = 0.07
var launch_windup: float = 0.22
var launch_pull: float = 0.42
var kick_gain: float = 0.0
var kick_hold: float = 0.22
var kick_end: float = 0.5
var asym_gain: float = 0.0
var spin_gain: float = 0.95
## Ritmo da puxada contínua (0..1), escrito pelo gesto.
var pull_rate: float = 0.0
## GUIAR: direção pedida pelo dedo (mundo) e força 0..1 (zero = sem guiar).
var _guide_dir := Vector3.ZERO
var _guide_amount := 0.0
var _guide_slack := 0.0
## Puxão de RECOLHER (gesto de arrastar para baixo): a linha puxada fica na mão.
var _recolher := false
## DESBICO POR TOQUES (estilo pipa de combate): cada toque = um balanço, lados
## alternados (1º esquerda, 2º direita, …) e as asas batem. Ritmo constante = os
## balanços se anulam e ela segue reta para onde aponta (subindo devagar, sem
## chegar mais perto). Pausa depois de um toque = o último balanço "rende" e ela
## vira para aquele lado. O rumo é mantido enquanto você desbica.
var _tap_side := 1.0          # lado do último balanço (+1 dir, −1 esq)
var _tap_rate := 0.0          # giro do balanço atual (rad/s), decai
var _tap_clock := -10.0       # quando foi o último toque
var _hold_heading := 0.0      # rumo mantido (rad, 0 = bico para cima, + = direita)
var _hold_active := false
var _flap_t := 10.0
var _push_t := 10.0
var _thrust_t := 10.0
## Puxe: rumo mantido durante a puxada (vai reta para onde aponta).
var _pull_heading := 0.0
var _pull_hold := false

var rig: KiteRig
var stroke: float = 0.0
## Vizinhos: no puxão com a pipa alta a mão deixa escorregar um pouco (ganha linha).
var auto_feed: bool = false
## Lado do último desbico (−1 esquerda, +1 direita, vista de quem empina).
var last_side: float = 1.0
## Força dos comandos (vizinhos variam; o jogador usa 1).
var strength: float = 1.0

# Desbico.
var _desb_down: bool = false       # dedo encostado
var _desb_active: bool = false     # dando linha (inclui o mínimo de um toque)
var _desb_t: float = 0.0
var _desb_side: float = 0.0
var _desb_arm_from: float = 0.0
var _recover_t: float = -1.0
var _recover_arm_from: float = 0.0
var _last_press: float = -10.0
var _queued_side: float = 0.0
var _throw_pull: bool = false
var _desb_min: float = DESB_MIN
# Puxão.
var _pulling: bool = false
# Tranco de soltar da mão (linha curta): folga, tranco puxado de lado (lados
# alternados = zigue-zague, a pipa cruza o vento e ganha velocidade), devolve.
var _launch: bool = false
var _launch_side: float = -1.0
var _wu: float = 0.0
var _launch_from: float = 0.0
var _pull_t: float = 0.0
var _pull_from: float = 0.0
var _pull_to: float = 0.0
var _pull_held: bool = false
var _pull_repeat_t: float = 0.0
var _pull_pending: int = 0
var _clock: float = 0.0
var _kick := 0.0       # impulso lateral atual (−1..1)
var _spin := 0.0       # viés da vareta relaxada (−1..1)
var _pitch := 0.0      # ponto de tração deslocado (+ nariz / − cauda)


func _init(p_rig: KiteRig) -> void:
	rig = p_rig


func is_desbicando() -> bool:
	return _desb_active


func is_pulling() -> bool:
	return _pulling


# --- Comandos ----------------------------------------------------------------

## Dedo encostou: começa a dar linha para o lado (±1). Segundo toque rápido = dupla.
func press_desbico(side: float) -> void:
	if rig == null or rig.body == null:
		return
	if rig.held:
		rig.release_hold()
	var s := signf(side) if side != 0.0 else -last_side
	_last_press = _clock
	_start_desbico(s)
	_desb_down = true


## Dedo soltou: retoma a linha (respeitando a folga mínima de um toque).
func release_desbico() -> void:
	_desb_down = false


## Toque completo (vizinhos): folga mínima e retomada.
func tap_desbico(side: float) -> void:
	press_desbico(side)
	_desb_down = false


## JOGAR para o lado (duplo toque): desbico forte para `side` até o bico apontar
## para lá e, ao retomar, um puxão — a pipa dispara para onde o bico aponta.
## Se já está desbicando para esse lado (1º toque), só estica e emenda o puxão.
func throw(side: float) -> void:
	if rig == null or rig.body == null:
		return
	if rig.held:
		rig.release_hold()
	var s := signf(side) if side != 0.0 else last_side
	if not (_desb_active and _desb_side == s):
		_start_desbico(s)
	_desb_down = false
	_desb_min = maxf(_desb_t + 0.05, THROW_DESB)
	desbico_intensity = 1.0
	_throw_pull = true


## Dupla de uma vez (teclado): começa pelo lado contrário ao último.
func double_desbico() -> void:
	var first := -last_side
	_start_desbico(first)
	_desb_down = false
	_queued_side = -first


## Compatibilidade: toque/clique de desbico (lado ±1).
func tap(side: float) -> void:
	tap_desbico(side)


func desbico(side: float) -> void:
	tap_desbico(side)


## Virou arrasto logo no começo: para de dar linha já.
func cancel() -> void:
	if _desb_active:
		_desb_down = false
		_desb_t = DESB_MIN


## Um puxão (toques seguidos acumulam: mão sobre mão).
func puxao() -> void:
	if rig == null or rig.body == null:
		return
	_recolher = false
	if rig.held:
		rig.release_hold()
	if _pulling and _pull_t < (windup_time if _wu > 0.0 else 0.0) + pull_time:
		_pull_pending = mini(_pull_pending + 1, 2)   # pediu no meio do arranque: emenda
		return
	_start_pull()


## DESBICO de um toque (sem lado: os balanços alternam sozinhos).
func desbico_toque() -> void:
	if rig == null or rig.body == null:
		return
	if rig.held:
		rig.release_hold()
	if _clock - _tap_clock > TAP_SEQ_RESET:
		_tap_side = 1.0               # sequência nova: o 1º balanço é para a esquerda
	_tap_side = -_tap_side
	_tap_rate = _tap_side * float(SWING_RATE_BY_SIZE[_size()])
	_tap_clock = _clock
	if not _hold_active:
		_hold_heading = heading()
		_hold_active = true
	_flap_t = 0.0
	_thrust_t = 0.0
	# A batida (folga + tranco curto) empurra a pipa um pouco para onde o bico aponta:
	# no ritmo ela avança devagar nessa direção (sobe, vai de lado ou desce).
	_push_t = 0.0


func _size() -> int:
	return clampi(rig.profile.size_class, 0, 2) if rig != null and rig.profile != null else 1


## Rumo do bico na janela de vento (rad): 0 = para cima, +π/2 = direita do pipeiro.
func heading() -> float:
	if rig == null or rig.body == null:
		return 0.0
	var b := rig.body
	var fr := _window_frame()
	var nose: Vector3 = b.q * Vector3.UP
	return atan2(nose.dot(fr[1]), nose.dot(fr[0]))


## [cima, direita] da janela de vento em volta da pipa.
func _window_frame() -> Array:
	var ld: Vector3 = rig.body.line_dir
	var up_t := Vector3.UP - ld * ld.y
	up_t = up_t.normalized() if up_t.length() > 0.05 else Vector3.FORWARD
	var right_t := ld.cross(up_t).normalized()
	return [up_t, right_t]


func _heading_dir(h: float) -> Vector3:
	var fr := _window_frame()
	return (fr[0] as Vector3) * cos(h) + (fr[1] as Vector3) * sin(h)


## GUIAR (desbico por toque): o bico vai para `world_dir` (força 0..1). Passar
## Vector3.ZERO (ou força 0) solta: a pipa segue por inércia e a rabiola endireita.
func guide(world_dir: Vector3, amount: float) -> void:
	if rig == null or rig.body == null:
		return
	if amount > 0.0 and world_dir != Vector3.ZERO and rig.held:
		rig.release_hold()
	_guide_dir = world_dir
	_guide_amount = clampf(amount, 0.0, 1.0) if world_dir != Vector3.ZERO else 0.0
	if _guide_amount > 0.0 and _desb_active:
		_desb_active = false   # guiar substitui o desbico de toque antigo


func is_guiding() -> bool:
	return _guide_amount > 0.0


## PUXÃO de recolher (arrastar de cima para baixo): braçada com a mão fechada e a
## linha puxada FICA (vai para o chão aos pés): a pipa sobe e chega mais perto.
## `amount` 0..1 = tamanho do arrasto (braçada de 0,4 a 0,9 m).
func recolher(amount: float) -> void:
	if rig == null or rig.body == null:
		return
	var keep := pull_len
	pull_len = lerpf(0.4, 0.9, clampf(amount, 0.0, 1.0))
	puxao()
	pull_len = keep
	if not _pull_hold:
		_pull_heading = heading()
		_pull_hold = true
	# Só o tranco de soltar da mão (em zigue-zague) com a linha bem curta; no ar o
	# puxão é reto: recolhe sem jogar a pipa para os lados.
	if _launch and rig.flying_length() > RECOLHER_LAUNCH_LEN:
		_launch = false
	_recolher = not _launch


## Botão de puxar segurado: puxões em série enquanto segura.
func set_pull_held(held: bool) -> void:
	if held and not _pull_held:
		_pull_repeat_t = 0.0
	_pull_held = held


func _start_desbico(side: float) -> void:
	_desb_side = side
	last_side = side
	_desb_active = true
	_desb_t = 0.0
	_desb_min = DESB_MIN
	_throw_pull = false
	_desb_arm_from = stroke
	_recover_t = -1.0
	_pulling = false          # dar linha cancela o puxão (a mão abriu)
	_pull_pending = 0


func _start_pull() -> void:
	# Puxar fecha a mão: encerra qualquer desbico na hora.
	if _desb_active:
		_desb_active = false
		_desb_down = false
	_recover_t = -1.0   # o braço agora é o do puxão (a mão fecha na hora)
	_pull_from = stroke
	_pull_to = stroke + pull_len * strength
	if _pull_to > PULL_MAX:
		# Braço no fim do curso: a outra mão pega a linha mais à frente (mão sobre
		# mão) — o trecho já puxado fica, e o braço recomeça mais à frente.
		var regrip := _pull_to - PULL_MAX
		rig.regrip(regrip)
		_pull_from -= regrip
		stroke -= regrip
		_pull_to = PULL_MAX
	_pull_t = 0.0
	_pulling = true
	_wu = windup
	_launch = rig.flying_length() < LAUNCH_LEN or (rig.body.x.y - rig.hand_position().y) < LAUNCH_ALT
	if _launch:
		_launch_side = -_launch_side


# --- Atualização (a cada tick físico) ----------------------------------------

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / maxf(b - a, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _launch_kick_decay() -> bool:
	return _launch and absf(_kick) > 0.01


## Perto do chão / da mão os comandos laterais saem mais retos (técnica).
func _low_factor() -> float:
	if rig == null or rig.body == null:
		return 1.0
	var alt := rig.body.x.y - rig.hand_position().y
	return clampf(0.7 + (alt - 1.5) / 20.0, 0.7, 1.0)


## Tranco de soltar da mão: bem perto do chão o puxão sai quase reto.
func _launch_low_factor() -> float:
	if rig == null or rig.body == null:
		return 1.0
	var alt := rig.body.x.y - rig.hand_position().y
	return clampf((alt - 1.5) / 8.0, 0.2, 1.0)


## Ângulo da linha acima do horizonte (rad), da mão até a pipa.
func line_elevation() -> float:
	if rig == null or rig.body == null:
		return 0.0
	var d := rig.body.x - rig.hand_position()
	return asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0))


## pull_stroke: braçada pedida pelo arrasto (m) · grip_in: pegada pedida · reel: enrolar.
func update(delta: float, pull_stroke: float, grip_in: float, reel: float) -> void:
	_clock += delta
	if rig == null:
		return
	var grip := grip_in
	var kick_target := 0.0
	var spin_target := 0.0
	var pitch_target := 0.0
	var keep_line := true   # o braço voltando deixa a linha com a outra mão
	var launch_asym := false

	# Puxada contínua (segurando para baixo): braçadas em série, mão sobre mão; o
	# ritmo vem de quanto o dedo desceu. Braçadas mais rápidas que a volta do braço
	# acumulam curso → a outra mão pega a linha mais à frente (recolhe linha).
	if _pull_held:
		_pull_repeat_t += delta
		if _pull_repeat_t >= lerpf(PULL_REPEAT_SLOW, PULL_REPEAT_FAST, clampf(pull_rate, 0.0, 1.0)):
			_pull_repeat_t = 0.0
			recolher(0.75)

	if _desb_active:
		_desb_t += delta
		# Braço vai à frente e a mão abre: a linha corre e a tensão some.
		stroke = lerpf(_desb_arm_from, DESB_ARM, _smooth(0.0, DESB_ARM_TIME, _desb_t))
		var open_grip := lerpf(desb_grip + 0.1, desb_grip - 0.05, desbico_intensity)
		grip = minf(grip, lerpf(1.0, open_grip, _smooth(0.0, 0.06, _desb_t)))
		# Puxada leve para o lado só no começo (ainda há tensão para girar o bico).
		kick_target = _desb_side * kick_gain * _smooth(0.0, 0.08, _desb_t) * (1.0 - _smooth(kick_hold, kick_end, _desb_t))
		# Enquanto dá linha, a vareta relaxa torta para o lado escolhido. Com a pipa
		# baixa o pipeiro solta reto (sem torcer), senão ela vira e vai ao chão.
		spin_target = _desb_side * spin_gain * lerpf(0.55, 1.15, desbico_intensity) * _low_factor()
		pitch_target = 1.0   # ponto de tração para o nariz: a vela "deita", sustentação cai
		keep_line = false
		if not _desb_down and _desb_t >= _desb_min:
			_desb_active = false
			_recover_t = 0.0
			_recover_arm_from = stroke
			if _throw_pull:
				# Jogar: retoma com um puxão seco (não o tranco de soltar da mão).
				_throw_pull = false
				_start_pull()
				_launch = false
				_pull_to = minf(_pull_from + 0.75 * strength, PULL_MAX)
				_pull_pending = 1   # emenda um segundo puxão (mão sobre mão): ela dispara
			elif _queued_side != 0.0:
				var q := _queued_side
				_queued_side = 0.0
				_start_desbico(q)
	elif _recover_t >= 0.0 and not _pulling:
		# Retomada: a mão fecha e o braço volta devagar → a linha estica aos poucos.
		_recover_t += delta
		grip = minf(grip, lerpf(desb_grip, 1.0, _smooth(0.0, RECOVER_GRIP_TIME, _recover_t)))
		stroke = lerpf(_recover_arm_from, 0.0, _smooth(0.0, RECOVER_ARM_TIME, _recover_t))
		keep_line = false
		if _recover_t >= RECOVER_ARM_TIME:
			_recover_t = -1.0

	if _pulling and _launch:
		_pull_t += delta
		var lt := _pull_t
		if lt < 0.07:
			stroke = lerpf(_pull_from, -0.22, _smooth(0.0, 0.07, lt))
			_launch_from = stroke
			pitch_target = 1.0
		elif lt < 0.2:
			stroke = lerpf(_launch_from, launch_pull * strength, _smooth(0.07, 0.18, lt))
			pitch_target = -0.6
			if line_elevation() > 0.5:
				grip = minf(grip, 0.35)
		elif lt < 0.36:
			stroke = lerpf(launch_pull * strength, -0.14, _smooth(0.2, 0.36, lt))
			pitch_target = -0.6 * (1.0 - _smooth(0.2, 0.32, lt))
		elif lt < 0.55:
			stroke = lerpf(-0.14, 0.0, _smooth(0.36, 0.55, lt))
		else:
			_pulling = false
			stroke = 0.0
		keep_line = false
		kick_target = _launch_side * _smooth(0.0, 0.05, lt) * (1.0 - _smooth(0.2, 0.4, lt)) * _launch_low_factor()
		launch_asym = true
	elif _pulling:
		_pull_t += delta
		# Mão fechada; se o jogador já está dando linha, a puxada sai "correndo linha"
		# (a linha escorrega na mão quando a pipa puxa forte → ela sobe ganhando linha).
		grip = 1.0 if grip_in > 0.9 else maxf(grip_in, 0.3)
		var t0 := windup_time if _wu > 0.0 else 0.0
		var t1 := t0 + pull_time
		var t2 := t1 + PULL_HOLD
		var t3 := t2 + PULL_RETURN
		if _pull_t < t0:
			# Preparação: o braço cede um pouco (a linha afrouxa um instante).
			stroke = lerpf(_pull_from, _pull_from - _wu, _smooth(0.0, t0, _pull_t))
			keep_line = false
		elif _pull_t < t1:
			# Arranque: o braço puxa a linha (ease-in-out, pico ~10 m/s).
			stroke = lerpf(_pull_from - _wu, _pull_to, _smooth(t0, t1, _pull_t))
			pitch_target = -0.35 if _recolher else -1.0   # a tração vem de baixo: a vela "morde" o vento
			keep_line = false
			var el := line_elevation()
			if (auto_feed or rig.flying_length() < LAUNCH_LEN) and el > 0.5:
				# Soltando da mão (linha curta) ou vizinho com a pipa alta: a linha
				# escorrega no tranco e a pipa sobe levando linha.
				grip = minf(grip, 0.35)
		elif _pull_pending > 0:
			_pull_pending -= 1
			_start_pull()
		elif _pull_t < t2:
			stroke = _pull_to
			pitch_target = -0.2 if _recolher else -0.5
		elif _pull_t < t3:
			# O braço devolve devagar (tranco): a linha volta para a pipa e a tensão cai
			# aos poucos. Nada é recolhido (recolher é mão sobre mão / enrolar).
			stroke = lerpf(_pull_to, 0.0, _smooth(t2, t3, _pull_t))
			# Recolher: a outra mão segura e o braço volta sem devolver a linha.
			keep_line = _recolher
		else:
			_pulling = false
			stroke = 0.0
	elif not _desb_active and _recover_t < 0.0:
		stroke = move_toward(stroke, pull_stroke, 6.0 * delta)
		if pull_stroke > 0.05 and rig.held:
			rig.release_hold()

	# GUIAR: o bico vai para o dedo. Mão de pipeiro de combate: desalinhada, ela
	# afrouxa um pouco (a pipa fica instável e vira); alinhada, estica (estável:
	# voa reto pelo bico e acelera). Puxando sem guiar, a linha esticada mantém o
	# bico para cima: ela sobe, sem girar.
	var steer_target := Vector3.ZERO
	var steer_gain := 0.0
	var steer_ff := 0.0
	var slack_target := 0.0
	if rig.body != null and _hold_active:
		# Desbico por toques: o rumo mantido anda com o balanço atual (que decai).
		_hold_heading = wrapf(_hold_heading + _tap_rate * delta, -PI, PI)
		_tap_rate *= exp(-delta / float(SWING_TAU_BY_SIZE[_size()]))
		steer_target = _heading_dir(_hold_heading)
		steer_gain = 1.0
		steer_ff = _tap_rate
		if _clock - _tap_clock > TAP_HOLD_TIME:
			_hold_active = false
	elif _guide_amount > 0.0 and rig.body != null:
		steer_target = _guide_dir
		steer_gain = lerpf(0.45, 1.0, _guide_amount)
		var err := absf(rig.body.steer_error)
		slack_target = clampf((err - 0.3) / 1.0, 0.0, 1.0) * (0.0 if _pulling else 1.0)
	elif _pulling and _recolher and _pull_hold and rig.body != null:
		# Puxe: vai reta para onde aponta (o rumo do começo da puxada é mantido).
		steer_target = _heading_dir(_pull_heading)
		steer_gain = 0.6
	if not _pulling:
		_pull_hold = false
	# Pulso de tração do desbico: braço curto e rápido, a linha volta (não recolhe):
	# a pipa avança para onde aponta, devagar, sem chegar mais perto.
	if _thrust_t < THRUST_UP + THRUST_DOWN and not _pulling and not _desb_active:
		_thrust_t += delta
		var a := _smooth(0.0, THRUST_UP, _thrust_t) * (1.0 - _smooth(THRUST_UP, THRUST_UP + THRUST_DOWN, _thrust_t))
		stroke = THRUST_LEN * strength * a
		keep_line = false
		grip = maxf(grip, 1.0)
	# Empurrão da batida, espalhado em DESB_PUSH_TIME (sem salto de velocidade),
	# sempre na direção ATUAL do bico no plano da janela.
	var push := Vector3.ZERO
	if _push_t < DESB_PUSH_TIME and rig.body != null:
		_push_t += delta
		var ldp: Vector3 = rig.body.line_dir
		var nose: Vector3 = rig.body.q * Vector3.UP
		var nt := nose - ldp * nose.dot(ldp)
		if nt.length() > 0.1:
			var shape := sin(PI * clampf(_push_t / DESB_PUSH_TIME, 0.0, 1.0))
			push = nt.normalized() * (DESB_THRUST * shape * strength)
	rig.push_accel = push
	# Asas batendo (visual): fecham rápido e abrem.
	_flap_t += delta
	rig.flap = sin(PI * clampf(_flap_t / 0.2, 0.0, 1.0)) if _flap_t < 0.2 else 0.0
	rig.steer_ff = steer_ff
	# Inclinação: cada balanço deita a pipa para o lado dele (de um lado para o
	# outro no ritmo), proporcional ao giro do balanço; volta reta quando para.
	var sz := _size()
	var bank_target := 0.0
	if _hold_active:
		bank_target = clampf(_tap_rate / float(SWING_RATE_BY_SIZE[sz]), -1.0, 1.0) * float(BANK_BY_SIZE[sz])
	rig.bank = lerpf(rig.bank, bank_target, 1.0 - exp(-delta / float(BANK_TAU_BY_SIZE[sz])))
	rig.steer_dir = steer_target
	rig.steer_gain = steer_gain

	# Atuadores suaves (nada muda de uma vez: constante de tempo ~60–80 ms).
	if launch_asym:
		_kick = move_toward(_kick, kick_target * strength, delta * 22.0)
	else:
		_kick = lerpf(_kick, kick_target * strength, 1.0 - exp(-delta / 0.06))
	_spin = lerpf(_spin, spin_target * strength, 1.0 - exp(-delta / (0.07 if spin_target != 0.0 else 0.2)))
	_pitch = pitch_target if launch_asym else lerpf(_pitch, pitch_target, 1.0 - exp(-delta / 0.08))
	var p := rig.profile
	if p != null and rig.body != null:
		rig.bridle_offset = Vector2(_kick * p.bridle_shift * p.width, _pitch * (0.05 if launch_asym else 0.04) * p.height)
		rig.sail_asym = -_kick * p.flex_asym * (1.0 if launch_asym or _launch_kick_decay() else asym_gain)
	rig.spin_bias = _spin
	rig.shorten_on_return = keep_line
	rig.stroke = stroke
	rig.grip = grip
	rig.reel_rate = reel
