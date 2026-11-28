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
var _lh: LineHand
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
var _prev_geo: Dictionary = {}    # par -> [pontos A, material A, pontos B, material B] do tick anterior
var _sail_prev: Dictionary = {}
var sail_pierce := 0
var _prev_cap: Dictionary = {}    # idx -> [[s, sinal, dist], ...]
var flips_ll := 0
var _sail_watch := 0
var rolled_ll := 0
var renormal_ll := 0
var renormal_cap := 0
var _prev_line_geo: Array = []   # sinal trocado só porque a normal dos trechos mudou (não atravessou)   # linhas paralelas rolando uma em volta da outra encostadas (permitido)
var flips_cap := 0
var box_ticks := 0
var kite_in := 0
var near_ll := 0
var near_cap := 0

var _phase := 0
var _give_mode := false
var _n_bots := 2
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
		elif a == "--give":
			_give_mode = true
		elif a.begins_with("--trace="):
			_trace_from = float(a.substr(8))
		elif a.begins_with("--bots="):
			_n_bots = int(a.substr(7))
	_rng.seed = seed
	if OS.get_cmdline_user_args().has("--flips"):
		LineCombat.DEBUG_FLIPS = true
	Wind.direction_wander_deg = 0.0
	Wind.gust_strength = 0.15
	obs = main.get_tree().get_first_node_in_group(&"street_builder").get("obstacles")
	if _mode != "bots" and _mode != "combate":
		for b in main.bots:
			b.rig = null
		main.bot.rig = null
	if _mode == "wire":
		_setup_wire()
	elif _mode == "bots":
		_setup_bots()
	elif _mode == "combate":
		_setup_combat()
	else:
		_setup_line()
	hand = KiteHand.new(rig)
	print("PASS: modo=%s dur=%.0f semente=%d" % [_mode, _dur, seed])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--obsinfo="):
			for id in a.substr(10).split(","):
				var e: Array = obs.entries[int(id)]
				print("PASS obst %s: %s" % [id, str(e)])


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


## Combate de verdade: a sua pipa já no ar (30 m) na rua, os vizinhos mais perto já no
## ar caçando a sua linha com a IA deles; o piloto rela como gente (toques, puxadas
## rápidas com dois dedos, dar linha). Linhas sem corte.
func _setup_combat() -> void:
	_wd = Wind.get_direction()
	_side = _wd.cross(Vector3.UP).normalized()
	_hand_a = main.player.global_position + Vector3(0.2, 1.18, -0.3)
	rig.launch(_hand_a, 30.0, 52.0, _wd)
	rig.hand_rest = _hand_a
	_tough(rig)
	var p0: Vector3 = main.player.global_position
	var all: Array = main.bots.duplicate()
	all.sort_custom(func(x, y) -> bool: return x.global_position.distance_to(p0) < y.global_position.distance_to(p0))
	var kept := 0
	for b in all:
		if b.rig == null:
			continue
		if kept >= _n_bots:
			b.set_physics_process(false)
			b.rig.stow()
			continue
		kept += 1
		_tough(b.rig)
		b.rotation.y = atan2(-_wd.x, -_wd.z)
		b.rig.launch(b.hand_rest(), _rng.randf_range(32.0, 42.0), 50.0, _wd)
		b._hand = KiteHand.new(b.rig)
		b._target_length = 40.0
		b._best_alt = 99.0
		b._state = BotFlyer.State.HUNT
		print("PASS: vizinho %s a %.0f m" % [b.name, b.global_position.distance_to(p0)])


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
	if _mode == "bots" or _mode == "combate":
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
		_grip = 0.0 if _rng.randf() < (0.5 if _give_mode else 0.15) else 1.0
		# Às vezes desbica por toques em vez de guiar (ritmo ou pares com pausa).
		_tapping = _rng.randf() < 0.45
		_tap_int = _rng.randf_range(0.18, 0.32)
	var pulling := fmod(_t, 9.0) > 6.5
	if rig.physical and _mode == "combate":
		_pilot_relo(delta)
		return
	if rig.physical:
		# Física real: só a mão na linha (toques alternando, puxar com o dedo, dar linha).
		if _lh == null or _lh.rig != rig:
			_lh = LineHand.new(rig)
		_tap_clock += delta
		if _tapping:
			if _tap_clock >= _tap_int:
				_tap_clock = 0.0
				_lh.tap()
		elif _tap_clock >= 0.9:
			_tap_clock = 0.0
			var want := signf(_g.x) if absf(_g.x) > 0.3 else 0.0
			if want != 0.0 and signf(rig.heading()) != want:
				_lh.tap()
				if rig.next_desbico_side() != want:
					_lh.tap(KiteRig.DESB_CHAIN + 0.1)
		if pulling and fmod(_t, 0.2) < delta:
			_lh.pull_line(0.35)
		rig.hand_rest = _hand_a
		_lh.update(delta, _grip if not pulling else 1.0, 0.0)
		if rig.flying_length() > 60.0:
			_grip = 1.0
		return
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
	if rig.flying_length() > 60.0:
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


