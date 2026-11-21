class_name TouchButton
extends Control
## Botão redondo de toque com estado "segurando". Não recebe eventos sozinho:
## TouchControls decide qual toque pertence a qual botão (multitoque confiável).

signal pressed
signal released

@export var label: String = "BOTÃO"
@export var accent: Color = Color(1, 1, 1)
@export var font_scale: float = 0.3

var held: bool = false:
	set(value):
		if held == value:
			return
		held = value
		queue_redraw()
		if held:
			pressed.emit()
		else:
			released.emit()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func contains_point(screen_pos: Vector2) -> bool:
	var r := minf(size.x, size.y) * 0.5 * 1.15  # área de toque um pouco maior que o desenho
	return get_global_rect().get_center().distance_to(screen_pos) <= r


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var fill := Color(accent, 0.45) if held else Color(0, 0, 0, 0.3)
	draw_circle(c, r, fill)
	draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(accent, 0.8), 3.0, true)
	var font := ThemeDB.fallback_font
	var fs := maxi(10, int(r * font_scale))
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.35), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
