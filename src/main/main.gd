extends Node3D
## Cena principal: liga os sistemas (injeção de dependências). A lógica fica nos módulos.

const LINE_TYPES := [
	"res://src/physics/lines/pura.tres",
	"res://src/physics/lines/rapinha.tres",
	"res://src/physics/lines/cerol.tres",
	"res://src/physics/lines/cerol_fino.tres",
	"res://src/physics/lines/chilena.tres",
]

@export var start_line_length: float = 30.0
@export var start_elevation_deg: float = 50.0

@onready var physics_world: KitePhysicsWorld = $KitePhysicsWorld
@onready var player: FPController = $Player
@onready var player_rig: KiteRig = $PlayerRig
@onready var bot: BotFlyer = $Bot
@onready var bot_rig: KiteRig = $BotRig
@onready var input_router: InputRouter = $InputRouter
@onready var gestures: GestureControls = $UI/GestureControls
@onready var hud: HUD = $UI/HUD
@onready var audio: AudioDirector = $AudioDirector

var _line_index: int = 2


func _ready() -> void:
	input_router.set_gesture_controls(gestures)
	input_router.line_cycle_requested.connect(_cycle_line)
	player.input_router = input_router
	player.rig = player_rig
	player_rig.is_local_player = true
	physics_world.register(player_rig)
	physics_world.register(bot_rig)
	bot.rig = bot_rig
	bot.target = player_rig
	bot.world = physics_world
	hud.setup(player_rig, physics_world)
	audio.world = physics_world
	audio.player_rig = player_rig
	EventBus.reset_requested.connect(reset_kite)
	EventBus.line_cut.connect(_on_line_cut)

	var args := OS.get_cmdline_user_args()
	if args.has("--autotest"):
		_attach("res://src/main/autotest.gd")
		return
	reset_kite()
	bot.launch()
	if args.has("--screenshots"):
		_attach("res://src/main/screenshot_tour.gd")


func _attach(path: String) -> void:
	var n: Node = load(path).new()
	n.name = path.get_file().get_basename()
	add_child(n)
	n.call("start", self)


## Nova pipa no ar (com a linha atual) e câmera virada para ela.
func reset_kite() -> void:
	player_rig.launch(player.global_position + Vector3(0.2, 1.18, -0.3), start_line_length, start_elevation_deg, Wind.get_direction())
	player.look_at_point(player_rig.body.x)
	EventBus.kite_launched.emit()


func _cycle_line() -> void:
	_line_index = (_line_index + 1) % LINE_TYPES.size()
	player_rig.line_type = load(LINE_TYPES[_line_index])
	reset_kite()
	hud.show_message("Linha: " + player_rig.line_type.display_name, 1.5)


func _on_line_cut(winner: Node, loser: Node) -> void:
	if loser == player_rig or winner == player_rig:
		# Acompanha com o olhar a pipa que foi mandada.
		for r in physics_world.rigs:
			if r.loose and r.age < 0.5:
				player.watch_target = r
				player.watch_time = 5.0
