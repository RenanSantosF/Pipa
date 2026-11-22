class_name HUD
extends Control
## Interface mínima: vento, linha (voando / no chão / tipo), tensão e desgaste,
## e mensagens curtas. Tudo discreto, longe das áreas de gesto.

@onready var wind_indicator: WindIndicator = $WindIndicator
@onready var line_label: Label = $LinePanel/LineLabel
@onready var tension_bar: ProgressBar = $LinePanel/TensionBar
@onready var wear_bar: ProgressBar = $LinePanel/WearBar
@onready var type_label: Label = $LinePanel/TypeLabel
@onready var message: Label = $Message
@onready var debug_overlay: DebugOverlay = $DebugOverlay

var rig: KiteRig
var world: KitePhysicsWorld
var _message_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.modulate.a = 0.0
	EventBus.line_snapped.connect(_on_line_snapped)
	EventBus.line_cut.connect(_on_line_cut)
	EventBus.kite_crashed.connect(_on_kite_crashed)


func setup(p_rig: KiteRig, p_world: KitePhysicsWorld) -> void:
	rig = p_rig
	world = p_world
	debug_overlay.rig = p_rig
	debug_overlay.world = p_world


func _on_line_snapped(_pos: Vector3) -> void:
	show_message("A linha arrebentou na mão!")


func _on_line_cut(winner: Node, loser: Node) -> void:
	if winner == rig:
		show_message("CORTOU! Mandou a pipa do vizinho.")
	elif loser == rig:
		var near_hand := rig.rope != null and rig.rope.length() < 8.0
		show_message("Te cortaram!" + (" Foi na mão!" if near_hand else "") + "\nRecolha a linha ou toque em NOVA.")


func _on_kite_crashed(_pos: Vector3) -> void:
	if rig and rig.is_flying() and rig.body.resting:
		show_message("A pipa enroscou! Dê linha ou puxe.", 2.0)


func show_message(text: String, duration: float = 4.0) -> void:
	message.text = text
	_message_time = duration


func _process(delta: float) -> void:
	if rig:
		var flying := rig.flying_length()
		var txt := "Linha %d m" % roundi(flying)
		if rig.pile > 0.5:
			txt += "  ·  no chão %d m" % roundi(rig.pile)
		txt += "  ·  lata %d m" % roundi(rig.spool)
		line_label.text = txt
		type_label.text = rig.line_type.display_name + ("  (rabiola c/ cerol)" if rig.profile.tail_abrasion > 0.0 else "")
		tension_bar.max_value = rig.line_type.break_tension
		tension_bar.value = rig.tension
		var danger := rig.tension / rig.line_type.break_tension
		tension_bar.modulate = Color(1, 1, 1).lerp(Color(1, 0.3, 0.2), clampf((danger - 0.5) * 2.0, 0.0, 1.0))
		var w := LineCombat.max_wear(rig)
		wear_bar.value = clampf(w, 0.0, 1.0)
		wear_bar.visible = w > 0.01
	if _message_time > 0.0:
		_message_time -= delta
		message.modulate.a = clampf(_message_time, 0.0, 1.0)
