extends Node3D
## LABORATÓRIO DA FÍSICA DA PIPA (cena isolada, sem cidade, sem vizinhos).
##
## Chão plano, vento controlado, uma pipa com a física de verdade (corpo rígido +
## cabresto de linha + linha XPBD + rabiola), controlada só pela mão na linha.
## Serve para validar a física ANTES de ir para o jogo.
##
## Interativo (PC):
##   Espaço = desbico (puxadinha)     S = puxão (braçada)      segurar D = puxada contínua
##   segurar W = dar linha (mão aberta)   segurar R = aparar (enrolar)
##   segurar Q = braço à frente (folga)   segurar E = braço para trás
##   ←/→ = direção do vento   ↑/↓ = força do vento   G = rajadas liga/desliga
##   1/2/3 = pipa P/M/G   C = câmera (olho / lado)   Enter = relançar
##
## Medições headless (imprime e sai):
##   godot --headless --path . res://src/lab/physics_lab.tscn -- --seq=<nome> [--len=30] [--wind=6.5] [--size=1]
##   seq: eq | puxao | toques | ritmo | pausa | soltar | aparar | folga | mao | todos

const HAND := Vector3(0.0, 1.3, 0.0)

var world: KitePhysicsWorld
var rig: KiteRig
var hand: LineHand
var cam: Camera3D
var label: Label
var _seq := ""
var _t := 0.0
var _events: Array = []        # [tempo, ação, valor]
var _log_every := 0.5
var _log_t := -1.0
var _len := 30.0
var _size := 1
var _grip := 1.0
var _reel := 0.0
var _cam_side := false
var _stats := {}
var _end_t := 25.0
var _knot_y := -1.0
var _knot_z := -1.0
var _p0 := Vector3.ZERO
var _h_prev := 0.0
var _swings: Array = []         # lados dos balanços (sinal do giro do bico) após toques
var _last_tap_t := -1.0
var _rate_hist: Array = []
var _pmul := {}
var _hs: Array = []
## Azimute e elevação da pipa vistos do pipeiro depois dos 12 s (quanto ela ANDA no céu).
var _azs: Array = []
var _tap_int := 0.25
var _loose: KiteRig = null
var _other: KiteRig = null
var _other_hand := Vector3.ZERO
var _other_sweep := false
var _evlog: Array = []
var _flex := -1.0
var _tail := 1
var _flexrest := -1.0


