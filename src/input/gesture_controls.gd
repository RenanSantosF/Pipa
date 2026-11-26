class_name GestureControls
extends Control
## Controles por GESTOS (sem botões de jogo), como no Pipa Combate:
##
##   TOCAR (qualquer dedo)     → DESBICO: cada toque é uma puxadinha; o bico balança
##                               para um lado, alternando (1º esquerda, 2º direita…).
##                               Ritmo constante = segue reto balançando; pausa =
##                               o último balanço rende (1 ou 3 toques = esquerda,
##                               2 = direita).
##   SEGURAR E ARRASTAR        → GUIAR: arraste para onde o bico deve apontar (como um
##                               manche que nasce onde o dedo encostou).
##   ARRASTAR RÁPIDO P/ BAIXO  → PUXÃO: recolhe linha; ela acelera, sobe e chega perto,
##                               sem desbicar. Esfregar = mais braçadas.
##   Arrastar rápido p/ CIMA   → dar linha (abrir a mão)
##   2º dedo                   → toque = desbico; arrastar p/ baixo = puxão; arrasto
##                               lento = olhar em volta
##   Faixa estreita no topo → olhar em volta · Canto inferior esquerdo → andar

signal reset_pressed
signal menu_pressed
signal sound_pressed
signal size_pressed
signal bow_pressed
signal tail_pressed
signal lab_pressed
## Área da tela ocupada por um painel (os toques ali não comandam a pipa).
var blocked_rect := Rect2()

## Câmera: só a faixa de cima (fração da altura) — o resto é da pipa.
const LOOK_ZONE := 0.15
## Joystick: canto inferior esquerdo.
const MOVE_ZONE_X := 0.2
const MOVE_ZONE_Y := 0.6
## Classificação do gesto: toque = soltou rápido e quase sem mexer; guiar = segurou
## ou arrastou além disso (sem ser o arrasto vertical rápido do puxão).
const CLASSIFY_PX := 16.0
const TAP_TIME := 0.32
const TAP_PX := 38.0
const GUIDE_PX := 40.0
const GUIDE_HOLD := 0.24
## Dois toques dentro desta janela (s) = jogar para o lado.
const DOUBLE_WINDOW := 0.32
## Puxada contínua: dedo abaixo da origem (px) para começar / para o ritmo máximo.
const PULL_DEAD := 22.0
const PULL_FULL := 220.0
## Esfregar: descida mínima (px) e velocidade (px/s) para contar um puxão.
const SCRUB_PX := 38.0
const SCRUB_SPEED := 320.0
## Arrasto vertical que vira PUXÃO / DAR LINHA (e não guiar): distância e velocidade
## mínimas, e tempo máximo desde o toque para decidir.
const SWIPE_PX := 34.0
const SWIPE_SPEED := 420.0
const SWIPE_DECIDE := 0.22
## Esfregar no puxão: descida mínima para mais um puxão.
const SCRUB_PULL_PX := 36.0
var _second_mode: String = ""
var _second_index_last: int = -1
var _second_top: float = 0.0
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
var tail_level: int = 1

var _joy_index: int = -1
var _aux_t0: float = 0.0
var _aux_origin := Vector2.ZERO
var _look_index: int = -1
## Segundo dedo (toque = puxão; arrasto = câmera).
var _second_index: int = -1
var _second_origin := Vector2.ZERO
var _second_t0: float = 0.0
var _last_tap_t: float = -10.0
var _scrub_top: float = 0.0
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
		["size", Vector2(x - ICON_R * 7.5, y)], ["bow", Vector2(x - ICON_R * 10.0, y)], ["tail", Vector2(x - ICON_R * 12.5, y)], ["lab", Vector2(x - ICON_R * 15.0, y)]]


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
		elif sd.index == _second_index:
			_second_index_last = sd.index
			_second_drag(sd.position, sd.velocity)
		elif sd.index == _kite_index:
			_kite_drag(sd.position, sd.velocity)


