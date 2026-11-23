class_name KiteHand
extends RefCounted
## A mão do pipeiro: transforma comandos (desbico, puxar, dar linha, enrolar) nas
## entradas FÍSICAS da KiteRig. Usada pelo jogador e pelos vizinhos (bots).
##
## DESBICO (docs/REVISAO_V5.md §1) — nada gira a pipa diretamente. Cada desbico é
## uma sequência curta do que a mão faz de verdade:
##   folga   (0–0,07 s) mão avança → tensão cai, o bico "cai" (α diminui);
##   lado    (0–0,25 s) puxão lateral carrega uma perna do cabresto (ponto de
##           tração desloca) e flexiona a vareta daquele lado (centro de
##           sustentação desloca) → a tensão da linha gira o bico para o lado;
##   tranco  (0,07–0,20 s) mão puxa rápido → pico de tensão, α sobe: a pipa
##           dispara para onde o bico aponta;
##   retorno (0,20–0,55 s) tudo volta ao neutro → diedro + rabiola trazem o bico
##           de volta: a pipa oscila e retoma a trajetória (não muda de rumo).
##
## tap(lado): toque/clique. Dois toques em até DOUBLE_WINDOW = desbicada dupla: o
## primeiro sai na hora para o lado dele, o segundo encadeia o lado oposto.

const DOUBLE_WINDOW := 0.25
const SLACK_END := 0.07
const TUG_END := 0.20
const RETURN_END := 0.55
const SLACK_STROKE := -0.22
const TUG_STROKE := 0.42
const GIVE_AT := 0.36
const GIVE_STROKE := -0.14
## Encadeamento da dupla: o 2º desbico começa logo depois do tranco do 1º.
const CHAIN_AT := 0.3
const LAT_HOLD := 0.2
const LAT_END := 0.4

var rig: KiteRig
var stroke: float = 0.0
## No desbico a mão deixa a linha escorregar quando a pipa puxa (ajuda a levantar).
var auto_feed: bool = true
## Lado do último desbico (−1 esquerda, +1 direita, vista de quem empina).
var last_side: float = 1.0
## Força do desbico (0..1,3): vizinhos variam; o jogador usa 1.
var strength: float = 1.0

var _active: bool = false
var _t: float = 0.0
var _side: float = 0.0
var _queue: Array[float] = []
var _clock: float = 0.0
var _last_tap: float = -10.0
var _tug_from: float = 0.0
var _slack_from: float = 0.0
var _env := 0.0      # envelope lateral atual (0..1)


func _init(p_rig: KiteRig) -> void:
	rig = p_rig


func is_desbicando() -> bool:
	return _active


## Toque / clique para um lado (±1). Detecta a desbicada dupla.
func tap(side: float) -> void:
	if rig == null or rig.body == null:
		return
	var s := signf(side) if side != 0.0 else -last_side
	if _active and _clock - _last_tap < DOUBLE_WINDOW and _queue.is_empty():
		_queue.append(-_side)      # dupla: encadeia o lado oposto
	else:
		desbico(s)
	_last_tap = _clock


## Desbicada dupla pedida de uma vez (teclado): começa pelo lado contrário ao último.
func double_desbico() -> void:
	var first := -last_side
	desbico(first)
	_queue.clear()
	_queue.append(-first)


## Um desbico para o lado dado (±1), sem detecção de toque duplo (vizinhos).
func desbico(side: float) -> void:
	if rig == null or rig.body == null:
		return
	if rig.held:
		rig.release_hold()
	_side = signf(side) if side != 0.0 else 1.0
	last_side = _side
	_active = true
	_t = 0.0
	_slack_from = stroke
	_queue.clear()


## Virou arrasto (puxar/dar linha) logo no começo: aborta o desbico.
func cancel() -> void:
	if _active and _t < TUG_END:
		_active = false
		_queue.clear()


## Ângulo da linha acima do horizonte (rad), da mão até a pipa.
func line_elevation() -> float:
	if rig == null or rig.body == null:
		return 0.0
	var d := rig.body.x - rig.hand_position()
	return asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0))


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / maxf(b - a, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## pull_stroke: braçada pedida (m) · grip_in: pegada pedida · reel: enrolar (m/s).
func update(delta: float, pull_stroke: float, grip_in: float, reel: float) -> void:
	_clock += delta
	if rig == null:
		return
	var grip := grip_in
	var lat := 0.0     # envelope do lado (cabresto + vareta)
	var pitch := 0.0   # + = ponto de tração para o nariz (pipa deita, α cai)
	if _active:
		_t += delta
		if _t < SLACK_END:
			stroke = lerpf(_slack_from, SLACK_STROKE, _smooth(0.0, SLACK_END, _t))
			_tug_from = stroke
			pitch = 1.0
		elif _t < TUG_END:
			stroke = lerpf(_tug_from, TUG_STROKE * strength, _smooth(SLACK_END, TUG_END - 0.02, _t))
			pitch = -0.6
			if auto_feed and line_elevation() > 0.5:
				grip = minf(grip, 0.35)  # pipa alta puxando forte: a linha escorrega → ela sobe
		elif _t < RETURN_END:
			# A mão devolve a linha (pequena folga): a pipa perde tração e a rabiola
			# (pêndulo) traz o bico de volta mais rápido.
			if _t < GIVE_AT:
				stroke = lerpf(TUG_STROKE * strength, GIVE_STROKE, _smooth(TUG_END, GIVE_AT, _t))
			else:
				stroke = lerpf(GIVE_STROKE, 0.0, _smooth(GIVE_AT, RETURN_END, _t))
			pitch = -0.6 * (1.0 - _smooth(TUG_END, TUG_END + 0.12, _t))
		else:
			_active = false
			stroke = 0.0
		lat = _smooth(0.0, 0.05, _t) * (1.0 - _smooth(LAT_HOLD, LAT_END, _t))
		if _active and not _queue.is_empty() and _t >= CHAIN_AT:
			var nxt: float = _queue.pop_front()
			var rest := _queue.duplicate()
			desbico(nxt)
			_queue = rest
	else:
		stroke = move_toward(stroke, pull_stroke, 6.0 * delta)
		if pull_stroke > 0.05 and rig.held:
			rig.release_hold()
	# Envelope lateral contínuo (sem degrau quando um desbico encadeia o outro).
	# Perto do chão o pipeiro puxa reto (o desbico serve para subir); abre com a altura.
	var open := 1.0
	if rig.body != null:
		var alt := rig.body.x.y - rig.hand_position().y
		open = clampf((alt - 1.5) / 8.0, 0.2, 1.0)
	var target := lat * _side * strength * open
	_env = move_toward(_env, target, delta * 22.0)
	var p := rig.profile
	if p != null and rig.body != null:
		rig.bridle_offset = Vector2(_env * p.bridle_shift * p.width, pitch * 0.05 * p.height)
		rig.sail_asym = -_env * p.flex_asym  # o lado puxado firma; a vareta do outro lado fecha
	rig.shorten_on_return = not _active
	rig.stroke = stroke
	rig.grip = grip
	rig.reel_rate = reel
