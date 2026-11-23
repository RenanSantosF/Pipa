class_name AudioDirector
extends Node
## Sons do jogo, todos posicionais (mais alto perto, mais baixo longe):
##  - cada pipa: papel tremulando (volume/tom pela velocidade do ar);
##  - cada cruzamento de linhas: chiado do cerol relando (força × deslizamento);
##  - corte/arrebentar: estalo no ponto do corte;
##  - jogador: linha "cantando" na mão (tom ∝ √tensão, como corda esticada),
##    catraca da lata, vento ambiente.
## Também cuida da vibração do celular (tensão alta, relando, corte).

var world: KitePhysicsWorld
var player_rig: KiteRig

var _flutters: Dictionary = {}   # KiteRig -> AudioStreamPlayer3D
var _grinds: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer
var _vibe_cooldown: float = 0.0


func _ready() -> void:
	_wind = _player2d(Sfx.wind, -24.0)
	for i in 2:
		var g := AudioStreamPlayer3D.new()
		g.stream = Sfx.grind
		g.unit_size = 4.0
		g.max_distance = 120.0
		g.volume_db = -60.0
		add_child(g)
		g.play()
		_grinds.append(g)
	EventBus.line_cut.connect(_on_line_cut)
	EventBus.line_snapped.connect(_on_snapped)


func _player2d(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	_vibe_cooldown = maxf(_vibe_cooldown - delta, 0.0)
	if world == null:
		return
	# Papel tremulando em cada pipa.
	for r in world.rigs:
		if not is_instance_valid(r) or r.body == null:
			continue
		var f: AudioStreamPlayer3D = _flutters.get(r)
		if f == null or not is_instance_valid(f):
			f = AudioStreamPlayer3D.new()
			f.stream = Sfx.flutter
			f.unit_size = 1.2
			f.max_distance = 45.0
			r.add_child(f)
			f.play(randf() * 1.5)
			_flutters[r] = f
		f.global_position = r.body.x
		var air := clampf(r.body.airspeed / 12.0, 0.0, 1.5)
		f.volume_db = linear_to_db(0.02 + air * 0.35)
		f.pitch_scale = 0.85 + air * 0.25
	for k in _flutters.keys():
		if not is_instance_valid(k) or (k as KiteRig).body == null:
			var p = _flutters[k]
			if is_instance_valid(p):
				p.queue_free()
			_flutters.erase(k)
	# Linhas relando.
	var cs := world.combat.contacts.duplicate()
	cs.sort_custom(func(a, b) -> bool: return a.force * a.slide > b.force * b.slide)
	for i in _grinds.size():
		var g := _grinds[i]
		if i < cs.size():
			var c: LineCombat.Contact = cs[i]
			var energy := clampf(c.force * (0.2 + c.slide) / 6.0, 0.0, 1.0)
			g.global_position = c.position
			g.volume_db = linear_to_db(0.01 + energy * 0.5)
			g.pitch_scale = 0.8 + clampf(c.slide / 4.0, 0.0, 0.8)
			if player_rig and (c.a == player_rig or c.b == player_rig) and energy > 0.15:
				_vibrate(25, clampf(energy, 0.2, 1.0))
		else:
			g.volume_db = -60.0
	if player_rig and player_rig.rope and player_rig.tension > player_rig.line_type.break_tension * 0.75:
		_vibrate(15, 0.4)
	_wind.volume_db = linear_to_db(0.05 + clampf(Wind.get_gust_factor() - 0.7, 0.0, 1.0) * 0.12)


func set_enabled(on: bool) -> void:
	AudioServer.set_bus_mute(0, not on)


func _vibrate(ms: int, amplitude: float) -> void:
	if _vibe_cooldown > 0.0 or not OS.has_feature("mobile"):
		return
	_vibe_cooldown = 0.06
	Input.vibrate_handheld(ms, amplitude)


func _snap_at(pos: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.snap
	p.unit_size = 5.0
	p.volume_db = -6.0
	p.max_distance = 200.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func _on_line_cut(winner: Node, loser: Node) -> void:
	var lr := loser as KiteRig
	if lr and lr.rope:
		_snap_at(lr.rope.end_point())
	if player_rig and (winner == player_rig or loser == player_rig):
		_vibrate(180, 1.0)


func _on_snapped(pos: Vector3) -> void:
	_snap_at(pos)
	_vibrate(200, 1.0)
