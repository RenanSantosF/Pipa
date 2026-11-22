class_name BotFlyer
extends Node3D
## Adversário controlado pelo computador (para testar o combate antes do online).
## Usa exatamente as mesmas entradas que o jogador (mão, braçada, pegada, lata),
## então só pode fazer o que a física permite:
##   - SUBIR: dá braçadas quando o nariz aponta para cima;
##   - APROXIMAR: dá braçadas quando o nariz aponta para a linha do alvo,
##     e solta a mão (desbica) quando o nariz aponta para o lado errado;
##   - CRUZADO: alterna dar linha (espalha o próprio desgaste) e puxadas.

@export var start_line_length: float = 28.0
@export var line_type: LineType
@export var aggression: float = 0.7

var rig: KiteRig
var target: KiteRig
var world: KitePhysicsWorld

@onready var character: TeenCharacter = $Character

var _stroke: float = 0.0
var _stroke_phase: float = 0.0
var _release_timer: float = 0.0
var _think: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -50
	_rng.randomize()


func hand_rest() -> Vector3:
	var b := global_transform.basis
	return global_position + b * Vector3(0.2, 1.18, -0.36)


func launch() -> void:
	if rig == null:
		return
	rig.launch(hand_rest(), start_line_length, 45.0, Wind.get_direction())


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	if not rig.is_flying():
		if rig.rope:
			rig.reel_rate = 3.0  # recolhe a sobra de linha
		else:
			_think += delta
			if _think > 4.0:
				_think = 0.0
				launch()
		_write(delta, false, 1.0)
		return
	# Vira o corpo para a pipa.
	var to_kite := rig.body.x - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to_kite.x, -to_kite.z), 1.0 - exp(-2.0 * delta))

	var b := rig.body
	var line_dir := (b.x - rig.hand_position()).normalized()
	var nose := b.q * Vector3.UP
	nose = (nose - line_dir * nose.dot(line_dir)).normalized()
	var up := (Vector3.UP - line_dir * line_dir.y).normalized()
	var altitude := b.x.y

	var desired := up
	var in_contact := false
	if target and target.is_flying():
		var tp := target.rope.pos
		var aim: Vector3 = tp[int(tp.size() * 0.75)] if tp.size() > 2 else target.body.x
		var to_aim := aim - b.x
		var lateral := to_aim - line_dir * to_aim.dot(line_dir)
		if altitude > 12.0 and lateral.length() > 1.0 and _rng.randf() < aggression + 0.3:
			desired = lateral.normalized().lerp(up, 0.25).normalized()
		if world and world.strongest_contact_for(rig) != null:
			in_contact = true

	var align := nose.dot(desired)
	var pull := false
	var grip := 1.0
	_release_timer = maxf(_release_timer - delta, 0.0)
	if in_contact:
		# Cruzado: dar linha na maior parte do tempo, com puxadas curtas.
		_think += delta
		if fmod(_think, 1.6) < 1.0:
			grip = 0.15
		else:
			pull = true
	elif _release_timer > 0.0:
		grip = 0.2
	elif align > 0.75:
		pull = true
	elif align < -0.2 and rig.tension > 1.0:
		_release_timer = 0.5  # desbica: afrouxa para a rabiola endireitar
	if altitude < 6.0 and align > 0.3:
		pull = true
	if rig.flying_length() > 70.0:
		rig.reel_rate = 1.5
	else:
		rig.reel_rate = 0.0
	_write(delta, pull, grip)


func _write(delta: float, pull: bool, grip: float) -> void:
	# Braçadas ritmadas: puxa ~0,6 m em 0,25 s e volta.
	if pull:
		_stroke_phase += delta * 1.8
		var ph := fmod(_stroke_phase, 1.0)
		_stroke = 0.65 * clampf(ph / 0.35, 0.0, 1.0) if ph < 0.6 else 0.0
	else:
		_stroke = move_toward(_stroke, 0.0, 4.0 * delta)
	rig.hand_rest = hand_rest()
	rig.stroke_dir = (global_transform.basis * Vector3(0.05, -0.4, 1.0)).normalized()
	rig.stroke = _stroke
	rig.grip = grip
	if character:
		character.right_hand_target = rig.hand_position()
		character.line_tension = rig.tension
		character.reel_speed = rig.reel_rate - rig.feed_speed