func _ready() -> void:
	process_physics_priority = -10
	var args := OS.get_cmdline_user_args()
	Wind.direction_wander_deg = 0.0
	Wind.gust_strength = 0.0
	Wind.base_direction_deg = 0.0
	for a in args:
		if a.begins_with("--seq="):
			_seq = a.substr(6)
		elif a.begins_with("--len="):
			_len = float(a.substr(6))
		elif a.begins_with("--wind="):
			Wind.base_speed = float(a.substr(7))
		elif a.begins_with("--size="):
			_size = int(a.substr(7))
		elif a.begins_with("--gust="):
			Wind.gust_strength = float(a.substr(7))
		elif a.begins_with("--ky="):
			_knot_y = float(a.substr(5))
		elif a.begins_with("--kz="):
			_knot_z = float(a.substr(5))
		elif a.begins_with("--flutter="):
			TailChain.FLUTTER_SCALE = float(a.substr(10))
		elif a.begins_with("--flex="):
			_flex = float(a.substr(7))
		elif a.begins_with("--flexrest="):
			_flexrest = float(a.substr(11))
		elif a.begins_with("--tap="):
			# --tap=folga,tempo_folga,pegada,puxada,subida,volta
			var v := a.substr(6).split(",")
			LineHand.TAP_SLACK = float(v[0])
			LineHand.TAP_SLACK_T = float(v[1])
			LineHand.TAP_GIVE = float(v[2])
			LineHand.TUG_LEN = float(v[3])
			LineHand.TUG_UP = float(v[4])
			LineHand.TUG_DOWN = float(v[5])
		elif a.begins_with("--tail="):
			_tail = int(a.substr(7))
		elif a.begins_with("--int="):
			_tap_int = float(a.substr(6))
		elif a.begins_with("--dwn="):
			KiteRig.DESB_WN = float(a.substr(6))
		elif a.begins_with("--dforce="):
			KiteRig.DESB_FORCE = float(a.substr(9))
		elif a.begins_with("--dang="):
			KiteRig.DESB_ANGLE_DEG = float(a.substr(7))
		elif a.begins_with("--dtime="):
			KiteRig.DESB_TIME = float(a.substr(8))
		elif a.begins_with("--rotd="):
			KiteRig.ROT_DAMP_PHYSICAL = float(a.substr(7))
		elif a.begins_with("--dhold2="):
			KiteRig.DESB_HOLD = float(a.substr(9))
		elif a.begins_with("--tslack="):
			LineHand.TAP_SLACK = float(a.substr(9))
		elif a.begins_with("--tslackt="):
			LineHand.TAP_SLACK_T = float(a.substr(10))
		elif a.begins_with("--tgive="):
			LineHand.TAP_GIVE = float(a.substr(8))
		elif a.begins_with("--sdrag="):
			KiteRig.SPOOL_DRAG = float(a.substr(8))
		elif a.begins_with("--tcd="):
			KiteRig.TAIL_CD_PHYSICAL = float(a.substr(6))
		elif a.begins_with("--tflut="):
			KiteRig.TAIL_FLUTTER_PHYSICAL = float(a.substr(8))
		elif a.begins_with("--dchain="):
			KiteRig.DESB_CHAIN = float(a.substr(9))
		elif a.begins_with("--dret="):
			KiteRig.DESB_RETURN = float(a.substr(7))
		elif a.begins_with("--tapauth="):
			KiteRig.DESB_TAP_AUTH = float(a.substr(10))
		elif a.begins_with("--shear="):
			Wind.shear_exponent = float(a.substr(8))
		elif a.begins_with("--gblock="):
			Wind.ground_block_min = float(a.substr(9))
		elif a.begins_with("--wtop="):
			Wind.shear_top = float(a.substr(7))
		elif a.begins_with("--camfov="):
			_cam_fov = float(a.substr(9))
		elif a.begins_with("--addm="):
			KiteRigidBody.ADDED_MASS = float(a.substr(7))
		elif a.begins_with("--addi="):
			KiteRigidBody.ADDED_INERTIA = float(a.substr(7))
		elif a.begins_with("--tug="):
			LineHand.TUG_LEN = float(a.substr(6))
		elif a.begins_with("--dhold="):
			KiteRig.DESB_HOLD = float(a.substr(8))
		elif a.begins_with("--far="):
			LineHand.FAR_GAIN = float(a.substr(6))
		elif a.begins_with("--belly="):
			Rope.LINE_BELLY = float(a.substr(8))
		elif a.begins_with("--tailmul="):
			KiteRig.TAIL_PHYSICAL_OVERRIDE = float(a.substr(10))
		elif a.begins_with("--tailit="):
			TailChain.ITER_OVERRIDE = int(a.substr(9))
		elif a.begins_with("--rolld="):
			KiteRigidBody.ROLL_DAMPING = float(a.substr(8))
		elif a.begins_with("--p:"):
			# --p:campo=valor  (multiplica um campo do perfil depois do tamanho)
			var kv := a.substr(4).split("=")
			_pmul[kv[0]] = float(kv[1])

	_build_scene()
	_launch()
	if _seq != "":
		_plan(_seq)


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.55, 0.35)
	ground.material_override = gm
	add_child(ground)
	# Marcas no chão a cada 10 m (noção de distância).
	for i in range(1, 9):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8.0, 0.02, 0.15)
		m.mesh = bm
		m.position = Vector3(0, 0.01, -10.0 * i)
		add_child(m)
	world = KitePhysicsWorld.new()
	world.name = "KitePhysicsWorld"
	add_child(world)
	rig = KiteRig.new()
	rig.name = "LabRig"
	rig.profile = (load("res://src/kite/profiles/pipa_classica.tres") as KiteProfile).duplicate()
	rig.profile.apply_size(_size)
	rig.profile.apply_tail(_tail)
	for k in _pmul:
		rig.profile.set(k, float(rig.profile.get(k)) * float(_pmul[k]))
	rig.line_type = load("res://src/physics/lines/pura.tres")
	rig.is_local_player = true
	rig.physical = true
	if _knot_y > 0.0:
		rig.knot_y = _knot_y
	if _knot_z > 0.0:
		rig.knot_z = _knot_z
	if _flex >= 0.0:
		rig.flex_per_n = _flex
	if _flexrest >= 0.0:
		rig.flex_rest = _flexrest
	add_child(rig)
	world.register(rig)
	hand = LineHand.new(rig)
	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1))
	ui.add_child(label)


