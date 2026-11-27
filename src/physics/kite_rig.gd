class_name KiteRig
extends Node3D
## Uma pipa completa: corpo rígido + linha + rabiola + lata/carretel.
## Quem controla (jogador, bot, rede) só escreve as entradas abaixo a cada tick;
## a simulação roda no KitePhysicsWorld, junto com todas as outras pipas
## (necessário para o cruzamento de linhas ser estável).
##
## Entradas de controle:
##   hand_rest  — onde fica a mão da linha em repouso (mundo)
##   stroke_dir — direção da braçada (da mão para o peito/baixo)
##   stroke     — quanto a mão está puxada (m, 0 = repouso)
##   grip       — força da pegada (1 = segura, 0 = solta; linha corre com a tensão)
##   reel_rate  — enrolando na lata (m/s)
##
## Braçada (como na rua): a mão puxa a linha; quando a mão volta para pegar de novo,
## a outra mão segura, então o trecho puxado vai para o chão ("linha no chão").
## Recolher enrola primeiro a linha do chão; soltar dá primeiro a linha do chão.

signal line_cut(rig: KiteRig, position: Vector3)

const GRIP_MAX := 40.0       # N de atrito com a mão fechada
const FEED_MASS := 0.06      # inércia da linha + lata girando
const FEED_DAMP := 2.5
const MIN_LENGTH := 2.0
const REEL_HARD_TENSION := 25.0
## Amortecimento residual de rotação da pipa física (balanços do desbico claros).
static var ROT_DAMP_PHYSICAL := 0.4
## Comprimento da rabiola na pipa física (× o do perfil), por rabiola [curta, média,
## grande]. Na física real é a rabiola que segura a pipa: a curta do perfil (55%)
## deixava a pipinha e a média instáveis (davam looping e caíam).
const TAIL_PHYSICAL := [1.65, 1.2, 1.0]
static var TAIL_PHYSICAL_OVERRIDE := 0.0

@export var profile: KiteProfile
@export var line_type: LineType
@export var spool_capacity: float = 300.0
@export var display_name: String = "Você"

var body: KiteRigidBody
var rope: Rope
var tail: TailChain
## Pipa voada (linha cortada, sem dono).
var loose: bool = false
var is_local_player: bool = false

# Controle.
var hand_rest := Vector3.ZERO
var stroke_dir := Vector3.BACK
var stroke: float = 0.0
var grip: float = 1.0
var reel_rate: float = 0.0
## Atuadores físicos do desbico (escritos pela KiteHand; ver docs/REVISAO_V5.md §1):
##   bridle_offset — deslocamento do ponto de tração (m, local X lateral / Y espinha):
##                   a perna do cabresto do lado puxado carrega mais. O torque que gira
##                   o bico sai da PRÓPRIA tensão da linha (T·sen b·Δx).
##   sail_asym     — flexão assimétrica das varetas envergadas (rad; + = meia-vela
##                   direita fecha). Desloca o centro de sustentação.
var bridle_offset := Vector2.ZERO
var sail_asym: float = 0.0
## Viés da vareta relaxada na folga (−1..1), escrito pela mão no desbico.
var spin_bias: float = 0.0
## Guiar: direção desejada do bico (mundo) e força, escritas pela mão.
var steer_dir := Vector3.ZERO
var steer_gain: float = 0.0
var steer_ff: float = 0.0
## Batida das asas no desbico (0..1, só visual: as duas meias-velas fecham juntas).
var flap: float = 0.0
## Empurrão da batida do desbico (aceleração, m/s²), escrito pela mão.
var push_accel := Vector3.ZERO
## Inclinação do desbico (rad, em torno da vareta; + = asa direita para trás).
var bank: float = 0.0
## Modelo de voo (pipa do jogador presa na linha); nulo = física de corpo rígido.
var flight: KiteFlightModel = null
## FÍSICA DE VERDADE (v0.18): corpo rígido + cabresto de linha (nó + 2 pernas) +
## rabiola acoplada, controlado SÓ pela mão na linha (posição da mão, pegada,
## carretel). Sem modelo de voo, sem servo, sem empurrão. Vale no próximo launch().
var physical: bool = false
## Nó do cabresto (frações da altura): abaixo da cabeça e à frente do papel.
var knot_y: float = 0.25
var knot_z: float = 0.30
## Arqueamento elástico da travessa (rad por N na meia-vela) e diedro sem carga (rad).
var flex_per_n: float = 0.05
var flex_rest: float = 0.05
## Cruzamentos com outras linhas encostadas no último tick: [trecho, t] (LineCombat).
var line_pivots: Array = []
## Escala do DESENHO da pipa (longe da câmera ela é desenhada um pouco maior para o
## desbico ser visível no celular; a física não muda). Escrita pelo KiteVisual.
var visual_scale: float = 1.0
## A linha foi empurrada por outra linha neste subpasso (refaz o contato com o cenário).
var pushed_by_line: bool = false
## Pose da pipa no começo do tick (fim do anterior): o desenho interpola entre ela e a
## atual, para ficar liso a 60 quadros/s com a física a 30 Hz.
var vis_prev_x := Vector3.ZERO
var vis_prev_q := Quaternion.IDENTITY
var visual_tail_offset := Vector3.ZERO
var _t_steady: float = 5.0
## A mão voltando da braçada joga a linha no chão? (falso no desbico: a linha escorrega)
var shorten_on_return: bool = true
## Pipa ainda segura na mão (antes do primeiro desbico).
var held: bool = false
## Enroscado (árvore, poste, fio): a pipa fica presa até um tranco forte soltar.
var snagged: bool = false
var snag_point := Vector3.ZERO
var snag_strength: float = 10.0
var snag_what: String = ""
var snag_cooldown: float = 0.0
var _snag_pull: float = 0.0
var _held_x := Vector3.ZERO
var _held_q := Quaternion.IDENTITY

