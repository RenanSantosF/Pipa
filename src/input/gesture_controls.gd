class_name GestureControls
extends Control
## Controles 100% por GESTOS (sem botões de jogo). Um dedo na área grande da tela:
##
##   TOQUE rápido              → PUXÃO (toques seguidos = puxões seguidos)
##   Arrastar para o LADO      → DESBICO para aquele lado: enquanto o dedo está fora
##                               do centro a mão dá linha e o bico vai GIRANDO para
##                               o lado (quanto mais longe, mais forte). Voltou ao
##                               centro ou soltou = retoma a linha (ela se firma).
##                               Desbica até o bico apontar e TOCA: ela vai pra lá.
##   Arranque para BAIXO       → puxão forte; continuar descendo = braçada (recolhe)
##   Arrastar para CIMA        → abrir a mão / dar linha
##   CÍRCULOS                  → enrolar na lata
##   Segundo dedo: TOQUE = puxão (desbica com um polegar, puxa com o outro);
##                 ARRASTAR = olhar em volta
##   Faixa estreita no topo → olhar em volta
##   Canto inferior esquerdo   → andar (joystick)
##   Ícones no canto           → nova pipa · linha · som · tamanho · envergadura

signal reset_pressed
signal menu_pressed
signal sound_pressed
signal size_pressed
signal bow_pressed

## Câmera: só a faixa de cima (fração da altura) — o resto é da pipa.
const LOOK_ZONE := 0.15
## Joystick: canto inferior esquerdo.
const MOVE_ZONE_X := 0.2
const MOVE_ZONE_Y := 0.6
## Classificação do gesto.
const CLASSIFY_PX := 16.0
const TAP_TIME := 0.28
const FLICK_SPEED := 650.0     # px/s para baixo = arranque (puxão forte)
## Desbico: deslocamento lateral (px) para intensidade máxima.
const DESBICO_PX := 150.0
const DESBICO_DEAD := 14.0
const STROKE_MAX := 0.75
const STROKE_PX := 230.0
const RELEASE_PX := 130.0
const SPOOL_RADIUS := 0.06
const REEL_GAIN := 1.6
const REEL_MAX := 4.5
const ICON_R := 24.0

@onready var joystick: TouchJoystick = $Joystick

var intent: PlayerIntent
var touch_enabled: bool = false
var line_color := Color.WHITE
var sound_on: bool = true
## Rótulos dos ícones de tamanho/envergadura (atualizados pelo Main).
var size_label: String = "M"
var bow_level: int = 1

var _joy_index: int = -1
var _look_index: int = -1
## Segundo dedo (toque = puxão; arrasto = câmera).
var _second_index: int = -1
var _second_origin := Vector2.ZERO
var _second_t0: float = 0.0
var _kite_index: int = -1
var _icon_down: Dictionary = {}
# Gesto da pipa (um dedo).
var _origin := Vector2.ZERO
var _finger := Vector2.ZERO
var _t0: float = 0.0
var _mode: String = ""          # "", "desbico", "puxar", "soltar", "enrolar"
var _desb_side: float = 0.0
var _samples: Array[Vector2] = []
var _sample_times: Array[float] = []
var _turn_accum: float = 0.0
var _last_dir := Vector2.ZERO
var _reel_angle: float = 0.0
var _reel_omega: float = 0.0
var _time: float = 0.0
var _fx: Array = []             # [posição, idade, cor]
var _dirty: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_enabled = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_enabled


func _icons() -> Array:
	var y := ICON_R + 16.0
	var x := size.x - ICON_R - 16.0
	return [["reset", Vector2(x, y)], ["line", Vector2(x - ICON_R * 2.5, y)], ["sound", Vector2(x - ICON_R * 5.0, y)],
		["size", Vector2(x - ICON_R * 7.5, y)], ["bow", Vector2(x - ICON_R * 10.0, y)]]


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
		if sd.index == _joy_index:
			joystick.move(sd.position)
		elif sd.index == _look_index:
			intent.look_delta += sd.relative * GameConfig.touch_sensitivity
			intent.look_active = true
		elif sd.index == _second_index and sd.position.distance_to(_second_origin) > CLASSIFY_PX:
			_second_index = -1
			if _look_index == -1:
				_look_index = sd.index
		elif sd.index == _kite_index:
			_kite_drag(sd.position, sd.velocity)