func _down(index: int, pos: Vector2) -> void:
	if blocked_rect.has_point(pos):
		return
	var ic := _icon_at(pos)
	if ic != "":
		_icon_down[index] = ic
		_dirty = true
		return
	if pos.x < size.x * MOVE_ZONE_X and pos.y > size.y * MOVE_ZONE_Y:
		if _joy_index == -1:
			_joy_index = index
			joystick.begin(pos)
			_aux_t0 = _time
			_aux_origin = pos
		return
	# Faixa de cima = câmera.
	if pos.y < size.y * LOOK_ZONE:
		if _look_index == -1:
			_look_index = index
			_aux_t0 = _time
			_aux_origin = pos
		return
	# Segundo dedo com o primeiro na tela: puxão / dar linha (combinação).
	if _kite_index != -1:
		if _second_index == -1:
			_second_index = index
			_second_origin = pos
			_second_t0 = _time
			_second_mode = ""
			_second_top = pos.y
		return
	_kite_index = index
	_origin = pos
	_finger = pos
	_t0 = _time
	_scrub_top = pos.y
	# Ainda não se sabe: toque (desbico), segurar/arrastar (guiar) ou puxão.
	_mode = ""
	intent.guide_active = false
	intent.guide_vec = Vector2.ZERO
	intent.guide_finger = pos


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
				"tail":
					tail_pressed.emit()
				"lab":
					lab_pressed.emit()
		_dirty = true
		return
	if index == _joy_index:
		_joy_index = -1
		joystick.end()
		if _time - _aux_t0 < TAP_TIME and pos.distance_to(_aux_origin) < TAP_PX:
			_tap(pos)   # toque rápido no canto também desbica
	if index == _look_index:
		_look_index = -1
		intent.look_active = false
		if _time - _aux_t0 < TAP_TIME and pos.distance_to(_aux_origin) < TAP_PX:
			_tap(pos)
	if index == _second_index:
		_second_index = -1
		if _second_mode == "" and _time - _second_t0 < TAP_TIME and pos.distance_to(_second_origin) < TAP_PX:
			_tap(pos)   # toque do 2º dedo também é desbico (dá para alternar os polegares)
		if _second_mode == "soltar":
			intent.grip = 1.0
		intent.pull_held = false
		_second_mode = ""
		_dirty = true
	if index == _kite_index:
		_kite_index = -1
		if _mode == "" and _time - _t0 < TAP_TIME and pos.distance_to(_origin) < TAP_PX:
			_tap(pos)
		_mode = ""
		intent.guide_active = false
		intent.guide_vec = Vector2.ZERO
		intent.stroke = 0.0
		intent.grip = 1.0
		intent.reel_rate = 0.0
		intent.pull_held = false
		intent.pull_rate = 0.0
		intent.gesture_mode = ""
		_dirty = true


## Arrasto vertical rápido logo no começo = puxão (para baixo) ou dar linha (cima).
func _swipe_kind(origin: Vector2, pos: Vector2, velocity: Vector2, t0: float) -> String:
	var d := pos - origin
	if _time - t0 > SWIPE_DECIDE:
		return ""
	if absf(d.y) < SWIPE_PX or absf(d.y) < absf(d.x) * 1.4:
		return ""
	var spd := maxf(absf(velocity.y), absf(d.y) / maxf(_time - t0, 0.016))
	if spd < SWIPE_SPEED:
		return ""
	return "puxar" if d.y > 0.0 else "soltar"


## DESBICO: um toque = uma puxadinha.
func _tap(pos: Vector2) -> void:
	intent.desbico_toques += 1
	intent.desbico_times.append(Time.get_ticks_usec() / 1000000.0)
	_fx.append([pos, 0.0, Color(0.55, 0.85, 1.0)])
	_dirty = true


var _last_vel_y := 0.0


func _kite_drag(pos: Vector2, velocity: Vector2) -> void:
	_finger = pos
	_last_vel_y = velocity.y
	_dirty = true
	if _mode == "":
		var k := _swipe_kind(_origin, pos, velocity, _t0)
		if k != "":
			_mode = k
			intent.guide_active = false
			_scrub_top = pos.y
			if k == "puxar":
				_pull_from_swipe(pos)
			return
		var dist := pos.distance_to(_origin)
		if dist > GUIDE_PX or (_time - _t0 > GUIDE_HOLD and dist > CLASSIFY_PX):
			_start_guide()
		return
	if _mode == "guiar":
		intent.guide_vec = pos - _origin
		intent.guide_finger = pos
		return
	_vertical(pos, _origin, true)


func _start_guide() -> void:
	_mode = "guiar"
	intent.guide_active = true
	intent.guide_vec = _finger - _origin
	intent.guide_finger = _finger


## Puxar / dar linha com o dedo `pos` (comum ao 1º e ao 2º dedo).
func _vertical(pos: Vector2, origin: Vector2, first: bool) -> void:
	var mode := _mode if first else _second_mode
	var d := pos - origin
	if mode == "puxar":
		# Esfregar: cada nova descida grande = mais um puxão.
		var top := _scrub_top if first else _second_top
		if pos.y < top:
			top = pos.y
		elif pos.y - top > SCRUB_PULL_PX:
			# Esfregar mais rápido = braçadas mais longas e mais seguidas (puxa mais rápido).
			var spd := absf(_last_vel_y)
			intent.recolhe.append(clampf((pos.y - top) / 200.0 + spd / 2600.0, 0.3, 1.0))
			_fx.append([pos, 0.0, Color(1.0, 0.82, 0.35)])
			top = pos.y
		if first:
			_scrub_top = top
		else:
			_second_top = top
		# Segurando bem embaixo: continua puxando (mão sobre mão).
		intent.pull_held = d.y > PULL_FULL
		intent.pull_rate = clampf((d.y - PULL_FULL) / PULL_FULL, 0.0, 1.0)
	elif mode == "soltar":
		intent.grip = 1.0 - clampf(-d.y / RELEASE_PX, 0.0, 1.0)


