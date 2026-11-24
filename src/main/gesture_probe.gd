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
	var c := Vector2(640, 420)
	_steps = [
		# Segurar à direita da pipa = guiar para a direita (bico vai para a direita).
		[1.0, "down_rel", 0, Vector2(260, 0)], [1.6, "check_guide", 1.0], [2.0, "up", 0, c],
		# Segurar à esquerda = guiar para a esquerda.
		[3.0, "down_rel", 0, Vector2(-260, 0)], [3.6, "check_guide", -1.0], [4.0, "up", 0, c],
		# Arrastar de cima para baixo = puxão (recolhe linha), não guia.
		[5.0, "down", 0, c], [5.04, "drag", 0, c + Vector2(0, 60)], [5.08, "drag", 0, c + Vector2(0, 140)],
		[5.12, "check_noguide", 0], [5.3, "up", 0, c + Vector2(0, 140)], [6.2, "check_shorter", 0],
		# Guiando com um dedo + 2º dedo arrastando para baixo = puxão junto.
		[7.0, "down_rel", 0, Vector2(240, 0)], [7.3, "down", 1, Vector2(1000, 250)], [7.34, "drag", 1, Vector2(1000, 330)],
		[7.38, "drag", 1, Vector2(1000, 420)], [7.45, "check_guide", 1.0], [7.6, "up", 1, Vector2(1000, 420)],
		[8.0, "check_shorter", 0], [8.2, "up", 0, c],
		# Arrastar de baixo para cima = dar linha.
		[9.0, "down", 0, c], [9.04, "drag", 0, c + Vector2(0, -60)], [9.1, "drag", 0, c + Vector2(0, -140)],
		[9.2, "check_grip", 0.3], [9.5, "up", 0, c + Vector2(0, -140)],
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
			"down_rel":
				# Toque relativo à pipa na tela.
				var cam := get_viewport().get_camera_3d()
				var ks := cam.unproject_position(main.player_rig.body.x) if cam else Vector2(640, 360)
				var ev0 := InputEventScreenTouch.new()
				ev0.index = s[2]
				ev0.position = (ks + s[3]).clamp(Vector2(300, 150), Vector2(1270, 710))
				ev0.pressed = true
				gc._input(ev0)
				_len_mark = main.player_rig.flying_length()
			"check_guide":
				var hg = main.player.get("_hand")
				var sd: Vector3 = main.player_rig.steer_dir
				var cam2 := get_viewport().get_camera_3d()
				var side_ok := cam2 != null and signf(sd.dot(cam2.global_basis.x)) == float(s[2])
				_check("guiar para %+.0f (comando %s)" % [s[2], str(sd.snapped(Vector3.ONE * 0.01))], hg != null and bool(hg.call("is_guiding")) and side_ok)
			"check_noguide":
				_check("arrastar para baixo não guia", not main.input_router.intent.guide_active)
			"check_shorter":
				_check("puxão recolheu linha (%.2f → %.2f m)" % [_len_mark, main.player_rig.flying_length()], main.player_rig.flying_length() < _len_mark - 0.1)
				_len_mark = main.player_rig.flying_length()
			"down", "up":
				if s[1] == "down" and s[2] == 0:
					_len_mark = main.player_rig.flying_length()
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
var _len_mark := 0.0
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
