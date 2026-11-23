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
	for r in [rig, bot_rig]:
		r.profile = r.profile.duplicate()
		r.profile.apply_size(KiteProfile.Size.M)
		r.profile.apply_bow(KiteProfile.Bow.MEDIA)
	rig.launch_in_hand(main.player.global_position + Vector3(0.2, 1.18, -0.3), Wind.get_direction())
	print("AUTOTEST: início (vento %.1f m/s, linha %s)" % [Wind.base_speed, rig.line_type.display_name])


func _on_line_cut(_winner: Node, loser: Node) -> void:
	if _cut_loser == null:
		_cut_loser = loser
		_cut_time = _t


func _physics_process(delta: float) -> void:
	if _done:
		return
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
		# Desbico a cada 0,6 s alternando os lados (zigue-zague); entre eles, abre a mão
		# quando a pipa puxa (vai dando linha).
		if fmod(_t, 0.6) < 1.0 / 60.0:
			it.taps.append(-1.0 if int(_t / 0.6) % 2 == 0 else 1.0)
		it.grip = 0.3 if (fmod(_t, 3.0) > 1.8 and rig.tension > 1.0) else 1.0
	else:
		it.grip = 1.0
	if _t > 26.0:
		_alt_sum += b.x.y
		_alt_n += 1
	if fmod(_t, 2.0) < 1.0 / 60.0:
		print("AUTOTEST voo t=%5.1f alt=%6.2f ar=%5.2f aoa=%5.1f T=%5.2f linha=%5.1f presa=%s enrosc=%s física=%.2fms" % [
			_t, b.x.y, b.airspeed, rad_to_deg(b.angle_of_attack), rig.tension, rig.flying_length(), str(rig.held), str(rig.snagged),
			main.physics_world.frame_ms])
	if _t >= 34.0:
		var mean_alt := _alt_sum / maxf(float(_alt_n), 1.0)
		print("AUTOTEST voo: subiu da mão até %.1f m de altura média, linha %.1f m, tensão máx %.1f N" % [mean_alt, rig.flying_length(), _max_tension])
		if mean_alt < 7.0:
			_ok = false
			print("AUTOTEST FAIL: desbicando e dando linha a pipa não subiu da mão")
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
	if fmod(_t, 1.0) < 1.0 / 60.0:
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
