class_name FPController
extends CharacterBody3D
## Jogador em primeira pessoa empinando pipa.
##
## Câmera: SEMPRE focada na pipa. O jogador pode virar a câmera (gesto/mouse),
## mas ao soltar ela volta para a pipa como uma mola (amortecimento crítico).
## Também escreve as entradas da sua KiteRig (mão da linha, braçada, pegada, lata).

@export var walk_speed: float = 2.6
@export var acceleration: float = 9.0
## Limite para baixo: o cotovelo (onde a malha dos braços termina) nunca entra na tela.
@export var pitch_min_deg: float = -30.0
@export var pitch_max_deg: float = 86.0
## Rigidez da mola que traz a câmera de volta para a pipa.
@export var look_spring: float = 10.0
## Quão rápido a câmera acompanha o movimento da pipa (1/s).
@export var follow_rate: float = 5.0
## Mão da linha em repouso, no referencial do corpo (x direita, y altura, -z frente).
@export var hand_rest_local: Vector3 = Vector3(0.2, 1.18, -0.36)
@export var stroke_dir_local: Vector3 = Vector3(0.05, -0.4, 1.0)

var input_router: InputRouter
var rig: KiteRig
## Pipa voada a seguir com o olhar por alguns segundos depois de um corte.
var watch_target: KiteRig
var watch_time: float = 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Bob/Camera3D
@onready var character: TeenCharacter = $Character

var _yaw: float = 0.0
var _pitch: float = 0.0
var _base_yaw: float = 0.0
var _base_pitch: float = 0.0
var _off := Vector2.ZERO
var _off_vel := Vector2.ZERO
var _gravity: float = 9.8
var _stroke_smooth: float = 0.0
var _body_yaw: float = 0.0
var _hand: KiteHand
## Mão na linha da FÍSICA REAL (rig.physical): só posição do braço, pegada e carretel.
var _line_hand: LineHand

## Curva da mão num desbico (m; negativo = mão vai para a frente e afrouxa a linha).
const DESBICO_TIME := 0.46
static func desbico_offset(t: float) -> float:
	if t < 0.08:
		return -0.25 * t / 0.08
	if t < 0.18:
		return -0.25 + 0.70 * (t - 0.08) / 0.10
	if t < DESBICO_TIME:
		return 0.45 * (1.0 - (t - 0.18) / (DESBICO_TIME - 0.18))
	return 0.0


## Guiar: arrasto mínimo (px) e arrasto para o cabresto todo (px).
const GUIDE_DEAD_PX := 18.0
## Câmera: campo de visão normal, mínimo (zoom máximo), fração da altura da tela
## que a pipa deve ocupar e zona livre (fração do campo) em que ela anda sem a
## câmera ir atrás.
const BASE_FOV := 74.0
const MIN_FOV := 40.0
## Quanto do campo de visão a câmera mira abaixo da pipa (0,22 = pipa a ~28% do topo).
const AIM_BELOW := 0.22
const KITE_SCREEN_FRACTION := 0.04
const FREE_ZONE := 0.18
const GUIDE_FULL_PX := 110.0
## Erro de rumo (rad) que já pede cabresto todo para um lado.
const STEER_FULL_ERR := 0.7


func _ready() -> void:
	camera.far = GameConfig.camera_far()
	GameConfig.quality_changed.connect(func(_q: int) -> void: camera.far = GameConfig.camera_far())
	process_physics_priority = -50  # escreve as entradas da pipa antes da simulação
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_yaw = rotation.y
	_base_yaw = _yaw
	_body_yaw = _yaw
	if character:
		character.first_person = true
		head.position.y = character.eye_height
	_head_base = head.position
	if character:
		_char_base = character.position
	_phys_prev = global_position
	_phys_cur = global_position


func look_at_point(world_point: Vector3) -> void:
	var to := world_point - head.global_position
	if to.length() < 0.01:
		return
	to = to.normalized()
	_base_yaw = atan2(-to.x, -to.z)
	_base_pitch = asin(clampf(to.y, -1.0, 1.0))
	_off = Vector2.ZERO
	_off_vel = Vector2.ZERO
	_apply_rotation()


func focus_point() -> Vector3:
	if watch_target and is_instance_valid(watch_target) and watch_target.body and watch_time > 0.0:
		return watch_target.body.x
	if rig and rig.body:
		# Pipa no chão/perto dos pés: olha para a frente, não para o pé.
		var k := rig.visual_pose().origin
		if k.y < head.global_position.y + 0.5 and k.distance_to(global_position) < 6.0:
			return head.global_position + (Vector3(k.x, head.global_position.y, k.z) - head.global_position).normalized() * 10.0 + Vector3.UP * 1.5
		return k
	return head.global_position + Basis(Vector3.UP, _yaw) * Vector3(0, 1.5, -10)


