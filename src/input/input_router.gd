class_name InputRouter
extends Node
## Junta toque (TouchControls) e teclado/mouse (testes no PC) em um PlayerIntent.

var touch_controls: TouchControls
var intent := PlayerIntent.new()
## Quando verdadeiro, a entrada dos dispositivos é ignorada e o intent é escrito
## por outro sistema (teste automático; no futuro, replays).
var autopilot: bool = false


func _ready() -> void:
	_register_default_actions()


func set_touch_controls(tc: TouchControls) -> void:
	touch_controls = tc
	if tc == null:
		return
	tc.look_dragged.connect(_on_touch_look)
	tc.reset_pressed.connect(_on_reset_pressed)
	tc.quality_pressed.connect(GameConfig.cycle_quality)


func _on_reset_pressed() -> void:
	EventBus.reset_requested.emit()


func _register_default_actions() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("kite_pull", [KEY_SPACE])
	_add_keys("kite_release", [KEY_E])
	_add_keys("kite_reel", [KEY_Q])
	_add_keys("kite_reset", [KEY_R])
	_add_keys("toggle_debug", [KEY_F1])
	_add_keys("cycle_quality", [KEY_F2])
	# Botão esquerdo do mouse também puxa (testes no PC).
	if not InputMap.has_action("kite_pull_mouse"):
		InputMap.add_action("kite_pull_mouse")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("kite_pull_mouse", mb)


func _add_keys(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not _is_touch_device():
			var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			intent.look_delta += mm.relative * GameConfig.mouse_sensitivity
	elif event.is_action_pressed("kite_reset"):
		EventBus.reset_requested.emit()
	elif event.is_action_pressed("toggle_debug"):
		GameConfig.show_debug = not GameConfig.show_debug
		GameConfig.settings_changed.emit()
	elif event.is_action_pressed("cycle_quality"):
		GameConfig.cycle_quality()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_touch_look(relative: Vector2) -> void:
	intent.look_delta += relative * GameConfig.touch_sensitivity


func _process(_delta: float) -> void:
	if autopilot:
		return
	var kb := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var touch_move := Vector2.ZERO
	var t_pull := false
	var t_release := false
	var t_reel := false
	if touch_controls and touch_controls.visible:
		touch_move = touch_controls.get_move()
		t_pull = touch_controls.is_pull_held()
		t_release = touch_controls.is_release_held()
		t_reel = touch_controls.is_reel_held()
	intent.move = (kb + touch_move).limit_length(1.0)
	var mouse_pull := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("kite_pull_mouse")
	intent.pull = t_pull or Input.is_action_pressed("kite_pull") or mouse_pull
	intent.release = t_release or Input.is_action_pressed("kite_release")
	intent.reel = t_reel or Input.is_action_pressed("kite_reel")


func _is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
