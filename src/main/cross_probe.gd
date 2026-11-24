extends Node
## Sonda de ATRAVESSAMENTO de linhas:  -- --crossprobe [--sweep=m/s] [--pulls]
## Duas linhas cruzadas em X; a mão do vizinho varre de um lado para o outro
## (forçando a linha dele contra a do jogador) e o jogador dá puxões. Conta quantas
## vezes uma linha passou para o outro lado da outra SEM dar a volta pela ponta:
## o lado é medido na normal comum dos trechos mais próximos (as duas a < 30 cm).

var main
var rig: KiteRig
var bot: KiteRig
var _t := 0.0
var _hand_b0 := Vector3.ZERO
var _side := Vector3.RIGHT
var _prev_sign := 0.0
var _prev_key := Vector2i(-1, -1)
var _flips := 0
var _contacts_max := 0
var _sweep := 3.0
var _pulls := false
var _hand_a: KiteHand
var _min_d := 99.0
var _near_ticks := 0
var _phase := 0
var _prev_best := 9.0
var _rise := 0.0
var _t1 := 0.0


func start(p_main) -> void:
	main = p_main
	main.input_router.autopilot = true
	for b in main.bots:
		b.rig = null
	rig = main.player_rig
	bot = main.bot_rig
	main.player.rig = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sweep="):
			_sweep = float(a.substr(8))
		elif a == "--pulls":
			_pulls = true
	var wd := Wind.get_direction()
	_side = wd.cross(Vector3.UP).normalized()
	var center := Vector3(0, 0, 40)
	var hand_a := center
	var top := Ground.height_at(center.x, center.z) + 30.0
	hand_a.y = top
	# Vizinho atrás e mais baixo (relo por baixo), linha um pouco atravessada.
	var hand_b := center - wd * 10.0
	hand_b.y = top - 13.0
	rig.launch(hand_a, 30.0, 50.0, wd)
	bot.launch(hand_b, 40.0, 50.0, (wd + _side * 0.25).normalized())
	rig.hand_rest = hand_a
	bot.hand_rest = hand_b
	_hand_b0 = hand_b
	_hand_a = KiteHand.new(rig)
	print("CROSS: varredura %.1f m/s, puxões=%s" % [_sweep, str(_pulls)])


func _physics_process(delta: float) -> void:
	_t += delta
	# Mão do vizinho vai e volta de lado (força a linha dele através da do jogador).
	# Sobe até encostar por baixo; depois força para cima e varre de lado.
	var con := (main.physics_world as KitePhysicsWorld).strongest_contact_for(bot)
	if _phase == 0:
		_rise += 1.5 * delta
		if con != null or _rise > 18.0:
			_phase = 1
			_t1 = _t
	else:
		_rise += 0.6 * delta * (1.0 if con != null else 2.0)   # aperta contra a outra
	var off := sin((_t - _t1) * _sweep / 5.0) * 5.0 if _phase == 1 else 0.0
	bot.hand_rest = _hand_b0 + Vector3.UP * _rise + _side * off
	if _pulls and fmod(_t, 0.5) < delta:
		_hand_a.puxao()
	_hand_a.update(delta, 0.0, 1.0, 0.0)
	if not (rig.is_flying() and bot.is_flying()):
		_finish("uma linha foi cortada em t=%.1f" % _t)
		return
	_measure()
	if _t > 40.0:
		_finish("fim")


func _pts(r: Rope) -> PackedVector3Array:
	var p := r.pos.duplicate()
	if r.end_body != null:
		p.append(r.end_point())
	return p


func _measure() -> void:
	var pa := _pts(rig.rope)
	var pb := _pts(bot.rope)
	var best := 1e9
	var bi := -1
	var bj := -1
	var bres: Array = []
	for i in pa.size() - 1:
		for j in pb.size() - 1:
			var res := LineCombat.closest_segments(pa[i], pa[i + 1], pb[j], pb[j + 1])
			if float(res[2]) < best:
				best = res[2]
				bi = i
				bj = j
				bres = res
	_contacts_max = maxi(_contacts_max, (main.physics_world as KitePhysicsWorld).combat.contacts.size())
	_min_d = minf(_min_d, best)
	if best > 1.5 or bi < 0:
		_prev_sign = 0.0
		return
	if best < 0.05:
		_near_ticks += 1
	var ta: float = bres[0]
	var tb: float = bres[1]
	if ta <= 0.0 or ta >= 1.0 or tb <= 0.0 or tb >= 1.0:
		_prev_sign = 0.0
		return
	var ea := pa[bi + 1] - pa[bi]
	var eb := pb[bj + 1] - pb[bj]
	var n := ea.cross(eb)
	if n.length() < 0.2 * ea.length() * eb.length():
		_prev_sign = 0.0
		return
	n = n.normalized()
	var d := pb[bj].lerp(pb[bj + 1], tb) - pa[bi].lerp(pa[bi + 1], ta)
	var sgn := signf(d.dot(n))
	var key := Vector2i(bi, bj)
	if _prev_sign != 0.0 and sgn != _prev_sign and absi(key.x - _prev_key.x) <= 1 and absi(key.y - _prev_key.y) <= 1 and minf(best, _prev_best) < 0.3:
		_flips += 1
		print("CROSS atravessou t=%.2f dist=%.3f trechos=%s contatos=%d" % [_t, best, str(key), (main.physics_world as KitePhysicsWorld).combat.contacts.size()])
	_prev_sign = sgn
	_prev_key = key
	_prev_best = best


func _finish(why: String) -> void:
	print("CROSS resumo: atravessou=%d ticks_perto=%d dist_min=%.3f contatos_max=%d (%s)" % [_flips, _near_ticks, _min_d, _contacts_max, why])
	set_physics_process(false)
	get_tree().quit()
