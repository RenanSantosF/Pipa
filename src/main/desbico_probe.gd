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
	main.bot.rig = null
	rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 25.0, 55.0, Wind.get_direction())
	_side = Wind.get_direction().cross(Vector3.UP).normalized() * -1.0


func heading() -> float:
	var b := rig.body
	var d := (b.x - rig.hand_position()).normalized()
	var up := (Vector3.UP - d * d.y).normalized()
	var nose := b.q * Vector3.UP
	nose = (nose - d * nose.dot(d)).normalized()
	return rad_to_deg(atan2(up.cross(nose).dot(d), up.dot(nose)))


var wrap_mode := false
var _tree_added := false


func _physics_process(delta: float) -> void:
	_t += delta
	if wrap_mode:
		_wrap_step(delta)
		return
	var lat := rig.body.x.dot(_side)
	if absf(_t - 6.0) < delta:
		_x0 = lat
	# 6–12 s: toques ESPAÇADOS (1 s) → deve alternar os lados
	# 13–16 s: toques SEGUIDOS (0,35 s) → deve continuar para o mesmo lado
	# 18 s: um toque LONGO (0,7 s)
	var press := false
	if _t > 6.0 and _t < 12.0:
		press = fmod(_t - 6.0, 1.0) < 0.12
	elif _t > 13.0 and _t < 16.0:
		press = fmod(_t - 13.0, 0.35) < 0.1
	elif _t > 18.0 and _t < 18.7:
		press = true
	if it.slack and not press:
		it.desbico_taps += 1
	it.slack = press
	if fmod(_t, 0.25) < delta and _t > 5.5:
		print("PROBE t=%5.2f rumo=%6.1f lateral=%6.2f alt=%5.1f T=%5.2f linha=%5.1f %s" % [_t, rad_to_deg(rig.heading()), lat - _x0, rig.body.x.y, rig.tension, rig.flying_length(), "■" if press else ""])
	if _t > 24.0:
		get_tree().quit(0)


## Copa ao lado do meio da linha; desbica para lá e mede o enrosco.
func _wrap_step(delta: float) -> void:
	var world: KitePhysicsWorld = main.physics_world
	if _t > 4.0 and not _tree_added and world.obstacles:
		var mid := rig.rope.pos[int(rig.rope.pos.size() * 0.5)]
		world.obstacles.add_canopy(mid + _side * 2.2, 1.6)
		_tree_added = true
		print("WRAP árvore em ", mid + _side * 2.2)
	var press := false
	if _t > 5.0 and _t < 12.0:
		press = fmod(_t, 0.5) < 0.2
	if it.slack and not press:
		it.desbico_taps += 1
	it.slack = press
	it.steer = -1.0
	if fmod(_t, 0.5) < delta:
		var r := rig.rope
		print("WRAP t=%5.1f nós_presos=%d T_mão=%5.2f T_pipa=%5.2f lateral=%6.2f alt=%5.1f" % [_t, r.pin_count(), r.tension_hand, r.tension_end, rig.body.x.dot(_side), rig.body.x.y])
	if _t > 16.0:
		get_tree().quit(0)
