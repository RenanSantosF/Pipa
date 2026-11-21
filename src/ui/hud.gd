class_name HUD
extends Control
## Interface discreta: vento, comprimento de linha, barra de tensão e mensagens.

@onready var wind_indicator: WindIndicator = $WindIndicator
@onready var line_label: Label = $LinePanel/LineLabel
@onready var tension_bar: ProgressBar = $LinePanel/TensionBar
@onready var message: Label = $Message
@onready var debug_overlay: DebugOverlay = $DebugOverlay

var line: KiteLine
var kite: KiteBody
var _message_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.modulate.a = 0.0
	EventBus.line_snapped.connect(_on_line_snapped)
	EventBus.kite_crashed.connect(_on_kite_crashed)


func setup(p_line: KiteLine, p_kite: KiteBody) -> void:
	line = p_line
	kite = p_kite
	debug_overlay.kite = p_kite
	debug_overlay.line = p_line
	tension_bar.max_value = p_line.break_tension


func _on_line_snapped(_pos: Vector3) -> void:
	show_message("A linha arrebentou!\nToque em NOVA (ou R) para outra pipa.")


func _on_kite_crashed(_pos: Vector3) -> void:
	if line and not line.is_broken:
		show_message("A pipa encostou! Puxe ou recolha a linha.", 2.0)


func show_message(text: String, duration: float = 4.0) -> void:
	message.text = text
	_message_time = duration


func _process(delta: float) -> void:
	if line:
		line_label.text = "Linha %d m" % roundi(line.length)
		tension_bar.value = line.tension
		var danger := line.tension / line.break_tension
		tension_bar.modulate = Color(1, 1, 1).lerp(Color(1, 0.3, 0.2), clampf((danger - 0.5) * 2.0, 0.0, 1.0))
	if _message_time > 0.0:
		_message_time -= delta
		message.modulate.a = clampf(_message_time, 0.0, 1.0)
