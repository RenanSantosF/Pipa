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
	for a in OS.get_cmdline_user_args():
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
		if tow >= 0.0:
			r.profile.tow_fraction = tow
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--prof="):
				var kv := a.substr(7).split(":")
				r.profile.set(kv[0], float(kv[1]))
	rig.launch_in_hand(main.player.global_position + Vector3(0.2, 1.18, -0.3), Wind.get_direction())
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
	it.stroke = 0.0
	it.reel_rate = 0.0
	if _t < 28.0:
		# Como um pipeiro levantando a pipa: trancos a cada 0,6 s (soltando da mão
		# eles saem de lado, em zigue-zague); com ela alta e puxando, de tempos em
		# tempos abre a mão e deixa correr linha. Firme no alto: para de puxar.
		var d := rig.body.x - rig.hand_position()
		var el := d.y / maxf(d.length(), 0.01)
		if _every(0.6):
			it.pull_taps += 1
		it.grip = 0.3 if (fmod(_t, 3.0) > 1.8 and rig.tension > 1.0 and el > 0.48) else 1.0
	else:
		it.grip = 1.0
	if _t > 26.0:
		_alt_sum += b.x.y
		_alt_n += 1
	if OS.get_cmdline_user_args().has("--debugtug") and _t > 0.55 and _t < 1.0:
		print("TUG t=%.3f stroke=%.3f grip=%.2f Tend=%.2f Thand=%.2f hand=%s kite=%s held=%s len=%.2f" % [_t, rig.stroke, rig.grip, rig.rope.tension_end, rig.rope.tension_hand, str(rig.hand_position().snapped(Vector3.ONE * 0.01)), str(b.x.snapped(Vector3.ONE * 0.01)), str(rig.held), rig.flying_length()])
	if OS.get_cmdline_user_args().has("--debuglaunch") and _t < 3.0 and _every(0.1):
		var hp := rig.hand_position()
		print("LAUNCH t=%.2f aoa=%.0f ar=%.1f lift=%.2f drag=%.2f w=%s kite=%s v=%s hand=%s chão=%.2f T=%.2f grip=%.2f stroke=%.2f nose=%s" % [_t, rad_to_deg(b.angle_of_attack), b.airspeed, b.lift, b.drag, str(b.w.snapped(Vector3.ONE * 0.1)), str(b.x.snapped(Vector3.ONE * 0.01)), str(b.v.snapped(Vector3.ONE * 0.01)), str(hp.snapped(Vector3.ONE * 0.01)), Ground.height_at(b.x.x, b.x.z), rig.tension, rig.grip, rig.stroke, str((b.q * Vector3.UP).snapped(Vector3.ONE * 0.01))])
	if _every(2.0):
		print("AUTOTEST voo t=%5.1f alt=%6.2f ar=%5.2f aoa=%5.1f T=%5.2f linha=%5.1f presa=%s enrosc=%s contatos=%d física=%.2fms" % [
			_t, b.x.y, b.airspeed, rad_to_deg(b.angle_of_attack), rig.tension, rig.flying_length(), str(rig.held), str(rig.snagged), rig.rope.contact_count(),
			main.physics_world.frame_ms])
	if _every(4.0) and rig.rope.contact_count() > 0:
		var obs: WorldObstacles = main.physics_world.obstacles
		var names := []
		for i in rig.rope.pos.size():
			var oi := rig.rope.pin_obstacle[i]
			if oi >= 0:
				names.append("%s%s@%.1f" % [obs.entry_name(oi), "*" if rig.rope.pinned[i] == 1 else "", rig.rope.pos[i].y])
		print("AUTOTEST   contatos: ", names, " T_seg=", rig.rope.seg_tension)
	if _t >= 34.0:
		var mean_alt := _alt_sum / maxf(float(_alt_n), 1.0)
		print("AUTOTEST voo: subiu da mão até %.1f m de altura média, linha %.1f m, tensão máx %.1f N" % [mean_alt, rig.flying_length(), _max_tension])
		if mean_alt < 7.0:
			_ok = false
			print("AUTOTEST FAIL: desbicando e dando linha a pipa não subiu da mão")
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
	if _t > 2.0 and (con == null or con.force < 1.5) and _rise < 16.0:
		_rise += 1.2 * _delta
	bot_rig.hand_rest = _hand_b0 + Vector3.UP * _rise
	_hand_b.update(_delta, 0.0, 0.3 if fmod(_t, 2.0) < 0.8 and _t > 4.0 else 1.0, 0.0)
	if OS.get_cmdline_user_args().has("--debugcombat") and _t > 0.0:
		var w2 := main.physics_world as KitePhysicsWorld
		var c2 := w2.strongest_contact_for(rig)
		var fs := []
		for cc in w2.combat.contacts:
			fs.append("%.1f/%.2f%s a=%s ia=%d/%d ta=%.2f ib=%d/%d tb=%.2f" % [cc.force, cc.slide, "H" if cc.hooked else "", "eu" if cc.a == rig else "bot", cc.ia, cc.a.rope.segment_count(), cc.ta, cc.ib, cc.b.rope.segment_count(), cc.tb])
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
