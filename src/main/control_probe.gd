extends Node
## Sonda do desbico e do puxão (CI/local):  -- --controlprobe [--seq=nome]
## Mede, a cada 0,05 s: inclinação do nariz, rumo, deslocamento (lateral, altura),
## tensão na pipa e na mão, velocidade do ar, ângulo de ataque e o ESCORREGAMENTO
## (ângulo entre a velocidade da pipa no plano da vela e a direção do nariz:
## pipa de verdade anda para onde aponta, não de lado).
##
## Sequências (--seq=):
##   desbico  — segura desbico à esquerda 0,7 s, solta; depois toque curto à direita
##   puxao    — um puxão; depois 4 puxões rápidos (0,22 s)
##   combo    — desbico à esquerda + puxão quando o nariz aponta para o lado

var main
var rig: KiteRig
var it: PlayerIntent
var _t: float = 0.0
var _side := Vector3.RIGHT
var _ref := Vector3.ZERO
var _seq := "desbico"
var _events: Array = []   # [tempo, ação, valor]
var _log_from := 5.8
var _max := {}
var _hold := 0.7
var _curving := false
var _gdir := Vector2.ZERO


## Direção na janela de vento (x = lado, y = cima), como o dedo no jogo.
func _window_dir(g: Vector2) -> Vector3:
	var ld: Vector3 = rig.body.line_dir
	var up_t := (Vector3.UP - ld * ld.y).normalized()
	var right_t := ld.cross(up_t).normalized()
	if right_t.dot(_side) < 0.0:
		right_t = -right_t
	return (right_t * g.x + up_t * g.y).normalized()
