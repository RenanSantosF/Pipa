extends Node
## Teste automático (CI, sem tela):  godot --headless --path . --fixed-fps 60 -- --autotest
##
## Fase 1 — voo (30 s): pipa estável no ar; dar linha aumenta o comprimento;
##          braçadas mandam linha para o chão; recolher enrola.
## Fase 2 — combate (até 90 s): duas linhas cruzadas em X, CHILENA contra PURA.
##          A pura tem que ser cortada (e a chilena não).

var main
var rig: KiteRig
var bot_rig: KiteRig
var router: InputRouter
var _t: float = 0.0
var _phase: int = 1
var _ok: bool = true
var _alt_sum: float = 0.0
var _alt_n: int = 0
var _len_before_release: float = 0.0
var _len_after_release: float = 0.0
var _pile_after_strokes: float = 0.0
var _max_tension: float = 0.0
var _cut_loser: Node = null
var _cut_time: float = -1.0
var _done: bool = false
var _hand_b0 := Vector3.ZERO
var _side := Vector3.RIGHT
const PILOT_PERIOD := 0.65
const PILOT_HOLD := 0.15
const PILOT_PULL := 0.18
var _hand_b: KiteHand
var _lh_b: LineHand
var _saw_t0 := -1.0
var _rise := 0.0
var _sweep := 1.0
## Tempo máximo do combate (s): relo de verdade demora — esfregando apertado corta.
const COMBAT_LIMIT := 90.0
var _saw_dir := Vector3.FORWARD


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	bot_rig = main.bot_rig
	router = main.input_router
	router.autopilot = true
	for b in main.bots:
		b.rig = null  # vizinhos parados durante o teste
	# O vizinho principal também (a IA dele é aleatória e a linha dele podia encostar
	# na sua durante o teste de voo); na fase de combate o teste controla a pipa dele.
	main.bot.rig = null
	bot_rig.stow()
	EventBus.line_cut.connect(_on_line_cut)
	# Começa na mão, como no jogo.
	seed(20260)
	var size := KiteProfile.Size.M
	var bow := KiteProfile.Bow.MEDIA
	var tow := -1.0
	var tail := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tail="):
			tail = int(a.substr(7))
		if a.begins_with("--tow="):
			tow = float(a.substr(6))
		if a.begins_with("--size="):
			size = int(a.substr(7))
		elif a.begins_with("--bow="):
			bow = int(a.substr(6))
	for r in [rig, bot_rig]:
		r.profile = r.profile.duplicate()
		r.profile.apply_size(size)
		r.profile.apply_bow(bow)
		r.profile.apply_tail(tail)
		if tow >= 0.0:
			r.profile.tow_fraction = tow
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--prof="):
				var kv := a.substr(7).split(":")
				r.profile.set(kv[0], float(kv[1]))
	# Como no jogo: a pipa começa no ar (20 m de linha), voando pelo modelo de voo.
	rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 20.0, 50.0, Wind.get_direction())
	print("AUTOTEST: início (vento %.1f m/s, linha %s)" % [Wind.base_speed, rig.line_type.display_name])


func _on_line_cut(_winner: Node, loser: Node) -> void:
	if _cut_loser == null:
		_cut_loser = loser
		_cut_time = _t


var _dt := 1.0 / 60.0


## Passou por um múltiplo de `period` neste tick? (independe da taxa de física)
func _every(period: float, offset: float = 0.0) -> bool:
	return floorf((_t - offset) / period) != floorf((_t - offset - _dt) / period)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_dt = delta
	_t += delta
	if _phase == 1:
		_phase_flight(delta)
	else:
		_phase_combat(delta)


func _input_set(stroke: float, grip: float, reel: float) -> void:
	var it := router.intent
	it.stroke = stroke
	it.grip = grip
	it.reel_rate = reel


var _m := {}


## Direção na janela de vento (x = lado, y = cima) em volta da pipa.
func _window_dir(g: Vector2) -> Vector3:
	var ld := (rig.body.x - rig.hand_position()).normalized()
	var up_t := (Vector3.UP - ld * ld.y).normalized()
	var right_t := ld.cross(up_t).normalized()
	return (right_t * g.x + up_t * g.y).normalized()


