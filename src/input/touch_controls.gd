class_name TouchControls
extends Control
## Controles touch em paisagem com multitoque real (rastreamento por índice do dedo):
##  - metade esquerda (40%): joystick dinâmico;
##  - resto da tela: arrastar para olhar;
##  - botões: puxar, soltar, recolher, relançar e qualidade.

signal look_dragged(relative: Vector2)
signal reset_pressed
signal quality_pressed

@onready var joystick: VirtualJoystick = $Joystick
@onready var pull_button: TouchButton = $PullButton
@onready var release_button: TouchButton = $ReleaseButton
@onready var reel_button: TouchButton = $ReelButton
@onready var reset_button: TouchButton = $ResetButton
@onready var quality_button: TouchButton = $QualityButton

var _buttons: Array[TouchButton] = []
var _button_touch: Dictionary = {}  # índice do dedo -> TouchButton
var _joy_index: int = -1
var _look_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons = [pull_button, release_button, reel_button, reset_button, quality_button]
	reset_button.pressed.connect(func() -> void: reset_pressed.emit())
	quality_button.pressed.connect(func() -> void: quality_pressed.emit())
	visible = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_index:
			joystick.move(sd.position)
		elif sd.index == _look_index:
			look_dragged.emit(sd.relative)


func _touch_down(index: int, pos: Vector2) -> void:
	for b in _buttons:
		if b.visible and b.contains_point(pos):
			_button_touch[index] = b
			_refresh_buttons()
			return
	if pos.x < size.x * 0.4 and _joy_index == -1:
		_joy_index = index
		joystick.begin(pos)
	elif _look_index == -1:
		_look_index = index


func _touch_up(index: int) -> void:
	if _button_touch.has(index):
		_button_touch.erase(index)
		_refresh_buttons()
	if index == _joy_index:
		_joy_index = -1
		joystick.end()
	if index == _look_index:
		_look_index = -1


func _refresh_buttons() -> void:
	var held_buttons := _button_touch.values()
	for b in _buttons:
		b.held = held_buttons.has(b)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _release_all() -> void:
	_button_touch.clear()
	_refresh_buttons()
	_joy_index = -1
	_look_index = -1
	if joystick:
		joystick.end()


## Movimento em coordenadas do jogador (x = direita, y = frente).
func get_move() -> Vector2:
	return Vector2(joystick.output.x, -joystick.output.y)


func is_pull_held() -> bool:
	return pull_button.held


func is_release_held() -> bool:
	return release_button.held


func is_reel_held() -> bool:
	return reel_button.held
