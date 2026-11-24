extends Node
## Teste automático (CI, sem tela):  godot --headless --path . --fixed-fps 60 -- --autotest
##
## Fase 1 — voo (30 s): pipa estável no ar; dar linha aumenta o comprimento;
##          braçadas mandam linha para o chão; recolher enrola.
## Fase 2 — combate (até 30 s): duas linhas cruzadas em X, CHILENA contra PURA.
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
var _rise := 0.0


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	bot_rig = main.bot_rig
	router = main.input_router
	router.autopilot = true
	for b in main.bots:
		b.rig = null  # vizinhos parados durante o teste
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
	elif _t < 10.0:
		it.grip = 0.15                      # dar linha
		_m["len1"] = rig.flying_length()
		_m["el1"] = el
	elif _t < 14.0:
		if _every(0.4):
			it.recolhe.append(0.8)          # puxões
		_m["len2"] = rig.flying_length()
		_m["el2"] = el
		_m["lat2"] = lat
	elif _t < 17.0:
		it.guide_dir = _window_dir(Vector2(-1, 0))   # guiar para a esquerda
		it.guide_amount = 1.0
		_m["lat3"] = lat
	elif _t < 20.0:
		it.guide_dir = _window_dir(Vector2(1, 0))    # guiar para a direita
		it.guide_amount = 1.0
		_m["lat4"] = lat
	if _t > 26.0:
		_alt_sum += b.x.y - main.player.global_position.y
		_alt_n += 1
	if _every(2.0):
		print("AUTOTEST voo t=%5.1f alt=%6.2f el=%4.0f lat=%+6.1f T=%5.2f linha=%5.1f física=%.2fms" % [
			_t, b.x.y - main.player.global_position.y, el, lat, rig.tension, rig.flying_length(), main.physics_world.frame_ms])
	if _t >= 30.0:
		var mean_alt := _alt_sum / maxf(float(_alt_n), 1.0)
		print("AUTOTEST voo: dar linha %.1f → %.1f m · puxar %.1f → %.1f m (elevação %.0f° → %.0f°) · esquerda %+.1f m · direita %+.1f m · altura final %.1f m" % [
			_m["len0"], _m["len1"], _m["len1"], _m["len2"], _m["el1"], _m["el2"], _m["lat3"] - _m["lat2"], _m["lat4"] - _m["lat3"], mean_alt])
		var checks := [
			[_m["len1"] > _m["len0"] + 2.0, "dar linha não deu linha"],
			[_m["len2"] < _m["len1"] - 2.0, "puxar não recolheu linha"],
			[_m["el2"] > _m["el1"] + 2.0, "puxar não fez a pipa subir no céu"],
			[_m["lat3"] - _m["lat2"] < -3.0, "guiar para a esquerda não levou a pipa para a esquerda"],
			[_m["lat4"] - _m["lat3"] > 3.0, "guiar para a direita não levou a pipa para a direita"],
			[mean_alt > 6.0, "a pipa não se manteve no ar"],
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
	var center := Vector3(0, 0, 40)
	var hand_a := center
	var hand_b := center - wd * 10.0
	var top := maxf(Ground.height_at(hand_a.x, hand_a.z), Ground.height_at(hand_b.x, hand_b.z)) + 30.0
	hand_a.y = top
	hand_b.y = top - 13.0
	rig.launch(hand_a, 30.0, 50.0, wd)
	bot_rig.launch(hand_b, 40.0, 50.0, wd)
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
	# Mãos paradas; o bot "dá linha" de vez em quando (como no relo de verdade).
	rig.grip = 1.0
	# Sobe a mão até a linha dele apertar a sua por baixo; depois segura a altura.
	var con := (main.physics_world as KitePhysicsWorld).strongest_contact_for(bot_rig)
	if _t > 2.0 and (con == null or con.force < 1.5) and _rise < 22.0:
		_rise += 1.2 * _delta
	bot_rig.hand_rest = _hand_b0 + Vector3.UP * _rise
	# Dá linha só relando (apertando contra a outra), como no relo de verdade.
	var relando := con != null and con.force > 0.5
	_hand_b.update(_delta, 0.0, 0.3 if relando and fmod(_t, 2.0) < 0.8 and _t > 4.0 else 1.0, 0.0)
	if OS.get_cmdline_user_args().has("--debugcombat") and _t > 0.0:
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
	elif _t > 30.0:
		_ok = false
		print("AUTOTEST FAIL: as linhas cruzadas não cortaram em 30 s")
		_finish()


func _fail(reason: String) -> void:
	_ok = false
	print("AUTOTEST FAIL: ", reason)
	_finish()


func _finish() -> void:
	_done = true
	print("AUTOTEST PASS" if _ok else "AUTOTEST FAILED")
	get_tree().quit(0 if _ok else 1)
