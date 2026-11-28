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
	add_to_group(&"people")   # a linha encosta no corpo dele
	process_physics_priority = -50
	_rng.seed = randi()  # segue a semente global (testes reproduzíveis com --seed)
	_style_release = _rng.randf() < 0.5
	_timer = _rng.randf_range(0.5, 4.0)


func reseed(v: int) -> void:
	_rng.seed = v
	_style_release = _rng.randf() < 0.5
	_timer = _rng.randf_range(0.5, 4.0)


func hand_rest() -> Vector3:
	return global_position + global_transform.basis * Vector3(0.2, 1.18, -0.36)


func launch() -> void:
	if rig == null:
		return
	rotation.y = atan2(-Wind.get_direction().x, -Wind.get_direction().z)
	if rig.physical:
		# Física real: "soltar de longe" — um amigo segura a pipa ~15 m vento abaixo e
		# solta (na rua, entre as casas, o vento junto do chão é fraco demais para soltar
		# da mão sem ajuda).
		rig.launch(hand_rest(), _rng.randf_range(13.0, 17.0), 32.0, Wind.get_direction())
	else:
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
	if rig.physical:
		_physical_update(delta)
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
					_pull()  # puxões para subir (a linha escorrega quando ela está alta)
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
			_pull()
			_tap_timer = _rng.randf_range(1.2, 2.0)
		return [pull, grip]
	var b := rig.body
	# Desbicos seguidos para um lado levam a pipa para a beira da janela e ela
	# desce: baixa demais, para de caçar e volta a subir (zigue-zague, sem dar linha).
	if alt < 10.0 or _hand.line_elevation() < 0.45:
		if _tap_timer <= 0.0:
			_pull()
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
			# Desbica para o lado (o bico gira) e puxa quando o bico aponta para lá.
			_combo(need_side, clampf(absf(lateral) / 10.0, 0.0, 1.0))
			_tap_timer = lerpf(1.1, 0.75, skill)
	elif _tap_timer <= 0.0:
		_pull()
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


## Puxão (mão do vizinho).
func _pull() -> void:
	_hand.strength = lerpf(0.85, 1.1, skill)
	_hand.puxao()


## Desbico para o lado (dá linha um tempo proporcional à distância) e, quando o
## bico já girou, puxão: a pipa sai na direção do bico.
func _combo(side: float, amount: float) -> void:
	_hand.strength = lerpf(0.85, 1.1, skill)
	_hand.press_desbico(side)
	var hold := lerpf(0.3, 0.6, amount) * _rng.randf_range(0.85, 1.15)
	get_tree().create_timer(hold, true, true).timeout.connect(func() -> void:
		if _hand != null:
			_hand.release_desbico())
	get_tree().create_timer(hold + lerpf(0.12, 0.05, skill), true, true).timeout.connect(func() -> void:
		if _hand != null and rig != null and rig.is_flying():
			_hand.puxao())


# --- FÍSICA REAL (v0.19): o vizinho usa a mesma mão na linha do jogador -------------
## Só o que a mão de verdade faz: toques (desbico), puxar linha, dar linha, enrolar.
## Para ir para um lado ele desbica até o bico apontar para lá e então PUXA (a pipa sai
## para onde o bico aponta). Para subir puxa; para descer/ir longe dá linha. Cruzado
## com a sua linha, rela: dá linha (espalha o desgaste) ou puxa rápido.

var _lh: LineHand
var _pull_timer: float = 0.0
## Relógio do jogo (não do sistema): o ritmo do relo não depende da velocidade da máquina.
var _clock: float = 0.0
var _rest_time: float = 0.0


func _physical_update(delta: float) -> void:
	_clock += delta
	if _lh == null or _lh.rig != rig:
		_lh = LineHand.new(rig)
	_timer -= delta
	_tap_timer -= delta
	_pull_timer -= delta
	var grip := 1.0
	var reel := 0.0
	if not rig.is_flying():
		if rig.rope != null:
			reel = 3.0
			if _state != State.WAIT:
				_state = State.WAIT
				_timer = 6.0
			elif _timer <= 0.0:
				rig.rope = null
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
		var alt := rig.body.x.y - rig.hand_position().y
		var in_contact := world != null and world.strongest_contact_for(rig) != null
		if alt > _best_alt + 0.5:
			_best_alt = alt
			_stall_time = 0.0
		elif _state == State.CLIMB or rig.snagged or (_state == State.HUNT and alt < 2.0):
			_stall_time += delta
		# Pipa parada com a linha frouxa = deitada num telhado/no chão: recolhe e solta de novo.
		if rig.body.v.length() < 0.5 and rig.tension < 0.6:
			_rest_time += delta
		else:
			_rest_time = 0.0
		if _rest_time > 6.0:
			_recovering = true
		if _stall_time > 12.0 or _recovering:
			_recovering = true
			reel = 4.0
			if rig.flying_length() < 3.0:
				rig.stow()
				_state = State.WAIT
				_timer = _rng.randf_range(1.0, 3.0)
				_recovering = false
		elif in_contact:
			_state = State.ENGAGE
		elif _state == State.ENGAGE:
			_state = State.HUNT
		if not _recovering:
			match _state:
				State.CLIMB:
					# Da mão: solta da mão (1 toque) e sobe com puxadinhas curtas e a mão
					# entreaberta (a linha corre só quando ela puxa). Sem desbicar: perto do
					# chão o balanço do desbico jogaria a pipa no chão.
					if rig.held and _tap_timer <= 0.0:
						_lh.tap()
						_tap_timer = 1.0
					if not rig.held and rig.tension < 2.0 and _pull_timer <= 0.0:
						_lh.pull_line(0.2)
						_pull_timer = 0.6
					# Mão entreaberta: a linha corre só quando a pipa puxa (sobe ganhando linha);
					# afundando (pouca tração), fecha a mão e puxa para ela pegar vento.
					if rig.flying_length() < _target_length and rig.tension > 0.7:
						grip = 0.2
					elif rig.tension < 0.6 and alt < 10.0 and _pull_timer <= 0.0 and rig.age > 3.0:
						_lh.pull_line(0.4)
						_pull_timer = 0.5
					if alt < 0.5 and rig.age > 3.0 and _pull_timer <= 0.0:
						_lh.pull_line(0.35)
						_pull_timer = 0.6
					if rig.flying_length() >= _target_length and alt > 12.0:
						_state = State.HUNT
				State.HUNT:
					grip = _hunt_physical(alt)
				State.ENGAGE:
					var phase := fmod(_clock + float(get_instance_id() % 7), 1.8)
					if _style_release:
						grip = 0.2 if phase < 1.1 else 1.0
						if phase > 1.2 and _pull_timer <= 0.0:
							_lh.pull_line(0.5)
							_pull_timer = 0.3
					else:
						if _pull_timer <= 0.0:
							_lh.pull_line(0.45)
							_pull_timer = 0.28
						grip = 0.3 if phase > 1.4 else 1.0
	_lh.update(delta, grip, reel)
	rig.hand_rest = hand_rest()
	rig.stroke_dir = (global_transform.basis * Vector3(0.05, -0.4, 1.0)).normalized()
	if character:
		character.right_hand_target = rig.hand_position() + rig.stroke_dir * _lh.visual_pull
		character.line_tension = rig.tension
		character.reel_speed = rig.reel_rate - rig.feed_speed


