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
