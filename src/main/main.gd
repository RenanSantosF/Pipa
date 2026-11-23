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
var bots: Array[BotFlyer] = []

const BOT_LINES := ["rapinha", "cerol", "cerol_fino", "chilena"]
const BOT_COLORS := [
	[Color(0.15, 0.4, 0.85), Color(0.95, 0.95, 0.92)], [Color(0.1, 0.6, 0.3), Color(0.98, 0.85, 0.1)],
	[Color(0.85, 0.2, 0.55), Color(0.2, 0.2, 0.25)], [Color(0.95, 0.5, 0.1), Color(0.3, 0.7, 0.95)],
]


func _bot_spots(street: StreetBuilder, center: Vector3, n: int) -> Array:
	var back := -Wind.get_direction()
	var out := []
	var angles := [-70.0, 35.0, -25.0, 75.0]
	var radii := [22.0, 18.0, 30.0, 26.0]
	for i in n:
		var best := Vector3.ZERO
		# Procura em volta do ponto planejado um lugar com o céu livre a favor do vento
		# (pipa sobe sem cair direto numa copa, fio ou casa).
		for tries in 24:
			var ang: float = angles[i % angles.size()] + (float(tries % 6) - 2.5) * 12.0
			var rad: float = radii[i % radii.size()] + float(tries / 6) * 6.0
			var d := back.rotated(Vector3.UP, deg_to_rad(ang))
			var p: Vector3 = center + d * rad
			p.y = street.obstacles.top_at(p.x, p.z) + 0.05
			if best == Vector3.ZERO:
				best = p
			if _sky_clear(street.obstacles, p):
				best = p
				break
		out.append(best)
	return out


## Céu livre a partir de p na direção do vento (subindo a ~45°) por 30 m?
func _sky_clear(obs: WorldObstacles, p: Vector3) -> bool:
	var d := (Wind.get_direction() * 0.7 + Vector3.UP * 0.7).normalized()
	for k in range(2, 31, 2):
		var q := p + Vector3.UP * 1.2 + d * float(k)
		for idx in obs.query(q):
			var e: Array = obs.entries[idx]
			match e[0]:
				WorldObstacles.Kind.CANOPY:
					if q.distance_to(e[1]) < float(e[2]) + 2.0:
						return false
				WorldObstacles.Kind.CAPSULE:
					var res := LineCombat.closest_segments(q, q, e[1], e[2])
					if float(res[2]) < float(e[3]) + 1.5:
						return false
				WorldObstacles.Kind.BOX:
					if (e[1] as AABB).grow(1.0).has_point(q):
						return false
	return true


