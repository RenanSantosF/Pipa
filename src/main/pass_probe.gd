extends Node
## Sonda de ATRAVESSAMENTO com árbitro geométrico independente da física:
##   -- --passprobe [--mode=line|wire] [--dur=40] [--seed=n]
##
## line: a sua pipa (modelo de voo, como no jogo) varre a janela de um lado para o
##       outro por cima da linha de um vizinho, com puxões e dando linha; a mão do
##       vizinho também varre de lado. Corte desligado (o teste não acaba no corte).
## wire: a sua pipa voa logo acima de uma rede de fios/postes e mergulha, varre e
##       puxa por cima deles.
##
## O árbitro, a cada tick, mede o LADO de cada trecho de linha em relação a cada
## outro trecho de linha / fio / galho / poste por perto (sinal na normal comum, nos
## pontos mais próximos, com os dois pontos no MEIO dos trechos) e conta quando o
## lado troca com as duas a menos de 35 cm (= atravessou). Conta também trecho de
## linha dentro de casa/muro e a pipa dentro de poste/fio/casa.

var main
var rig: KiteRig
var bot: KiteRig
var obs: WorldObstacles
var hand: KiteHand
var _mode := "line"
var _dur := 40.0
var _t := 0.0
var _hand_a := Vector3.ZERO
var _hand_b0 := Vector3.ZERO
var _side := Vector3.RIGHT
var _wd := Vector3.FORWARD
var _rng := RandomNumberGenerator.new()
var _g := Vector2.ZERO
var _next_cmd := 0.0
var _grip := 1.0
# Árbitro.
var _prev_ll: Dictionary = {}     # par -> [[sa, sb, sinal, dist, d], ...]
var _sail_prev: Dictionary = {}
var sail_pierce := 0
var _prev_cap: Dictionary = {}    # idx -> [[s, sinal, dist], ...]
var flips_ll := 0
var flips_cap := 0
var box_ticks := 0
var kite_in := 0
var near_ll := 0
var near_cap := 0

var _phase := 0
var _tapping := false
var _tap_int := 0.25
var _tap_clock := 0.0
var _rise := 0.0
var _t1 := 0.0


func start(p_main) -> void:
	main = p_main
	main.input_router.autopilot = true
	rig = main.player_rig
	bot = main.bot_rig
	main.player.rig = null
	var seed := 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a.begins_with("--dur="):
			_dur = float(a.substr(6))
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
	_rng.seed = seed
	Wind.direction_wander_deg = 0.0
	Wind.gust_strength = 0.15
	obs = main.get_tree().get_first_node_in_group(&"street_builder").get("obstacles")
	if _mode != "bots":
		for b in main.bots:
			b.rig = null
		main.bot.rig = null
	if _mode == "wire":
		_setup_wire()
	elif _mode == "bots":
		_setup_bots()
	else:
		_setup_line()
	hand = KiteHand.new(rig)
	print("PASS: modo=%s dur=%.0f semente=%d" % [_mode, _dur, seed])


func _tough(r: KiteRig) -> void:
	r.line_type = r.line_type.duplicate()
	r.line_type.toughness = 1.0e9
	r.line_type.break_tension = 1.0e6


func _setup_line() -> void:
	Wind.base_direction_deg = 0.0
	Wind._update_cache()
	_wd = Wind.get_direction()
	_side = _wd.cross(Vector3.UP).normalized()
	var center := Vector3(0, 0, 40)
	var top := Ground.height_at(center.x, center.z) + 32.0
	_hand_a = Vector3(center.x, top, center.z)
	# Vizinho atrás e mais baixo, linha um pouco atravessada: a mão dele sobe até a
	# linha encostar por baixo na sua e depois aperta e varre de lado.
	_hand_b0 = _hand_a - _wd * 10.0 + Vector3.DOWN * 13.0
	_tough(rig)
	_tough(bot)
	rig.launch(_hand_a, 30.0, 50.0, _wd)
	bot.launch(_hand_b0, 40.0, 50.0, (_wd + _side * 0.25).normalized())
	rig.hand_rest = _hand_a
	bot.hand_rest = _hand_b0


## Jogo de verdade: vizinhos com a IA deles atacando a sua pipa (linhas sem corte).
func _setup_bots() -> void:
	_wd = Wind.get_direction()
	_side = _wd.cross(Vector3.UP).normalized()
	_hand_a = main.player.global_position + Vector3(0.2, 1.18, -0.3)
	rig.launch(_hand_a, 30.0, 50.0, _wd)
	rig.hand_rest = _hand_a
	for r in (main.physics_world as KitePhysicsWorld).rigs:
		_tough(r)