var _wsum := 0.0
var _wn := 0.0
var _wb := Vector3.ZERO
var _end_t := 14.0


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	main.input_router.autopilot = true
	it = main.input_router.intent
	for b in main.bots:
		b.rig = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seq="):
			_seq = a.substr(6)
		elif a.begins_with("--bow="):
			rig.profile.apply_bow(int(a.substr(6)))
		elif a.begins_with("--size="):
			rig.profile.apply_size(int(a.substr(7)))
		elif a.begins_with("--tailmass="):
			rig.profile.tail_mass = float(a.substr(11))
		elif a.begins_with("--tailarea="):
			rig.profile.tail_area = float(a.substr(11))
		elif a.begins_with("--taillen="):
			rig.profile.tail_length = float(a.substr(10))
		elif a.begins_with("--spin="):
			rig.profile.spin_coef = float(a.substr(7))
		elif a.begins_with("--end="):
			_end_t = float(a.substr(6))
		elif a.begins_with("--hold="):
			_hold = float(a.substr(7))
	var length := 25.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--len="):
			length = float(a.substr(6))
		elif a.begins_with("--prof="):
			var kv := a.substr(7).split(":")
			rig.profile.set(kv[0], float(kv[1]))
	rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), length, 55.0, Wind.get_direction())
	_side = Wind.get_direction().cross(Vector3.UP).normalized()  # direita de quem empina
	match _seq:
		"desbico":
			_events = [[6.0, "desbico", -1.0], [6.0 + _hold, "solta", 0.0], [10.0, "desbico", 1.0], [10.15, "solta", 0.0]]
		"puxao":
			_events = [[6.0, "puxao", 0.0], [9.0, "puxao", 0.0], [9.22, "puxao", 0.0], [9.44, "puxao", 0.0], [9.66, "puxao", 0.0]]
		"spam":
			for k in 17:
				_events.append([6.0 + 0.6 * k, "puxao", 0.0])
		"ritmo":
			# Toques no mesmo ritmo (0,25 s): segue reta para onde aponta.
			for k in 16:
				_events.append([6.0 + 0.25 * k, "dtap", 0.0])
		"dupla":
			# Dois toques e pausa, 4 vezes: vai virando para a direita.
			for k in 4:
				_events.append([6.0 + 0.9 * k, "dtap", 0.0])
				_events.append([6.2 + 0.9 * k, "dtap", 0.0])
		"um":
			# Um toque e pausa, 3 vezes: vira para a esquerda.
			for k in 3:
				_events.append([6.0 + 1.0 * k, "dtap", 0.0])
		"virar_ritmo":
			# Dois pares (aponta para a direita) e depois ritmo: vai reto para a direita.
			_events = [[6.0, "dtap", 0.0], [6.2, "dtap", 0.0], [6.9, "dtap", 0.0], [7.1, "dtap", 0.0], [7.8, "dtap", 0.0], [8.0, "dtap", 0.0]]
			for k in 12:
				_events.append([8.8 + 0.25 * k, "dtap", 0.0])
		"virar_puxar":
			# Vira até apontar para baixo e puxa: ela desce para onde aponta.
			for k in 5:
				_events.append([6.0 + 0.6 * k, "dtap", 0.0])
				_events.append([6.15 + 0.6 * k, "dtap", 0.0])
			for k in 5:
				_events.append([9.3 + 0.4 * k, "recolhe", 0.8])
		"guide":
			# Esquerda, direita, cima, baixo e uma curva contínua.
			_events = [[6.0, "g_left", 1.0], [8.0, "g_off", 0.0], [9.0, "g_right", 1.0], [11.0, "g_off", 0.0],
				[12.0, "g_up", 1.0], [13.5, "g_down", 0.7], [14.5, "g_off", 0.0], [15.0, "g_curve", 1.0], [19.0, "g_off", 0.0]]
		"recolher":
			for k in 8:
				_events.append([6.0 + 0.45 * k, "recolhe", 0.8])
		"guidepull":
			# Guiando para a direita e puxando ao mesmo tempo (combinação).
			_events = [[6.0, "g_right", 1.0]]
			for k in 6:
				_events.append([6.6 + 0.4 * k, "recolhe", 0.8])
			_events.append([9.5, "g_off", 0.0])
		"taps":
			# Desbicando para descer: toques alternados a cada 0,6 s.
			for k in 10:
				_events.append([6.0 + 0.6 * k, "tap", -1.0 if k % 2 == 0 else 1.0])
		"tapsame":
			for k in 8:
				_events.append([6.0 + 0.5 * k, "tap", 1.0])
		"hold":
			_events = [[6.0, "hold", 0.5], [10.0, "hold", -1.0]]
		"holdfast":
			_events = [[6.0, "hold", 1.0], [10.0, "hold", -1.0]]
		"throw":
			_events = [[6.0, "throw", 1.0], [10.0, "throw", -1.0]]
		"combo":
			_events = [[6.0, "desbico", -1.0], [6.45, "solta", 0.0], [6.5, "puxao", 0.0], [9.5, "desbico", 1.0], [9.95, "solta", 0.0], [10.0, "puxao", 0.0]]
	print("CTRL perfil: ", rig.profile.describe(), " seq=", _seq)


var _tuned := false