func _phase_flight(_delta: float) -> void:
	if not rig.is_flying():
		_fail("pipa caiu/arrebentou na fase de voo (t=%.1f)" % _t)
		return
	var b := rig.body
	if not b.is_valid():
		_fail("estado não finito")
		return
	_max_tension = maxf(_max_tension, rig.tension)
	var it := router.intent
	var d := b.x - rig.hand_position()
	var el := rad_to_deg(asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0)))
	var side: Vector3 = Wind.get_direction().cross(Vector3.UP).normalized()
	var lat: float = (b.x - main.player.global_position).dot(side)
	it.grip = 1.0
	it.guide_amount = 0.0
	it.guide_dir = Vector3.ZERO
	if _t < 6.0:
		_m["len0"] = rig.flying_length()
	elif _t < 9.0:
		it.grip = 0.15                      # dar linha
	elif _t < 10.0:
		_m["len1"] = rig.flying_length()    # espera a linha esticar de novo
		_m["el1"] = el
	elif _t < 14.0:
		if _every(0.4):
			it.recolhe.append(0.8)          # puxões
		_m["len2"] = rig.flying_length()
		_m["el2"] = el
		_m["lat2"] = lat
	elif rig.physical and _t < 27.0:
		# FÍSICA REAL: não existe "guiar" direto — só a mão na linha. Mede o giro do bico
		# parada (14–20 s) e com desbicos em ritmo (21–25 s), e se ela não dá loopings.
		var hd := rig.heading()
		var rate := rad_to_deg(wrapf(hd - float(_m.get("hprev", hd)), -PI, PI)) / maxf(_dt, 1e-4)
		_m["hprev"] = hd
		if _t > 14.5 and _t < 20.0:
			_m["ri2"] = float(_m.get("ri2", 0.0)) + rate * rate
			_m["rin"] = int(_m.get("rin", 0)) + 1
		elif _t >= 20.0 and _t < 21.0:
			_m["h5"] = hd
		elif _t >= 21.0 and _t < 24.6:
			# DESBICO DIRECIONAL: 2 toques + pausa (três vezes) → vira para a DIREITA.
			var k2 := fmod(_t - 21.0, 1.2)
			if _every(1.2, 21.0) or (k2 >= 0.25 and k2 - _dt < 0.25):
				it.desbico_toques += 1
			_m["rt2"] = float(_m.get("rt2", 0.0)) + rate * rate
			_m["rtn"] = int(_m.get("rtn", 0)) + 1
			# O bico balança e VOLTA para cima (v0.23): mede o maior balanço para a direita.
			var dr := wrapf(hd - float(_m["h5"]), -PI, PI)
			_m["h6pk"] = maxf(float(_m.get("h6pk", -PI)), dr)
			_m["h6"] = hd
		elif _t >= 24.6 and _t < 26.4:
			# O próximo toque é para a ESQUERDA (os lados sempre alternam).
			if _t - _dt < 24.6:
				it.desbico_toques += 1
			_m["h7pk"] = minf(float(_m.get("h7pk", PI)), wrapf(hd - float(_m["h5"]), -PI, PI))
			_m["h7"] = hd
		if absf(rad_to_deg(hd)) > 150.0:
			_m["inv"] = int(_m.get("inv", 0)) + 1
	elif _t < 17.0:
		it.guide_dir = _window_dir(Vector2(-1, 0))   # guiar para a esquerda
		it.guide_amount = 1.0
		_m["lat3"] = lat
		_m["hl"] = rig.flight.heading if rig.flight else 0.0
	elif _t < 20.0:
		it.guide_dir = _window_dir(Vector2(1, 0))    # guiar para a direita
		it.guide_amount = 1.0
		_m["lat4"] = lat
		_m["hr"] = rig.flight.heading if rig.flight else 0.0
	elif _t < 21.0:
		it.guide_dir = _window_dir(Vector2(0, 1))    # bico para cima de novo
		it.guide_amount = 1.0
		_m["h5"] = rig.flight.heading if rig.flight else 0.0
	elif _t < 24.6:
		# DESBICO: 2 toques + pausa (três vezes) → vira para a DIREITA.
		var k := fmod(_t - 21.0, 1.2)
		if _every(1.2, 21.0) or (k >= 0.25 and k - _dt < 0.25):
			it.desbico_toques += 1
		_m["h6"] = rig.flight.heading if rig.flight else 0.0
	elif _t < 27.0:
		# 1 toque + pausa → depois de um par (último balanço para a direita) o próximo
		# é para a ESQUERDA (os lados sempre alternam) e ela vira para a esquerda.
		if _t - _dt < 24.6:
			it.desbico_toques += 1
		_m["h7"] = rig.flight.heading if rig.flight else 0.0
	if _t > 26.0:
		_alt_sum += b.x.y - main.player.global_position.y
		_alt_n += 1
	if _every(2.0):
		print("AUTOTEST voo t=%5.1f alt=%6.2f el=%4.0f lat=%+6.1f T=%5.2f linha=%5.1f física=%.2fms presa=%s rabiola_presa=%d contatos=%d rumo=%+.0f°" % [
			_t, b.x.y - main.player.global_position.y, el, lat, rig.tension, rig.flying_length(), main.physics_world.frame_ms,
			str(rig.snagged), rig.tail.pinned_index if rig.tail else -2, rig.rope.contact_count(), rad_to_deg(rig.heading())])
	if _t >= 30.0 and rig.physical:
		var mean_alt2 := _alt_sum / maxf(float(_alt_n), 1.0)
		var r_idle := sqrt(float(_m.get("ri2", 0.0)) / maxf(float(_m.get("rin", 1)), 1.0))
		var r_tap := sqrt(float(_m.get("rt2", 0.0)) / maxf(float(_m.get("rtn", 1)), 1.0))
		print("AUTOTEST voo (física real): dar linha %.1f → %.1f m · puxar %.1f → %.1f m (elevação %.0f° → %.0f°) · giro do bico parada %.0f°/s, desbicando %.0f°/s · 2 toques %+.0f° · 1 toque %+.0f° · invertida %d ticks · altura final %.1f m" % [
			_m["len0"], _m["len1"], _m["len1"], _m["len2"], _m["el1"], _m["el2"], r_idle, r_tap,
			rad_to_deg(float(_m.get("h6pk", 0.0))),
			rad_to_deg(float(_m.get("h7pk", 0.0))), int(_m.get("inv", 0)), mean_alt2])
		var checks2 := [
			[_m["len1"] > _m["len0"] + 2.0, "dar linha não deu linha"],
			[_m["len2"] < _m["len1"] - 2.0, "puxar não recolheu linha"],
			[_m["el2"] > _m["el1"] + 2.0, "puxar não fez a pipa subir no céu"],
			[mean_alt2 > 6.0, "a pipa não se manteve no ar"],
			[r_tap > 1.3 * r_idle and r_tap > 15.0, "desbicar não mexeu o bico (giro %.0f°/s × %.0f°/s parada)" % [r_tap, r_idle]],
			[rad_to_deg(float(_m.get("h6pk", 0.0))) > 25.0, "2 toques + pausa não virou para a direita"],
			[rad_to_deg(float(_m.get("h7pk", 0.0))) < -20.0, "o toque seguinte não virou para a esquerda"],
			[int(_m.get("inv", 0)) < 30, "a pipa ficou de cabeça para baixo (looping)"],
		]
		for c in checks2:
			if not c[0]:
				_ok = false
				print("AUTOTEST FAIL: ", c[1])
		if OS.get_cmdline_user_args().has("--flightonly"):
			_finish()
			return
		_start_combat()
		return
	if _t >= 30.0:
		var mean_alt := _alt_sum / maxf(float(_alt_n), 1.0)
		var turn_r := rad_to_deg(float(_m.get("h6pk", 0.0)))
		var turn_l := rad_to_deg(float(_m.get("h7pk", 0.0)))
		print("AUTOTEST voo: dar linha %.1f → %.1f m · puxar %.1f → %.1f m (elevação %.0f° → %.0f°) · esquerda %+.1f m · direita %+.1f m · desbico 2 toques %+.0f° · 1 toque %+.0f° · altura final %.1f m" % [
			_m["len0"], _m["len1"], _m["len1"], _m["len2"], _m["el1"], _m["el2"], _m["lat3"] - _m["lat2"], _m["lat4"] - _m["lat3"], turn_r, turn_l, mean_alt])
		var checks := [
			[_m["len1"] > _m["len0"] + 2.0, "dar linha não deu linha"],
			[_m["len2"] < _m["len1"] - 2.0, "puxar não recolheu linha"],
			[_m["el2"] > _m["el1"] + 2.0, "puxar não fez a pipa subir no céu"],
			# Lá no alto da janela ela anda devagar: vale andar para o lado OU o bico
			# ficar virado para aquele lado.
			[_m["lat3"] - _m["lat2"] < -2.0 or float(_m["hl"]) < -0.8, "guiar para a esquerda não levou a pipa para a esquerda"],
			[_m["lat4"] - _m["lat3"] > 2.0 or float(_m["hr"]) > 0.8, "guiar para a direita não levou a pipa para a direita"],
			[mean_alt > 6.0, "a pipa não se manteve no ar"],
			[turn_r > 25.0, "desbico de 2 toques + pausa não virou para a direita"],
			[turn_l < -20.0, "desbico de 1 toque + pausa não virou para a esquerda"],
		]
		for c in checks:
			if not c[0]:
				_ok = false
				print("AUTOTEST FAIL: ", c[1])
		if OS.get_cmdline_user_args().has("--flightonly"):
			_finish()
			return
		_start_combat()


