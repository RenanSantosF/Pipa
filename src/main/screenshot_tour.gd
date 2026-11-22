extends Node
## Captura telas para revisão visual no CI:  -- --screenshots
## Salva PNGs em res://build/shots/ (fora do APK) e fecha o jogo.

const SHOTS := [
	[5.0, "01_inicio", "player"],
	[9.0, "02_maos", "down"],
	[12.0, "03_vizinho", "bot"],
	[15.0, "04_visao_geral", "overview"],
	[18.0, "05_linha_barriga", "side"],
]

var main
var _t: float = 0.0
var _i: int = 0
var _cam: Camera3D
var _dir: String = ""
var _capturing: bool = false


func start(p_main) -> void:
	main = p_main
	_dir = ProjectSettings.globalize_path("res://build/shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 800.0
	main.add_child(_cam)


func _process(delta: float) -> void:
	_t += delta
	if _i >= SHOTS.size():
		return
	var shot: Array = SHOTS[_i]
	var at: float = shot[0]
	var mode: String = shot[2]
	if _t > at - 1.0:
		_aim(mode)
	if _t >= at and not _capturing:
		_capturing = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_dir.path_join(String(shot[1]) + ".png"))
		print("SCREENSHOT ", shot[1])
		_i += 1
		_capturing = false
		if _i >= SHOTS.size():
			get_tree().quit(0)


func _aim(mode: String) -> void:
	var player: FPController = main.player
	var rig: KiteRig = main.player_rig
	match mode:
		"player":
			player.camera.current = true
		"down":
			player.camera.current = true
			player.input_router.intent.look_delta += Vector2(0, 40)
			player.input_router.intent.look_active = true
		"bot":
			player.input_router.intent.look_active = false
			var bot: Node3D = main.bot
			_cam.global_position = player.camera.global_position + Vector3(0, 0.3, 0)
			_cam.look_at(bot.global_position + Vector3(0, 1.2, 0))
			_cam.current = true
		"overview":
			var k: Vector3 = rig.body.x if rig.body else Vector3(0, 20, 30)
			var pp: Vector3 = player.global_position
			_cam.global_position = Vector3(38, 18, 62)
			_cam.look_at((k + pp) * 0.5)
			_cam.current = true
		"side":
			var k2: Vector3 = rig.body.x if rig.body else Vector3(0, 20, 30)
			var pp2: Vector3 = player.global_position
			var mid: Vector3 = (k2 + pp2) * 0.5
			_cam.global_position = mid + Vector3(25, 2, 0)
			_cam.look_at(mid)
			_cam.current = true
