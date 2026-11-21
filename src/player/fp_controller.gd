class_name FPController
extends CharacterBody3D
## Controlador em primeira pessoa: andar, olhar (yaw no corpo, pitch na cabeça),
## gravidade e assistência de mira opcional para acompanhar a pipa.

@export var walk_speed: float = 3.0
@export var acceleration: float = 10.0
@export var air_control: float = 0.3
@export var pitch_min_deg: float = -75.0
@export var pitch_max_deg: float = 86.0
## Velocidade da assistência de mira (1/s).
@export var aim_assist_rate: float = 1.4
## Ângulo (graus) dentro do qual a assistência não age (a pipa já está no quadro).
@export var aim_assist_dead_angle: float = 10.0

var input_router: InputRouter
## Alvo da assistência de mira (a pipa).
var aim_target: Node3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Bob/Camera3D
@onready var viewmodel: Viewmodel = $Head/Bob/Camera3D/Viewmodel

var _yaw: float = 0.0
var _pitch: float = 0.0
var _gravity: float = 9.8


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_yaw = rotation.y
	_pitch = head.rotation.x


## Ponto onde a linha sai da mão (usado por KiteLine e LineRenderer).
func get_hand_anchor() -> Node3D:
	return viewmodel.hand_anchor


## Vira a câmera instantaneamente para um ponto do mundo.
func look_at_point(world_point: Vector3) -> void:
	var to := world_point - head.global_position
	if to.length() < 0.01:
		return
	to = to.normalized()
	_yaw = atan2(-to.x, -to.z)
	_pitch = clampf(asin(clampf(to.y, -1.0, 1.0)), deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	_apply_rotation()


func _process(delta: float) -> void:
	if input_router == null:
		return
	var intent := input_router.intent
	var look := intent.consume_look()
	var inv := -1.0 if GameConfig.invert_y else 1.0
	_yaw -= deg_to_rad(look.x)
	_pitch -= deg_to_rad(look.y) * inv
	if GameConfig.aim_assist and aim_target and intent.is_handling_line() and look.length_squared() < 0.0001:
		_apply_aim_assist(delta)
	_pitch = clampf(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	_apply_rotation()


func _apply_rotation() -> void:
	_yaw = wrapf(_yaw, -PI, PI)
	rotation.y = _yaw
	head.rotation.x = _pitch


func _apply_aim_assist(delta: float) -> void:
	var to := aim_target.global_position - camera.global_position
	if to.length() < 1.0:
		return
	to = to.normalized()
	var desired_yaw := atan2(-to.x, -to.z)
	var desired_pitch := asin(clampf(to.y, -1.0, 1.0))
	var off := absf(angle_difference(_yaw, desired_yaw)) + absf(desired_pitch - _pitch)
	if off < deg_to_rad(aim_assist_dead_angle):
		return
	var k := 1.0 - exp(-aim_assist_rate * delta)
	_yaw = lerp_angle(_yaw, desired_yaw, k)
	_pitch = lerpf(_pitch, desired_pitch, k)


func _physics_process(delta: float) -> void:
	var move := Vector2.ZERO
	if input_router:
		move = input_router.intent.move
	var wish := Basis(Vector3.UP, _yaw) * Vector3(move.x, 0.0, -move.y)
	var target := wish * walk_speed
	var accel := acceleration if is_on_floor() else acceleration * air_control
	var k := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
