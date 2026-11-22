class_name GestureControls
extends Control
## Controles por GESTOS (sem botões de ação). O dedo é a mão da linha:
##
##   Faixa de cima (30%)        → arrastar = olhar em volta (a câmera volta
##                                 sozinha para a pipa, como uma mola, ao soltar)
##   Esquerda (40%)             → joystick flutuante para andar
##   Direita (60%), mão da linha:
##      arrastar PARA BAIXO     → braçada (puxar). Distância = tamanho da braçada,
##                                velocidade do dedo = velocidade do puxão.
##                                Soltar o dedo = mão volta (linha vai pro chão).
##      arrastar PARA CIMA      → abrir a mão (dar linha). Quanto mais alto,
##                                mais solta; a linha corre com a força da pipa.
##      fazer CÍRCULOS          → enrolar na lata (recolher). Rodar mais rápido
##                                = enrolar mais rápido.
##   Mais de um dedo funciona ao mesmo tempo (andar + puxar + olhar).

signal reset_pressed
signal menu_pressed

const STROKE_MAX := 0.75          # m
const STROKE_PX := 230.0          # px de arrasto para a braçada completa
const RELEASE_PX := 130.0         # px para cima para abrir a mão toda
const LOOK_ZONE := 0.28
const MOVE_ZONE := 0.4
const SPOOL_RADIUS := 0.06        # m (lata)
const REEL_GAIN := 1.6
const REEL_MAX := 4.5             # m/s

@onready var joystick: TouchJoystick = $Joystick
@onready var reset_button: TouchButton = $ResetButton
@onready var menu_button: TouchButton = $MenuButton

var intent: PlayerIntent
var touch_enabled: bool = false

var _joy_index: int = -1
var _look_index: int = -1
var _line_index: int = -1
var _button_index: Dictionary = {}

# Gesto da linha.
var _origin := Vector2.ZERO
var _finger := Vector2.ZERO
var _mode: String = ""
var _samples: Array[Vector2] = []
var _sample_times: Array[float] = []
var _turn_accum: float = 0.0
var _last_dir := Vector2.ZERO
var _reel_angle: float = 0.0
var _reel_omega: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_enabled = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_enabled
	reset_button.pressed.connect(func() -> void: reset_pressed.emit())
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())