func _down(index: int, pos: Vector2) -> void:
	var ic := _icon_at(pos)
	if ic != "":
		_icon_down[index] = ic
		_dirty = true
		return
	if pos.x < size.x * MOVE_ZONE_X and pos.y > size.y * MOVE_ZONE_Y:
		if _joy_index == -1:
			_joy_index = index
			joystick.begin(pos)
		return
	# Faixa de cima = câmera.
	if pos.y < size.y * LOOK_ZONE:
		if _look_index == -1:
			_look_index = index
		return
	# Segundo dedo com o primeiro na pipa: toque rápido = PUXÃO (desbica com um
	# polegar e puxa com o outro); se arrastar, vira câmera.
	if _kite_index != -1:
		if _second_index == -1 and _look_index == -1:
			_second_index = index
			_second_origin = pos
			_second_t0 = _time
		return
	_kite_index = index
	_origin = pos
	_finger = pos
	_t0 = _time
	_mode = ""
	_desb_side = 0.0
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
		_dirty = true
		return
	if index == _joy_index:
		_joy_index = -1
		joystick.end()
	if index == _look_index:
		_look_index = -1
		intent.look_active = false
	if index == _second_index:
		_second_index = -1
		if _time - _second_t0 < TAP_TIME and pos.distance_to(_second_origin) < CLASSIFY_PX:
			intent.pull_taps += 1
			_fx.append([pos, 0.0, Color(1.0, 0.82, 0.35)])
			_dirty = true
	if index == _kite_index:
		if _mode == "" and _time - _t0 < TAP_TIME:
			# Toque rápido = puxão.
			intent.pull_taps += 1
			_fx.append([pos, 0.0, Color(1.0, 0.82, 0.35)])
		elif _mode == "desbico" and _desb_side != 0.0:
			intent.release_desbico()
		_kite_index = -1
		_mode = ""
		intent.stroke = 0.0
		intent.grip = 1.0
		intent.reel_rate = 0.0
		intent.gesture_mode = ""
		_dirty = true