# Carretel.
var spool: float = 250.0
var pile: float = 0.0
var feed_speed: float = 0.0
## Tensão filtrada na mão (N) — HUD, vibração, animação.
var tension: float = 0.0
var age: float = 0.0
## Desgaste acumulado por trecho de material (bin de 10 cm → 0..1).
var wear: Dictionary = {}
## Qualidade deste carretel (cerol nunca sai igual): multiplica abrasão e resistência.
var spool_quality: float = 1.0
var _strength_seed: int = 0

var kite_visual: KiteVisual
var tail_renderer: TailRenderer
var line_renderer: LineRenderer

var _stroke_prev: float = 0.0
var _was_on_ground: bool = false
var _in_leaves: bool = false
var _last_impact: float = -10.0
var _x_frame_start := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()


func _ready() -> void:
	add_to_group(&"kite_rigs")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_ray.collision_mask = 1
	_sphere.radius = 0.3
	_shape_query.shape = _sphere
	_shape_query.collision_mask = 1
	kite_visual = KiteVisual.new()
	kite_visual.name = "KiteVisual"
	add_child(kite_visual)
	tail_renderer = TailRenderer.new()
	tail_renderer.name = "TailRenderer"
	add_child(tail_renderer)
	line_renderer = LineRenderer.new()
	line_renderer.name = "LineRenderer"
	add_child(line_renderer)


func is_flying() -> bool:
	return body != null and not loose and rope != null


func has_rope() -> bool:
	return rope != null