func _physics_process(delta: float) -> void:
	_t += delta
	if not _tuned:
		var hand = main.player.get("_hand")
		if hand != null:
			_tuned = true
			for a in OS.get_cmdline_user_args():
				for k in ["desb_grip", "kick_gain", "kick_hold", "kick_end", "asym_gain", "spin_gain", "pull_len", "pull_time"]:
					if a.begins_with("--%s=" % k):
						hand.set(k, float(a.get_slice("=", 1)))
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var ev: Array = _events.pop_front()
		print("CTRL ── t=%.2f %s %s" % [_t, ev[1], str(ev[2])])
		_apply(ev[1], float(ev[2]))
	if _curving:
		# Alvo girando devagar (90°/s): a pipa faz curvas/círculos.
		var ang := (_t - 15.0) * PI * 0.5
		_gdir = Vector2(cos(ang), sin(ang))
	if _gdir != Vector2.ZERO and it.guide_amount > 0.0:
		it.guide_dir = _window_dir(_gdir)
	if absf(_t - _log_from) < delta * 0.5:
		_ref = rig.body.x
	if _t < _log_from or rig.body == null:
		return
	var b := rig.body
	var nose: Vector3 = b.q * Vector3.UP
	var nrm: Vector3 = b.q * Vector3.BACK
	var rel := b.x - _ref
	# Escorregamento no plano tangente à esfera de voo (⟂ à linha): a pipa deve
	# andar para onde o bico aponta; afastar-se pela linha (dando linha) não conta.
	var dl := (b.x - rig.hand_position()).normalized()
	var v_t := b.v - dl * b.v.dot(dl)
	var nose_t := nose - dl * nose.dot(dl)
	var slip := 0.0
	if v_t.length() > 0.8 and nose_t.length() > 0.01:
		slip = rad_to_deg(v_t.normalized().angle_to(nose_t.normalized()))
	_track("escorr_med", slip, false)
	var nose_el := rad_to_deg(asin(clampf(nose.y, -1.0, 1.0)))
	_track("nariz_min", nose_el, true)
	_track("rumo_max", absf(rad_to_deg(rig.heading())), false)
	_track("T_pipa_max", rig.rope.tension_end if rig.rope else 0.0, false)
	_track("v_max", b.v.length(), false)
	_track("push_max", b.push_accel.length(), false)
	_track("incl_max", absf(rad_to_deg(rig.bank)), false)
	_wsum += b.w.length_squared()
	_wn += 1
	var wb: Vector3 = b.q.inverse() * b.w
	_wb += Vector3(wb.x * wb.x, wb.y * wb.y, wb.z * wb.z)
	if fmod(_t, 0.05) < delta:
		print("CTRL t=%5.2f nariz=%6.1f° rumo=%6.1f° lat=%+6.2f alt=%+6.2f vel=%5.2f escorr=%5.1f° T_pipa=%5.2f T_mão=%5.2f ar=%5.2f aoa=%5.1f mão=%+.2f pegada=%.2f linha=%.1f el=%.0f° cont=%d enr=%s" % [
			_t, nose_el, rad_to_deg(rig.heading()), rel.dot(_side), rel.y, b.v.length(), slip,
			rig.rope.tension_end, rig.rope.tension_hand, b.airspeed, rad_to_deg(b.angle_of_attack), rig.stroke, rig.grip, rig.flying_length(), rad_to_deg(asin(clampf(dl.y, -1.0, 1.0))), rig.rope.contact_count(), str(rig.snagged)])
	if _t > _end_t:
		print("CTRL resumo: ", _max, " rms_w=%.2f arfagem(x)=%.2f rolagem(y)=%.2f giro_bico(z)=%.2f" % [sqrt(_wsum / maxf(_wn, 1.0)), sqrt(_wb.x / maxf(_wn, 1.0)), sqrt(_wb.y / maxf(_wn, 1.0)), sqrt(_wb.z / maxf(_wn, 1.0))])
		get_tree().quit(0)


func _track(k: String, v: float, is_min: bool) -> void:
	if _t < 6.0:
		return
	if not _max.has(k) or (is_min and v < _max[k]) or (not is_min and v > _max[k]):
		_max[k] = snappedf(v, 0.01)


func _apply(action: String, value: float) -> void:
	match action:
		"g_left", "g_right", "g_up", "g_down":
			_gdir = {"g_left": Vector2(-1, 0), "g_right": Vector2(1, 0), "g_up": Vector2(0, 1), "g_down": Vector2(0, -1)}[action]
			it.guide_dir = _window_dir(_gdir)
			it.guide_amount = value
			_curving = false
		"g_curve":
			_curving = true
			it.guide_amount = value
		"g_off":
			_gdir = Vector2.ZERO
			it.guide_dir = Vector3.ZERO
			it.guide_amount = 0.0
			_curving = false
		"recolhe":
			it.recolhe.append(value)
		"dtap":
			it.desbico_toques += 1
		"tap":
			it.taps.append(value)
		"throw":
			it.throws.append(value)
		"hold":
			it.pull_held = value >= 0.0
			it.pull_rate = maxf(value, 0.0)
		"desbico":
			if it.has_method("press_desbico"):
				it.call("press_desbico", value)
			else:
				it.taps.append(value)
		"solta":
			if it.has_method("release_desbico"):
				it.call("release_desbico")
		"puxao":
			if "pull_taps" in it:
				it.set("pull_taps", int(it.get("pull_taps")) + 1)
			else:
				# Controle antigo: arrastar para baixo (braçada) por 0,25 s.
				it.stroke = 0.7
				get_tree().create_timer(0.25).timeout.connect(func() -> void: it.stroke = 0.0)
