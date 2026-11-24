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
	var l := Vector2(400, 420)
	_steps = [
		# Toque na metade direita = desbico para a direita.
		[1.0, "down", 0, c], [1.08, "up", 0, c], [1.15, "check_desb", 1.0],
		# Toque na metade esquerda = desbico para a esquerda.
		[2.0, "down", 0, l], [2.08, "up", 0, l], [2.15, "check_desb", -1.0],
		# Dois toques rápidos na direita = jogar (desbico + puxão na retomada).
		[3.0, "down", 0, c], [3.06, "up", 0, c], [3.16, "down", 0, c], [3.22, "up", 0, c],
		[3.3, "check_desb", 1.0], [3.75, "check_pulling", true],
		# Arrastar para o lado e segurar = desbico; 2º dedo tocando = puxão.
		[5.0, "down", 0, c], [5.05, "drag", 0, c + Vector2(40, 2)], [5.1, "drag", 0, c + Vector2(110, 4)],
		[5.2, "check_desb", 1.0], [5.5, "down", 1, Vector2(300, 400)], [5.56, "up", 1, Vector2(300, 400)],
		[5.6, "check_pull", 1], [5.9, "up", 0, c + Vector2(110, 4)], [6.0, "check_release", 0],
		# Arrastar e segurar para baixo = puxada contínua (vários puxões).
		[7.0, "down", 0, c], [7.05, "drag", 0, c + Vector2(0, 30)], [7.1, "drag", 0, c + Vector2(0, 160)],
		[7.15, "mark_pulls"], [8.4, "check_pulls_since", 3], [8.5, "up", 0, c + Vector2(0, 160)],
		# Arrastar para cima = dar linha.
		[9.0, "down", 0, c], [9.1, "drag", 0, c + Vector2(0, -40)], [9.2, "drag", 0, c + Vector2(0, -120)],
		[9.3, "check_grip", 0.3], [9.5, "up", 0, c + Vector2(0, -120)],
		# Faixa do topo = câmera.
		[10.0, "down", 0, Vector2(600, 40)], [10.1, "drag", 0, Vector2(650, 40)], [10.15, "check_look", true], [10.3, "up", 0, Vector2(650, 40)],
		[11.0, "done"],
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
				ev2.velocity = Vector2(300, 100)
				gc._input(ev2)
			"mark_pulls":
				_mark = _hand_pulls()
			"check_pulls_since":
				_check("segurar para baixo = puxada contínua (%d puxões em 1,2 s)" % (_hand_pulls() - _mark), _hand_pulls() - _mark >= int(s[2]))
			"check_pulling":
				var h3 = main.player.get("_hand")
				_check("jogar: puxão depois do desbico", h3 != null and (bool(h3.get("_pulling")) or _hand_pulls() > _mark_throw))
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
	var hh = main.player.get("_hand")
	if hh != null:
		var pt: float = hh.get("_pull_t")
		var pulling: bool = hh.get("_pulling")
		if pulling and (not _was_pulling or pt < _last_pt):
			_hand_pull_count += 1
		_last_pt = pt
		_was_pulling = pulling


var _pulls := 0
var _mark := 0
var _mark_throw := 0
var _hand_pull_count := 0
var _was_pulling := false
var _last_pt := 0.0


func _hand_pulls() -> int:
	return _hand_pull_count


func _check(what: String, cond: bool) -> void:
	_log.append(("  ok   " if cond else "  FALHA ") + what)
	if not cond:
		_ok = false