## Coloca a pipa no ar, a favor de `direction`, com a linha quase esticada.
func launch(hand: Vector3, length: float, elevation_deg: float, direction: Vector3) -> void:
	if not is_local_player:
		# Vizinhos: rabiola com menos nós (mesma física, menos custo).
		profile.tail_nodes = mini(profile.tail_nodes, [6, 8, 10][GameConfig.quality])
	body = KiteRigidBody.new(profile)
	var use_flight := is_local_player and not physical
	if use_flight:
		# Pipa do jogador (modelo de voo): o nó do cabresto fica onde fica na pipa de
		# verdade — na altura logo abaixo da travessa (~38% da altura, a partir da
		# cabeça) e uns 40% da altura à frente do papel. Antes ele ficava rente à
		# cabeça e a linha parecia sair da ponta de cima.
		var hh := profile.height
		body.tow_local = Vector3(0.0, body.corners[0].y - 0.38 * hh, 0.40 * hh)
	var br: Bridle = null
	if physical:
		var bp := Bridle.standard_points(body, knot_y, knot_z)
		br = Bridle.new()
		br.setup(body, bp[0], bp[1], bp[2])
		body.tow_local = br.knot_local
	var el := deg_to_rad(elevation_deg)
	var dir_h := Vector3(direction.x, 0.0, direction.z).normalized()
	var d := (dir_h * cos(el) + Vector3.UP * sin(el)).normalized()
	body.orient_facing(-d)
	var tow := hand + d * (length * 0.995)
	body.x = tow - body.q * body.tow_local
	rope = Rope.new(line_type)
	rope.owner_id = get_instance_id()
	rope.max_nodes = GameConfig.rope_max_nodes(is_local_player)
	rope.setup(hand, body, body.tow_local, length)
	rope.bridle = br
	# Pipa física: rabiola 20% mais longa (é ela que estabiliza a pipa de verdade) e
	# com menos tremulação forçada.
	var tmul: float = TAIL_PHYSICAL[clampi(profile.tail_class, 0, 2)]
	if TAIL_PHYSICAL_OVERRIDE > 0.0:
		tmul = TAIL_PHYSICAL_OVERRIDE
	tail = TailChain.new(body, profile, tmul if physical else 1.0)
	if physical:
		body.rot_damp_scale = ROT_DAMP_PHYSICAL
		tail.flutter_scale = 0.5
		body.flex_per_n = flex_per_n
		body.flex_rest = flex_rest
	flight = null
	if use_flight:
		body.kinematic = true
		flight = KiteFlightModel.new(self)
	# Física de verdade: nenhum atuador artificial na pipa.
	bridle_offset = Vector2.ZERO
	sail_asym = 0.0
	spin_bias = 0.0
	steer_dir = Vector3.ZERO
	steer_gain = 0.0
	steer_ff = 0.0
	push_accel = Vector3.ZERO
	spool = maxf(spool_capacity - length, 0.0)
	pile = 0.0
	feed_speed = 0.0
	stroke = 0.0
	_stroke_prev = 0.0
	tension = 0.0
	loose = false
	held = false
	snagged = false
	snag_cooldown = 0.0
	age = 0.0
	wear.clear()
	spool_quality = randf_range(0.75, 1.3)
	_strength_seed = randi()
	hand_rest = hand
	visible = true
	kite_visual.bind(self)
	tail_renderer.bind(self)
	line_renderer.bind(rope, line_type)


## Começa com a pipa na mão: linha curta, pipa segura na frente do jogador até o
## primeiro desbico (release_hold).
func launch_in_hand(hand: Vector3, facing: Vector3) -> void:
	var dir := Vector3(facing.x, 0.0, facing.z).normalized()
	launch(hand, 3.2 if is_local_player else 2.6, 38.0, dir)
	held = true
	_held_x = body.x
	_held_q = body.q


## Contato da pipa com galhos, postes, fios e copas (WorldObstacles.kite_contact):
## encostar só quica/escorrega; prende quando o cabresto engancha ou entra fundo na copa.
func try_snag(obstacles: WorldObstacles, dt: float) -> void:
	if held or body == null:
		return
	var knot := body.world_point(rope.end_local if rope != null and rope.end_body == body else body.tow_local)
	var c := body.corners
	var h := profile.height
	var anchors := PackedVector3Array([
		body.world_point(Vector3(0, c[1].y, 0)),
		body.world_point(c[4]),
		body.world_point(c[2])])
	var hit := obstacles.kite_contact(body, knot, anchors, dt, get_instance_id())
	if obstacles.kite_in_canopy and not _in_leaves:
		_impact(body.v.length(), "folhas")
	_in_leaves = obstacles.kite_in_canopy
	if snagged or snag_cooldown > 0.0 or hit.is_empty():
		return
	snagged = true
	snag_what = hit[0]
	snag_point = hit[1]
	_snag_pull = 0.0
	match snag_what:
		"fio":
			snag_strength = randf_range(9.0, 18.0)
		"poste", "cruzeta":
			snag_strength = randf_range(7.0, 13.0)
		_:
			snag_strength = randf_range(5.0, 14.0)
	EventBus.kite_snagged.emit(self, snag_what)


## Mão sobre mão: a outra mão pega a linha mais à frente — o trecho já puxado
## (`amount`) vai para o chão e o braço recomeça sem soltar a pipa.
func regrip(amount: float) -> void:
	if rope == null or amount <= 0.0:
		return
	var a := minf(amount, maxf(rope.length() - MIN_LENGTH, 0.0))
	rope.feed(-a)
	pile += a
	_stroke_prev = maxf(_stroke_prev - amount, 0.0)


func release_hold() -> void:
	held = false


## Resistência relativa de um trecho de 10 cm da linha (revestimento irregular).
func bin_strength(b: int) -> float:
	var hsh := hash(Vector2i(b, _strength_seed))
	var r := float(hsh % 1000) / 1000.0
	return 0.6 + 0.9 * r * r