func _start_combat() -> void:
	_phase = 2
	_t = 0.0
	_cut_loser = null
	# Relo por baixo: o vizinho está atrás (contra o vento) e mais baixo, com a linha
	# correndo logo abaixo da sua, no mesmo plano. Ele sobe a mão (a linha dele
	# encosta na sua por baixo) e vai dando linha: as duas relam até alguém cortar.
	rig.line_type = load("res://src/physics/lines/pura.tres")
	bot_rig.line_type = load("res://src/physics/lines/chilena.tres")
	for r in [rig, bot_rig]:
		r.profile.apply_size(KiteProfile.Size.M)
		r.profile.apply_bow(KiteProfile.Bow.MEDIA)
	var wd := Wind.get_direction()
	var side := wd.cross(Vector3.UP).normalized()
	_side = side
	_saw_dir = wd
	# Cruzamento em X: a sua pipa voa de verdade; a do vizinho fica PARADA no céu (como
	# presa num poste alto — só fixa a ponta), então a linha dele é uma reta que cruza a
	# sua quase em ângulo reto, logo abaixo do meio dela. A mão dele sobe até encostar e
	# serra de um lado para o outro: contato, atrito, desgaste e corte são os de verdade.
	var center := Vector3(0, 0, 40)
	var hand_a := center
	hand_a.y = Ground.height_at(hand_a.x, hand_a.z) + 30.0
	rig.launch(hand_a, 30.0, 50.0, wd)
	var ka := rig.body.x
	# As duas pontas ficam paradas (linhas amarradas no alto): o teste é do ATRITO entre
	# as linhas — o voo já foi testado na fase 1.
	rig.held = true
	# Linha esticada (~6 N): a ponta um pouco além do comprimento de repouso.
	rig._held_x = rig.body.x + (rig.body.x - hand_a).normalized() * 0.3
	rig._held_q = rig.body.q
	rig.spool = 0.0
	rig.pile = 0.0
	var mid := hand_a.lerp(ka, 0.45)
	# Linha dele quase em pé, 1,5 m ao lado da sua: a mão dele empurra DE LADO
	# (perpendicular à sua linha — o contato não escorrega para as pontas) e serra.
	var kb := mid + Vector3.UP * 8.0 - side * 1.5 + wd * 0.5
	var hand_b := mid + Vector3.DOWN * 8.0 - side * 1.5 - wd * 0.5
	var db := kb - hand_b
	bot_rig.launch(hand_b, db.length(), rad_to_deg(asin(clampf(db.y / db.length(), -1.0, 1.0))), db)
	bot_rig.held = true
	bot_rig._held_x = bot_rig.body.x
	bot_rig._held_q = bot_rig.body.q

	_hand_b = KiteHand.new(bot_rig)
	_hand_b.auto_feed = false
	main.player.rig = null  # mãos paradas, controladas pelo teste
	rig.hand_rest = hand_a
	bot_rig.hand_rest = hand_b
	_hand_b0 = hand_b
	rig.stroke = 0.0
	bot_rig.stroke = 0.0
	print("AUTOTEST combate: %s × %s" % [rig.line_type.display_name, bot_rig.line_type.display_name])


