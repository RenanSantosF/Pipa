extends Node3D
## Cena principal da demonstração offline. Só faz a ligação entre os sistemas
## (injeção de dependências); a lógica fica em cada módulo.

@export var start_line_length: float = 25.0
@export var start_elevation_deg: float = 42.0

@onready var player: FPController = $Player
@onready var kite: KiteBody = $Kite
@onready var line: KiteLine = $KiteLine
@onready var line_renderer: LineRenderer = $LineRenderer
@onready var input_router: InputRouter = $InputRouter
@onready var touch_controls: TouchControls = $UI/TouchControls
@onready var hud: HUD = $UI/HUD


func _ready() -> void:
	input_router.set_touch_controls(touch_controls)

	player.input_router = input_router
	player.aim_target = kite

	line.hand = player.get_hand_anchor()
	line.input_router = input_router
	line.initial_length = start_line_length
	kite.line = line

	line_renderer.setup(line, kite)
	player.viewmodel.animator.line = line
	player.viewmodel.animator.kite = kite
	hud.setup(line, kite)

	EventBus.reset_requested.connect(reset_kite)
	reset_kite()

	if OS.get_cmdline_user_args().has("--autotest"):
		var test: Node = load("res://src/main/autotest.gd").new()
		test.name = "Autotest"
		add_child(test)
		test.call("start", kite, line, input_router)


## Nova pipa no ar, com linha inteira, e câmera virada para ela.
func reset_kite() -> void:
	line.reset(start_line_length)
	kite.place_in_air(line.anchor_position, line.length, start_elevation_deg)
	player.look_at_point(kite.global_position)
	EventBus.kite_launched.emit()
