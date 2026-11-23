class_name BotFlyer
extends Node3D
## Vizinho controlado pelo computador. Usa a MESMA mão do jogador (KiteHand):
## desbico, puxar e dar linha — então só faz o que a física permite.
##
## Estados:
##   SUBIR  — sobe da mão desbicando e dando linha até o comprimento desejado;
##   CAÇAR  — leva a pipa até a linha do alvo: se o bico aponta para o lado certo,
##            toques seguidos (vai mais longe); se aponta para o lado errado, um
##            desbico para virar. Puxa/dá linha para ficar na altura do alvo;
##   RELAR  — cruzado: alterna dar linha e puxadas, conforme o estilo do vizinho.

enum State { WAIT, CLIMB, HUNT, ENGAGE }

@export var line_type: LineType
## 0..1: quanto ele vai para cima de você.
@export var aggression: float = 0.8
## 0..1: precisão no tempo dos toques.
@export var skill: float = 0.6

var rig: KiteRig
var target: KiteRig
var world: KitePhysicsWorld
var display_name: String = "Vizinho"

@onready var character: TeenCharacter = get_node_or_null("Character")

var _hand: KiteHand
var _state: int = State.WAIT
var _timer: float = 0.0
var _tap_timer: float = 0.0
var _target_length: float = 30.0
var _style_release: bool = true
var _best_alt: float = 0.0
var _stall_time: float = 0.0
var _recovering: bool = false
var _cross_side: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -50
	_rng.seed = randi()  # segue a semente global (testes reproduzíveis com --seed)
	_style_release = _rng.randf() < 0.5
	_timer = _rng.randf_range(0.5, 4.0)


func hand_rest() -> Vector3:
	return global_position + global_transform.basis * Vector3(0.2, 1.18, -0.36)


func launch() -> void:
	if rig == null:
		return
	rotation.y = atan2(-Wind.get_direction().x, -Wind.get_direction().z)
	rig.launch_in_hand(hand_rest(), Wind.get_direction())
	_hand = KiteHand.new(rig)
	_target_length = _rng.randf_range(25.0, 45.0)
	_state = State.CLIMB
	_best_alt = 0.0
	_stall_time = 0.0
	_recovering = false


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	if _hand == null or _hand.rig != rig:
		_hand = KiteHand.new(rig)
	_timer -= delta
	_tap_timer -= delta
	var pull := 0.0
	var grip := 1.0
	var reel := 0.0

	if not rig.is_flying():
		if rig.rope != null:
			reel = 3.0  # recolhe a sobra de linha
			if _state != State.WAIT:
				_state = State.WAIT
				_timer = 6.0
			elif _timer <= 0.0:
				rig.rope = null  # sobra enroscada: larga e relança
				rig.line_renderer.bind(null, rig.line_type)
				_timer = _rng.randf_range(1.0, 3.0)
		elif _state != State.WAIT:
			_state = State.WAIT
			_timer = _rng.randf_range(3.0, 7.0)
		elif _timer <= 0.0:
			launch()
	else:
		var to_kite := rig.body.x - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to_kite.x, -to_kite.z), 1.0 - exp(-2.0 * delta))
		# Altura acima da MÃO (o vizinho pode estar numa laje alta).
		var alt := rig.body.x.y - rig.hand_position().y
		var in_contact := world != null and world.strongest_contact_for(rig) != null
		# Não sobe / enroscou: recolhe tudo e relança.
		if alt > _best_alt + 0.5:
			_best_alt = alt
			_stall_time = 0.0
		elif _state == State.CLIMB or rig.snagged:
			_stall_time += delta
		if _stall_time > 7.0 or _recovering:
			_recovering = true
			reel = 4.0
			if rig.flying_length() < 3.0:
				rig.stow()  # pipa recolhida: guarda e relança
				_state = State.WAIT
				_timer = _rng.randf_range(1.0, 3.0)
				_recovering = false
			_hand.update(delta, 0.0, 1.0, reel)
			rig.hand_rest = hand_rest()
			return
		if in_contact:
			_state = State.ENGAGE
		elif _state == State.ENGAGE:
			_state = State.HUNT
		match _state:
			State.CLIMB:
				# Desbica a cada ~0,6 s e dá linha quando a pipa puxa.
				if _tap_timer <= 0.0:
					_tap(-_hand.last_side)  # zigue-zague para subir
					_tap_timer = _rng.randf_range(0.45, 0.7)
				# Só dá linha com a pipa alta e puxando (senão ela cai).
				if rig.tension > 1.2 and _hand.line_elevation() > 0.5 and rig.flying_length() < _target_length:
					grip = 0.3
				if rig.flying_length() >= _target_length and alt > 12.0:
					_state = State.HUNT
			State.HUNT:
				var res := _hunt(alt)
				pull = res[0]
				grip = res[1]
			State.ENGAGE:
				# Relando: estilo dar-linha (espalha o desgaste) ou puxadas rápidas.
				var phase := fmod(Time.get_ticks_msec() / 1000.0 + float(get_instance_id() % 7), 1.8)
				if _style_release:
					grip = 0.15 if phase < 1.2 else 1.0
					pull = 0.0 if phase < 1.2 else 0.6
				else:
					pull = 0.6 if fmod(phase, 0.6) < 0.3 else 0.0
					grip = 0.25 if phase > 1.4 else 1.0
	_hand.auto_feed = _state == State.CLIMB
	_hand.update(delta, pull, grip, maxf(reel, rig.reel_rate if _state == State.HUNT else 0.0))
	rig.hand_rest = hand_rest()
	rig.stroke_dir = (global_transform.basis * Vector3(0.05, -0.4, 1.0)).normalized()
	if character:
		character.right_hand_target = rig.hand_position()
		character.line_tension = rig.tension
		character.reel_speed = rig.reel_rate - rig.feed_speed