## Leva a pipa até a linha (ou a rabiola) do alvo só com a mão. Retorna a pegada.
func _hunt_physical(alt: float) -> float:
	var grip := 1.0
	rig.reel_rate = 0.0
	if target == null or not target.is_flying():
		if _tap_timer <= 0.0:
			_lh.tap()
			_tap_timer = _rng.randf_range(0.8, 1.4)
		if alt < 14.0 and _pull_timer <= 0.0:
			_lh.pull_line(0.4)
			_pull_timer = 0.8
		return grip
	var b := rig.body
	if alt < 8.0:
		# Baixa com pouca linha: puxar só encurta e joga no chão — dá linha devagar
		# (mão entreaberta) e deixa o vento levar a pipa para cima.
		if rig.flying_length() < 18.0:
			return 0.12 if rig.tension > 0.4 else 1.0
		# Baixa com linha: puxa para subir.
		if _pull_timer <= 0.0:
			_lh.pull_line(0.5)
			_pull_timer = 0.45
		return grip
	# Atravessar o plano vertical da linha do alvo (mão → pipa), na altura da pipa dele.
	var t_hand := target.hand_position()
	var t_dir := target.body.x - t_hand
	t_dir.y = 0.0
	var plane_n := t_dir.normalized().cross(Vector3.UP).normalized()
	var off := (b.x - t_hand).dot(plane_n)
	var side_now := signf(off) if off != 0.0 else 1.0
	if _cross_side == 0.0 or off * _cross_side > 6.0:
		_cross_side = -side_now
	var line_dir := (b.x - rig.hand_position()).normalized()
	var right := line_dir.cross(Vector3.UP).normalized()
	var lateral := (plane_n * _cross_side).dot(right) * 10.0
	var vertical := target.body.x.y - 3.0 - b.x.y   # mira um pouco abaixo da pipa dele
	var h := rig.heading()
	var need := signf(lateral)
	if absf(lateral) > 1.5 and _rng.randf() < aggression + 0.3:
		if signf(h) == need and absf(h) > 0.3 and absf(h) < 2.2:
			# O bico aponta para onde ele quer ir: puxa (a pipa sai para lá).
			if _pull_timer <= 0.0:
				_lh.pull_line(lerpf(0.4, 0.8, skill))
				_pull_timer = lerpf(0.5, 0.3, skill)
		elif _tap_timer <= 0.0:
			# Desbica para o lado certo (os lados alternam: 1 toque se o próximo já é
			# para lá, 2 toques se não) e espera o balanço render.
			_tap_toward(need)
			_tap_timer = _rng.randf_range(0.8, 1.1)
	elif _tap_timer <= 0.0:
		_lh.tap()
		_tap_timer = _rng.randf_range(0.6, 1.0)
	if vertical > 4.0 and _pull_timer <= 0.0 and absf(h) < 0.6:
		_lh.pull_line(0.5)   # abaixo da pipa dele: puxa (bico para cima = sobe)
		_pull_timer = 0.5
	elif vertical < -6.0 and rig.tension > 1.0 and rig.flying_length() < _target_length * 1.6:
		grip = 0.3            # muito acima: dá linha (vai mais longe e desce)
	if rig.flying_length() > _target_length * 1.6:
		rig.reel_rate = 1.5
	elif rig.flying_length() < _target_length * 0.7 and rig.tension > 0.8 and _pull_timer < 0.2:
		grip = minf(grip, 0.3)   # puxou demais: devolve linha (volta ao comprimento dele)
	return grip


## Desbico para um lado (−1 esquerda, +1 direita) respeitando a alternância.
func _tap_toward(side: float) -> void:
	_lh.tap()
	if rig.next_desbico_side() != side:
		_lh.tap(KiteRig.DESB_CHAIN + 0.1)   # depois do encadeamento: vai para o outro lado
