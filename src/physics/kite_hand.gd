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
##   Toque curto = desbicada curta (folga mínima DESB_MIN). Dois toques = dupla
##   (o 2º vai para o lado oposto do 1º).
##
## PUXÃO — arranque do braço (0,5 m em ~0,1 s) com a mão fechada: pico de tensão,
##   a pipa acelera para onde o NARIZ aponta (é a sustentação que cresce com o
##   vento aparente); a outra mão segura a linha enquanto o braço volta (keep_line),
##   então a tensão cai sozinha conforme a pipa desacelera. Toques seguidos =
##   puxões seguidos (mão sobre mão); botão segurado = puxões em série.

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
## Abaixo desta linha (m) é lançamento: o tranco deixa a linha correr.
const LAUNCH_LEN := 18.0
## …ou com a pipa ainda baixa (m acima da mão), onde o vento é fraco.
const LAUNCH_ALT := 14.0

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
var spin_gain: float = 1.0

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
	if _clock - _last_press < DOUBLE_WINDOW:
		s = -_desb_side if _desb_side != 0.0 else s   # desbicada dupla: lado oposto
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
	if rig.held:
		rig.release_hold()
	if _pulling and _pull_t < (windup_time if _wu > 0.0 else 0.0) + pull_time:
		_pull_pending = mini(_pull_pending + 1, 2)   # pediu no meio do arranque: emenda
		return
	_start_pull()


## Botão de puxar segurado: puxões em série enquanto segura.
func set_pull_held(held: bool) -> void:
	if held and not _pull_held:
		puxao()
		_pull_repeat_t = 0.0
	_pull_held = held


func _start_desbico(side: float) -> void:
	_desb_side = side
	last_side = side
	_desb_active = true
	_desb_t = 0.0
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

	# Botão segurado: puxões em série.
	if _pull_held:
		_pull_repeat_t += delta
		if _pull_repeat_t >= PULL_REPEAT:
			_pull_repeat_t = 0.0
			puxao()

	if _desb_active:
		_desb_t += delta
		# Braço vai à frente e a mão abre: a linha corre e a tensão some.
		stroke = lerpf(_desb_arm_from, DESB_ARM, _smooth(0.0, DESB_ARM_TIME, _desb_t))
		grip = minf(grip, lerpf(1.0, desb_grip, _smooth(0.0, 0.06, _desb_t)))
		# Puxada leve para o lado só no começo (ainda há tensão para girar o bico).
		kick_target = _desb_side * kick_gain * _smooth(0.0, 0.08, _desb_t) * (1.0 - _smooth(kick_hold, kick_end, _desb_t))
		# Enquanto dá linha, a vareta relaxa torta para o lado escolhido. Com a pipa
		# baixa o pipeiro solta reto (sem torcer), senão ela vira e vai ao chão.
		spin_target = _desb_side * spin_gain * _low_factor()
		pitch_target = 1.0   # ponto de tração para o nariz: a vela "deita", sustentação cai
		keep_line = false
		if not _desb_down and _desb_t >= DESB_MIN:
			_desb_active = false
			_recover_t = 0.0
			_recover_arm_from = stroke
			if _queued_side != 0.0:
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
		kick_target = _launch_side * _smooth(0.0, 0.05, lt) * (1.0 - _smooth(0.2, 0.4, lt)) * _low_factor()
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
			pitch_target = -1.0   # a tração vem de baixo: a vela "morde" o vento
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
			pitch_target = -0.5
		elif _pull_t < t3:
			# O braço devolve devagar (tranco): a linha volta para a pipa e a tensão cai
			# aos poucos. Nada é recolhido (recolher é mão sobre mão / enrolar).
			stroke = lerpf(_pull_to, 0.0, _smooth(t2, t3, _pull_t))
			keep_line = false
		else:
			_pulling = false
			stroke = 0.0
	elif not _desb_active and _recover_t < 0.0:
		stroke = move_toward(stroke, pull_stroke, 6.0 * delta)
		if pull_stroke > 0.05 and rig.held:
			rig.release_hold()

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
