class_name GestureControls
extends Control
## Controles por GESTOS, quase sem interface:
##
##   TOQUE na metade ESQUERDA  → desbico para a esquerda
##   TOQUE na metade DIREITA   → desbico para a direita
##   DOIS TOQUES rápidos       → desbicada dupla (lado do 1º toque → oposto)
##   Arrastar para BAIXO (lado direito) → braçada longa
##   Arrastar para CIMA  (lado direito) → abrir a mão / dar linha
##   CÍRCULOS            (lado direito) → enrolar na lata
##   Arrastar na faixa de cima          → olhar (volta para a pipa sozinha)
##   Joystick flutuante  (canto esquerdo de baixo) → andar
##   Ícones no canto: nova pipa · trocar linha · som · tamanho · envergadura

signal reset_pressed
signal menu_pressed
signal sound_pressed
signal size_pressed
signal bow_pressed

const STROKE_MAX := 0.75
const STROKE_PX := 230.0
const RELEASE_PX := 130.0
const LOOK_ZONE := 0.3
const MOVE_ZONE_X := 0.35
const MOVE_ZONE_Y := 0.45
const TAP_TIME := 1.2
const TAP_MOVE := 26.0
const SPOOL_RADIUS := 0.06
const REEL_GAIN := 1.6
const REEL_MAX := 4.5
const ICON_R := 24.0

@onready var joystick: TouchJoystick = $Joystick

var intent: PlayerIntent
var touch_enabled: bool = false
var line_color := Color.WHITE
var sound_on: bool = true

var _joy_index: int = -1
var _look_index: int = -1
var _line_index: int = -1
var _starts: Dictionary = {}   # índice -> [tempo, posição, deslocamento máx]
var _icon_down: Dictionary = {}

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
var _taps_fx: Array = []       # [posição, idade]
var _tap_index: int = -1
## Rótulos curtos dos ícones de tamanho/envergadura (atualizados pelo Main).
var size_label: String = "M"
var bow_level: int = 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_enabled = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_enabled


func _icons() -> Array:
	var y := ICON_R + 16.0
	var x := size.x - ICON_R - 16.0
	return [["reset", Vector2(x, y)], ["line", Vector2(x - ICON_R * 2.5, y)], ["sound", Vector2(x - ICON_R * 5.0, y)],
		["size", Vector2(x, y + ICON_R * 2.5)], ["bow", Vector2(x - ICON_R * 2.5, y + ICON_R * 2.5)]]


func _icon_at(pos: Vector2) -> String:
	for ic in _icons():
		if (ic[1] as Vector2).distance_to(pos) < ICON_R * 1.25:
			return ic[0]
	return ""


func _input(event: InputEvent) -> void:
	if not visible or intent == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_down(st.index, st.position)
		else:
			_up(st.index, st.position)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _starts.has(sd.index):
			var info: Array = _starts[sd.index]
			info[2] = maxf(info[2], (sd.position - (info[1] as Vector2)).length())
			if sd.index == _tap_index and float(info[2]) >= TAP_MOVE:
				if _time - float(info[0]) < 0.15:
					intent.cancel_desbico = true  # virou arrasto logo: aborta o desbico
				_tap_index = -1
		if sd.index == _joy_index:
			joystick.move(sd.position)
		elif sd.index == _look_index:
			intent.look_delta += sd.relative * GameConfig.touch_sensitivity
			intent.look_active = true
		elif sd.index == _line_index:
			_line_drag(sd.position)


func _down(index: int, pos: Vector2) -> void:
	var ic := _icon_at(pos)
	if ic != "":
		_icon_down[index] = ic
		queue_redraw()
		return
	_starts[index] = [_time, pos, 0.0]
	var is_joy := pos.x < size.x * MOVE_ZONE_X and pos.y > size.y * MOVE_ZONE_Y
	if not is_joy:
		# Desbico na hora do toque (resposta imediata): lado = metade da tela.
		intent.taps.append(-1.0 if pos.x < size.x * 0.5 else 1.0)
		_taps_fx.append([pos, 0.0])
		_tap_index = index
	if is_joy:
		if _joy_index == -1:
			_joy_index = index
			joystick.begin(pos)
	elif pos.y < size.y * LOOK_ZONE or pos.x < size.x * 0.5:
		if _look_index == -1:
			_look_index = index
	elif _line_index == -1:
		_line_index = index
		_origin = pos
		_finger = pos
		_mode = ""
		_samples.clear()
		_sample_times.clear()
		_turn_accum = 0.0
		_last_dir = Vector2.ZERO
		_reel_omega = 0.0


func _up(index: int, pos: Vector2) -> void:
	if _icon_down.has(index):
		var ic: String = _icon_down[index]
		_icon_down.erase(index)
		if _icon_at(pos) == ic:
			match ic:
				"reset":
					reset_pressed.emit()
				"line":
					menu_pressed.emit()
				"sound":
					sound_pressed.emit()
				"size":
					size_pressed.emit()
				"bow":
					bow_pressed.emit()
		queue_redraw()
		return
	_starts.erase(index)
	if index == _tap_index:
		_tap_index = -1
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


