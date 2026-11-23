extends Node
## Teste de desbico direcional (CI/local):  -- --desbicoprobe
## Mede rumo do bico e deslocamento lateral da pipa com toques para a direita/esquerda.

var main
var rig: KiteRig
var it: PlayerIntent
var _t: float = 0.0
var _side := Vector3.RIGHT
var _x0: float = 0.0


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	main.input_router.autopilot = true
	it = main.input_router.intent
	for b in main.bots:
		b.rig = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bow="):
			rig.profile.apply_bow(int(a.substr(6)))
		elif a.begins_with("--asym="):
			rig.profile.flex_asym = float(a.substr(7))
		elif a.begins_with("--shift="):
			rig.profile.bridle_shift = float(a.substr(8))
		elif a.begins_with("--tail="):
			var k := float(a.substr(7)) / rig.profile.tail_length
			rig.profile.tail_length *= k
			rig.profile.tail_area *= k
			rig.profile.tail_mass *= k
			rig.profile.tail_nodes = clampi(int(rig.profile.tail_nodes * k), 4, 20)
		elif a.begins_with("--tailmass="):
			rig.profile.tail_mass = float(a.substr(11))
		elif a.begins_with("--bridle="):
			rig.profile.bridle_length = float(a.substr(9))
		elif a.begins_with("--tow="):
			rig.profile.tow_fraction = float(a.substr(6))
		elif a.begins_with("--size="):
			rig.profile.apply_size(int(a.substr(7)))
	print("PROBE perfil: ", rig.profile.describe(), " diedro=%.1f°" % rad_to_deg(rig.profile.dihedral()))
	var el := 55.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--elev="):
			el = float(a.substr(7))
			zenith_mode = true
	rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 25.0, el, Wind.get_direction())
	_side = Wind.get_direction().cross(Vector3.UP).normalized()  # direita de quem empina


func heading() -> float:
	return rad_to_deg(rig.heading())


var wrap_mode := false
var zenith_mode := false
var _tree_added := false
var _events := [[6.0, "dir", [1.0]], [9.0, "esq", [-1.0]], [12.0, "dupla", [1.0, 1.0]], [15.0, "dir x6", [1, 1, 1, 1, 1, 1]], [21.0, "livre", []]]
var _ev := -1
var _ev_t0 := 0.0
var _ev_lat0 := 0.0
var _peak := 0.0
var _peak_t := 0.0
var _hpeak := 0.0
var _pending: Array = []
var _lat_hist: Array[float] = []


func _physics_process(delta: float) -> void:
	_t += delta
	if wrap_mode:
		_wrap_step(delta)
		return
	if zenith_mode:
		var d := rig.body.x - rig.hand_position()
		if fmod(_t, 0.5) < delta:
			print("ZEN t=%4.1f elev=%5.1f° ar=%5.2f aoa=%5.1f T=%5.2f sust=%5.2f arr=%5.2f" % [_t, rad_to_deg(asin(d.y / d.length())), rig.body.airspeed, rad_to_deg(rig.body.angle_of_attack), rig.tension, rig.body.lift, rig.body.drag])
		if _t > 10.0:
			get_tree().quit(0)
		return
	var lat := rig.body.x.dot(_side)
	_lat_hist.append(lat)
	# Dispara os eventos (toques com 0,1 s entre eles na dupla; 0,4 s na sequência).
	if _ev + 1 < _events.size() and _t >= float(_events[_ev + 1][0]):
		if _ev >= 0:
			_report()
		_ev += 1
		_ev_t0 = _t
		_ev_lat0 = lat
		_peak = 0.0
		_hpeak = 0.0
		var taps: Array = _events[_ev][2]
		var gap := 0.1 if _events[_ev][1] == "dupla" else 0.4
		_pending.clear()
		for k in taps.size():
			_pending.append([_t + gap * k, float(taps[k])])
	while not _pending.is_empty() and _t >= float(_pending[0][0]):
		it.taps.append(float(_pending[0][1]))
		_pending.pop_front()
	if _ev >= 0:
		var dl := lat - _ev_lat0
		if absf(dl) > absf(_peak):
			_peak = dl
			_peak_t = _t - _ev_t0
		if absf(heading()) > absf(_hpeak):
			_hpeak = heading()
	if fmod(_t, 0.1) < delta and _t > 5.5:
		print("PROBE t=%5.2f rumo=%6.1f lateral=%6.2f alt=%5.1f T=%5.2f aoa=%4.0f° CL·q·A=%5.2f" % [_t, heading(), lat - _ev_lat0, rig.body.x.y, rig.tension, rad_to_deg(rig.body.angle_of_attack), rig.body.lift])
	if _t > 25.0:
		_report()
		# Oscilação sem comando: desvio padrão lateral nos últimos 4 s.
		var n := mini(_lat_hist.size(), 240)
		var mean := 0.0
		for i in n:
			mean += _lat_hist[_lat_hist.size() - 1 - i]
		mean /= float(n)
		var var_sum := 0.0
		for i in n:
			var_sum += pow(_lat_hist[_lat_hist.size() - 1 - i] - mean, 2.0)
		print("PROBE oscilação livre (σ lateral) = %.2f m" % sqrt(var_sum / float(n)))
		get_tree().quit(0)