## Histórico curto (últimos ticks) dos contatos linha×linha e da topologia das linhas,
## impresso quando o árbitro acha um cruzamento.
var _hist: Array = []
var _hist_geo: Dictionary = {}
var crazy_ticks := 0
var max_mv := 0.0
func _record_hist() -> void:
	var cw := (main.physics_world as KitePhysicsWorld).combat
	var txt := "t=%.2f" % _t
	for r in (main.physics_world as KitePhysicsWorld).rigs:
		if r.rope != null:
			var cur := _pts(r.rope)
			var sv := _svals(r.rope)
			var mv := 0.0
			var mk := -1
			var old: Array = _hist_geo.get(r, [])
			if not old.is_empty():
				for k in cur.size():
					var dd := cur[k].distance_to(_closest_on(old[0], cur[k]))
					if dd > mv:
						mv = dd
						mk = k
			_hist_geo[r] = [cur, sv]
			if mv > 1.5:
				crazy_ticks += 1
				_log("LINHA LOUCA %s t=%.2f %.1f m num tick (nó %d, presa=%s, n=%d)" % [r.display_name, _t, mv, mk, str(r.snagged), cur.size()])
			max_mv = maxf(max_mv, mv)
			txt += " %s:n%d L%.1f mv%.2f@%d%s%s" % [r.display_name.right(1), r.rope.pos.size(), r.flying_length(), mv, mk,
				"(obst%d)" % r.rope.pin_obstacle[mk] if mk >= 0 and mk < r.rope.pos.size() and r.rope.pin_obstacle[mk] >= 0 else "",
				" PRESA" if r.snagged else ""]
	# Menor distância da sua linha a cada outra (e onde).
	if rig.rope != null:
		var pa0 := _pts(rig.rope)
		for r in (main.physics_world as KitePhysicsWorld).rigs:
			if r == rig or r.rope == null:
				continue
			var pb0 := _pts(r.rope)
			var best := 99.0
			var where := ""
			for i in pa0.size() - 1:
				for j in pb0.size() - 1:
					var res := LineCombat.closest_segments(pa0[i], pa0[i + 1], pb0[j], pb0[j + 1])
					if float(res[2]) < best:
						best = res[2]
						where = "%d/%d" % [i, j]
			if best < 3.0:
				txt += " d(%s)=%.2f@%s" % [r.display_name.right(1), best, where]
	for c in cw.contacts:
		if c.ia >= c.a.rope.segment_count() or c.ib >= c.b.rope.segment_count():
			txt += " [fora]"
			continue
		var pa := c.a.rope.segment_points(c.ia)
		var pb := c.b.rope.segment_points(c.ib)
		var d: Vector3 = pb[0].lerp(pb[1], c.tb) - pa[0].lerp(pa[1], c.ta)
		txt += " [%s%s%d/%d t%.2f/%.2f s%.1f/%.1f sep%.3f]" % ["H" if c.hooked else "", "X" if c.crossed else "", c.ia, c.ib, c.ta, c.tb,
			c.a.rope.material_at(mini(c.ia, c.a.rope.segment_count() - 1), c.ta), c.b.rope.material_at(mini(c.ib, c.b.rope.segment_count() - 1), c.tb), d.dot(c.normal)]
	_hist.append(txt)
	if _hist.size() > 14:
		_hist.pop_front()