## Rumo do bico em torno da linha (rad): 0 = bico para cima, + = inclinado para a direita.
func heading() -> float:
	if body == null:
		return 0.0
	var d := (body.x - hand_position()).normalized()
	var up := Vector3.UP - d * d.y
	if up.length() < 0.01:
		return 0.0
	up = up.normalized()
	var nose := body.q * Vector3.UP
	nose = nose - d * nose.dot(d)
	if nose.length() < 0.001:
		return 0.0
	nose = nose.normalized()
	return atan2(up.cross(nose).dot(d), up.dot(nose))


func hand_position() -> Vector3:
	return hand_rest + stroke_dir * stroke


func flying_length() -> float:
	return rope.length() if rope else 0.0


## Guarda a pipa (recolhida na mão): some sem virar pipa voada.
func stow() -> void:
	body = null
	tail = null
	rope = null
	loose = false
	held = false
	snagged = false
	wear.clear()
	kite_visual.unbind()
	tail_renderer.bind(null)
	line_renderer.bind(null, line_type)


## Adota pipa + rabiola + trecho de linha de outra pipa que foi cortada (pipa voada).
func adopt_loose(p_body: KiteRigidBody, p_tail: TailChain, p_rope: Rope) -> void:
	body = p_body
	tail = p_tail
	rope = p_rope
	loose = true
	kite_visual.bind(self)
	tail_renderer.bind(self)
	line_renderer.bind(rope, line_type)


## Pose interpolada da pipa para desenhar (entre o tick anterior e o atual).
func visual_pose() -> Transform3D:
	if body == null:
		return Transform3D.IDENTITY
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	if vis_prev_x == Vector3.ZERO or vis_prev_x.distance_to(body.x) > 5.0:
		return Transform3D(Basis(body.q), body.x)
	return Transform3D(Basis(vis_prev_q.slerp(body.q, f)), vis_prev_x.lerp(body.x, f))


func pre_frame(dt: float) -> void:
	age += dt
	if body != null:
		vis_prev_x = body.x
		vis_prev_q = body.q
	if rope != null:
		if not loose and rope.hand_fixed:
			_update_spool(dt)
			rope.hand_position = hand_position()
		rope.compute_forces()
		rope.snapshot_frame()
	if body != null:
		body.sail_asym = 0.0 if loose else sail_asym
		# Relaxação da vareta pela tensão REAL no cabresto (linha esticada = vareta
		# carregada e simétrica; frouxa = relaxa).
		# A vareta está "carregada" com a tensão normal desta pipa nesta linha (média
		# lenta fora do desbico); relaxa quando a tensão cai bem abaixo disso. Assim o
		# bico gira igual com linha curta ou comprida (linha longa segura mais tensão).
		var m := profile.mass + profile.tail_mass
		var t_end := rope.tension_end if rope != null and rope.end_body == body else 0.0
		if spin_bias == 0.0:
			_t_steady = lerpf(_t_steady, t_end, 1.0 - exp(-dt / 3.0))
		var t_full := maxf(75.0 * m, 0.75 * _t_steady)
		var t_slack := 0.25 * t_full
		body.relax = clampf((t_full - t_end) / (t_full - t_slack), 0.0, 1.0)
		body.spin_bias = 0.0 if loose else spin_bias
		body.steer_dir = Vector3.ZERO if loose or held else steer_dir
		body.steer_gain = steer_gain
		body.steer_ff = steer_ff
		body.push_accel = Vector3.ZERO if loose else push_accel
		if physical:
			# Física real: nenhum atuador artificial chega na pipa, venha de onde vier
			# (a mão antiga ainda escreve esses campos em sondas e no teste de combate).
			body.sail_asym = 0.0
			body.spin_bias = 0.0
			body.steer_dir = Vector3.ZERO
			body.steer_gain = 0.0
			body.steer_ff = 0.0
			body.push_accel = Vector3.ZERO
		if rope != null and rope.hand_fixed:
			var ld := body.x - hand_position()
			if ld.length() > 0.01:
				body.line_dir = ld.normalized()
		if rope != null and rope.end_body == body and rope.bridle == null:
			var off := Vector2.ZERO if loose else bridle_offset
			rope.end_local = body.tow_local + Vector3(off.x, off.y, 0.0)
		tail.compute_forces()
		_x_frame_start = body.x


