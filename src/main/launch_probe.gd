extends Node
## Sonda da SUBIDA DA MÃO na cidade (física real):  -- --launchprobe [--mode=a|b]
## A pipa começa na mão; desbica em ritmo e dá linha em pulsos, como o jogador.

var main
var rig: KiteRig
var it: PlayerIntent
var _t := 0.0
var _log := 0.0
var _mode := "a"


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	main.input_router.autopilot = true
	it = main.input_router.intent
	for b in main.bots:
		b.rig = null
	main.bot.rig = null
	main.bot_rig.stow()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.substr(7)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wind="):
			Wind.base_speed = float(a.substr(7))
	main.reset_kite()
	print("SUBIDA modo=%s vento=%.1f" % [_mode, Wind.base_speed])


func _physics_process(delta: float) -> void:
	_t += delta
	if rig.body == null:
		return
	# Toques a cada 0,3 s; dar linha em pulsos (mão aberta 0,3 s a cada 0,7 s) com a pipa puxando.
	if fmod(_t, 0.3) < delta and _t > 1.0 and not OS.get_cmdline_user_args().has("--notaps"):
		it.desbico_toques += 1
	if _t > 1.0 and _t < 1.1 and OS.get_cmdline_user_args().has("--notaps"):
		it.desbico_toques += 1   # só para soltar da mão
	var give := fmod(_t, 0.7) < 0.3 and _t > 2.0 and rig.flying_length() < 35.0
	if _mode == "b":
		give = _t > 2.0 and rig.flying_length() < 35.0 and rig.tension > 0.5
	var alt0 := rig.body.x.y - rig.hand_position().y
	if _mode == "c":
		# Puxa (mão sobre mão) enquanto está baixa; alta e puxando, dá linha.
		give = alt0 > 7.0 and rig.tension > 1.2 and rig.flying_length() < 35.0
		if alt0 < 9.0 and fmod(_t, 0.45) < delta and _t > 1.0:
			it.line_pull += 0.45
	it.grip = 0.0 if give else 1.0
	if _mode.begins_with("g"):
		# Mão entreaberta: a linha só corre quando a pipa puxa mais que o atrito.
		it.grip = float(_mode.substr(1)) if _t > 2.0 and rig.flying_length() < 35.0 else 1.0
	if _t - _log >= 1.0:
		_log = _t
		var alt := rig.body.x.y - rig.hand_position().y
		print("SUBIDA t=%4.1f linha=%5.1f m alt=%5.1f m T=%4.2f N na_mão=%s" % [_t, rig.flying_length(), alt, rig.tension, str(rig.held)])
	if _t > 25.0:
		get_tree().quit()
