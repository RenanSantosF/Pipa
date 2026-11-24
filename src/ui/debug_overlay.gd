class_name DebugOverlay
extends Label
## Depuração (F1 no PC): FPS, custo da física e estado da pipa.

var rig: KiteRig
var world: KitePhysicsWorld
var _accum: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 4)
	GameConfig.settings_changed.connect(_refresh_visibility)
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = GameConfig.show_debug
	set_process(visible)
	visibility_changed.connect(func() -> void: set_process(visible))


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.25 or not visible:
		return
	_accum = 0.0
	var t := "FPS %d  ·  física %.2f ms  ·  GFX %s" % [Engine.get_frames_per_second(), world.frame_ms if world else 0.0, GameConfig.quality_name()]
	if rig and rig.is_flying():
		var b := rig.body
		t += "\nAlt %.1f m · ar %.1f m/s · AoA %.0f° · tensão %.1f N · nós %d" % [b.x.y, b.airspeed, rad_to_deg(b.angle_of_attack), rig.tension, rig.rope.node_count()]
	if world:
		t += "\nContatos %d" % world.combat.contacts.size()
	text = t