func _launch() -> void:
	rig.launch(HAND, _len, 50.0, Wind.get_direction())
	rig.hand_rest = HAND
	rig.stroke_dir = Vector3(0.0, -0.45, 0.89).normalized()   # do braço para o peito
	hand = LineHand.new(rig)
	_p0 = rig.body.x


func _make_other(hand_pos: Vector3, length: float, elev: float) -> KiteRig:
	var o := KiteRig.new()
	o.name = "Outra"
	o.display_name = "Outra"
	o.profile = (load("res://src/kite/profiles/pipa_adversario.tres") as KiteProfile).duplicate()
	o.profile.apply_size(1)
	o.line_type = load("res://src/physics/lines/pura.tres")
	o.physical = true
	add_child(o)
	world.register(o)
	o.launch(hand_pos, length, elev, Wind.get_direction())
	o.hand_rest = hand_pos
	_other_hand = hand_pos
	for sg in ["loose_kite_hooked", "kite_caught", "tail_grabbed"]:
		EventBus.connect(sg, func(a: Node, b: Node) -> void: print("LAB EVENTO %s t=%.2f %s → %s" % [sg, _t, a.name, b.name]))
	EventBus.tail_cut.connect(func(a: Node, b: Node, _p: Vector3) -> void: print("LAB EVENTO tail_cut t=%.2f %s → %s (rabiola com %d nós)" % [_t, a.name, b.name, (b as KiteRig).tail.pos.size() if (b as KiteRig).tail else -1]))
	return o


# --- Sequências de medição -------------------------------------------------------

func _ev(t: float, what: String, val: float = 0.0) -> void:
	_events.append([t, what, val])