## VISUAL INTERPOLADO do jogador: o corpo anda no passo da física (30 Hz no celular)
## e a linha/pipa são desenhadas interpoladas a 60 quadros/s. Sem isto, andando, a
## câmera e a mão pulavam de 30 em 30 Hz e a ponta da linha perto da mão aparecia em
## dois lugares (linha "duplicada"). Cabeça (câmera), corpo e alvo da mão vão para a
## posição interpolada entre os dois últimos ticks, a mesma fração usada na linha.
var _phys_prev := Vector3.ZERO
var _phys_cur := Vector3.ZERO
var _head_base := Vector3.ZERO
var _char_base := Vector3.ZERO
var _hand_prev := Vector3.ZERO
var _hand_cur := Vector3.ZERO


func _set_hand_target(p: Vector3) -> void:
	_hand_prev = _hand_cur if _hand_cur != Vector3.ZERO else p
	_hand_cur = p


func _apply_visual_interpolation() -> void:
	var fr := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var off := _phys_prev.lerp(_phys_cur, fr) - _phys_cur
	if off.length() > 1.0:
		off = Vector3.ZERO   # teleporte (relançar, reposicionar)
	var lo := global_basis.inverse() * off
	head.position = _head_base + lo
	if character:
		character.position = _char_base + lo
		if _hand_cur != Vector3.ZERO:
			character.right_hand_target = _hand_prev.lerp(_hand_cur, fr) if _hand_prev.distance_to(_hand_cur) < 1.0 else _hand_cur


func _process(delta: float) -> void:
	_apply_visual_interpolation()
	watch_time = maxf(watch_time - delta, 0.0)
	var fp := focus_point()
	var to := fp - head.global_position
	var dist := to.length()
	if dist > 0.5:
		to = to.normalized()
		var k := 1.0 - exp(-follow_rate * delta)
		_base_yaw = lerp_angle(_base_yaw, atan2(-to.x, -to.z), k)
		# A câmera mira um pouco ABAIXO da pipa: ela fica no terço de cima da tela e
		# sobra tela para o bairro, as outras pipas e as linhas.
		var aim_down := deg_to_rad(camera.fov) * AIM_BELOW if rig and rig.body and not rig.held else 0.0
		_base_pitch = lerpf(_base_pitch, maxf(asin(clampf(to.y, -1.0, 1.0)) - aim_down, deg_to_rad(-15.0)), k)
	# ZOOM: aproxima a pipa conforme a distância (de longe ela ficava com ~10 px e o
	# desbico não aparecia). Perto (soltando da mão) volta ao campo de visão normal.
	var target_fov := BASE_FOV
	# Sem zoom (v0.24): a câmera não aproxima a pipa — campo de visão fixo, como o olho.
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-1.8 * delta))
	if input_router:
		var intent := input_router.intent
		var look := intent.consume_look()
		var inv := -1.0 if GameConfig.invert_y else 1.0
		_off.x -= deg_to_rad(look.x)
		_off.y -= deg_to_rad(look.y) * inv
		_off.x = clampf(_off.x, -PI * 0.9, PI * 0.9)
		_off.y = clampf(_off.y, -1.4, 1.4)
		if not intent.look_active and look.length_squared() < 0.0001:
			# Mola criticamente amortecida de volta para a pipa.
			var acc := -look_spring * _off - 2.0 * sqrt(look_spring) * _off_vel
			_off_vel += acc * delta
			_off += _off_vel * delta
		else:
			_off_vel = Vector2.ZERO
	_apply_rotation()
	# O corpo acompanha a câmera com atraso (o personagem vira o tronco).
	_body_yaw = lerp_angle(_body_yaw, _yaw, 1.0 - exp(-4.0 * delta))
	if character:
		character.rotation.y = _body_yaw - rotation.y