func _setup_wire() -> void:
	var p0: Vector3 = main.player.global_position
	var best := -1
	var best_d := INF
	for idx in obs.entries.size():
		var e: Array = obs.entries[idx]
		if e[0] != WorldObstacles.Kind.CAPSULE or String(e[4]) != "fio":
			continue
		var a: Vector3 = e[1]
		var b: Vector3 = e[2]
		var ax := b - a
		ax.y = 0.0
		if ax.length() < 1.5:
			continue
		var m := (a + b) * 0.5
		var dd := Vector2(m.x - p0.x, m.z - p0.z).length()
		if dd > 90.0 or dd > best_d:
			continue
		# A mão fica 8 m a barlavento, num lugar livre (sem casa em cima).
		var n := ax.normalized().cross(Vector3.UP).normalized()
		var ok := false
		for s in [1.0, -1.0]:
			var hp: Vector3 = m - n * (8.0 * s)
			if obs.top_at(hp.x, hp.z) < Ground.height_at(hp.x, hp.z) + 0.3:
				ok = true
				break
		if ok:
			best = idx
			best_d = dd
	if best < 0:
		push_error("PASS: nenhum fio encontrado")
		_setup_line()
		return
	var e: Array = obs.entries[best]
	var a2: Vector3 = e[1]
	var b2: Vector3 = e[2]
	var m2 := (a2 + b2) * 0.5
	var ax2 := b2 - a2
	ax2.y = 0.0
	var n2 := ax2.normalized().cross(Vector3.UP).normalized()
	var hp2 := m2 - n2 * 8.0
	if obs.top_at(hp2.x, hp2.z) > Ground.height_at(hp2.x, hp2.z) + 0.3:
		n2 = -n2
		hp2 = m2 - n2 * 8.0
	# Vento soprando da mão para o fio (a linha passa por cima da rede).
	Wind.base_direction_deg = rad_to_deg(atan2(n2.x, -n2.z))
	Wind._update_cache()
	_wd = Wind.get_direction()
	_side = _wd.cross(Vector3.UP).normalized()
	_hand_a = Vector3(hp2.x, Ground.height_at(hp2.x, hp2.z) + 1.25, hp2.z)
	_tough(rig)
	rig.launch(_hand_a, 24.0, 48.0, _wd)
	rig.hand_rest = _hand_a
	bot.stow()
	print("PASS: fio em %s (altura %.1f), mão em %s" % [str(m2.round()), m2.y - Ground.height_at(m2.x, m2.z), str(_hand_a.round())])


func _physics_process(delta: float) -> void:
	_t += delta
	if rig.body == null:
		_finish("pipa perdida")
		return
	_pilot(delta)
	if _mode == "bots":
		for r in (main.physics_world as KitePhysicsWorld).rigs:
			if r.line_type.toughness < 1.0e8:
				_tough(r)
	elif bot.is_flying():
		var con := (main.physics_world as KitePhysicsWorld).strongest_contact_for(bot)
		if _phase == 0:
			_rise += 1.5 * delta
			if con != null or _rise > 18.0:
				_phase = 1
				_t1 = _t
		else:
			_rise += 0.5 * delta * (1.0 if con != null else 2.0)
			_rise = minf(_rise, 26.0)
		var off := sin((_t - _t1) * 0.6) * 6.0 if _phase == 1 else 0.0
		bot.hand_rest = _hand_b0 + Vector3.UP * _rise + _side * off
	_referee()
	if _t > _dur:
		_finish("fim")


