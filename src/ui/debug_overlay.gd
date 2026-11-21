class_name DebugOverlay
extends Label
## Informações de depuração (FPS, física da pipa). F1 alterna no PC.

var kite: KiteBody
var line: KiteLine
var _accum: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 4)
	GameConfig.settings_changed.connect(_refresh_visibility)
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = GameConfig.show_debug


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.25 or not visible:
		return
	_accum = 0.0
	var t := "FPS %d  |  GFX %s" % [Engine.get_frames_per_second(), GameConfig.quality_name()]
	if kite and line:
		t += "\nAltura %.1f m  |  Vel. ar %.1f m/s  |  AoA %.0f°" % [kite.get_altitude(), kite.airspeed, rad_to_deg(kite.angle_of_attack)]
		t += "\nTensão %.1f N  |  Esticada %.0f%%  |  Rumo %.0f°" % [line.tension, line.tautness * 100.0, rad_to_deg(kite.heading)]
	text = t