func _update_spool(dt: float) -> void:
	# Braçada: mão voltando à posição de pegada → trecho puxado vai para o chão.
	var prev_pos := maxf(_stroke_prev, 0.0)
	var now_pos := maxf(stroke, 0.0)
	if shorten_on_return and now_pos < prev_pos and rope.length() > MIN_LENGTH:
		var amount := prev_pos - now_pos
		rope.feed(-amount)
		pile += amount
	_stroke_prev = stroke
	# Soltar (dar linha): a linha corre quando a tensão vence a pegada.
	# A mão não segura mais que ~70% do que a linha aguenta: num tranco forte a linha
	# escorrega na mão em vez de arrebentar (o pipeiro sente e alivia).
	var f_cap := 0.7 * line_type.break_tension
	# Pipa do jogador: a tração do voo nunca passa de 85% da resistência e a mão
	# fechada segura isso — puxando, a linha NÃO escorrega (antes, puxão forte fazia a
	# linha correr para fora e a pipa "não vinha").
	if flight != null and not snagged:
		f_cap = 0.97 * line_type.break_tension
	if (grip < 0.98 or rope.tension_hand > f_cap) and pile + spool > 0.05:
		# Atrito da mão cresce com o quadrado da pegada (mão quase aberta = linha corre fácil).
		var f_grip := minf(grip * grip * GRIP_MAX, f_cap)
		feed_speed += ((rope.tension_hand - f_grip) / FEED_MASS - FEED_DAMP * feed_speed) * dt
		feed_speed = maxf(feed_speed, 0.0)
		# DESCARREGAR (pipa do jogador): com a mão aberta a linha corre com o vento
		# mesmo com a pipa puxando pouco (alta, perto da cabeça).
		if flight != null and grip < 0.6 and not held:
			feed_speed = maxf(feed_speed, (0.6 - grip) / 0.6 * 2.0)
		# A linha não corre mais rápido do que o vento leva a pipa embora: com mais de
		# 1 m de folga ela para de sair (senão sobrava linha frouxa no ar).
		if flight != null:
			feed_speed = minf(feed_speed, 5.0)
			if flight.slack > 1.0:
				feed_speed = 0.0
	else:
		feed_speed = 0.0
	var out := feed_speed * dt
	if out > 0.0:
		var from_pile := minf(pile, out)
		pile -= from_pile
		var from_spool := minf(spool, out - from_pile)
		spool -= from_spool
		out = from_pile + from_spool
		rope.feed(out)
	# Recolher (enrolar na lata): primeiro a linha do chão, depois a que voa.
	if reel_rate > 0.0:
		var r := reel_rate * dt
		var take := minf(pile, r)
		pile -= take
		spool += take
		r -= take
		if r > 0.0 and rope.length() > MIN_LENGTH:
			var factor := clampf(1.0 - rope.tension_hand / REEL_HARD_TENSION, 0.15, 1.0)
			var amount := minf(r * factor, rope.length() - MIN_LENGTH)
			rope.feed(-amount)
			spool += amount


func predict(h: float) -> void:
	if body != null:
		if flight != null and (loose or rope == null or rope.end_body != body):
			# Cortada/solta: volta a ser corpo rígido livre (cai de verdade).
			body.kinematic = false
			flight = null
		if flight != null:
			body.predict(h)   # só guarda a posição anterior
			# Enroscada (fio, galho) ou na mão: o voo espera; volta quando soltar.
			if not held and not snagged:
				flight.step(h)
		else:
			body.compute_forces()
			body.predict(h)
		tail.predict(h)
	if rope != null:
		rope.predict(h)


func solve(h: float) -> void:
	if rope != null:
		rope.solve(h)
	if body != null:
		tail.solve(h)
		body.steer_correct(h)
		if snagged:
			body.x = body.x.lerp(snag_point, 0.6)
			body.v *= 0.3
			body.w *= 0.9
		var gy := Ground.height_at(body.x.x, body.x.z) + 0.12
		if body.x.y < gy:
			body.x.y = gy


func finalize(h: float) -> void:
	if body != null:
		body.finalize(h)
		tail.finalize(h)
		if held:
			body.x = _held_x
			body.q = _held_q
			body.v = Vector3.ZERO
			body.w = Vector3.ZERO
	if rope != null:
		rope.finalize(h)