## Leva a pipa até a linha do alvo. Retorna [braçada, pegada].
func _hunt(alt: float) -> Array:
	var pull := 0.0
	var grip := 1.0
	if target == null or not target.is_flying():
		# Sem alvo: só mantém no alto com desbicos espaçados.
		if _tap_timer <= 0.0:
			_tap(-_hand.last_side)
			_tap_timer = _rng.randf_range(1.2, 2.0)
		return [pull, grip]
	var b := rig.body
	# Desbicos seguidos para um lado levam a pipa para a beira da janela e ela
	# desce: baixa demais, para de caçar e volta a subir (zigue-zague, sem dar linha).
	if alt < 10.0 or _hand.line_elevation() < 0.45:
		if _tap_timer <= 0.0:
			_tap(-_hand.last_side)
			_tap_timer = _rng.randf_range(0.5, 0.7)
		rig.reel_rate = 0.6 if alt < 6.0 else 0.0
		return [0.0, 1.0]
	var tp := target.rope.pos
	# Para cruzar a linha do alvo, a pipa precisa ATRAVESSAR o plano vertical da
	# linha dele (mão → pipa). Vai para o outro lado desse plano, na altura da pipa dele.
	var t_hand := target.hand_position()
	var t_dir := target.body.x - t_hand
	t_dir.y = 0.0
	var plane_n := t_dir.normalized().cross(Vector3.UP).normalized()
	var side_now := signf((b.x - t_hand).dot(plane_n))
	if side_now == 0.0:
		side_now = 1.0
	if _cross_side == 0.0 or (b.x - t_hand).dot(plane_n) * _cross_side > 6.0:
		_cross_side = -side_now  # atravessa (e passa um pouco do plano) — depois volta
	var line_dir := (b.x - rig.hand_position()).normalized()
	var right := line_dir.cross(Vector3.UP).normalized()  # direita de quem empina
	var lateral := (plane_n * _cross_side).dot(right) * 10.0
	var vertical := target.body.x.y - b.x.y
	var need_side := signf(lateral)
	var h := rig.heading()
	if absf(lateral) > 2.0 and _rng.randf() < aggression + 0.2:
		if _tap_timer <= 0.0:
			# Desbicos seguidos para o lado certo (cada um empurra antes do retorno).
			_tap(need_side)
			_tap_timer = lerpf(0.5, 0.32, clampf(absf(lateral) / 10.0, 0.0, 1.0)) * lerpf(1.2, 0.85, skill)
			if signf(h) != need_side and _rng.randf() < 0.25 * skill:
				_hand.double_desbico()
	elif _tap_timer <= 0.0:
		_tap(-_hand.last_side)
		_tap_timer = _rng.randf_range(0.9, 1.5)
	if vertical > 4.0 and rig.tension > 0.8 and rig.flying_length() < _target_length * 1.4:
		# Abaixo da pipa do alvo: dá linha (pipa sobe ganhando linha) + puxadas.
		grip = 0.3
		pull = 0.4 if fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.3 else 0.0
	elif vertical < -8.0:
		rig.reel_rate = 1.2  # muito acima: recolhe para descer
	if rig.flying_length() > _target_length * 1.4:
		grip = 1.0
		rig.reel_rate = 1.5
	return [pull, grip]


func _tap(side: float) -> void:
	_hand.strength = lerpf(0.85, 1.1, skill)
	_hand.desbico(side)