func _report() -> void:
	var lat := rig.body.x.dot(_side)
	print("PROBE ▶ %-7s pico lateral %+.2f m em %.2f s · rumo pico %+.0f° · resto após %.1f s: %+.2f m" % [_events[_ev][1], _peak, _peak_t, _hpeak, _t - _ev_t0, lat - _ev_lat0])


## Obstáculos ao lado/embaixo da linha: encostar tem que DESLIZAR; enroscar só ao
## dar volta, pendurar ou apertar. Modo: --wrapprobe [--obj=poste|fio|galho|telhado]
var _obj := "poste"


func _wrap_step(delta: float) -> void:
	var world: KitePhysicsWorld = main.physics_world
	if _t < 0.1:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--obj="):
				_obj = a.substr(6)
	if _t > 4.0 and not _tree_added and world.obstacles:
		var r0 := rig.rope
		var mid := r0.pos[int(r0.pos.size() * 0.5)]
		match _obj:
			"poste":
				world.obstacles.add_capsule(mid - _side * 1.5 + Vector3.DOWN * 12.0, mid - _side * 1.5 + Vector3.UP * 6.0, 0.13, "poste")
			"galho":
				world.obstacles.add_capsule(mid - _side * 1.5 + Vector3.DOWN * 1.0, mid - _side * 1.5 + Vector3.UP * 1.5 + Wind.get_direction() * 1.0, 0.05, "galho")
			"fio":
				world.obstacles.add_capsule(mid + Vector3.DOWN * 1.2 - _side * 15.0, mid + Vector3.DOWN * 1.2 + _side * 15.0, 0.008, "fio")
			"telhado":
				world.obstacles.add_box(mid + Vector3.DOWN * 2.5, Vector3(8.0, 3.0, 8.0), "telhado")
		_tree_added = true
		print("WRAP obstáculo ", _obj, " perto de ", mid.round())
	# 5–11 s: desbicos para a esquerda (leva a linha para o obstáculo) ou dá linha (fio/telhado).
	if _obj in ["poste", "galho"]:
		if _t > 5.0 and _t < 11.0 and fmod(_t, 0.45) < delta:
			it.taps.append(-1.0)
	else:
		it.grip = 0.15 if (_t > 5.0 and _t < 9.0) else 1.0
		if _t > 12.0 and _t < 16.0 and fmod(_t, 0.5) < delta:
			it.taps.append(1.0 if fmod(_t, 1.0) < 0.5 else -1.0)
	if fmod(_t, 0.5) < delta:
		var r := rig.rope
		var dev := 0.0
		for i in range(1, r.pos.size()):
			if r.pin_obstacle[i] >= 0:
				var nx := r.pos[i + 1] if i + 1 < r.pos.size() else r.end_point()
				dev = maxf(dev, rad_to_deg(PI - acos(clampf((r.pos[i - 1] - r.pos[i]).normalized().dot((nx - r.pos[i]).normalized()), -1.0, 1.0))))
		if _obj == "fio" and _tree_added:
			var e: Array = world.obstacles.entries[world.obstacles.entries.size() - 1]
			var best := 99.0
			var sy := 0.0
			for i in r.segment_count():
				var pp := r.segment_points(i)
				var res := LineCombat.closest_segments(pp[0], pp[1], e[1], e[2])
				if float(res[2]) < best:
					best = float(res[2])
					sy = (pp[0].lerp(pp[1], res[0]) - (e[1] as Vector3).lerp(e[2], res[1])).y
			print("WRAP   fio: dist=%.3f lado_y=%+.3f" % [best, sy])
		print("WRAP t=%5.1f contatos=%d presos=%d θmax=%5.1f° T_mão=%5.2f T_pipa=%5.2f lateral=%6.2f alt=%5.1f linha=%5.1f pipa_presa=%s" % [_t, r.contact_count(), r.pin_count(), dev, r.tension_hand, r.tension_end, rig.body.x.dot(_side), rig.body.x.y, rig.flying_length(), str(rig.snagged)])
	if _t > 20.0:
		get_tree().quit(0)