func _plan(seq: String) -> void:
	var s := 12.0
	match seq:
		"eq":
			_end_t = 30.0
		"puxao":
			for k in 4:
				_ev(s + 0.6 * k, "pull")
			_log_every = 0.1
			_end_t = 20.0
		"lado":
			# Um toque por vez, sem puxar: o quanto a pipa anda para cada lado.
			for k in 8:
				_ev(s + k * _tap_int, "tap")
			_log_every = 0.1
			_end_t = s + 8 * _tap_int + 2.0
		"toques":
			# 2 toques + pausa, 4 vezes; depois 1 toque + pausa, 4 vezes.
			var t := s
			for k in 4:
				_ev(t, "tap")
				_ev(t + 0.25, "tap")
				t += 1.15
			t += 1.0
			for k in 4:
				_ev(t, "tap")
				t += 0.9
			_log_every = 0.1
			_end_t = t + 3.0
		"ritmo":
			var t2 := s
			while t2 < s + 5.0:
				_ev(t2, "tap")
				t2 += _tap_int
			_log_every = 0.1
			_end_t = s + 9.0
		"pausa":
			# Toques em ritmo, depois pausa longa: deve voltar reta (bico para cima).
			var t3 := s
			while t3 < s + 3.0:
				_ev(t3, "tap")
				t3 += 0.3
			_log_every = 0.2
			_end_t = s + 12.0
		"revirar":
			# Toques seguidos (0,25 s): continuam girando para o mesmo lado — revira.
			for k in 4:
				_ev(s + k * 0.25, "tap")
			for k in 4:
				_ev(s + 4.0 + k * 0.25, "tap")
			_log_every = 0.1
			_end_t = s + 9.0
		"volta":
			# Vira para a direita (2 toques) e PARA de desbicar: ela tem que voltar sozinha
			# para cima. Depois vira de novo e DESCARREGA (mão aberta 3 s): também volta.
			_ev(s, "tap")
			_ev(s + 0.25, "tap")
			_ev(s + 8.0, "tap")
			_ev(s + 8.25, "tap")
			_ev(s + 9.0, "grip", 0.0)
			_ev(s + 12.0, "grip", 1.0)
			_log_every = 0.25
			_end_t = s + 17.0
		"soltar":
			_ev(s, "grip", 0.0)
			_ev(s + 3.0, "grip", 1.0)
			_log_every = 0.25
			_end_t = s + 10.0
		"aparar":
			_ev(s, "reel", 2.0)
			_ev(s + 4.0, "reel", 0.0)
			_log_every = 0.25
			_end_t = s + 9.0
		"kickrol":
			_ev(s, "kickrol", 4.0)
			_log_every = 0.05
			_end_t = s + 3.0
		"kick", "kickfolga":
			_ev(s, "kick", 3.0)
			if seq == "kickfolga":
				_ev(s - 0.05, "grip", 0.0)
				_ev(s + 0.6, "grip", 1.0)
			_log_every = 0.05
			_end_t = s + 3.0
		"voada":
			# Outra pipa atrás de mim (contra o vento), mais alta; aos 12 s a linha dela é
			# cortada: a pipa voada e a linha dela caem sobre a minha. Eu recolho.
			_other = _make_other(HAND + Vector3(0.0, 0.0, 14.0), 48.0, 62.0)
			_ev(s, "cutother")
			# Mão puxando a 1,6 m/s (v0.24): recolher 30 m leva ~25 s.
			for k in 300:
				_ev(s + 3.0 + k * 0.1, "linepull_if_hooked", 0.15)
			_log_every = 0.5
			_end_t = s + 36.0
		"rabiola":
			# Linha de outra pipa (pura, sem cerol) varrendo de lado na altura da minha rabiola.
			_other = _make_other(HAND + Vector3(12.0, 11.0, -14.0), 30.0, 50.0)
			_other_sweep = true
			_log_every = 0.5
			_end_t = s + 14.0
		"rabiolacerol":
			_other = _make_other(HAND + Vector3(12.0, 11.0, -14.0), 30.0, 50.0)
			_other.line_type = load("res://src/physics/lines/cerol.tres")
			_other.rope.type = _other.line_type
			_other_sweep = true
			_log_every = 0.5
			_end_t = s + 14.0
		"direcao":
			# Vira para a direita (2 toques + pausa, ×2), puxa (vai para a direita);
			# depois vira de cabeça para baixo (1 toque + pausa, ×5) e puxa (desce).
			var t5 := s
			for k in 2:
				_ev(t5, "tap")
				_ev(t5 + 0.25, "tap")
				t5 += 1.1
			for k in 10:
				_ev(t5 + k * 0.2, "linepull", 0.25)
			t5 += 2.5
			for k in 5:
				_ev(t5, "tap")
				t5 += 0.9
			for k in 10:
				_ev(t5 + k * 0.2, "linepull", 0.25)
			_log_every = 0.25
			_end_t = t5 + 3.0
		"corte":
			_ev(s, "cut")
			_log_every = 0.5
			_end_t = s + 20.0
		"dedo":
			# Dedo puxando a linha: 6 arrastos de 0,5 m (0,15 s cada) com a mão voltando.
			for k in 6:
				for j in 5:
					_ev(s + k * 0.45 + j * 0.03, "linepull", 0.1)
			_log_every = 0.1
			_end_t = s + 8.0
		"folga":
			_ev(s, "arm", -1.0)
			_ev(s + 1.0, "arm", 0.0)
			_log_every = 0.1
			_end_t = s + 6.0
		"mao":
			rig.launch_in_hand(HAND, Wind.get_direction())
			rig.hand_rest = HAND
			hand = LineHand.new(rig)
			var t4 := 2.0
			while t4 < 14.0:
				_ev(t4, "tap")
				t4 += 0.3
			for k in 12:
				_ev(5.0 + k * 0.7, "grip", 0.0)
				_ev(5.0 + k * 0.7 + 0.35, "grip", 1.0)
			_log_every = 0.5
			_end_t = 20.0
	_events.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	print("LAB seq=%s linha=%.0f m vento=%.1f m/s tamanho=%d nó=(%.2f, %.2f) flex=%.3f rad/N" % [seq, _len, Wind.base_speed, _size, rig.knot_y, rig.knot_z, rig.flex_per_n])


# --- Medidas ----------------------------------------------------------------------

