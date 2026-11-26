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
	main.reset_kite()
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
		"descer":
			for k in 6:
				_events.append([s, "tap"])
				s += 0.9
			for k in 8:
				_events.append([s + k * 0.4, "pull"])
	print("TAP seq=%s intervalo=%.2f tamanho=%s" % [_seq, _int, rig.profile.size_class])
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
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var ev: String = _events[0][1]
		_events.pop_front()
		if ev == "tap":
			it.desbico_toques += 1
		else:
			it.recolhe.append(0.8)
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
	if _t > _start + 8.0:
		print("TAP resumo seq=%s: rumo final %+.0f° (mín %+.0f°, máx %+.0f°)" % [_seq, rad_to_deg(wrapf(f.heading - _h0, -PI, PI)), _min_h, _max_h])
		set_physics_process(false)
		get_tree().quit()