var _trace_from := -1.0
func _referee() -> void:
	LineCombat.DEBUG_TRACE = false
	if _trace_from >= 0.0:
		var pw := main.physics_world as KitePhysicsWorld
		var on := _t + 0.034 >= _trace_from and _t < _trace_from + 0.1
		LineCombat.DEBUG_TRACE = on and OS.get_cmdline_user_args().has("--tracecombat")
		pw.debug_rope_rig = null
		if on:
			for r in pw.rigs:
				if r.display_name.ends_with("2"):
					pw.debug_rope_rig = r
			print("FASE ---- fim do tick %.2f" % _t)
	if LineCombat.DEBUG_TRACE:
		print("TRACE ---- fim do tick %.2f" % _t)
	_record_hist()
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
							# Mesmo material nos dois ticks e a MESMA normal (a de agora): a
							# normal vem do trecho da linha × eixo, e a linha dobrando num
							# apoio troca de trecho (a normal troca de sinal sem atravessar).
							if not _prev_line_geo.is_empty():
								var nn := n.normalized()
								var oa := _point_at(_prev_line_geo[0], _prev_line_geo[1], s)
								var oc: Vector3 = WorldObstacles._axis_point(ca, cb, oa)[0]
								if (oa - oc).dot(nn) * (q - ca.lerp(cb, u)).dot(nn) >= 0.0:
									renormal_cap += 1
									break
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
		_prev_line_geo = [pa, sa]
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
			# Laçada: as duas linhas saem do MESMO ponto (o nó do cabresto) e giram uma em
			# volta da outra ali sem atravessar — os 2 m de cada lado da laçada não contam.
			if _near_hook(ra, rb, s_a_of(sa, i, ta), s_a_of(sb, j, tb)):
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
					if flip:
						# Confere no MESMO material dos dois ticks e na MESMA normal (a de
						# agora): a normal de cada tick vem dos trechos mais próximos, e numa
						# linha que dobra num apoio (fio, quina) o trecho muda e a normal
						# troca de sinal sem nada ter atravessado.
						var geo2: Array = _prev_geo.get(key, [])
						if not geo2.is_empty():
							var nn := n.normalized()
							var oa := _point_at(geo2[0], geo2[1], s_a)
							var ob := _point_at(geo2[2], geo2[3], s_b)
							var old_side := (ob - oa).dot(nn)
							var now_side := d.dot(nn)
							if old_side * now_side >= 0.0:
								flip = false
								renormal_ll += 1
				else:
					# Quase paralelas: o vetor de separação virou mais de 120° num tick.
					# Mede no MESMO ponto de material da linha A nos dois ticks (o ponto
					# mais próximo de linhas deitadas uma na outra pula ao longo delas).
					var geo: Array = _prev_geo.get(key, [])
					if geo.is_empty():
						continue
					var qa0 := _point_at(geo[0], geo[1], s_a)
					var qb0 := _closest_on(geo[2], qa0)
					var qb1 := _closest_on(pb, qa)
					var dp := qb0 - qa0
					var dn := qb1 - qa
					flip = maxf(dp.length(), dn.length()) < 0.15 and dn.dot(dp) < -0.5 * dn.length() * dp.length()
					if flip:
						# Atravessar = passar uma pela outra. Rolar em volta da outra
						# encostada (é assim que uma linha enrosca na outra) mantém a
						# folga do contato (3 mm) no caminho todo: isso não conta. Atravessar
						# = os centros chegarem a menos de 1 mm (a espessura da linha).
						var ch := dn - dp
						var lam := clampf(-dp.dot(ch) / maxf(ch.length_squared(), 1e-12), 0.0, 1.0)
						var pass_min := (dp + ch * lam).length()
						if pass_min >= 0.001:   # 1 mm = espessura da linha: menos que isso, sobrepõe
							flip = false
							rolled_ll += 1
						else:
							_log("   paralelas: |antes|=%.3f |agora|=%.3f ângulo=%.0f° menor distância no caminho=%.4f" % [dp.length(), dn.length(), rad_to_deg(dp.angle_to(dn)), pass_min])
				if flip:
					flips_ll += 1
					_log("ATRAVESSOU linha×linha t=%.2f dist=%.3f s=(%.1f, %.1f)%s contatos=%d" % [_t, dist, s_a, s_b, " paralelas" if parallel else "", (main.physics_world as KitePhysicsWorld).combat.contacts.size()])
					var dbg := []
					for cc in (main.physics_world as KitePhysicsWorld).combat.contacts:
						dbg.append("[%s%s s=%.1f/%.1f %d/%d t=%.2f/%.2f F=%.2f]" % ["H" if cc.hooked else "", "X" if cc.crossed else "", cc.a.rope.material_at(cc.ia, cc.ta), cc.b.rope.material_at(cc.ib, cc.tb), cc.ia, cc.ib, cc.ta, cc.tb, cc.force])
					for hl in _hist:
						print("PASS      hist " + str(hl))
					_log("   contatos: %s · obst A=%d B=%d · presa A=%s B=%s · enganches=%d · segA %d/%d segB %d/%d" % [" ".join(dbg), ra.rope.contact_count(), rb.rope.contact_count(), str(ra.snagged), str(rb.snagged), (main.physics_world as KitePhysicsWorld).grabs.grabs.size(), i, pa.size(), j, pb.size()])
					break
			cur.append([s_a, s_b, sgn, dist, d])
	_prev_ll[key] = cur
	_prev_geo[key] = [pa, sa, pb, sb]


static func s_a_of(sv: PackedFloat32Array, i: int, t: float) -> float:
	return lerpf(sv[i], sv[i + 1], t)


