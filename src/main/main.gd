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
	prof.apply_tail(randi() % 3)
	var tails := [[Color(0.95, 0.95, 0.95), Color(0.85, 0.15, 0.15)], [Color(0.1, 0.1, 0.1), Color(0.98, 0.84, 0.12)],
		[Color(0.2, 0.45, 0.9), Color(0.95, 0.95, 0.95)], [Color(0.1, 0.6, 0.25), Color(0.98, 0.84, 0.12)]]
	var tc: Array = tails[i % tails.size()]
	prof.tail_color_a = tc[0]
	prof.tail_color_b = tc[1]
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
		elif a.begins_with("--quality="):
			GameConfig.apply_quality(int(a.substr(10)))
	var street: StreetBuilder = $World/StreetBuilder
	player.global_position = street.spawn_point
	var z0 := street.spawn_point.z
	# Vizinhos em leque contra o vento, dos dois lados, em cima das lajes quando houver.
	var spots := _bot_spots(street, street.spawn_point, GameConfig.bot_count())
	bot.global_position = spots[0]
	input_router.set_gesture_controls(gestures)
	input_router.line_cycle_requested.connect(_cycle_line)
	input_router.sound_toggle_requested.connect(_toggle_sound)
	gestures.size_pressed.connect(func() -> void: input_router.intent.size_cycle += 1)
	gestures.bow_pressed.connect(func() -> void: input_router.intent.bow_cycle += 1)
	gestures.tail_pressed.connect(func() -> void: input_router.intent.tail_cycle += 1)
	# Área de testes do voo (painel com os parâmetros do modelo de voo).
	var lab := FlightLab.new()
	lab.rig = player_rig
	lab.position = Vector2(16, 70)
	$UI.add_child(lab)
	gestures.lab_pressed.connect(func() -> void:
		lab.visible = not lab.visible
		gestures.blocked_rect = Rect2(lab.position, lab.size) if lab.visible else Rect2())
	if OS.get_cmdline_user_args().has("--lab"):
		lab.visible = true
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
	if args.has("--crossprobe"):
		_attach("res://src/main/cross_probe.gd")
		return
	if args.has("--gestureprobe"):
		_attach("res://src/main/gesture_probe.gd")
		return
	reset_kite()
	if args.has("--renderstats"):
		_render_stats()
		return
	if args.has("--screenshots"):
		_attach("res://src/main/screenshot_tour.gd")


## Números de renderização da cena (draw calls, triângulos, objetos) — teste de peso.
func _render_stats() -> void:
	await get_tree().create_timer(4.0).timeout
	var cam := get_viewport().get_camera_3d()
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		if cam:
			cam.global_rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(yaw), 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		print("RENDER yaw=%3d draw_calls=%d tris=%d objetos=%d mem_video=%.0fMB" % [yaw,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	for a in OS.get_cmdline_user_args():
		if a == "--nobots":
			for b in bots:
				b.set_physics_process(false)
		elif a == "--noplayer":
			player.set_physics_process(false)
		elif a == "--nokites":
			physics_world.set_physics_process(false)
		elif a == "--nowind":
			Wind.set_physics_process(false)
	var tp := 0.0
	var tf := 0.0
	var tk := 0.0
	for _i in 60:
		await get_tree().physics_frame
		tp += Performance.get_monitor(Performance.TIME_PROCESS)
		tf += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		tk += physics_world.frame_ms
	print("PIPA voando=%s linha=%.1f alt=%.1f" % [str(player_rig.is_flying()), player_rig.flying_length(), player_rig.body.x.y - player.global_position.y if player_rig.body else -1.0])
	print("CPU process=%.2fms physics=%.2fms pipas=%.2fms (média de 60 ticks, %d Hz)" % [tp / 60.0 * 1000.0, tf / 60.0 * 1000.0, tk / 60.0, Engine.physics_ticks_per_second])
	var pp := []
	for n in get_tree().root.find_children("*", "", true, false):
		if n.is_physics_processing() or n.is_physics_processing_internal():
			pp.append("%s%s" % [n.name, "(i)" if n.is_physics_processing_internal() and not n.is_physics_processing() else ""])
	print("PHYSPROC %d: %s" % [pp.size(), str(pp.slice(0, 40))])
	var procs := {}
	var nodes := get_tree().root.find_children("*", "", true, false)
	for nd in nodes:
		if nd.is_processing():
			var sc: Script = nd.get_script()
			var key: String = sc.resource_path.get_file() if sc else nd.get_class()
			procs[key] = int(procs.get(key, 0)) + 1
	print("NOS total=%d com _process: %s" % [nodes.size(), str(procs)])
	var mats := {}
	for gi in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if g.material_override:
			mats[g.material_override.get_instance_id()] = g.material_override.get_class()
	print("MATERIAIS distintos (override)=%d" % mats.size())
	# Colisão do cenário ainda funciona? (raio horizontal a partir do jogador)
	var ss := player.get_world_3d().direct_space_state
	var hits := 0
	for k in 16:
		var a := float(k) / 16.0 * TAU
		var from: Vector3 = player.global_position + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0, sin(a)) * 40.0)
		if not ss.intersect_ray(q).is_empty():
			hits += 1
	print("COLISAO raios que bateram em algo: %d/16" % hits)
	print("FISICA3D ativos=%d pares=%d ilhas=%d corpos_estaticos=%d formas=%d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), get_tree().root.find_children("*", "StaticBody3D", true, false).size(), get_tree().root.find_children("*", "CollisionShape3D", true, false).size()])
	if OS.get_cmdline_user_args().has("--meshdump"):
		var rows := []
		for gi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
			var mi := gi as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var tris := 0
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				if arr.is_empty():
					continue
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
			rows.append([tris, str(mi.get_path()).right(70), mi.mesh.get_surface_count(), mi.visibility_range_end, mi.cast_shadow])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var total := 0
		for r in rows:
			total += r[0]
		print("MESH total=%d instâncias=%d" % [total, rows.size()])
		for r in rows.slice(0, 25):
			print("MESH %7d surf=%d vis_end=%.0f sombra=%d %s" % [r[0], r[2], r[3], r[4], r[1]])
	get_tree().quit()


func _attach(path: String) -> void:
	var n: Node = load(path).new()
	n.name = path.get_file().get_basename()
	add_child(n)
	n.call("start", self)


## Nova pipa no ar (com a linha atual) e câmera virada para ela.
func reset_kite() -> void:
	player.look_at_point(player.global_position + Wind.get_direction() * 10.0 + Vector3.UP * 4.0)
	# Começa já no ar (linha de 22 m): arrastar para baixo é só puxar, sempre — o
	# tranco de soltar da mão (de lado, em zigue-zague) parecia desbico.
	player_rig.launch(player.global_position + Vector3(0.2, 1.18, -0.3), 22.0, 50.0, Wind.get_direction())
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
	if it.size_cycle > 0 or it.bow_cycle > 0 or it.tail_cycle > 0:
		var p := player_rig.profile
		if it.size_cycle > 0:
			p.apply_size((p.size_class + it.size_cycle) % 3)
		if it.bow_cycle > 0:
			p.apply_bow((p.bow_class + it.bow_cycle) % 3)
		if it.tail_cycle > 0:
			p.apply_tail((p.tail_class + it.tail_cycle) % 3)
		it.size_cycle = 0
		it.bow_cycle = 0
		it.tail_cycle = 0
		gestures.size_label = KiteProfile.SIZE_NAMES[p.size_class]
		gestures.bow_level = p.bow_class
		gestures.tail_level = p.tail_class
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