## Piloto: troca de comando a cada 1,5–3,5 s (guiar para um lado/cima/baixo),
## puxões em rajadas e às vezes dá linha.
func _pilot(delta: float) -> void:
	if _t >= _next_cmd:
		_next_cmd = _t + _rng.randf_range(1.5, 3.5)
		var r := _rng.randf()
		if _mode == "wire":
			# Mais mergulho e varrida rente aos fios.
			if r < 0.35:
				_g = Vector2(_rng.randf_range(-0.6, 0.6), -1.0)
			elif r < 0.7:
				_g = Vector2(signf(_rng.randf() - 0.5), _rng.randf_range(-0.5, 0.2))
			else:
				_g = Vector2(_rng.randf_range(-0.3, 0.3), 1.0)
		else:
			if r < 0.75:
				_g = Vector2(signf(_rng.randf() - 0.5), _rng.randf_range(-0.4, 0.4))
			else:
				_g = Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-1.0, 1.0))
		_grip = 0.25 if _rng.randf() < 0.15 else 1.0
		# Às vezes desbica por toques em vez de guiar (ritmo ou pares com pausa).
		_tapping = _rng.randf() < 0.45
		_tap_int = _rng.randf_range(0.18, 0.32)
	var pulling := fmod(_t, 9.0) > 6.5
	if _tapping and rig.flight != null:
		_tap_clock += delta
		if _tap_clock >= _tap_int:
			_tap_clock = 0.0
			rig.flight.tap()
		rig.flight.steer = 0.0
		rig.hand_rest = _hand_a
		hand.update(delta, 0.0, _grip if not pulling else 1.0, 0.0)
		if pulling and fmod(_t, 0.45) < delta:
			hand.recolher(0.8)
		return
	if pulling and fmod(_t, 0.45) < delta:
		hand.recolher(0.8)
	if rig.flight != null:
		var fr: Array = rig.flight.frame()
		var wdir: Vector3 = ((fr[2] as Vector3) * _g.x + (fr[1] as Vector3) * _g.y).normalized()
		var target := atan2(wdir.dot(fr[2]), wdir.dot(fr[1]))
		var err := wrapf(target - rig.flight.heading, -PI, PI)
		rig.flight.steer = clampf(err / 0.7, -1.0, 1.0)
	rig.hand_rest = _hand_a
	hand.update(delta, 0.0, _grip if not pulling else 1.0, 0.0)
	if rig.flying_length() > 45.0:
		_grip = 1.0


func _pts(r: Rope) -> PackedVector3Array:
	var p := r.pos.duplicate()
	if r.end_body != null:
		p.append(r.end_point())
	return p


func _svals(r: Rope) -> PackedFloat32Array:
	var s := r.mat_s.duplicate()
	if r.end_body != null:
		s.append(0.0)
	return s


