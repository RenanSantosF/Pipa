class_name HeadMotion
extends Node3D
## Balanço da cabeça ao andar + respiração leve parada.
## Fica entre Head (pitch) e Camera3D; só altera a própria posição/rotação local.

@export var bob_frequency: float = 1.9
@export var bob_amplitude: float = 0.03
@export var roll_amplitude_deg: float = 0.6
@export var breathe_amplitude: float = 0.004
@export var reference_speed: float = 3.0

var _body: CharacterBody3D
var _phase: float = 0.0
var _amount: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_body = owner as CharacterBody3D


func _process(delta: float) -> void:
	_time += delta
	var target := 0.0
	if _body and _body.is_on_floor():
		var hv := Vector2(_body.velocity.x, _body.velocity.z).length()
		target = clampf(hv / reference_speed, 0.0, 1.0)
	_amount = lerpf(_amount, target, 1.0 - exp(-8.0 * delta))
	_phase += delta * TAU * bob_frequency * (0.5 + 0.5 * _amount)
	var breathe := sin(_time * 1.4) * breathe_amplitude
	position = Vector3(
		sin(_phase) * bob_amplitude * 0.5 * _amount,
		sin(_phase * 2.0) * bob_amplitude * _amount + breathe,
		0.0)
	rotation.z = deg_to_rad(sin(_phase) * roll_amplitude_deg * _amount)