func _near_hook(ra: KiteRig, rb: KiteRig, s_a: float, s_b: float) -> bool:
	for c in (main.physics_world as KitePhysicsWorld).combat.contacts:
		if not c.hooked:
			continue
		if c.a == ra and c.b == rb:
			if absf(c.s_a - s_a) < 2.0 or absf(c.s_b - s_b) < 2.0:
				return true
		elif c.a == rb and c.b == ra:
			if absf(c.s_b - s_a) < 2.0 or absf(c.s_a - s_b) < 2.0:
				return true
	return false


## Ponto da linha na coordenada de material `s`.
static func _point_at(pts: PackedVector3Array, sv: PackedFloat32Array, s: float) -> Vector3:
	for k in pts.size() - 1:
		var s0 := sv[k]
		var s1 := sv[k + 1]
		if (s - s0) * (s - s1) <= 0.0 and absf(s1 - s0) > 1e-6:
			return pts[k].lerp(pts[k + 1], (s - s0) / (s1 - s0))
	return pts[0] if absf(sv[0] - s) < absf(sv[sv.size() - 1] - s) else pts[pts.size() - 1]


## Ponto da polilinha mais perto de `q`.
static func _closest_on(pts: PackedVector3Array, q: Vector3) -> Vector3:
	var best := pts[0]
	var bd := INF
	for k in pts.size() - 1:
		var ab := pts[k + 1] - pts[k]
		var t := clampf((q - pts[k]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var c := pts[k] + ab * t
		var dd := c.distance_squared_to(q)
		if dd < bd:
			bd = dd
			best = c
	return best


## Piloto do combate: ciclos de ~4 s escolhidos ao acaso entre desbicar no ritmo,
## puxar rápido (um ou dois dedos, 3–5,5 m/s), dar linha (mão entreaberta ou aberta)
## e relar (dar linha e puxar alternando) — o que se faz de verdade no cruzamento.
var _relo_mode := 0
var _relo_until := 0.0
var _relo_clock := 0.0
func _pilot_relo(delta: float) -> void:
	if _lh == null or _lh.rig != rig:
		_lh = LineHand.new(rig)
	if _t >= _relo_until:
		_relo_until = _t + _rng.randf_range(2.0, 5.0)
		_relo_mode = _rng.randi() % 5
		_tap_int = _rng.randf_range(0.2, 0.6)
		_relo_clock = 0.0
	_relo_clock += delta
	_tap_clock += delta
	var grip := 1.0
	_lh.pull_fingers = 1
	match _relo_mode:
		0:  # desbico no ritmo
			if _tap_clock >= _tap_int:
				_tap_clock = 0.0
				_lh.tap()
		1:  # puxada rápida com dois dedos
			_lh.pull_fingers = 2
			if fmod(_relo_clock, 0.1) < delta:
				_lh.pull_line(0.6)
		2:  # dar linha (entreaberta), às vezes aberta
			grip = 0.25 if fmod(_relo_clock, 2.0) < 1.4 else 0.0
		3:  # relo: dá linha e puxa, alternando
			if fmod(_relo_clock, 1.2) < 0.6:
				grip = 0.2
			elif fmod(_relo_clock, 0.12) < delta:
				_lh.pull_line(0.4)
		4:  # toques + puxada (direciona e puxa)
			if _tap_clock >= 0.7:
				_tap_clock = 0.0
				_lh.tap()
				_lh.tap(0.2)
			elif fmod(_relo_clock, 0.15) < delta and fmod(_relo_clock, 2.0) > 1.0:
				_lh.pull_line(0.45)
	if rig.flying_length() > 70.0:
		grip = 1.0
	if rig.flying_length() < 12.0:
		grip = 0.25
	rig.hand_rest = _hand_a
	_lh.update(delta, grip, 0.0)


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
		_sail_watch = 10
	if _sail_watch > 0:
		_sail_watch -= 1
		print("PASS    vela t=%.2f furando=%s laçada=%s" % [_t, str(piercing), str(hooked)])
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
	print("PASS resumo modo=%s: linha×linha=%d furou_pipa=%d linha×obst=%d linha_em_caixa=%d pipa_dentro=%d encostes(ll=%d obst=%d) rolou_encostada=%d normal_trocou=%d/%d linha_louca=%d (máx %.1f m/tick) linha=%.1f (%s)" % [
		_mode, flips_ll, sail_pierce, flips_cap, box_ticks, kite_in, near_ll, near_cap, rolled_ll, renormal_ll, renormal_cap, crazy_ticks, max_mv, rig.flying_length() if rig.rope else 0.0, why])
	set_physics_process(false)
	get_tree().quit()