func _referee() -> void:
	if not rig.is_flying():
		return
	var pa := _pts(rig.rope)
	var sa := _svals(rig.rope)
	var kite := rig.body.x
	# Linha × linha (todos os pares de pipas no ar).
	var rigs: Array[KiteRig] = (main.physics_world as KitePhysicsWorld).rigs
	for i in rigs.size():
		for j in range(i + 1, rigs.size()):
			if rigs[i].is_flying() and rigs[j].is_flying():
				_ref_pair(rigs[i], rigs[j])
				_ref_sail(rigs[i], rigs[j])
				_ref_sail(rigs[j], rigs[i])
	# Linha × fio/galho/poste e linha dentro de caixa.
	if obs != null:
		var cur_cap := {}
		for i in pa.size() - 1:
			var a := pa[i]
			var b := pa[i + 1]
			if not (obs.below_top(a, 1.0) or obs.below_top(b, 1.0) or obs.below_top((a + b) * 0.5, 1.0)):
				continue
			for idx in obs.query_segment(a, b):
				var e: Array = obs.entries[idx]
				if e[0] == WorldObstacles.Kind.CAPSULE:
					var ca: Vector3 = e[1]
					var cb: Vector3 = e[2]
					var res := LineCombat.closest_segments(a, b, ca, cb)
					var dist: float = res[2]
					if dist > 0.6:
						continue
					var t: float = res[0]
					var u: float = res[1]
					if t < 0.03 or t > 0.97 or u < 0.05 or u > 0.95:
						continue
					# Corda entre dois nós de contato no mesmo fio (a linha dando a volta
					# nele): passa a milímetros do centro do fio — não é atravessar.
					var r2 := rig.rope
					if i > 0 and i + 1 < r2.pos.size() and r2.pin_obstacle[i] >= 0 and r2.pin_obstacle[i + 1] >= 0 \
							and absi(r2.pin_obstacle[i] - idx) <= 1 and absi(r2.pin_obstacle[i + 1] - idx) <= 1:
						continue
					var e1 := b - a
					var e2 := cb - ca
					var n := e1.cross(e2)
					if n.length() < 0.3 * e1.length() * e2.length():
						continue
					var q := a.lerp(b, t)
					if q.distance_to(kite) < 0.5:
						continue
					var sgn := signf((q - ca.lerp(cb, u)).dot(n.normalized()))
					var s := lerpf(sa[i], sa[i + 1], t)
					if dist < float(e[3]) + 0.02:
						near_cap += 1
					var prev: Array = _prev_cap.get(idx, [])
					var bestc: Array = []
					var bestcd := 0.8
					for pp in prev:
						if absf(float(pp[0]) - s) < bestcd:
							bestcd = absf(float(pp[0]) - s)
							bestc = pp
					for p in ([bestc] if not bestc.is_empty() else []):
						if float(p[1]) != sgn and minf(float(p[2]), dist) < 0.35:
							flips_cap += 1
							_log("ATRAVESSOU linha×%s t=%.2f dist=%.3f s=%.1f trecho=%d/%d obst=%d contatos=%s" % [String(e[4]), _t, dist, s, i, pa.size() - 1, idx, _contacts_str(rig.rope)])
							break
					if not cur_cap.has(idx):
						cur_cap[idx] = []
					(cur_cap[idx] as Array).append([s, sgn, dist])
				elif e[0] == WorldObstacles.Kind.BOX:
					var box: AABB = e[1]
					if box.size.y < 0.3 or box.size.x < 0.2 or box.size.z < 0.2:
						continue
					var inner := box.grow(-0.06)
					for k in 5:
						var p := a.lerp(b, (float(k) + 0.5) / 5.0)
						if inner.has_point(p):
							box_ticks += 1
							_log("LINHA DENTRO de %s t=%.2f trecho=%d/%d obst=%d a_dentro=%s b_dentro=%s caixa=%s a=%s b=%s contatos=%s" % [String(e[2]), _t, i, pa.size() - 1, idx,
								str(box.has_point(a)), str(box.has_point(b)), str(box), str(a), str(b), _contacts_str(rig.rope)])
							break
		_prev_cap = cur_cap
		# Diagnóstico: nó de contato dentro da própria caixa.
		var rr := rig.rope
		for k in rr.pos.size():
			var ob := rr.pin_obstacle[k]
			if ob < 0:
				continue
			var eo: Array = obs.entries[ob]
			if eo[0] == WorldObstacles.Kind.BOX and (eo[1] as AABB).grow(-0.05).has_point(rr.pos[k]):
				_log("NO DENTRO k=%d/%d obst=%d n=%s pinned=%d prev_dentro=%s hold=%.2f" % [k, rr.pos.size(), ob, str(rr.c_normal[k]), rr.pinned[k], str((eo[1] as AABB).has_point(rr.prev[k])), rr.c_hold[k]])
		# Pipa dentro de obstáculo (enroscada no fio/galho não conta: o fio passa no cabresto).
		for idx in (obs.query(kite) if not rig.snagged else PackedInt32Array()):
			var e: Array = obs.entries[idx]
			if e[0] == WorldObstacles.Kind.CAPSULE:
				var q: Vector3 = WorldObstacles._axis_point(e[1], e[2], kite)[0]
				if kite.distance_to(q) < float(e[3]) + 0.02:
					kite_in += 1
					_log("PIPA DENTRO de %s t=%.2f d=%.3f r=%.3f voo=%s presa=%s" % [String(e[4]), _t, kite.distance_to(q), float(e[3]), str(rig.flight != null), str(rig.snagged)])
			elif e[0] == WorldObstacles.Kind.BOX:
				var box2: AABB = e[1]
				if box2.size.y > 0.3 and box2.size.x > 0.2 and box2.size.z > 0.2 and box2.grow(-0.05).has_point(kite):
					kite_in += 1
					_log("PIPA DENTRO de %s t=%.2f caixa=%s pipa=%s voo=%s presa=%s" % [String(e[2]), _t, str(box2), str(kite), str(rig.flight != null), str(rig.snagged)])


