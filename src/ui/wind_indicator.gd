class_name WindIndicator
extends Control
## Indicador de vento discreto: seta relativa à direção da câmera + velocidade.

var camera: Camera3D
var _speed: float = 0.0
var _arrow := Vector2.UP


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return
	var local := camera.global_basis.inverse() * Wind.get_direction()
	var v := Vector2(local.x, local.z)
	if v.length() > 0.01:
		_arrow = v.normalized()
	_speed = Wind.get_reference_speed()
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var c := Vector2(r + 4.0, r + 4.0)
	draw_circle(c, r, Color(0, 0, 0, 0.3))
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 1.5, true)
	var tip := c + _arrow * r * 0.75
	var tail := c - _arrow * r * 0.55
	var perp := Vector2(-_arrow.y, _arrow.x)
	var width := clampf(_speed / 12.0, 0.25, 1.0) * r * 0.35
	draw_line(tail, tip, Color(1, 1, 1, 0.9), 2.5, true)
	draw_colored_polygon(PackedVector2Array([tip, tip - _arrow * width * 1.4 + perp * width, tip - _arrow * width * 1.4 - perp * width]), Color(1, 1, 1, 0.9))
	var font := ThemeDB.fallback_font
	var text := "%.1f m/s" % _speed
	draw_string(font, Vector2(c.x + r + 8.0, c.y + 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