func _line_drag(pos: Vector2) -> void:
	var move := pos - _finger
	_finger = pos
	_samples.append(pos)
	_sample_times.append(_time)
	while _samples.size() > 24 or (_sample_times.size() > 0 and _time - _sample_times[0] > 1.0):
		_samples.remove_at(0)
		_sample_times.remove_at(0)
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
		_reel_omega = lerpf(_reel_omega, absf(da) / maxf(get_process_delta_time(), 0.001), 0.3)
		return
	var dy := pos.y - _origin.y
	if (pos - _origin).length() < TAP_MOVE * 0.6:
		return
	if dy >= 0.0:
		_mode = "puxar"
		intent.stroke = clampf(dy / STROKE_PX, 0.0, 1.0) * STROKE_MAX
		intent.grip = 1.0
	else:
		_mode = "soltar"
		intent.stroke = 0.0
		intent.grip = 1.0 - clampf(-dy / RELEASE_PX, 0.0, 1.0)


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
		_reel_omega = lerpf(_reel_omega, 0.0, 1.0 - exp(-3.0 * delta))
		intent.reel_rate = clampf(_reel_omega * SPOOL_RADIUS * REEL_GAIN, 0.0, REEL_MAX)
		intent.stroke = 0.0
		intent.grip = 1.0
	intent.gesture_mode = _mode if _line_index != -1 else ""
	for fx in _taps_fx:
		fx[1] += delta
	_taps_fx = _taps_fx.filter(func(fx) -> bool: return fx[1] < 0.35)
	queue_redraw()


func get_move() -> Vector2:
	return Vector2(joystick.output.x, -joystick.output.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		for idx in [_joy_index, _look_index, _line_index]:
			if idx != -1:
				_up(idx, Vector2(-999, -999))


func _draw() -> void:
	# Ícones (canto superior direito).
	for ic in _icons():
		var c: Vector2 = ic[1]
		var pressed := _icon_down.values().has(ic[0])
		Icons.glass_circle(self, c, ICON_R, pressed)
		match ic[0]:
			"reset":
				Icons.kite(self, c + Vector2(-2, -1), ICON_R * 0.42, Icons.INK, 1.6)
				Icons.refresh(self, c + Vector2(6, 6), ICON_R * 0.28, Icons.ACCENT, 1.8)
			"line":
				Icons.spool(self, c + Vector2(-2, 2), ICON_R * 0.42, line_color, Icons.INK, 1.6)
			"sound":
				Icons.speaker(self, c, ICON_R * 0.42, sound_on, Icons.INK, 1.6)
			"size":
				Icons.kite(self, c + Vector2(-5, -1), ICON_R * (0.26 + 0.07 * float("PMG".find(size_label))), Icons.INK, 1.6)
				draw_string(ThemeDB.fallback_font, c + Vector2(5, 12), size_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Icons.ACCENT)
			"bow":
				Icons.bow(self, c, ICON_R * 0.5, bow_level, Icons.INK, 1.8)
	# Dicas de gesto nos primeiros segundos (só ícones).
	if _time < 7.0:
		var a := clampf(1.0 - (_time - 4.0) / 3.0, 0.0, 1.0) * 0.75
		var col := Color(1, 1, 1, a)
		var base := Vector2(size.x * 0.72, size.y * 0.62)
		Icons.tap(self, base, 26.0, col)
		Icons.tap(self, Vector2(size.x * 0.28, size.y * 0.4), 26.0, col)
		Icons.arrow(self, Vector2(size.x * 0.28 - 20, size.y * 0.4 - 50), Vector2(size.x * 0.28 - 70, size.y * 0.4 - 50), col)
		Icons.arrow(self, base + Vector2(20, -50), base + Vector2(70, -50), col)
		Icons.arrow(self, base + Vector2(70, 10), base + Vector2(70, -45), Color(0.55, 0.85, 1.0, a))
		Icons.arrow(self, base + Vector2(110, -45), base + Vector2(110, 10), Color(1.0, 0.82, 0.35, a))
		draw_arc(base + Vector2(165, -18), 22.0, 0.0, TAU * 0.8, 20, Color(0.6, 1.0, 0.55, a), 2.5, true)
	# Toques: onda curta onde tocou.
	for fx in _taps_fx:
		var t: float = fx[1] / 0.35
		draw_arc(fx[0], 12.0 + 40.0 * t, 0.0, TAU, 32, Color(1, 1, 1, 0.5 * (1.0 - t)), 2.5, true)
	if _line_index == -1 or _mode == "":
		return
	var colm := Color(1, 1, 1, 0.5)
	match _mode:
		"puxar":
			colm = Color(1.0, 0.82, 0.35, 0.7)
		"soltar":
			colm = Color(0.55, 0.85, 1.0, 0.7)
		"enrolar":
			colm = Color(0.6, 1.0, 0.55, 0.7)
	if _mode == "enrolar":
		draw_arc(_finger, 34.0, _reel_angle, _reel_angle + 4.5, 24, colm, 3.0, true)
	else:
		draw_line(_origin, _finger, colm, 3.0, true)
		draw_circle(_finger, 14.0, Color(colm, 0.25))
