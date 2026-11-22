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


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	bot_rig = main.bot_rig
	router = main.input_router
	router.autopilot = true
	main.bot.rig = null  # bot parado durante a fase 1
	EventBus.line_cut.connect(_on_line_cut)
	rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 30.0, 50.0, Wind.get_direction())
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
	if _t < 10.0:
		_input_set(0.0, 1.0, 0.0)
		if _t > 5.0:
			_alt_sum += b.x.y
			_alt_n += 1
	elif _t < 14.0:
		if _len_before_release == 0.0:
			_len_before_release = rig.flying_length()
		_input_set(0.0, 0.0, 0.0)  # mão aberta: dá linha
	elif _t < 20.0:
		if _len_after_release == 0.0:
			_len_after_release = rig.flying_length()
		var ph := fmod(_t, 1.0)
		_input_set(0.6 if ph < 0.4 else 0.0, 1.0, 0.0)  # braçadas
	elif _t < 24.0:
		if _pile_after_strokes == 0.0:
			_pile_after_strokes = rig.pile
		_input_set(0.0, 1.0, 2.5)  # enrola
	else:
		_input_set(0.0, 1.0, 0.0)
	if fmod(_t, 2.0) < 1.0 / 60.0:
		print("AUTOTEST voo t=%5.1f alt=%6.2f ar=%5.2f aoa=%5.1f T=%5.2f linha=%5.1f chão=%4.1f lata=%5.1f nós=%d física=%.2fms" % [
			_t, b.x.y, b.airspeed, rad_to_deg(b.angle_of_attack), rig.tension, rig.flying_length(), rig.pile, rig.spool,
			rig.rope.node_count(), main.physics_world.frame_ms])
	if _t >= 30.0:
		var mean_alt := _alt_sum / maxf(float(_alt_n), 1.0)
		print("AUTOTEST voo: altura média %.1f m, linha antes/depois de soltar %.1f/%.1f m, chão após braçadas %.1f m, tensão máx %.1f N" % [
			mean_alt, _len_before_release, _len_after_release, _pile_after_strokes, _max_tension])
		if mean_alt < 10.0:
			_ok = false
			print("AUTOTEST FAIL: a pipa não se sustentou no ar")
		if _len_after_release < _len_before_release + 2.0:
			_ok = false
			print("AUTOTEST FAIL: dar linha não aumentou o comprimento")
		if _pile_after_strokes < 1.0:
			_ok = false
			print("AUTOTEST FAIL: braçadas não puxaram linha")
		_start_combat()


func _start_combat() -> void:
	_phase = 2
	_t = 0.0
	_cut_loser = null
	# X simétrico: as duas linhas se cruzam no meio, na mesma altura.
	rig.line_type = load("res://src/physics/lines/pura.tres")
	bot_rig.line_type = load("res://src/physics/lines/chilena.tres")
	var wd := Wind.get_direction()
	var side := wd.cross(Vector3.UP).normalized()
	var center := Vector3(0, 0, 40)
	var hand_a := center + side * 6.0 + Vector3.UP * 1.4
	var hand_b := center - side * 6.0 + Vector3.UP * 1.4
	rig.launch(hand_a, 30.0, 45.0, (wd - side * 0.7).normalized())
	bot_rig.launch(hand_b, 30.0, 45.0, (wd + side * 0.7).normalized())
	rig.hand_rest = hand_a
	bot_rig.hand_rest = hand_b
	print("AUTOTEST combate: %s × %s" % [rig.line_type.display_name, bot_rig.line_type.display_name])


func _phase_combat(_delta: float) -> void:
	# Mãos paradas; o bot "dá linha" de vez em quando (como no relo de verdade).
	_input_set(0.0, 1.0, 0.0)
	rig.hand_rest = rig.hand_rest
	bot_rig.grip = 0.3 if fmod(_t, 2.0) < 0.8 else 1.0
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