func _phase_combat(_delta: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tracecombat="):
			var tt := float(a.substr(14))
			LineCombat.DEBUG_TRACE = _t > tt - 0.12 and _t < tt + 0.02
			(main.physics_world as KitePhysicsWorld).debug_rope_rig = rig if LineCombat.DEBUG_TRACE else null
			if LineCombat.DEBUG_TRACE:
				print("TRACE ---- t=%.3f" % _t)
	# Mãos paradas; o bot "dá linha" de vez em quando (como no relo de verdade).
	rig.grip = 1.0
	rig.held = true
	# Sobe a mão até a linha dele apertar a sua por baixo; depois segura a altura.
	var con := (main.physics_world as KitePhysicsWorld).strongest_contact_for(bot_rig)
	# Sem contato: sobe procurando (ou, se já encostou antes, volta um pouco para baixo
	# — a linha dele passou da sua); encostado: aperta de leve; apertado demais: alivia.
	# Contato que conta é o encostado de verdade (os antecipados existem com as
	# linhas ainda a dezenas de cm).
	if con != null and con.force < 0.05:
		con = null
	if _t > 2.0:
		if con == null:
			# Varre para cima e para baixo até achar a sua linha.
			_rise += 0.5 * _delta * _sweep
			if _rise > 4.0:
				_sweep = -1.0
			elif _rise < 0.0:
				_sweep = 1.0
		else:
			if con.force < 2.0:
				_rise = minf(_rise + 0.6 * _delta, 8.0)   # aperta a linha dele contra a sua
			elif con.force > 4.0:
				_rise = maxf(_rise - 0.4 * _delta, 0.0)
	# Relo: encostado, o vizinho SERRA (leva a mão de um lado para o outro) e dá linha
	# em pulsos — a linha dele desliza apertada sobre a sua (desgaste por atrito).
	# Serra sempre (de um lado para o outro): sem encostar, varre até achar a linha;
	# encostado, desliza apertado.
	var saw := Vector3.ZERO
	if _t > 2.0:
		saw = Vector3(_saw_dir.x, 0.0, _saw_dir.z).normalized() * (2.5 * sin((_t - 2.0) * 2.6))
	bot_rig.hand_rest = _hand_b0 + _side * (_rise * 2.0) + saw
	# Dá linha só relando (apertando contra a outra), como no relo de verdade.
	var relando := con != null and con.force > 0.5
	bot_rig.grip = 1.0   # a ponta dele está parada: a mão só sobe e serra
	bot_rig.held = true
	if OS.get_cmdline_user_args().has("--debugcombat") and fmod(_t, 2.5) < _delta:
		var pk := rig.body.x if rig.body else Vector3.ZERO
		var bk := bot_rig.body.x if bot_rig.body else Vector3.ZERO
		if rig.rope == null or bot_rig.rope == null:
			return
		var best := 99.0
		var dv := Vector3.ZERO
		var pa := rig.rope.pos.duplicate()
		pa.append(rig.rope.end_point())
		var pb := bot_rig.rope.pos.duplicate()
		pb.append(bot_rig.rope.end_point())
		for i in pa.size() - 1:
			for j in pb.size() - 1:
				var res := LineCombat.closest_segments(pa[i], pa[i + 1], pb[j], pb[j + 1])
				if float(res[2]) < best:
					best = res[2]
					dv = pb[j].lerp(pb[j + 1], res[1]) - pa[i].lerp(pa[i + 1], res[0])
		var cc := (main.physics_world as KitePhysicsWorld).strongest_contact_for(bot_rig)
		if cc != null:
			print("    contato s_eu=%.2f/%.1f s_bot=%.2f/%.1f %d/%d t=%.2f/%.2f" % [cc.a.rope.material_at(cc.ia, cc.ta) if cc.a == rig else cc.b.rope.material_at(cc.ib, cc.tb), rig.flying_length(),
				cc.b.rope.material_at(cc.ib, cc.tb) if cc.a == rig else cc.a.rope.material_at(cc.ia, cc.ta), bot_rig.flying_length(), cc.ia, cc.ib, cc.ta, cc.tb])
		print("  t=%.2f lado=%+.2f rise=%.1f dist=%.3f (dy=%+.3f) força=%.2f T_eu=%.1f T_bot=%.1f L_bot=%.1f" % [_t, dv.dot(_side), _rise, best, dv.y, cc.force if cc else 0.0, rig.rope.tension_hand, bot_rig.rope.tension_hand, bot_rig.flying_length()])
	if OS.get_cmdline_user_args().has("--debugcombat") and _t > 0.0 and false:
		var w2 := main.physics_world as KitePhysicsWorld
		var c2 := w2.strongest_contact_for(rig)
		var fs := []
		for cc in w2.combat.contacts:
			var spa := cc.a.rope.segment_points(cc.ia)
			var spb := cc.b.rope.segment_points(cc.ib)
			var dd: Vector3 = spb[0].lerp(spb[1], cc.tb) - spa[0].lerp(spa[1], cc.ta)
			fs.append("%.1f/%.2f%s a=%s sep=%.3f |d|=%.3f rise=%.1f" % [cc.force, cc.slide, "H" if cc.hooked else "", "eu" if cc.a == rig else "bot", dd.dot(cc.normal), dd.length(), _rise])
		print("  ", fs)
		print("COMB t=%.2f n=%d F=%.2f slide=%.2f wear=%.3f/%.3f T=%.1f/%.1f" % [_t, w2.combat.contacts.size(), c2.force if c2 else 0.0, c2.slide if c2 else 0.0, LineCombat.max_wear(rig), LineCombat.max_wear(bot_rig), rig.tension, bot_rig.tension])
	if _every(1.0):
		var w := main.physics_world as KitePhysicsWorld
		var c := w.strongest_contact_for(rig)
		print("AUTOTEST combate t=%5.1f contatos=%d força=%.2fN desliz=%.2fm/s desgaste pura=%.2f chilena=%.2f" % [
			_t, w.combat.contacts.size(), c.force if c else 0.0, c.slide if c else 0.0,
			LineCombat.max_wear(rig), LineCombat.max_wear(bot_rig)])
	if _cut_loser != null:
		print("AUTOTEST combate: corte em t=%.1f s, perdedor = %s" % [_cut_time, (_cut_loser as KiteRig).display_name])
		if _cut_loser != rig:
			_ok = false
			print("AUTOTEST FAIL: a linha pura deveria perder para a chilena")
		_finish()
	elif _t > COMBAT_LIMIT:
		_ok = false
		print("AUTOTEST FAIL: as linhas cruzadas não cortaram em %.0f s" % COMBAT_LIMIT)
		_finish()


func _fail(reason: String) -> void:
	_ok = false
	print("AUTOTEST FAIL: ", reason)
	_finish()


func _finish() -> void:
	_done = true
	print("AUTOTEST PASS" if _ok else "AUTOTEST FAILED")
	get_tree().quit(0 if _ok else 1)