func _pull_from_swipe(pos: Vector2) -> void:
	intent.recolhe.append(clampf((pos.y - _origin.y) / 200.0, 0.4, 1.0))
	_fx.append([pos, 0.0, Color(1.0, 0.82, 0.35)])


func _second_drag(pos: Vector2, velocity: Vector2) -> void:
	_last_vel_y = velocity.y
	if _second_mode == "":
		var k := _swipe_kind(_second_origin, pos, velocity, _second_t0)
		if k == "":
			if _time - _second_t0 > SWIPE_DECIDE and pos.distance_to(_second_origin) > CLASSIFY_PX * 2.0:
				# Arrasto lento do 2º dedo = olhar em volta.
				_second_index = -1
				if _look_index == -1:
					_look_index = _second_index_last
			return
		_second_mode = k
		_second_top = _second_origin.y
		if k == "puxar":
			intent.recolhe.append(clampf((pos.y - _second_origin.y) / 200.0, 0.4, 1.0))
			_fx.append([pos, 0.0, Color(1.0, 0.82, 0.35)])
			_second_top = pos.y
	_vertical(pos, _second_origin, false)


func _process(delta: float) -> void:
	_time += delta
	if intent == null:
		return
	intent.gesture_mode = _mode if _kite_index != -1 else ""
	# Segurou parado: vira guiar (o manche nasce ali; mexer o dedo dá a direção).
	if _kite_index != -1 and _mode == "" and _time - _t0 > GUIDE_HOLD:
		_start_guide()
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
		for idx in [_joy_index, _look_index, _kite_index, _second_index]:
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
			"tail":
				Icons.tail(self, c, ICON_R * 0.5, tail_level, Icons.INK)
			"lab":
				# Tubo de ensaio (área de testes do voo).
				draw_line(c + Vector2(-4, -10), c + Vector2(-4, 6), Icons.INK, 2.0, true)
				draw_line(c + Vector2(4, -10), c + Vector2(4, 6), Icons.INK, 2.0, true)
				draw_arc(c + Vector2(0, 6), 4.0, 0.0, PI, 10, Icons.INK, 2.0, true)
				draw_line(c + Vector2(-6, -10), c + Vector2(6, -10), Icons.INK, 2.0, true)
				draw_rect(Rect2(c + Vector2(-3, 0), Vector2(6, 6)), Icons.ACCENT)
	# Dicas nos primeiros segundos (só desenhos): toques = desbico, arrastar de cima
	# para baixo = puxe, de baixo para cima = dar linha.
	if _time < 9.0:
		var a := clampf(1.0 - (_time - 6.0) / 3.0, 0.0, 1.0) * 0.8
		var g := Vector2(size.x * 0.32, size.y * 0.55)
		Icons.tap(self, g, 24.0, Color(0.55, 0.85, 1.0, a))
		Icons.tap(self, g + Vector2(46, -10), 18.0, Color(0.55, 0.85, 1.0, a * 0.7))
		Icons.tap(self, g + Vector2(84, -16), 14.0, Color(0.55, 0.85, 1.0, a * 0.5))
		var pbase := Vector2(size.x * 0.7, size.y * 0.35)
		Icons.arrow(self, pbase, pbase + Vector2(0, 150), Color(1.0, 0.82, 0.35, a), 4.0)
		Icons.arrow(self, pbase + Vector2(70, 150), pbase + Vector2(70, 40), Color(0.55, 0.85, 1.0, a))
		draw_line(Vector2(0, size.y * LOOK_ZONE), Vector2(size.x * 0.6, size.y * LOOK_ZONE), Color(1, 1, 1, a * 0.35), 1.5, true)
	for fx in _fx:
		var t: float = fx[1] / 0.35
		var c2: Color = fx[2]
		draw_arc(fx[0], 12.0 + 40.0 * t, 0.0, TAU, 32, Color(c2, 0.6 * (1.0 - t)), 3.0, true)
	if _kite_index == -1 or _mode == "":
		return
	var colm := Color(1, 1, 1, 0.5)
	match _mode:
		"guiar":
			colm = Color(1, 1, 1, 0.75)
		"puxar":
			colm = Color(1.0, 0.82, 0.35, 0.7)
		"soltar":
			colm = Color(0.55, 0.85, 1.0, 0.7)
		"enrolar":
			colm = Color(0.6, 1.0, 0.55, 0.7)
	if _mode == "guiar":
		draw_arc(_origin, GUIDE_PX + 70.0, 0.0, TAU, 40, Color(1, 1, 1, 0.22), 2.0, true)
		draw_line(_origin, _finger, Color(1, 1, 1, 0.55), 3.0, true)
		draw_circle(_finger, 16.0, Color(1, 1, 1, 0.22))
	elif _mode == "enrolar":
		draw_arc(_finger, 34.0, _reel_angle, _reel_angle + 4.5, 24, colm, 3.0, true)
	else:
		draw_line(_origin, _finger, colm, 3.0, true)
		draw_circle(_finger, 14.0, Color(colm, 0.25))
