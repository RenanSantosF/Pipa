extends Node
## Teste automático (usado no CI, sem tela):
##   godot --headless --path . --fixed-fps 60 -- --autotest
## Simula ~40 s com um roteiro de comandos (soltar, puxar, recolher) e verifica
## se a física da pipa ficou estável e se a pipa realmente voa.

const DURATION := 40.0

var _kite: KiteBody
var _line: KiteLine
var _router: InputRouter
var _t: float = 0.0
var _ok: bool = true
var _alt_sum: float = 0.0
var _alt_samples: int = 0
var _max_tension: float = 0.0
var _length_after_release: float = 0.0
var _done: bool = false


func start(kite: KiteBody, line: KiteLine, router: InputRouter) -> void:
	_kite = kite
	_line = line
	_router = router
	_router.autopilot = true
	print("AUTOTEST: início (vento base %.1f m/s)" % Wind.base_speed)


func _physics_process(delta: float) -> void:
	if _kite == null or _done:
		return
	_t += delta
	var intent := _router.intent
	intent.release = _t > 10.0 and _t < 14.0
	intent.pull = _t > 14.0 and _t < 20.0 and fmod(_t, 1.5) < 0.35
	intent.reel = _t > 20.0 and _t < 23.0
	if absf(_t - 14.0) < delta:
		_length_after_release = _line.length

	if not (_kite.position_ws.is_finite() and _kite.velocity.is_finite()):
		_fail("estado não finito")
		return
	_max_tension = maxf(_max_tension, _line.tension)
	if _t > 28.0:
		_alt_sum += _kite.get_altitude()
		_alt_samples += 1
	if fmod(_t, 2.0) < delta:
		print("AUTOTEST t=%5.1f alt=%6.2f vel_ar=%5.2f aoa=%5.1f tensao=%5.2f linha=%5.1f esticada=%.2f" % [
			_t, _kite.get_altitude(), _kite.airspeed, rad_to_deg(_kite.angle_of_attack),
			_line.tension, _line.length, _line.tautness])
	if _t >= DURATION:
		_finish()


func _fail(reason: String) -> void:
	_ok = false
	print("AUTOTEST FAIL: ", reason)
	_finish()


func _finish() -> void:
	_done = true
	var mean_alt := _alt_sum / maxf(float(_alt_samples), 1.0)
	print("AUTOTEST resumo: altura média (28–40 s) = %.2f m, tensão máx = %.2f N, linha após soltar = %.1f m, arrebentou = %s" % [
		mean_alt, _max_tension, _length_after_release, str(_line.is_broken)])
	if _ok and mean_alt < 8.0:
		_ok = false
		print("AUTOTEST FAIL: a pipa não se manteve no ar")
	if _ok and _line.is_broken:
		_ok = false
		print("AUTOTEST FAIL: a linha arrebentou no roteiro normal")
	if _ok and _length_after_release <= 25.5:
		_ok = false
		print("AUTOTEST FAIL: soltar linha não aumentou o comprimento")
	print("AUTOTEST PASS" if _ok else "AUTOTEST FAILED")
	get_tree().quit(0 if _ok else 1)
