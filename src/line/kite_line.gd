class_name KiteLine
extends Node
## Linha da pipa: restrição física unilateral (só puxa, nunca empurra) + carretel.
##
## - Puxar: a mão faz uma "puxada" (stroke) que encurta a linha efetiva rapidamente;
##   isso aumenta o vento relativo na pipa, que ganha força e acelera para onde aponta.
## - Soltar: a linha corre da lata numa velocidade proporcional à tensão.
## - Recolher: enrola a linha (mais devagar quanto maior a tensão).
## - Tensão excessiva arrebenta a linha.
##
## KiteBody chama solve() em cada subpasso e finish_step() ao fim do tick.

@export var initial_length: float = 25.0
@export var min_length: float = 3.0
@export var max_length: float = 250.0
@export_group("Carretel")
@export var reel_speed: float = 2.8
@export var release_speed_min: float = 0.6
@export var release_speed_max: float = 9.0
## m/s de linha liberada por newton de tensão acima do limiar.
@export var release_gain: float = 0.9
@export var release_threshold: float = 0.8
@export_group("Puxada")
@export var pull_stroke: float = 0.9
@export var pull_speed: float = 4.0
@export var pull_return_speed: float = 1.4
@export_group("Material")
## Tensão (N) que arrebenta a linha.
@export var break_tension: float = 35.0
## kg por metro (linha de algodão/nylon fina ≈ 0,4 g/m).
@export var mass_per_meter: float = 0.0004
@export var diameter: float = 0.0006

## Ponto da mão onde a linha sai (definido por Main).
var hand: Node3D
## Fonte das intenções do jogador (definido por Main).
var input_router: InputRouter

# --- Estado público ---
var length: float = 25.0
var pull_offset: float = 0.0
## m/s: > 0 soltando, < 0 recolhendo.
var payout_speed: float = 0.0
## Tensão filtrada (N), para HUD/animação/arrebentar.
var tension: float = 0.0
## Tensão do último tick, sem filtro.
var raw_tension: float = 0.0
## 0 = frouxa, 1 = esticada.
var tautness: float = 0.0
var is_broken: bool = false
var anchor_position := Vector3.ZERO
var anchor_velocity := Vector3.ZERO

var _prev_anchor := Vector3.ZERO
var _has_prev: bool = false
var _pull_rate: float = 0.0
var _impulse: float = 0.0


func _ready() -> void:
	# Atualiza a âncora e o comprimento antes da pipa integrar (prioridade menor roda antes).
	process_physics_priority = -10
	length = initial_length


func reset(new_length: float = -1.0) -> void:
	length = initial_length if new_length < 0.0 else new_length
	pull_offset = 0.0
	payout_speed = 0.0
	tension = 0.0
	raw_tension = 0.0
	is_broken = false
	_has_prev = false
	_update_anchor(1.0 / 60.0)


func effective_length() -> float:
	return maxf(length - pull_offset, 0.5)


func _physics_process(delta: float) -> void:
	_update_anchor(delta)
	var pull := false
	var release := false
	var reel := false
	if input_router:
		pull = input_router.intent.pull
		release = input_router.intent.release
		reel = input_router.intent.reel

	# Puxada de mão.
	var prev_offset := pull_offset
	var target := pull_stroke if (pull and not is_broken) else 0.0
	var rate := pull_speed if target > pull_offset else pull_return_speed
	pull_offset = move_toward(pull_offset, target, rate * delta)
	_pull_rate = (pull_offset - prev_offset) / delta

	# Carretel.
	payout_speed = 0.0
	if not is_broken:
		if release and not reel:
			payout_speed = clampf(release_speed_min + maxf(tension - release_threshold, 0.0) * release_gain,
				0.0, release_speed_max)
		elif reel and not release:
			var hard := clampf(tension / break_tension, 0.0, 1.0)
			payout_speed = -reel_speed * (1.0 - 0.75 * hard)
		var new_length := clampf(length + payout_speed * delta, min_length, max_length)
		payout_speed = (new_length - length) / delta
		length = new_length
	_impulse = 0.0


func _update_anchor(delta: float) -> void:
	if hand == null:
		return
	var p := hand.global_position
	if _has_prev:
		anchor_velocity = ((p - _prev_anchor) / delta).limit_length(15.0)
	else:
		anchor_velocity = Vector3.ZERO
		_has_prev = true
	_prev_anchor = p
	anchor_position = p


## Restrição de distância unilateral aplicada à pipa (chamada por subpasso).
func solve(body: KiteBody, _dt: float) -> void:
	if is_broken or hand == null:
		tautness = 0.0
		return
	var eff := effective_length()
	var delta := body.position_ws - anchor_position
	var dist := delta.length()
	if dist < 0.001:
		return
	var dir := delta / dist
	tautness = clampf((dist / eff - 0.95) / 0.05, 0.0, 1.0)
	if dist > eff:
		body.position_ws = anchor_position + dir * eff
		# Velocidade radial máxima permitida = taxa de variação do comprimento efetivo.
		var allowed := payout_speed - _pull_rate
		var vr := (body.velocity - anchor_velocity).dot(dir) - allowed
		if vr > 0.0:
			body.velocity -= dir * vr
			_impulse += body.mass * vr


## Converte o impulso acumulado no tick em tensão e verifica se a linha arrebenta.
func finish_step(delta: float) -> void:
	if is_broken:
		raw_tension = 0.0
		tension = lerpf(tension, 0.0, 1.0 - exp(-10.0 * delta))
		return
	raw_tension = _impulse / delta
	tension = lerpf(tension, raw_tension, 1.0 - exp(-12.0 * delta))
	_impulse = 0.0
	if tension > break_tension:
		snap()


func snap() -> void:
	if is_broken:
		return
	is_broken = true
	tautness = 0.0
	EventBus.line_snapped.emit(anchor_position)