func _apply_rotation() -> void:
	_yaw = wrapf(_base_yaw + _off.x, -PI, PI)
	_pitch = clampf(_base_pitch + _off.y, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	rotation.y = _yaw
	head.rotation.x = _pitch


## Área onde o jogador pode andar (centro e raio, m); 0 = livre.
var leash_center := Vector3.ZERO
var leash_radius := 0.0


func _physics_process(delta: float) -> void:
	_phys_prev = global_position
	var move := Vector2.ZERO
	if input_router:
		move = input_router.intent.move
	var wish := Basis(Vector3.UP, _yaw) * Vector3(move.x, 0.0, -move.y)
	var k := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, wish.x * walk_speed, k)
	velocity.z = lerpf(velocity.z, wish.z * walk_speed, k)
	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	# Preso na laje: não sai dela (raio em volta do centro da laje).
	if leash_radius > 0.0:
		var off := Vector2(global_position.x - leash_center.x, global_position.z - leash_center.z)
		if off.length() > leash_radius:
			off = off.normalized() * leash_radius
			global_position.x = leash_center.x + off.x
			global_position.z = leash_center.z + off.y
			velocity.x = 0.0
			velocity.z = 0.0
	_phys_cur = global_position
	_drive_rig(delta)
	if character:
		character.set_locomotion(Vector2(velocity.x, velocity.z).length())


## FÍSICA REAL: os gestos viram SÓ movimentos da mão na linha (LineHand). Quem decide
## o que a pipa faz é a linha (tração/folga), o cabresto, o vento, o peso e a rabiola.
##   toque (qualquer dedo) = desbico "dá e puxa" · arrastar rápido para baixo = puxão
##   (braçada que recolhe) · segurar para baixo = puxada contínua · arrastar para cima
##   = dar linha (mão abre) · segurar e arrastar devagar = braço à frente (folga) ou
##   para trás (estica) · aparar = enrolar na lata.
func _drive_physical(delta: float, intent: PlayerIntent) -> void:
	if _line_hand == null or _line_hand.rig != rig:
		_line_hand = LineHand.new(rig)
	var now := Time.get_ticks_usec() / 1000000.0
	var n := intent.desbico_toques + intent.taps.size() + intent.double_taps * 2 + intent.desbico_press.size()
	for i in n:
		# O toque entra na hora exata em que o dedo soltou (ritmo do jogador).
		var dl := 0.0
		if i < intent.desbico_times.size():
			dl = clampf(intent.desbico_times[i] + delta - now, 0.0, delta)
		_line_hand.tap(dl)
	intent.desbico_toques = 0
	intent.desbico_times.clear()
	intent.taps.clear()
	intent.double_taps = 0
	intent.desbico_press.clear()
	intent.desbico_release = 0
	intent.throws.clear()
	intent.cancel_desbico = false
	for _a in intent.recolhe:
		_line_hand.pull()
	intent.recolhe.clear()
	for _i in intent.pull_taps:
		_line_hand.pull()
	intent.pull_taps = 0
	_line_hand.pull_fingers = intent.pull_fingers
	_line_hand.pull_line(intent.line_pull)
	intent.line_pull = 0.0
	_line_hand.pull_held = intent.pull_held
	_line_hand.pull_rate = intent.pull_rate
	var arm := 0.0
	if intent.guide_active and intent.guide_vec.length() > GUIDE_DEAD_PX:
		# Arrastar para cima = braço à frente (folga); para baixo = braço para trás.
		arm = clampf(intent.guide_vec.y / GUIDE_FULL_PX, -1.0, 1.0)
	if intent.stroke > 0.01:
		arm = maxf(arm, clampf(intent.stroke / 0.5, 0.0, 1.0))   # braçada lenta (PC)
	_line_hand.arm = arm
	_line_hand.update(delta, intent.grip, intent.reel_rate)
	if character:
		_set_hand_target(rig.hand_position() + rig.stroke_dir * _line_hand.visual_pull)
		character.line_tension = rig.tension
		character.reel_speed = rig.reel_rate - rig.feed_speed


