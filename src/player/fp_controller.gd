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


## Guiar: zona morta em volta da pipa na tela e distância para força máxima (px).
const GUIDE_DEAD_PX := 28.0
## Câmera: campo de visão normal, mínimo (zoom máximo), fração da altura da tela
## que a pipa deve ocupar e zona livre (fração do campo) em que ela anda sem a
## câmera ir atrás.
const BASE_FOV := 72.0
const MIN_FOV := 52.0
const KITE_SCREEN_FRACTION := 0.07
const FREE_ZONE := 0.18
const GUIDE_FULL_PX := 240.0
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
		var k := rig.body.x
		if k.y < head.global_position.y + 0.5 and k.distance_to(global_position) < 6.0:
			return head.global_position + (Vector3(k.x, head.global_position.y, k.z) - head.global_position).normalized() * 10.0 + Vector3.UP * 1.5
		return k
	return head.global_position + Basis(Vector3.UP, _yaw) * Vector3(0, 1.5, -10)


func _process(delta: float) -> void:
	watch_time = maxf(watch_time - delta, 0.0)
	var fp := focus_point()
	var to := fp - head.global_position
	var dist := to.length()
	if dist > 0.5:
		to = to.normalized()
		var k := 1.0 - exp(-follow_rate * delta)
		_base_yaw = lerp_angle(_base_yaw, atan2(-to.x, -to.z), k)
		_base_pitch = lerpf(_base_pitch, maxf(asin(clampf(to.y, -1.0, 1.0)), deg_to_rad(-15.0)), k)
	# ZOOM: aproxima a pipa conforme a distância (de longe ela ficava com ~10 px e o
	# desbico não aparecia). Perto (soltando da mão) volta ao campo de visão normal.
	var target_fov := BASE_FOV
	if rig and rig.body and not rig.held and dist > 8.0 and watch_time <= 0.0:
		var size := rig.profile.height if rig.profile else 0.65
		target_fov = clampf(rad_to_deg(2.0 * atan(size / (2.0 * dist * KITE_SCREEN_FRACTION))), MIN_FOV, BASE_FOV)
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


func _physics_process(delta: float) -> void:
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
	_drive_rig(delta)
	if character:
		character.set_locomotion(Vector2(velocity.x, velocity.z).length())


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
	# Desbico/puxar/dar linha pela "mão do pipeiro" (mesma lógica dos vizinhos).
	if _hand == null or _hand.rig != rig:
		_hand = KiteHand.new(rig)
	_hand.desbico_intensity = intent.desbico_intensity
	for side in intent.desbico_press:
		_hand.press_desbico(side)
	intent.desbico_press.clear()
	if intent.desbico_release > 0:
		_hand.release_desbico()
		intent.desbico_release = 0
	for side in intent.taps:
		_hand.tap_desbico(side)
	intent.taps.clear()
	for _i in intent.pull_taps:
		_hand.puxao()
	intent.pull_taps = 0
	# CONTROLE (separado da física): o dedo na tela, em relação à pipa na tela, diz
	# para onde o jogador quer que ela vá. Vira só um COMANDO DE CABRESTO (−1..1)
	# proporcional ao quanto o bico está fora dessa direção; o modelo de voo faz o
	# resto (inclina, curva, acelera) com a inércia dele.
	var wdir := Vector3.ZERO
	var amount := 0.0
	if intent.guide_active and camera and rig.body and not camera.is_position_behind(rig.body.x):
		var ks := camera.unproject_position(rig.body.x)
		var off := intent.guide_finger - ks
		var dist := off.length()
		if dist > GUIDE_DEAD_PX:
			var ld: Vector3 = (rig.body.x - rig.hand_position()).normalized()
			var up_t := (Vector3.UP - ld * ld.y).normalized()
			var right_t := ld.cross(up_t).normalized()
			if right_t.dot(camera.global_basis.x) < 0.0:
				right_t = -right_t
			wdir = (right_t * off.x - up_t * off.y).normalized()
			amount = clampf((dist - GUIDE_DEAD_PX) / GUIDE_FULL_PX, 0.35, 1.0)
	elif intent.guide_amount > 0.0:
		wdir = intent.guide_dir
		amount = intent.guide_amount
	if rig.flight != null:
		var cmd := 0.0
		if wdir != Vector3.ZERO:
			var fr: Array = rig.flight.frame()
			var target := atan2(wdir.dot(fr[2]), wdir.dot(fr[1]))
			var err := wrapf(target - rig.flight.heading, -PI, PI)
			cmd = clampf(err / STEER_FULL_ERR, -1.0, 1.0) * amount
		rig.flight.steer = cmd
	else:
		_hand.guide(wdir, amount)
	for _i in intent.desbico_toques:
		_hand.desbico_toque()
	intent.desbico_toques = 0
	for a in intent.recolhe:
		_hand.recolher(a)
	intent.recolhe.clear()
	_hand.pull_rate = intent.pull_rate
	_hand.set_pull_held(intent.pull_held)
	for side in intent.throws:
		_hand.throw(side)
	intent.throws.clear()
	for _i in intent.double_taps:
		_hand.double_desbico()
	intent.double_taps = 0
	if intent.cancel_desbico:
		_hand.cancel()
		intent.cancel_desbico = false
	_hand.update(delta, intent.stroke, intent.grip, intent.reel_rate)
	if character:
		character.right_hand_target = rig.hand_position()
		character.line_tension = rig.tension
		character.reel_speed = rig.reel_rate - rig.feed_speed