## [distância, elevação°, azimute°, rumo°, ataque°, rolagem°, arfagem°]
func measure() -> Array:
	var b := rig.body
	var p := b.x - rig.hand_position()
	var d := p.length()
	var el := rad_to_deg(asin(clampf(p.y / maxf(d, 0.001), -1.0, 1.0)))
	var az := rad_to_deg(atan2(p.x, -p.z))
	var knot := rig.rope.end_point() if rig.rope != null else b.x
	var l := (rig.rope.pos[rig.rope.pos.size() - 1] - knot).normalized() if rig.rope != null else -p.normalized()
	var ll := b.q.inverse() * l
	var roll := rad_to_deg(atan2(ll.x, ll.z))
	var pitch := rad_to_deg(atan2(ll.y, ll.z))
	return [d, el, az, rad_to_deg(rig.heading()), rad_to_deg(b.angle_of_attack), roll, pitch]


func _log_line() -> void:
	var m := measure()
	var b := rig.body
	var br := rig.rope.bridle if rig.rope else null
	print("LAB t=%5.2f dist=%5.1f elev=%5.1f° az=%+6.1f° rumo=%+7.1f° ataque=%5.1f° rol=%+6.1f° arf=%+6.1f° vel=%4.1f T_mão=%5.2f T_nó=%5.2f pernas=%4.2f/%4.2f linha=%5.1f diedro=%2.0f/%2.0f°" % [
		_t, m[0], m[1], m[2], m[3], m[4], m[5], m[6], b.v.length(), rig.rope.tension_hand, rig.rope.tension_end,
		br.leg_tension[0] if br else 0.0, br.leg_tension[1] if br else 0.0, rig.flying_length(), rad_to_deg(b.half_dihedral(0)), rad_to_deg(b.half_dihedral(1))])


func _physics_process(delta: float) -> void:
	_t += delta
	if _seq == "corte" and _loose != null and is_instance_valid(_loose) and _loose.body != null and _t - _log_t >= _log_every:
		_log_t = _t
		var lb := _loose.body
		var d := lb.x - HAND
		print("LAB VOADA t=%5.2f alt=%5.1f m longe=%5.1f m (a favor do vento %5.1f m) vel=%4.1f m/s desce=%+4.1f m/s ataque=%3.0f° rumo_bico=%+4.0f° linha=%4.1f m" % [
			_t, lb.x.y, Vector2(d.x, d.z).length(), -d.z, lb.v.length(), lb.v.y, rad_to_deg(lb.angle_of_attack),
			rad_to_deg(atan2((lb.q * Vector3.UP).x, (lb.q * Vector3.UP).y)), _loose.rope.length() if _loose.rope else 0.0])
		if _t >= _end_t:
			get_tree().quit()
		return
	if rig.body == null:
		if _t >= _end_t:
			get_tree().quit()
		return
	if _seq == "":
		_interactive_input()
	else:
		while not _events.is_empty() and _t >= float(_events[0][0]):
			var ev: Array = _events.pop_front()
			match ev[1]:
				"tap":
					hand.tap()
					_last_tap_t = _t
				"pull":
					hand.pull()
				"grip":
					_grip = ev[2]
				"reel":
					_reel = ev[2]
				"arm":
					hand.arm = ev[2]
				"cut":
					_loose = rig.cut(rig.rope.length() - 1.0)
					print("LAB CORTE: linha cortada a 1 m da mão; pipa voada com %.1f m de linha" % (_loose.rope.length() if _loose.rope else 0.0))
				"cutother":
					if _other != null and _other.is_flying():
						_loose = _other.cut(_other.rope.length() - 1.0)
						print("LAB: linha da outra pipa cortada (voada com %.0f m de linha)" % (_loose.rope.length() if _loose.rope else 0.0))
				"linepull_if_hooked":
					for g in world.grabs.grabs:
						if g.catcher == rig:
							hand.pull_line(float(ev[2]))
							break
				"linepull":
					hand.pull_line(float(ev[2]))
				"kick":
					rig.body.w += (rig.body.q * Vector3.BACK) * float(ev[2])
				"kickrol":
					rig.body.w += (rig.body.q * Vector3.UP) * float(ev[2])
	if _other_sweep and _other != null and is_instance_valid(_other) and _other.is_flying():
		var u := clampf((_t - 12.0) / 8.0, 0.0, 1.0)
		_other.hand_rest = _other_hand + Vector3(-24.0 * u, 0.0, 0.0)
		_other.grip = 1.0
	if _seq in ["rabiola", "rabiolacerol"] and _t - _log_t >= _log_every and rig.tail != null:
		var g := world.grabs.grabbed_tail_of(rig)
		print("LAB t=%5.2f rabiola %d nós · presa=%s força=%.2f N · minha pipa alt %.1f az %+.0f°" % [_t, rig.tail.pos.size(), str(g != null), g.force if g else 0.0, rig.body.x.y if rig.body else -1.0, measure()[2] if rig.body else 0.0])
	if _seq == "voada" and _loose == null and _other != null and fmod(_t, 1.0) < delta:
		var ob := _other.body
		print("LAB outra t=%.1f voando=%s alt=%.1f T=%.2f enganches=%d" % [_t, str(_other.is_flying()), ob.x.y if ob else -1.0, _other.tension, world.grabs.grabs.size()])
		for g in world.grabs.grabs:
			print("   enganche tipo=%d %s → %s" % [g.kind, g.catcher.name, g.target.name])
	if _loose != null and _seq == "voada" and _t - _log_t >= _log_every and is_instance_valid(_loose):
		var lb := _loose.body
		var gg := ""
		for g in world.grabs.grabs:
			gg = "enganchada em s=%.1f m (minha linha %.1f m) força %.2f N" % [g.s, rig.flying_length(), g.force]
		print("LAB t=%5.2f voada alt=%.1f %s" % [_t, lb.x.y if lb else -1.0, gg])
	if rig.body == null:
		return
	hand.update(delta, _grip, _reel)
	if _seq != "":
		_collect(delta)
		if _t - _log_t >= _log_every:
			_log_t = _t
			_log_line()
		if _t >= _end_t:
			_report()
			get_tree().quit()