## Escreve as entradas da pipa a partir do intent.
func _drive_rig(delta: float) -> void:
	if rig == null or input_router == null:
		return
	var intent := input_router.intent
	var body_basis := Basis(Vector3.UP, _body_yaw)
	var t_norm := clampf(rig.tension / 15.0, 0.0, 1.0)
	var to_kite := (focus_point() - global_position).normalized()
	rig.hand_rest = global_position + body_basis * hand_rest_local + to_kite * (0.12 * t_norm)
	rig.stroke_dir = (body_basis * stroke_dir_local).normalized()
	if rig.physical:
		_drive_physical(delta, intent)
		return
	# Desbico/puxar/dar linha pela "mão do pipeiro" (mesma lógica dos vizinhos).
	if _hand == null or _hand.rig != rig:
		_hand = KiteHand.new(rig)
	_hand.desbico_intensity = intent.desbico_intensity
	if rig.flight == null:
		for side in intent.desbico_press:
			_hand.press_desbico(side)
		if intent.desbico_release > 0:
			_hand.release_desbico()
		for side in intent.taps:
			_hand.tap_desbico(side)
	else:
		intent.desbico_toques += intent.taps.size()
	intent.desbico_press.clear()
	intent.desbico_release = 0
	intent.taps.clear()
	for _i in intent.pull_taps:
		_hand.puxao()
	intent.pull_taps = 0
	# CONTROLE (separado da física):
	#  * TOQUE = desbico (puxadinha): o modelo de voo dá o tranco e o balanço.
	#  * SEGURAR E ARRASTAR = guiar: a direção do arrasto (a partir de onde o dedo
	#    encostou, como um manche em qualquer lugar da tela) é para onde o bico deve
	#    apontar na tela. Vira só um COMANDO DE CABRESTO (−1..1); o modelo de voo
	#    inclina, curva e acelera com a inércia dele.
	if rig.flight != null and rig.held and (intent.desbico_toques > 0 or not intent.recolhe.is_empty() \
			or intent.grip < 0.95 or intent.pull_held or (intent.guide_active and intent.guide_vec.length() > GUIDE_DEAD_PX)):
		rig.release_hold()   # pipa na mão: o primeiro comando solta
	if rig.flight != null:
		# Cada toque entra com atraso fixo de um tick a partir da hora em que o dedo
		# soltou: o intervalo entre toques fica exato (o ritmo é o que o jogador fez).
		var now := Time.get_ticks_usec() / 1000000.0
		for i in intent.desbico_toques:
			if i < intent.desbico_times.size():
				rig.flight.tap_at(clampf(intent.desbico_times[i] + delta - now, 0.0, delta))
			else:
				rig.flight.tap()
		intent.desbico_times.clear()
		var cmd := 0.0
		var target := NAN
		var amount := 0.0
		if intent.guide_active and intent.guide_vec.length() > GUIDE_DEAD_PX:
			target = atan2(intent.guide_vec.x, -intent.guide_vec.y)
			amount = clampf((intent.guide_vec.length() - GUIDE_DEAD_PX) / GUIDE_FULL_PX, 0.0, 1.0)
		elif intent.guide_amount > 0.0 and intent.guide_dir != Vector3.ZERO:
			var fr0: Array = rig.flight.frame()
			target = atan2(intent.guide_dir.dot(fr0[2]), intent.guide_dir.dot(fr0[1]))
			amount = intent.guide_amount
		var ks := Input.get_axis(&"desbico_left", &"desbico_right") if InputMap.has_action(&"desbico_left") else 0.0
		if ks != 0.0:
			cmd = ks
		elif not is_nan(target):
			var err := wrapf(target - rig.flight.heading, -PI, PI)
			cmd = clampf(err / STEER_FULL_ERR, -1.0, 1.0) * amount
		rig.flight.steer = cmd
		intent.desbico_press.clear()
		intent.desbico_release = 0
	else:
		var wdir := Vector3.ZERO
		var gamount := 0.0
		if intent.guide_amount > 0.0:
			wdir = intent.guide_dir
			gamount = intent.guide_amount
		_hand.guide(wdir, gamount)
		for _i in intent.desbico_toques:
			_hand.desbico_toque()
		intent.desbico_times.clear()
	intent.desbico_toques = 0
	for a in intent.recolhe:
		_hand.recolher(a)
	intent.recolhe.clear()
	_hand.pull_rate = intent.pull_rate
	_hand.set_pull_held(intent.pull_held)
	if rig.flight == null:
		for side in intent.throws:
			_hand.throw(side)
		for _i in intent.double_taps:
			_hand.double_desbico()
	else:
		intent.desbico_toques += intent.double_taps * 2
	intent.throws.clear()
	intent.double_taps = 0
	if intent.cancel_desbico:
		_hand.cancel()
		intent.cancel_desbico = false
	_hand.update(delta, intent.stroke, intent.grip, intent.reel_rate)
	if character:
		# Puxadinha do desbico: o braço dá o tranco (só visual; a física está no voo).
		var tug := rig.flight.tug_visual() if rig.flight != null else 0.0
		_set_hand_target(rig.hand_position() + rig.stroke_dir * (0.09 * tug))
		character.line_tension = rig.tension
		character.reel_speed = rig.reel_rate - rig.feed_speed