func _spawn_bot(pos: Vector3, i: int) -> void:
	var r := KiteRig.new()
	r.name = "BotRig%d" % (i + 2)
	var prof: KiteProfile = (load("res://src/kite/profiles/pipa_classica.tres") as KiteProfile).duplicate()
	prof.color_a = BOT_COLORS[i % BOT_COLORS.size()][0]
	prof.color_b = BOT_COLORS[i % BOT_COLORS.size()][1]
	prof.pattern = (i + 1) % 4
	prof.apply_size(randi() % 3)
	prof.apply_bow(randi() % 3)
	r.profile = prof
	r.line_type = load("res://src/physics/lines/%s.tres" % BOT_LINES[randi() % BOT_LINES.size()])
	r.display_name = "Vizinho %d" % (i + 2)
	add_child(r)
	physics_world.register(r)
	var b := BotFlyer.new()
	b.name = "Bot%d" % (i + 2)
	var ch := TeenCharacter.new()
	ch.name = "Character"
	b.add_child(ch)
	add_child(b)
	b.global_position = pos
	b.rig = r
	b.target = player_rig
	b.world = physics_world
	b.aggression = randf_range(0.6, 1.0)
	b.skill = randf_range(0.4, 0.9)
	bots.append(b)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed(int(a.substr(7)))
	var street: StreetBuilder = $World/StreetBuilder
	player.global_position = street.spawn_point
	var z0 := street.spawn_point.z
	# Vizinhos em leque contra o vento, dos dois lados, em cima das lajes quando houver.
	var spots := _bot_spots(street, street.spawn_point, 4)
	bot.global_position = spots[0]
	input_router.set_gesture_controls(gestures)
	input_router.line_cycle_requested.connect(_cycle_line)
	input_router.sound_toggle_requested.connect(_toggle_sound)
	gestures.size_pressed.connect(func() -> void: input_router.intent.size_cycle += 1)
	gestures.bow_pressed.connect(func() -> void: input_router.intent.bow_cycle += 1)
	player_rig.profile = player_rig.profile.duplicate()
	player_rig.profile.apply_size(KiteProfile.Size.M)
	if bot_rig.profile:
		bot_rig.profile = bot_rig.profile.duplicate()
		bot_rig.profile.apply_size(randi() % 3)
		bot_rig.profile.apply_bow(randi() % 3)
	gestures.line_color = player_rig.line_type.color
	player.input_router = input_router
	player.rig = player_rig
	player_rig.is_local_player = true
	physics_world.register(player_rig)
	physics_world.register(bot_rig)
	bot.rig = bot_rig
	bot.target = player_rig
	bot.world = physics_world
	bots.append(bot)
	# Mais vizinhos, um em cada canto do bairro.
	for i in range(1, spots.size()):
		_spawn_bot(spots[i], i - 1)
	hud.setup(player_rig, physics_world)
	audio.world = physics_world
	audio.player_rig = player_rig
	EventBus.reset_requested.connect(reset_kite)
	EventBus.line_cut.connect(_on_line_cut)

	var args := OS.get_cmdline_user_args()
	if args.has("--desbicoprobe") or args.has("--wrapprobe"):
		var probe: Node = load("res://src/main/desbico_probe.gd").new()
		probe.set("wrap_mode", args.has("--wrapprobe"))
		add_child(probe)
		probe.call("start", self)
		return
	if args.has("--controlprobe"):
		_attach("res://src/main/control_probe.gd")
		return
	if args.has("--botprobe"):
		reset_kite()
		_attach("res://src/main/bot_probe.gd")
		return
	if args.has("--autotest"):
		_attach("res://src/main/autotest.gd")
		return
	reset_kite()
	if args.has("--screenshots"):
		_attach("res://src/main/screenshot_tour.gd")


func _attach(path: String) -> void:
	var n: Node = load(path).new()
	n.name = path.get_file().get_basename()
	add_child(n)
	n.call("start", self)


## Nova pipa no ar (com a linha atual) e câmera virada para ela.
func reset_kite() -> void:
	player.look_at_point(player.global_position + Wind.get_direction() * 10.0 + Vector3.UP * 4.0)
	player_rig.launch_in_hand(player.global_position + Vector3(0.2, 1.18, -0.3), Wind.get_direction())
	player.look_at_point(player_rig.body.x)
	EventBus.kite_launched.emit()


func _cycle_line() -> void:
	_line_index = (_line_index + 1) % LINE_TYPES.size()
	player_rig.line_type = load(LINE_TYPES[_line_index])
	gestures.line_color = player_rig.line_type.color
	reset_kite()
	hud.show_message(player_rig.line_type.display_name, 1.5)


func _process(_delta: float) -> void:
	var it := input_router.intent
	if it.size_cycle > 0 or it.bow_cycle > 0:
		var p := player_rig.profile
		if it.size_cycle > 0:
			p.apply_size((p.size_class + it.size_cycle) % 3)
		if it.bow_cycle > 0:
			p.apply_bow((p.bow_class + it.bow_cycle) % 3)
		it.size_cycle = 0
		it.bow_cycle = 0
		gestures.size_label = KiteProfile.SIZE_NAMES[p.size_class]
		gestures.bow_level = p.bow_class
		reset_kite()
		hud.show_message(p.describe(), 1.8)


func _toggle_sound() -> void:
	GameConfig.sound_enabled = not GameConfig.sound_enabled
	gestures.sound_on = GameConfig.sound_enabled
	audio.set_enabled(GameConfig.sound_enabled)


func _on_line_cut(winner: Node, loser: Node) -> void:
	if loser == player_rig or winner == player_rig:
		# Acompanha com o olhar a pipa que foi mandada.
		for r in physics_world.rigs:
			if r.loose and r.age < 0.5:
				player.watch_target = r
				player.watch_time = 5.0