func _kite_drag(pos: Vector2, velocity: Vector2) -> void:
	_finger = pos
	_samples.append(pos)
	_sample_times.append(_time)
	while _samples.size() > 24 or (_sample_times.size() > 0 and _time - _sample_times[0] > 1.0):
		_samples.remove_at(0)
		_sample_times.remove_at(0)
	var d := pos - _origin
	var move := pos - (_samples[_samples.size() - 2] if _samples.size() > 1 else _origin)
	if move.length() > 2.0:
		var dir := move.normalized()
		if _last_dir != Vector2.ZERO:
			_turn_accum += _last_dir.angle_to(dir)
		_last_dir = dir
	_dirty = true
	# Círculos viram "enrolar" de qualquer modo.
	if _mode != "enrolar" and absf(_turn_accum) > TAU * 0.8 and _path_extent() > 60.0:
		if _mode == "desbico" and _desb_side != 0.0:
			intent.release_desbico()
		_mode = "enrolar"
		_reel_angle = _angle_around_center(pos)
	if _mode == "enrolar":
		var ang := _angle_around_center(pos)
		var da := wrapf(ang - _reel_angle, -PI, PI)
		_reel_angle = ang
		_reel_omega = lerpf(_reel_omega, absf(da) / maxf(get_process_delta_time(), 0.001), 0.3)
		return
	if _mode == "":
		if d.length() < CLASSIFY_PX:
			return
		if absf(d.x) > absf(d.y) * 0.9:
			_mode = "desbico"
		elif d.y > 0.0:
			_mode = "puxar"
			if velocity.y > FLICK_SPEED or d.y / maxf(_time - _t0, 0.016) > FLICK_SPEED:
				intent.pull_taps += 1   # arranque para baixo: puxão na hora
				_fx.append([pos, 0.0, Color(1.0, 0.82, 0.35)])
		else:
			_mode = "soltar"
	match _mode:
		"desbico":
			# Lado e força pela distância do centro; volta ao centro = retoma.
			var off := d.x
			var side := signf(off) if absf(off) > DESBICO_DEAD else 0.0
			if side != _desb_side:
				if _desb_side != 0.0:
					intent.release_desbico()
				if side != 0.0:
					intent.press_desbico(side)
				_desb_side = side
			intent.desbico_intensity = clampf((absf(off) - DESBICO_DEAD) / (DESBICO_PX - DESBICO_DEAD), 0.25, 1.0)
		"puxar":
			intent.stroke = clampf(d.y / STROKE_PX, 0.0, 1.0) * STROKE_MAX
			intent.grip = 1.0
		"soltar":
			intent.stroke = 0.0
			intent.grip = 1.0 - clampf(-d.y / RELEASE_PX, 0.0, 1.0)


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
	if _kite_index != -1 and _mode == "enrolar":
		_reel_omega = lerpf(_reel_omega, 0.0, 1.0 - exp(-3.0 * delta))
		intent.reel_rate = clampf(_reel_omega * SPOOL_RADIUS * REEL_GAIN, 0.0, REEL_MAX)
		intent.stroke = 0.0
		intent.grip = 1.0
	intent.gesture_mode = _mode if _kite_index != -1 else ""
	for fx in _fx:
		fx[1] += delta
	if not _fx.is_empty():
		_fx = _fx.filter(func(fx) -> bool: return fx[1] < 0.35)
		_dirty = true
	# Só redesenha quando algo muda (no celular cada redesenho custa CPU).
	if _dirty or _time < 9.0 or _kite_index != -1:
		_dirty = false
		queue_redraw()


func get_move() -> Vector2:
	return Vector2(joystick.output.x, -joystick.output.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		for idx in [_joy_index, _look_index, _kite_index]:
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
	# Dicas de gesto nos primeiros segundos (só desenhos): toque = puxão,
	# arrastar para o lado = desbico, cima = dar linha, círculo = enrolar.
	if _time < 9.0:
		var a := clampf(1.0 - (_time - 6.0) / 3.0, 0.0, 1.0) * 0.8
		var col := Color(1, 1, 1, a)
		var base := Vector2(size.x * 0.55, size.y * 0.58)
		Icons.tap(self, base, 24.0, Color(1.0, 0.82, 0.35, a))
		Icons.arrow(self, base + Vector2(-40, 0), base + Vector2(-120, 0), col)
		Icons.arrow(self, base + Vector2(40, 0), base + Vector2(120, 0), col)
		Icons.arrow(self, base + Vector2(0, -40), base + Vector2(0, -105), Color(0.55, 0.85, 1.0, a))
		draw_arc(base + Vector2(190, -10), 22.0, 0.0, TAU * 0.8, 20, Color(0.6, 1.0, 0.55, a), 2.5, true)
		draw_line(Vector2(0, size.y * LOOK_ZONE), Vector2(size.x * 0.6, size.y * LOOK_ZONE), Color(1, 1, 1, a * 0.35), 1.5, true)
	for fx in _fx:
		var t: float = fx[1] / 0.35
		var c2: Color = fx[2]
		draw_arc(fx[0], 12.0 + 40.0 * t, 0.0, TAU, 32, Color(c2, 0.6 * (1.0 - t)), 3.0, true)
	if _kite_index == -1 or _mode == "":
		return
	var colm := Color(1, 1, 1, 0.5)
	match _mode:
		"desbico":
			colm = Color(1, 1, 1, 0.75)
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
