class_name KiteHand
extends RefCounted
## A mão do pipeiro: transforma comandos (desbico, puxar, dar linha, enrolar) nas
## entradas físicas da KiteRig. Usada pelo jogador e pelos vizinhos (bots).
##
## DESBICO (estilo "Pipa Combate", com física real por baixo):
##   apertar  → a mão avança (folga) e o bico VIRA PARA O OUTRO LADO;
##   soltar   → tranco: a pipa sai para onde o bico aponta.
##   Toques seguidos (< 0,5 s) continuam para o MESMO lado (vai mais longe).
##   Toque mais longo vira mais (40° → 100°).
## PUXAR (braçada) e DAR LINHA vêm do arrasto do dedo.

const CHAIN_TIME := 0.5
const MIN_TURN := 40.0
const MAX_TURN := 100.0

var rig: KiteRig
var stroke: float = 0.0
## No desbico a mão deixa a linha escorregar quando a pipa puxa (ajuda a levantar).
var auto_feed: bool = true
## Lado do último desbico (−1 esquerda, +1 direita, vista de quem empina).
var side: float = 1.0

var _phase: int = 0       # 0 livre · 1 virando (dedo apertado) · 2 tranco
var _t: float = 0.0
var _hold: float = 0.0
var _clock: float = 0.0
var _last_desbico: float = -10.0
var _tug_from: float = 0.0


func _init(p_rig: KiteRig) -> void:
	rig = p_rig


func is_desbicando() -> bool:
	return _phase != 0


## Dedo encostou: começa o desbico. forced_side ≠ 0 escolhe o lado (vizinhos).
func press(forced_side: float = 0.0) -> void:
	if rig == null or rig.body == null:
		return
	if rig.held:
		rig.release_hold()
	if forced_side != 0.0:
		side = signf(forced_side)
	elif _clock - _last_desbico > CHAIN_TIME:
		var h := rig.heading()
		side = -signf(h) if absf(h) > deg_to_rad(10.0) else -side
	_phase = 1
	_t = 0.0
	_hold = 0.0


## Dedo soltou: tranco.
func release() -> void:
	if _phase == 1:
		_phase = 2
		_t = 0.0
		_tug_from = stroke
		_last_desbico = _clock


## Virou arrasto (puxar/dar linha): cancela o desbico.
func cancel() -> void:
	if _phase == 1:
		_phase = 0


func _turn() -> float:
	# Perto do chão o desbico é quase reto (serve para levantar); abre com a altura.
	var alt := 10.0
	if rig.body:
		alt = rig.body.x.y - Ground.height_at(rig.body.x.x, rig.body.x.z)
	var open := clampf((alt - 3.0) / 9.0, 0.2, 1.0)
	return side * deg_to_rad(lerpf(MIN_TURN, MAX_TURN, clampf(_hold / 0.6, 0.0, 1.0)) * open)


## pull_stroke: braçada pedida (m) · grip_in: pegada pedida · reel: enrolar (m/s).
func update(delta: float, pull_stroke: float, grip_in: float, reel: float) -> void:
	_clock += delta
	if rig == null:
		return
	var grip := grip_in
	rig.steer_active = false
	match _phase:
		1:
			_hold += delta
			_t += delta
			stroke = move_toward(stroke, -0.22, 3.0 * delta)
			rig.steer_active = true
			rig.steer_target = _turn()
			if _hold > 0.3 and auto_feed:
				grip = minf(grip, 0.3)  # segurou: descarrega um pouco de linha
		2:
			_t += delta
			rig.steer_active = _t < 0.3
			rig.steer_target = _turn()
			if _t < 0.1:
				stroke = lerpf(_tug_from, 0.5, _t / 0.1)
				if auto_feed:
					grip = minf(grip, 0.35)  # pipa puxando forte: a linha escorrega → ela sobe
			elif _t < 0.4:
				stroke = lerpf(0.5, 0.0, (_t - 0.1) / 0.3)
			else:
				_phase = 0
				stroke = 0.0
		_:
			stroke = move_toward(stroke, pull_stroke, 6.0 * delta)
			if pull_stroke > 0.05 and rig.held:
				rig.release_hold()
	rig.shorten_on_return = _phase == 0
	rig.stroke = stroke
	rig.grip = grip
	rig.reel_rate = reel