func _collect(delta: float) -> void:
	var m := measure()
	var h: float = m[3]
	var rate := wrapf(h - _h_prev, -180.0, 180.0) / delta
	_h_prev = h
	_stats["tmax"] = maxf(_stats.get("tmax", 0.0), rig.rope.tension_hand)
	if _t > 7.0 and _t < 12.0:
		_stats["ri2"] = _stats.get("ri2", 0.0) + rate * rate
		_stats["rin"] = _stats.get("rin", 0) + 1
	if _t > 12.0 and _t < 17.0:
		_stats["rt2"] = _stats.get("rt2", 0.0) + rate * rate
		_stats["rtn"] = _stats.get("rtn", 0) + 1
		_hs.append(h)
	if _t > 8.0 and _t < 12.0:
		_stats["el_sum"] = _stats.get("el_sum", 0.0) + float(m[1])
		_stats["el_n"] = _stats.get("el_n", 0) + 1
		_stats["el_min"] = minf(_stats.get("el_min", 99.0), m[1])
		_stats["el_max"] = maxf(_stats.get("el_max", -99.0), m[1])
		_stats["az_min"] = minf(_stats.get("az_min", 99.0), m[2])
		_stats["az_max"] = maxf(_stats.get("az_max", -99.0), m[2])
		_stats["h_min"] = minf(_stats.get("h_min", 999.0), h)
		_stats["h_max"] = maxf(_stats.get("h_max", -999.0), h)
		_stats["t_sum"] = _stats.get("t_sum", 0.0) + rig.rope.tension_hand
	if _t >= 12.0:
		_stats["h_min2"] = minf(_stats.get("h_min2", 999.0), h)
		_stats["h_max2"] = maxf(_stats.get("h_max2", -999.0), h)
		_stats["y_max2"] = maxf(_stats.get("y_max2", -99.0), rig.body.x.y)
		_stats["y_min2"] = minf(_stats.get("y_min2", 999.0), rig.body.x.y)
		_stats["az_min2"] = minf(_stats.get("az_min2", 99.0), m[2])
		_stats["az_max2"] = maxf(_stats.get("az_max2", -99.0), m[2])
		# Balanços do bico: picos de giro com sinal (para ver a alternância).
		_rate_hist.append(rate)
		_azs.append(Vector2(m[2], m[1]))
		_stats["h2_sum"] = _stats.get("h2_sum", 0.0) + h * h
		_stats["el2_sum"] = _stats.get("el2_sum", 0.0) + float(m[1])
		_stats["aoa2_sum"] = _stats.get("aoa2_sum", 0.0) + float(m[4])
		_stats["n2"] = _stats.get("n2", 0) + 1
		if absf(h) > 150.0:
			_stats["loops"] = _stats.get("loops", 0) + 1