func post_frame(dt: float, h: float) -> void:
	if rope != null:
		rope.finish_tick(h)
		if flight != null and rope.end_body == body and not snagged:
			# Tração vem do modelo de voo (aerodinâmica + puxão + tranco do desbico).
			# Enroscada, vale a tensão de verdade da linha (é ela que solta o enrosco).
			rope.tension_hand = flight.tension
			rope.tension_end = flight.tension
		tension = lerpf(tension, rope.tension_hand if rope.hand_fixed else 0.0, 1.0 - exp(-12.0 * dt))
		# Sobra de linha na mão depois do corte: some quando recolhida.
		if body == null and rope.length() <= MIN_LENGTH + 0.05:
			rope = null
			line_renderer.bind(null, line_type)
	if body == null:
		return
	snag_cooldown = maxf(snag_cooldown - dt, 0.0)
	if snagged and rope != null:
		# Trancos fortes soltam a pipa do galho/fio.
		if rope.tension_end > snag_strength:
			_snag_pull += dt
			if _snag_pull > 0.08:
				snagged = false
				EventBus.line_freed.emit(self, snag_what)
				snag_cooldown = 1.2
		else:
			_snag_pull = maxf(_snag_pull - dt * 0.5, 0.0)
	_collide_world()
	if not body.is_valid():
		push_warning("KiteRig: estado inválido, relançando.")
		if loose:
			queue_free()
		else:
			launch(hand_rest, maxf(rope.length(), 10.0), 45.0, Wind.get_direction())


func _collide_world() -> void:
	# Empurra a pipa (esfera do tamanho da vela) para fora de qualquer objeto.
	var space := get_world_3d().direct_space_state
	for _it in 3:
		_shape_query.transform = Transform3D(Basis.IDENTITY, body.x)
		var info := space.get_rest_info(_shape_query)
		if info.is_empty():
			break
		var n: Vector3 = info["normal"]
		var p: Vector3 = info["point"]
		var depth := _sphere.radius - (body.x - p).dot(n)
		if depth <= 0.0:
			break
		body.x += n * (depth + 0.01)
		var vn := body.v.dot(n)
		if vn < 0.0:
			body.v -= n * vn * 1.2
		body.v *= 0.7
		if not body.resting:
			_impact(-vn, "telhado" if p.y > Ground.height_at(p.x, p.z) + 1.5 else "chão")
		body.resting = true
	var motion := body.x - _x_frame_start
	var on_ground := body.x.y <= Ground.height_at(body.x.x, body.x.z) + 0.13
	if on_ground and not _was_on_ground:
		# Bateu no chão: velocidade de descida no quadro.
		_impact(maxf(-motion.y / maxf(get_physics_process_delta_time(), 0.001), body.v.length() * 0.5), "chão")
	_was_on_ground = on_ground
	body.resting = on_ground
	if motion.length_squared() < 1e-8:
		return
	_ray.from = _x_frame_start
	_ray.to = body.x + motion.normalized() * 0.1
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	var p: Vector3 = hit["position"]
	body.x = p + n * 0.1
	var vn := body.v.dot(n)
	if vn < 0.0:
		body.v -= n * vn
	body.v *= 0.5
	body.w *= 0.5
	if not body.resting:
		_impact(-vn, "telhado" if p.y > Ground.height_at(p.x, p.z) + 1.5 else "chão")
	body.resting = true


## Som/efeito de impacto (com intervalo mínimo para não metralhar).
func _impact(speed: float, surface: String) -> void:
	if speed < 0.8 or age - _last_impact < 0.25:
		return
	_last_impact = age
	EventBus.kite_crashed.emit(body.x, speed, surface)


## Corta a linha na coordenada de material s. A pipa, a rabiola e o trecho do lado
## dela passam para uma nova KiteRig "voada" (retornada); esta fica só com a sobra
## de linha na mão (que cai e pode ser recolhida).
func cut(s_cut: float) -> KiteRig:
	var kite_side := rope.split_at(s_cut)
	var cut_pos := rope.end_point()
	var lost := KiteRig.new()
	lost.name = name + "_Voada"
	lost.profile = profile
	lost.line_type = line_type
	lost.display_name = display_name
	get_parent().add_child(lost)
	# Sobra de linha muito curta presa na pipa não é simulada (instável e invisível).
	lost.adopt_loose(body, tail, kite_side if kite_side.length() > 0.5 else null)
	body = null
	tail = null
	wear.clear()
	kite_visual.unbind()
	tail_renderer.bind(null)
	line_renderer.bind(rope, line_type)
	line_cut.emit(self, cut_pos)
	return lost
