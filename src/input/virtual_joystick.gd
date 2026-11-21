class_name VirtualJoystick
extends Control
## Joystick dinâmico: aparece onde o polegar toca. Só desenha e calcula o vetor;
## o roteamento dos toques (multitoque) é feito por TouchControls.

@export var radius: float = 85.0
@export_range(0.0, 0.5) var dead_zone: float = 0.12
@export var rest_margin: Vector2 = Vector2(150, 150)

## Saída em coordenadas de tela (y para baixo), comprimento <= 1.
var output: Vector2 = Vector2.ZERO
var active: bool = false

var _center: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin(screen_pos: Vector2) -> void:
	active = true
	_center = screen_pos - global_position
	_knob = _center
	output = Vector2.ZERO
	queue_redraw()


func move(screen_pos: Vector2) -> void:
	if not active:
		return
	var d := (screen_pos - global_position) - _center
	if d.length() > radius:
		d = d.normalized() * radius
	_knob = _center + d
	var v := d / radius
	var l := v.length()
	if l < dead_zone:
		output = Vector2.ZERO
	else:
		output = v / l * ((l - dead_zone) / (1.0 - dead_zone))
	queue_redraw()


func end() -> void:
	active = false
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := _center
	var k := _knob
	var alpha := 0.55
	if not active:
		c = Vector2(rest_margin.x, size.y - rest_margin.y)
		k = c
		alpha = 0.25
	draw_circle(c, radius, Color(0, 0, 0, alpha * 0.5))
	draw_arc(c, radius, 0.0, TAU, 48, Color(1, 1, 1, alpha), 2.5, true)
	draw_circle(k, radius * 0.42, Color(1, 1, 1, alpha * 0.9))
