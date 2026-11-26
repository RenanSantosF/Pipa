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
	var r := c + Vector2(130, 0)
	_steps = [
		# Toque = desbico: 1º balança para a esquerda, 2º para a direita.
		[1.0, "mark_taps"], [1.0, "down", 0, c], [1.08, "up", 0, c], [1.3, "check_tap", 1, -1.0],
		[1.4, "down", 0, c + Vector2(30, 10)], [1.47, "up", 0, c + Vector2(30, 10)], [1.7, "check_tap", 2, 1.0],
		# Segurar e arrastar para a direita = cabresto para a direita (sem desbicar).
		[3.0, "mark_taps"], [3.0, "down", 0, c], [3.3, "drag", 0, c + Vector2(60, 0)], [3.4, "drag", 0, r],
		[3.7, "check_steer", 1.0], [3.8, "up", 0, r], [3.95, "check_steer", 0.0], [3.95, "check_tap_same"],
		# Segurar e arrastar para a esquerda = cabresto para a esquerda.
		[4.5, "down", 0, c], [4.8, "drag", 0, c + Vector2(-60, 0)], [4.9, "drag", 0, c + Vector2(-130, 0)],
		[5.2, "check_steer", -1.0], [5.3, "up", 0, c + Vector2(-130, 0)],
		# Arrastar rápido para baixo = puxão (recolhe), sem guiar e sem desbicar.
		[6.0, "mark_taps"], [6.0, "down", 0, c], [6.04, "drag", 0, c + Vector2(0, 60)], [6.08, "drag", 0, c + Vector2(0, 140)],
		[6.12, "check_noguide", 0], [6.3, "up", 0, c + Vector2(0, 140)], [7.2, "check_shorter", 0], [7.2, "check_tap_same"],
		# Guiando com um dedo + 2º dedo arrastando para baixo = puxão junto.
		[8.0, "down", 0, c], [8.3, "drag", 0, c + Vector2(60, 0)], [8.35, "drag", 0, r],
		[8.4, "down", 1, Vector2(1000, 250)], [8.44, "drag", 1, Vector2(1000, 330)], [8.48, "drag", 1, Vector2(1000, 420)],
		[8.55, "check_steer", 1.0], [8.7, "up", 1, Vector2(1000, 420)], [9.1, "check_shorter", 0],
		# 2º dedo tocando enquanto o 1º guia = desbico.
		[9.2, "mark_taps"], [9.2, "down", 1, Vector2(1000, 300)], [9.27, "up", 1, Vector2(1000, 300)], [9.5, "check_tap_more"],
		[9.6, "up", 0, r],
		# Arrastar rápido para cima = dar linha.
		[10.5, "down", 0, c], [10.54, "drag", 0, c + Vector2(0, -60)], [10.6, "drag", 0, c + Vector2(0, -140)],
		[10.7, "check_grip", 0.3], [11.0, "up", 0, c + Vector2(0, -140)],
		# Faixa do topo = câmera.
		[11.5, "down", 0, Vector2(600, 40)], [11.6, "drag", 0, Vector2(650, 40)], [11.65, "check_look", true], [11.8, "up", 0, Vector2(650, 40)],
		[12.5, "done"],
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
			"check_steer":
				var fl = main.player_rig.flight
				var st: float = fl.steer if fl else 99.0
				var want: float = s[2]
				var ok: bool = (absf(st) < 0.01) if want == 0.0 else (signf(st) == want and absf(st) > 0.2)
				_check("cabresto %s (comando %+.2f)" % ["solto" if want == 0.0 else ("direita" if want > 0.0 else "esquerda"), st], ok)
			"check_side":
				var hs = main.player.get("_hand")
				_check("toque = balanço para %s" % ("a esquerda" if float(s[2]) < 0.0 else "a direita"), hs != null and float(hs.get("_tap_side")) == float(s[2]))
			"mark_taps":
				var fm = main.player_rig.flight
				_mark_taps = float(fm.tap_count) if fm else 0.0
			"check_tap":
				var ft = main.player_rig.flight
				var n_ok: bool = ft != null and ft.taps == int(s[2]) and ft.swing_side == float(s[3])
				_check("toque %d = balanço para %s (toques %s, lado %s)" % [s[2], "a esquerda" if float(s[3]) < 0.0 else "a direita",
					str(ft.taps if ft else -1), str(ft.swing_side if ft else 0.0)], n_ok)
			"check_tap_same":
				var fs = main.player_rig.flight
				_check("sem desbico nesse gesto", fs != null and float(fs.tap_count) == _mark_taps)
			"check_tap_more":
				var fo = main.player_rig.flight
				_check("toque do 2º dedo desbica", fo != null and float(fo.tap_count) > _mark_taps)
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
var _mark_taps := 0.0
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