func _input(event: InputEvent) -> void:
	if not visible or intent == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_down(st.index, st.position)
		else:
			_up(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_index:
			joystick.move(sd.position)
		elif sd.index == _look_index:
			intent.look_delta += sd.relative * GameConfig.touch_sensitivity
		elif sd.index == _line_index:
			_line_drag(sd.position)


func _down(index: int, pos: Vector2) -> void:
	for b: TouchButton in [reset_button, menu_button]:
		if b.visible and b.contains_point(pos):
			_button_index[index] = b
			b.held = true
			return
	if pos.y < size.y * LOOK_ZONE:
		if _look_index == -1:
			_look_index = index
			intent.look_active = true
	elif pos.x < size.x * MOVE_ZONE:
		if _joy_index == -1:
			_joy_index = index
			joystick.begin(pos)
	elif _line_index == -1:
		_line_index = index
		_origin = pos
		_finger = pos
		_mode = "segurar"
		_samples.clear()
		_sample_times.clear()
		_turn_accum = 0.0
		_last_dir = Vector2.ZERO
		_reel_omega = 0.0


func _up(index: int) -> void:
	if _button_index.has(index):
		(_button_index[index] as TouchButton).held = false
		_button_index.erase(index)
	if index == _joy_index:
		_joy_index = -1
		joystick.end()
	if index == _look_index:
		_look_index = -1
		intent.look_active = false
	if index == _line_index:
		_line_index = -1
		_mode = ""
		intent.stroke = 0.0
		intent.grip = 1.0
		intent.reel_rate = 0.0
		intent.gesture_mode = ""
	queue_redraw()


func _line_drag(pos: Vector2) -> void:
	var move := pos - _finger
	_finger = pos
	_samples.append(pos)
	_sample_times.append(_time)
	while _samples.size() > 24 or (_sample_times.size() > 0 and _time - _sample_times[0] > 1.0):
		_samples.remove_at(0)
		_sample_times.remove_at(0)
	# Detecção de círculo: soma das mudanças de direção do traço.
	if move.length() > 2.0:
		var dir := move.normalized()
		if _last_dir != Vector2.ZERO:
			_turn_accum += _last_dir.angle_to(dir)
		_last_dir = dir
	if _mode != "enrolar" and absf(_turn_accum) > TAU * 0.8 and _path_extent() > 60.0:
		_mode = "enrolar"
		_reel_angle = _angle_around_center(pos)
	if _mode == "enrolar":
		var ang := _angle_around_center(pos)
		var da := wrapf(ang - _reel_angle, -PI, PI)
		_reel_angle = ang
		var dt := maxf(get_process_delta_time(), 0.001)
		_reel_omega = lerpf(_reel_omega, absf(da) / dt, 0.3)
		return
	var dy := pos.y - _origin.y
	if dy >= 0.0:
		_mode = "puxar" if dy > 8.0 else "segurar"
		intent.stroke = clampf(dy / STROKE_PX, 0.0, 1.0) * STROKE_MAX
		intent.grip = 1.0
	else:
		_mode = "soltar"
		intent.stroke = 0.0
		intent.grip = 1.0 - clampf(-dy / RELEASE_PX, 0.0, 1.0)
	queue_redraw()


func _path_extent() -> float:
	if _samples.size() < 4:
		return 0.0
	var mn := _samples[0]
	var mx := _samples[0]
	for p in _samples:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return (mx - mn).length()


func _angle_around_center(pos: Vector2) -> float:
	var c := Vector2.ZERO
	for p in _samples:
		c += p
	c /= maxf(float(_samples.size()), 1.0)
	return (pos - c).angle()


func _process(delta: float) -> void:
	_time += delta
	if intent == null:
		return
	if _line_index != -1 and _mode == "enrolar":
		_reel_omega = lerpf(_reel_omega, 0.0, 1.0 - exp(-3.0 * delta))  # parou de girar → para
		intent.reel_rate = clampf(_reel_omega * SPOOL_RADIUS * REEL_GAIN, 0.0, REEL_MAX)
		intent.stroke = 0.0
		intent.grip = 1.0
	intent.gesture_mode = _mode if _line_index != -1 else ""
	if visible:
		queue_redraw()


func get_move() -> Vector2:
	return Vector2(joystick.output.x, -joystick.output.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		for idx in [_joy_index, _look_index, _line_index]:
			if idx != -1:
				_up(idx)


func _draw() -> void:
	# Guia sutil das zonas (só nos primeiros segundos).
	if _time < 6.0:
		var a := clampf(1.0 - (_time - 3.0) / 3.0, 0.0, 1.0) * 0.5
		var font := ThemeDB.fallback_font
		draw_line(Vector2(0, size.y * LOOK_ZONE), Vector2(size.x, size.y * LOOK_ZONE), Color(1, 1, 1, a * 0.3), 1.0)
		draw_line(Vector2(size.x * MOVE_ZONE, size.y * LOOK_ZONE), Vector2(size.x * MOVE_ZONE, size.y), Color(1, 1, 1, a * 0.3), 1.0)
		draw_string(font, Vector2(size.x * 0.5 - 90, size.y * LOOK_ZONE * 0.5), "arraste para olhar", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, a))
		draw_string(font, Vector2(size.x * 0.12, size.y * 0.7), "andar", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, a))
		draw_string(font, Vector2(size.x * 0.62, size.y * 0.55), "↓ puxar   ↑ dar linha   ⟳ enrolar", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, a))
	if _line_index == -1:
		return
	var col := Color(1, 1, 1, 0.5)
	match _mode:
		"puxar":
			col = Color(1.0, 0.85, 0.35, 0.7)
		"soltar":
			col = Color(0.5, 0.85, 1.0, 0.7)
		"enrolar":
			col = Color(0.6, 1.0, 0.55, 0.7)
	draw_circle(_origin, 10.0, Color(col, 0.35))
	if _mode == "enrolar":
		draw_arc(_finger, 34.0, _reel_angle, _reel_angle + 4.5, 24, col, 3.0, true)
	else:
		draw_line(_origin, _finger, col, 3.0, true)
	draw_circle(_finger, 16.0, Color(col, 0.25))