func _report() -> void:
	var n: int = maxi(_stats.get("el_n", 1), 1)
	print("LAB resumo seq=%s: antes (8–12 s) elevação média %.1f° (%.1f..%.1f), azimute %.1f..%.1f°, rumo %.0f..%.0f°, tração média %.2f N" % [
		_seq, _stats.get("el_sum", 0.0) / n, _stats.get("el_min", 0.0), _stats.get("el_max", 0.0),
		_stats.get("az_min", 0.0), _stats.get("az_max", 0.0), _stats.get("h_min", 0.0), _stats.get("h_max", 0.0), _stats.get("t_sum", 0.0) / n])
	print("LAB resumo depois (12 s+): rumo %.0f..%.0f°, azimute %.1f..%.1f°, altura %.1f..%.1f m, tração máx %.1f N, linha %.1f m" % [
		_stats.get("h_min2", 0.0), _stats.get("h_max2", 0.0), _stats.get("az_min2", 0.0), _stats.get("az_max2", 0.0),
		_stats.get("y_min2", 0.0), _stats.get("y_max2", 0.0), _stats.get("tmax", 0.0), rig.flying_length()])
	# Picos de giro (balanços): sinal de cada pico com |giro| > 40°/s.
	var peaks := []
	var cur_sign := 0
	var cur_peak := 0.0
	for r in _rate_hist:
		var sg := 0 if absf(r) < 40.0 else (1 if r > 0.0 else -1)
		if sg != 0 and sg != cur_sign:
			if cur_sign != 0:
				peaks.append(cur_peak)
			cur_sign = sg
			cur_peak = r
		elif sg == cur_sign and absf(r) > absf(cur_peak):
			cur_peak = r
	if cur_sign != 0:
		peaks.append(cur_peak)
	var txt := ""
	for pk in peaks:
		txt += "%+.0f " % pk
	print("LAB balanços (picos de giro °/s): %s" % txt)
	var n2: int = maxi(_stats.get("n2", 1), 1)
	# Amplitude dos balanços: média das diferenças entre picos e vales consecutivos do rumo.
	var swings := []
	for i in range(1, _hs.size() - 1):
		if (_hs[i] > _hs[i - 1] and _hs[i] >= _hs[i + 1]) or (_hs[i] < _hs[i - 1] and _hs[i] <= _hs[i + 1]):
			swings.append(_hs[i])
	var amp := 0.0
	var na := 0
	for i in range(1, swings.size()):
		var dd := absf(float(swings[i]) - float(swings[i - 1]))
		if dd > 3.0:
			amp += dd
			na += 1
	print("LAB BALANÇO médio %.0f° (%d balanços)" % [amp / maxf(na, 1), na])
	# Quanto a pipa ANDA no céu (o que se vê de longe): vai-e-volta do ponto no céu
	# (azimute/elevação) entre extremos consecutivos, em graus e em metros.
	var walk := 0.0
	var nw := 0
	var last_ext := Vector2.INF
	for i in range(1, _azs.size() - 1):
		var a0: Vector2 = _azs[i - 1]
		var a1: Vector2 = _azs[i]
		var a2: Vector2 = _azs[i + 1]
		if (a1.x > a0.x and a1.x >= a2.x) or (a1.x < a0.x and a1.x <= a2.x):
			if last_ext != Vector2.INF and absf(a1.x - last_ext.x) > 0.3:
				walk += a1.distance_to(last_ext)
				nw += 1
			if last_ext == Vector2.INF or absf(a1.x - last_ext.x) > 0.3:
				last_ext = a1
	var dist := rig.body.x.distance_to(rig.rope.hand_position) if rig.body != null else 0.0
	print("LAB ANDA médio %.1f° (%.1f m a %.0f m) por vai-e-volta (%d)" % [walk / maxf(nw, 1), deg_to_rad(walk / maxf(nw, 1)) * dist, dist, nw])
	print("LAB GIRO parado=%.0f°/s toques=%.0f°/s" % [sqrt(_stats.get("ri2", 0.0) / maxf(_stats.get("rin", 1), 1)), sqrt(_stats.get("rt2", 0.0) / maxf(_stats.get("rtn", 1), 1))])
	print("LAB SCORE elev=%.1f rumo_rms=%.1f aoa=%.1f y_min=%.1f invertida=%.0f%% picos=%d" % [
		_stats.get("el2_sum", 0.0) / n2, sqrt(_stats.get("h2_sum", 0.0) / n2), _stats.get("aoa2_sum", 0.0) / n2,
		_stats.get("y_min2", 0.0), 100.0 * float(_stats.get("loops", 0)) / n2, peaks.size()])


