extends Node
## Teste dos GESTOS (sem tela):  -- --gestureprobe
## Injeta toques sintéticos no GestureControls e confere o que chega na mão:
## toque = puxão · arrastar para o lado = desbico (e soltar retoma) · segundo dedo
## tocando durante o desbico = puxão · arrastar para cima = dar linha.

var main
var gc: GestureControls
var _t: float = 0.0
var _steps: Array = []
var _ok := true
var _log: Array = []


func start(p_main) -> void:
	main = p_main
	gc = main.gestures
	gc.visible = true
	gc.size = Vector2(1280, 720)
	main.player_rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 30.0, 55.0, Wind.get_direction())
	var c := Vector2(800, 420)
	_steps = [
		[1.0, "down", 0, c], [1.08, "up", 0, c], [1.12, "check_pull", 1],
		[2.0, "down", 0, c], [2.05, "drag", 0, c + Vector2(40, 2)], [2.1, "drag", 0, c + Vector2(110, 4)],
		[2.2, "check_desb", 1.0], [2.5, "down", 1, Vector2(300, 400)], [2.56, "up", 1, Vector2(300, 400)],
		[2.6, "check_pull", 2], [2.9, "up", 0, c + Vector2(110, 4)], [3.0, "check_release", 0],
		[3.5, "down", 0, c], [3.55, "drag", 0, c + Vector2(-30, 0)], [3.6, "drag", 0, c + Vector2(-140, 0)],
		[3.7, "check_desb", -1.0], [4.2, "up", 0, c + Vector2(-140, 0)],
		[5.0, "down", 0, c], [5.1, "drag", 0, c + Vector2(0, -40)], [5.2, "drag", 0, c + Vector2(0, -120)],
		[5.3, "check_grip", 0.3], [5.5, "up", 0, c + Vector2(0, -120)],
		[6.0, "down", 0, Vector2(600, 40)], [6.1, "drag", 0, Vector2(650, 40)], [6.15, "check_look", true], [6.3, "up", 0, Vector2(650, 40)],
		[7.0, "done"],
	]


func _physics_process(delta: float) -> void:
	_t += delta
	var it: PlayerIntent = main.input_router.intent
	while not _steps.is_empty() and _t >= float(_steps[0][0]):
		var s: Array = _steps.pop_front()
		match s[1]:
			"down", "up":
				var ev := InputEventScreenTouch.new()
				ev.index = s[2]
				ev.position = s[3]
				ev.pressed = s[1] == "down"
				gc._input(ev)
			"drag":
				var ev2 := InputEventScreenDrag.new()
				ev2.index = s[2]
				ev2.position = s[3]
				ev2.relative = Vector2(10, 0)
				ev2.velocity = Vector2(300, 0)
				gc._input(ev2)
			"check_pull":
				_check("puxões contados = %d" % s[2], _pulls >= int(s[2]))
			"check_desb":
				var hand = main.player.get("_hand")
				_check("desbico para %+.0f (lado da mão %s)" % [s[2], str(hand.get("_desb_side") if hand else "?")], hand != null and float(hand.get("_desb_side")) == float(s[2]))
			"check_release":
				var hand2 = main.player.get("_hand")
				_check("soltou o desbico (dedo levantado)", hand2 != null and not bool(hand2.get("_desb_down")))
			"check_grip":
				_check("arrastar para cima abre a mão (pegada %.2f)" % it.grip, it.grip < float(s[2]))
			"check_look":
				_check("faixa do topo = câmera", it.look_active)
			"done":
				for l in _log:
					print(l)
				print("GESTOS OK" if _ok else "GESTOS FALHOU")
				get_tree().quit(0 if _ok else 1)
	if it.pull_taps > 0:
		_pulls += it.pull_taps


var _pulls := 0


func _check(what: String, cond: bool) -> void:
	_log.append(("  ok   " if cond else "  FALHA ") + what)
	if not cond:
		_ok = false