func _ref_pair(ra: KiteRig, rb: KiteRig) -> void:
	var key := str(ra.get_instance_id()) + ":" + str(rb.get_instance_id())
	var pa := _pts(ra.rope)
	var sa := _svals(ra.rope)
	var pb := _pts(rb.rope)
	var sb := _svals(rb.rope)
	var prev: Array = _prev_ll.get(key, [])
	var cur: Array = []
	for i in pa.size() - 1:
		for j in pb.size() - 1:
			var res := LineCombat.closest_segments(pa[i], pa[i + 1], pb[j], pb[j + 1])
			var dist: float = res[2]
			if dist > 0.6:
				continue
			var ta: float = res[0]
			var tb: float = res[1]
			if ta < 0.03 or ta > 0.97 or tb < 0.03 or tb > 0.97:
				continue
			var qa := pa[i].lerp(pa[i + 1], ta)
			var qb := pb[j].lerp(pb[j + 1], tb)
			# Perto das pipas a linha pode dar a volta pela ponta (laça no cabresto).
			if qa.distance_to(ra.body.x) < 0.6 or qb.distance_to(rb.body.x) < 0.6:
				continue
			var ea := pa[i + 1] - pa[i]
			var eb := pb[j + 1] - pb[j]
			var n := ea.cross(eb)
			var parallel := n.length() < 0.25 * ea.length() * eb.length()
			var d := qb - qa
			var sgn := 0.0 if parallel else signf(d.dot(n.normalized()))
			var s_a := lerpf(sa[i], sa[i + 1], ta)
			var s_b := lerpf(sb[j], sb[j + 1], tb)
			if dist < 0.05:
				near_ll += 1
			# Compara com o ponto mais próximo (em material) do tick anterior.
			var bestp: Array = []
			var bestd := 1.6
			for pp in prev:
				var dd := absf(float(pp[0]) - s_a) + absf(float(pp[1]) - s_b)
				if absf(float(pp[0]) - s_a) < 0.8 and absf(float(pp[1]) - s_b) < 0.8 and dd < bestd:
					bestd = dd
					bestp = pp
			for p in ([bestp] if not bestp.is_empty() else []):
				var flip := false
				if sgn != 0.0 and float(p[2]) != 0.0:
					flip = float(p[2]) != sgn and minf(float(p[3]), dist) < 0.35
				else:
					# Quase paralelas: o vetor de separação virou mais de 120° num tick.
					var dp: Vector3 = p[4]
					flip = maxf(float(p[3]), dist) < 0.15 and d.dot(dp) < -0.5 * d.length() * dp.length()
				if flip:
					flips_ll += 1
					_log("ATRAVESSOU linha×linha t=%.2f dist=%.3f s=(%.1f, %.1f)%s contatos=%d" % [_t, dist, s_a, s_b, " paralelas" if parallel else "", (main.physics_world as KitePhysicsWorld).combat.contacts.size()])
					break
			cur.append([s_a, s_b, sgn, dist, d])
	_prev_ll[key] = cur


## Linha de `other` furando a vela da pipa de `owner` sem estar laçada.
func _ref_sail(owner: KiteRig, other: KiteRig) -> void:
	var body := owner.body
	var pts := _pts(other.rope)
	var n: Vector3 = body.q * Vector3.BACK
	var inv := body.q.inverse()
	var hooked := false
	for c in (main.physics_world as KitePhysicsWorld).combat.contacts:
		if c.hooked and ((c.a == owner and c.b == other) or (c.a == other and c.b == owner)):
			hooked = true
	var key := str(owner.get_instance_id()) + ">" + str(other.get_instance_id())
	var piercing := false
	for j in pts.size() - 1:
		if (pts[j] - body.x).length() > 4.0 and (pts[j + 1] - body.x).length() > 4.0:
			continue
		if LineCombat._segment_hits_sail(body, inv, n, pts[j], pts[j + 1]):
			piercing = true
			break
	if piercing and not hooked and not _sail_prev.get(key, false):
		sail_pierce += 1
		_log("LINHA FUROU A PIPA t=%.2f" % _t)
	_sail_prev[key] = piercing and not hooked


func _contacts_str(r: Rope) -> String:
	var out := ""
	for k in r.pos.size():
		if r.pin_obstacle[k] >= 0:
			out += "[%d:%d%s]" % [k, r.pin_obstacle[k], "P" if r.pinned[k] == 1 else ""]
	return out


var _log_budget := {}


func _log(s: String) -> void:
	var cat := s.substr(0, 12)
	var n: int = _log_budget.get(cat, 6)
	if n > 0:
		_log_budget[cat] = n - 1
		print("PASS " + s)


func _finish(why: String) -> void:
	print("PASS resumo modo=%s: linha×linha=%d furou_pipa=%d linha×obst=%d linha_em_caixa=%d pipa_dentro=%d encostes(ll=%d obst=%d) linha=%.1f (%s)" % [
		_mode, flips_ll, sail_pierce, flips_cap, box_ticks, kite_in, near_ll, near_cap, rig.flying_length() if rig.rope else 0.0, why])
	set_physics_process(false)
	get_tree().quit()