# --- Interativo ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			hand.tap()
		KEY_S:
			hand.pull()
		KEY_LEFT:
			Wind.base_direction_deg -= 10.0
		KEY_RIGHT:
			Wind.base_direction_deg += 10.0
		KEY_UP:
			Wind.base_speed += 0.5
		KEY_DOWN:
			Wind.base_speed = maxf(Wind.base_speed - 0.5, 0.5)
		KEY_G:
			Wind.gust_strength = 0.0 if Wind.gust_strength > 0.0 else 0.35
		KEY_1, KEY_2, KEY_3:
			_size = int((event as InputEventKey).keycode - KEY_1)
			rig.profile.apply_size(_size)
			rig.profile.apply_tail(_tail)
			_launch()
		KEY_C:
			_cam_side = not _cam_side
		KEY_ENTER:
			_launch()


func _interactive_input() -> void:
	_grip = 0.0 if Input.is_key_pressed(KEY_W) else 1.0
	_reel = 2.0 if Input.is_key_pressed(KEY_R) else 0.0
	hand.pull_held = Input.is_key_pressed(KEY_D)
	hand.pull_rate = 0.6
	hand.arm = -1.0 if Input.is_key_pressed(KEY_Q) else (1.0 if Input.is_key_pressed(KEY_E) else 0.0)


var _shot_n := 0
var _cam_fov := 0.0


## --shots: salva quadros da câmera (olho e lado) em build/lab/ para revisão visual.
func _shots() -> void:
	if not OS.get_cmdline_user_args().has("--shots"):
		return
	var times := [6.0, 6.6, 12.3, 12.5, 14.0]
	var per := 1 if _cam_fov > 0.0 else 2   # com --camfov só a vista do olho
	if _shot_n >= times.size() * per or _t < float(times[_shot_n / per]):
		return
	_cam_side = per == 2 and _shot_n % 2 == 1
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://build/lab")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png("%s/lab_%02d_%s.png" % [dir, _shot_n, "lado" if _cam_side else "olho"])
	_shot_n += 1
	if _shot_n >= times.size() * per:
		get_tree().quit()


func _process(_delta: float) -> void:
	_shots()
	if rig.body == null:
		return
	var kp := rig.visual_pose().origin
	if _cam_side:
		var mid := (HAND + kp) * 0.5
		cam.global_position = mid + Vector3(-(kp - HAND).length() * 1.1, 1.0, 0.0)
		cam.look_at(mid)
		cam.fov = 60.0
	else:
		cam.global_position = HAND + Vector3(0.0, 0.35, 0.6)
		cam.look_at(kp)
		var d := cam.global_position.distance_to(kp)
		cam.fov = clampf(rad_to_deg(2.0 * atan(2.4 / maxf(d, 1.0))), 12.0, 60.0)
		if _cam_fov > 0.0:
			cam.fov = _cam_fov   # como no jogo (teste visual de longe)
	if label != null:
		var m := measure()
		var br := rig.rope.bridle if rig.rope else null
		label.text = "LABORATÓRIO DA FÍSICA  —  Espaço desbico · S puxão · D puxada · W dar linha · R aparar · Q/E braço · ←→ vento · ↑↓ força · 1/2/3 tamanho · C câmera · Enter relança\n" + \
			"vento %.1f m/s %+.0f°  rajadas %.2f | linha %.1f m | dist %.1f m  elevação %.0f°  azimute %+.0f° | rumo %+.0f°  ataque %.0f°  rolagem %+.0f° | tração mão %.2f N  nó %.2f N  pernas %.2f / %.2f N" % [
			Wind.base_speed, Wind.base_direction_deg, Wind.gust_strength, rig.flying_length(), m[0], m[1], m[2], m[3], m[4], m[5],
			rig.rope.tension_hand, rig.rope.tension_end, br.leg_tension[0] if br else 0.0, br.leg_tension[1] if br else 0.0]
