extends Node
## Sonda do DESBICO por toques:  -- --tapprobe [--seq=nome] [--size=0|1|2] [--int=0.25]
## Os toques entram pelo mesmo caminho do jogo (PlayerIntent.desbico_toques).
## Imprime o rumo do bico, a altura e a distância da pipa ao longo do tempo.
##
##   ritmo  — toques a cada `int` s por 4 s (deve manter o rumo, balançando)
##   dupla  — 2 toques + pausa de 0,9 s, quatro vezes (deve virar para a DIREITA)
##   um     — 1 toque + pausa de 0,9 s, quatro vezes (ESQUERDA)
##   tres   — 3 toques + pausa, três vezes (ESQUERDA)
##   virar  — 2 toques + pausa até apontar ~90° à direita, depois ritmo (vai reto p/ lá)
##   descer — 1 toque + pausa até ficar de cabeça para baixo, depois puxa (desce)

var main
var rig: KiteRig
var it: PlayerIntent
var _t := 0.0
var _seq := "ritmo"
var _int := 0.25
var _events: Array = []    # [tempo, "tap"|"pull"]
var _log_t := 0.0
var _h0 := 0.0
var _p0 := Vector3.ZERO
var _min_h := 99.0
var _max_h := -99.0
var _start := 3.0
## --film: salva quadros da câmera do jogador (0,1 s) em build/film/ para revisão.
var _film := false
var _film_t := -1.0
var _film_dir := ""
var _film_n := 0
var _give_until := -1.0
var _tmax := 0.0


func start(p_main) -> void:
	main = p_main
	rig = main.player_rig
	GameConfig.physical_flight = false
	rig.physical = false   # sonda do modelo de voo antigo
	main.input_router.autopilot = true
	it = main.input_router.intent
	for b in main.bots:
		b.rig = null
	main.bot.rig = null
	main.bot_rig.stow()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seq="):
			_seq = a.substr(6)
		elif a.begins_with("--size="):
			rig.profile.apply_size(int(a.substr(7)))
		elif a.begins_with("--int="):
			_int = float(a.substr(6))
		elif a == "--film":
			_film = true
	Wind.direction_wander_deg = 0.0
	Wind.gust_strength = 0.0
	if _seq == "subir":
		main.reset_kite()   # na mão, linha curta
	elif _seq == "parada":
		# Linha comprida, sem mexer: a linha nunca pode arrebentar nem escorregar sozinha.
		Wind.gust_strength = 0.45
		rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 75.0, 45.0, Wind.get_direction())
	else:
		rig.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 22.0, 50.0, Wind.get_direction())
		main.player.look_at_point(rig.body.x)
	var s := _start
	match _seq:
		"ritmo":
			var t := s
			while t < s + 4.0:
				_events.append([t, "tap"])
				t += _int
		"dupla":
			for k in 4:
				_events.append([s, "tap"])
				_events.append([s + _int, "tap"])
				s += _int + 0.9
		"um":
			for k in 4:
				_events.append([s, "tap"])
				s += 0.9
		"tres":
			for k in 3:
				for j in 3:
					_events.append([s + j * _int, "tap"])
				s += 2.0 * _int + 0.9
		"virar":
			for k in 3:
				_events.append([s, "tap"])
				_events.append([s + _int, "tap"])
				s += _int + 0.9
			var t2 := s
			while t2 < s + 3.0:
				_events.append([t2, "tap"])
				t2 += _int
		"subir":
			# Da mão: desbicando em ritmo; a partir de 4 s, dando linha junto.
			var t3 := s
			while t3 < s + 8.0:
				_events.append([t3, "tap"])
				t3 += 0.28
			for k in 9:
				_events.append([s + 3.0 + k * 0.5, "give"])
		"descer":
			for k in 6:
				_events.append([s, "tap"])
				s += 0.9
			for k in 8:
				_events.append([s + k * 0.4, "pull"])
	_events.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	print("TAP seq=%s intervalo=%.2f tamanho=%s olho=%.2f m" % [_seq, _int, rig.profile.size_class, main.player.head.position.y])
	if _film:
		_film_dir = ProjectSettings.globalize_path("res://build/film")
		DirAccess.make_dir_recursive_absolute(_film_dir)


func _process(_delta: float) -> void:
	if not _film or _t < _start - 0.2 or _t > _start + 6.0:
		return
	if _t - _film_t >= 0.1:
		_film_t = _t
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var cam := get_viewport().get_camera_3d()
		var ks := cam.unproject_position(rig.body.x) if cam and rig.body else Vector2.ZERO
		img.save_png("%s/f%03d_%.2f_%d_%d.png" % [_film_dir, _film_n, _t - _start, int(ks.x), int(ks.y)])
		_film_n += 1


func _physics_process(delta: float) -> void:
	_t += delta
	if rig.body == null or rig.flight == null:
		return
	if _seq != "subir" and _t < _start and _t > 0.5:
		rig.release_hold()
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var ev: String = _events[0][1]
		_events.pop_front()
		if ev == "tap":
			it.desbico_toques += 1
		elif ev == "give":
			_give_until = _t + 0.3
		else:
			it.recolhe.append(0.8)
	it.grip = 0.0 if _t < _give_until else 1.0
	var f := rig.flight
	var p := rig.body.x
	if _t < _start:
		_h0 = f.heading
		_p0 = p
		return
	var dh := rad_to_deg(wrapf(f.heading - _h0, -PI, PI))
	_min_h = minf(_min_h, dh)
	_max_h = maxf(_max_h, dh)
	if _t - _log_t >= 0.1:
		_log_t = _t
		var side := (p - _p0).dot(f.frame()[2])
		print("TAP t=%5.2f rumo=%+6.1f° giro=%+6.0f°/s lado=%+5.1fm alt=%5.1fm dist=%5.1fm vel=%4.1f linha=%4.1f" % [
			_t - _start, dh, rad_to_deg(f.yaw_rate), side, p.y - main.player.global_position.y,
			(p - rig.hand_position()).length(), f.speed, rig.flying_length()])
	if rig.rope != null:
		_tmax = maxf(_tmax, rig.tension)
	if _t > _start + (11.0 if _seq == "subir" else (40.0 if _seq == "parada" else 8.0)):
		print("TAP tração máx %.1f N (linha aguenta %.0f N, mão escorrega acima de %.0f N), linha %.1f m" % [_tmax, rig.line_type.break_tension, 0.7 * rig.line_type.break_tension, rig.flying_length()])
		print("TAP resumo seq=%s: rumo final %+.0f° (mín %+.0f°, máx %+.0f°)" % [_seq, rad_to_deg(wrapf(f.heading - _h0, -PI, PI)), _min_h, _max_h])
		set_physics_process(false)
		get_tree().quit()
