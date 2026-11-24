class_name InputRouter
extends Node
## Junta gestos (GestureControls) e teclado/mouse (testes no PC) num PlayerIntent.
## Teclado/mouse: WASD anda · SEGURAR clique ESQUERDO / ← = desbico para a esquerda ·
## SEGURAR clique DIREITO / → = desbico para a direita (soltou = retoma a linha) ·
## Espaço = desbicada dupla · F = PUXÃO (toques seguidos; segurar = em série) ·
## botão do meio ou Tab prende o mouse para olhar · G segurado = braçada lenta ·
## E = abrir a mão (dar linha) · Q = enrolar · R = nova pipa · T = trocar linha ·
## Y = tamanho da pipa · U = envergadura · F1 debug · F2 qualidade.

signal line_cycle_requested
signal sound_toggle_requested

var gestures: GestureControls
var intent := PlayerIntent.new()
## Quando verdadeiro, o intent é escrito por outro sistema (teste automático).
var autopilot: bool = false

var _kb_stroke: float = 0.0


func _ready() -> void:
	_register_default_actions()


func set_gesture_controls(gc: GestureControls) -> void:
	gestures = gc
	if gc == null:
		return
	gc.intent = intent
	gc.reset_pressed.connect(func() -> void: EventBus.reset_requested.emit())
	gc.menu_pressed.connect(func() -> void: line_cycle_requested.emit())
	gc.sound_pressed.connect(func() -> void: sound_toggle_requested.emit())


func _register_default_actions() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A])
	_add_keys("move_right", [KEY_D])
	_add_keys("desbico_left", [KEY_LEFT, KEY_J])
	_add_keys("desbico_right", [KEY_RIGHT, KEY_L])
	_add_keys("desbico_double", [KEY_SPACE])
	_add_keys("mouse_look", [KEY_TAB])
	_add_keys("kite_size", [KEY_Y])
	_add_keys("kite_bow", [KEY_U])
	_add_keys("kite_puxao", [KEY_F])
	_add_keys("kite_pull", [KEY_G])
	_add_keys("kite_release", [KEY_E])
	_add_keys("kite_reel", [KEY_Q])
	_add_keys("kite_reset", [KEY_R])
	_add_keys("line_cycle", [KEY_T])
	_add_keys("toggle_debug", [KEY_F1])
	_add_keys("cycle_quality", [KEY_F2])


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
		if mb.pressed and not _is_touch_device():
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					intent.press_desbico(-1.0)
				MOUSE_BUTTON_RIGHT:
					intent.press_desbico(1.0)
				MOUSE_BUTTON_MIDDLE:
					_toggle_mouse()
		elif not mb.pressed and not _is_touch_device() and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			intent.release_desbico()
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			intent.look_delta += (event as InputEventMouseMotion).relative * GameConfig.mouse_sensitivity
	elif event.is_action_pressed("desbico_left") and not event.is_echo():
		intent.press_desbico(-1.0)
	elif event.is_action_pressed("desbico_right") and not event.is_echo():
		intent.press_desbico(1.0)
	elif event.is_action_released("desbico_left") or event.is_action_released("desbico_right"):
		intent.release_desbico()
	elif event.is_action_pressed("kite_puxao") and not event.is_echo():
		intent.pull_taps += 1
		intent.pull_held = true
	elif event.is_action_released("kite_puxao"):
		intent.pull_held = false
	elif event.is_action_pressed("desbico_double"):
		intent.desbico_toques += 1
	elif event.is_action_pressed("mouse_look"):
		_toggle_mouse()
	elif event.is_action_pressed("kite_size"):
		intent.size_cycle += 1
	elif event.is_action_pressed("kite_bow"):
		intent.bow_cycle += 1
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_J:
		intent.tail_cycle += 1
	elif event.is_action_pressed("kite_reset"):
		EventBus.reset_requested.emit()
	elif event.is_action_pressed("line_cycle"):
		line_cycle_requested.emit()
	elif event.is_action_pressed("toggle_debug"):
		GameConfig.show_debug = not GameConfig.show_debug
		GameConfig.settings_changed.emit()
	elif event.is_action_pressed("cycle_quality"):
		GameConfig.cycle_quality()


func _process(delta: float) -> void:
	if autopilot:
		return
	var kb := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var touch_move := gestures.get_move() if gestures and gestures.visible else Vector2.ZERO
	intent.move = (kb + touch_move).limit_length(1.0)
	if gestures and gestures.visible:
		return  # gestos escrevem stroke/grip/reel diretamente
	# Teclado: Espaço faz uma braçada contínua; soltar a tecla = mão volta.
	var pulling := Input.is_action_pressed("kite_pull")
	_kb_stroke = move_toward(_kb_stroke, 0.7 if pulling else 0.0, (3.0 if pulling else 6.0) * delta)
	intent.stroke = _kb_stroke
	intent.grip = 0.0 if Input.is_action_pressed("kite_release") else 1.0
	intent.reel_rate = 2.5 if Input.is_action_pressed("kite_reel") else 0.0
	intent.look_active = false
	intent.gesture_mode = "puxar" if pulling else ("soltar" if intent.grip < 0.5 else ("enrolar" if intent.reel_rate > 0.0 else ""))


func _toggle_mouse() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED


func _is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
