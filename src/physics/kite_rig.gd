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

# Carretel.
var spool: float = 250.0
var pile: float = 0.0
var feed_speed: float = 0.0
## Tensão filtrada na mão (N) — HUD, vibração, animação.
var tension: float = 0.0
var age: float = 0.0
## Desgaste acumulado por trecho de material (bin de 10 cm → 0..1).
var wear: Dictionary = {}

var kite_visual: KiteVisual
var tail_renderer: TailRenderer
var line_renderer: LineRenderer

var _stroke_prev: float = 0.0
var _x_frame_start := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	add_to_group(&"kite_rigs")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_ray.collision_mask = 1
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
	body = KiteRigidBody.new(profile)
	var el := deg_to_rad(elevation_deg)
	var dir_h := Vector3(direction.x, 0.0, direction.z).normalized()
	var d := (dir_h * cos(el) + Vector3.UP * sin(el)).normalized()
	body.orient_facing(-d)
	var tow := hand + d * (length * 0.995)
	body.x = tow - body.q * body.tow_local
	rope = Rope.new(line_type)
	rope.setup(hand, body, body.tow_local, length)
	tail = TailChain.new(body, profile)
	spool = maxf(spool_capacity - length, 0.0)
	pile = 0.0
	feed_speed = 0.0
	stroke = 0.0
	_stroke_prev = 0.0
	tension = 0.0
	loose = false
	age = 0.0
	wear.clear()
	hand_rest = hand
	visible = true
	kite_visual.bind(self)
	tail_renderer.bind(self)
	line_renderer.bind(rope, line_type)


func hand_position() -> Vector3:
	return hand_rest + stroke_dir * stroke


func flying_length() -> float:
	return rope.length() if rope else 0.0


## Adota pipa + rabiola + trecho de linha de outra pipa que foi cortada (pipa voada).
func adopt_loose(p_body: KiteRigidBody, p_tail: TailChain, p_rope: Rope) -> void:
	body = p_body
	tail = p_tail
	rope = p_rope
	loose = true
	kite_visual.bind(self)
	tail_renderer.bind(self)
	line_renderer.bind(rope, line_type)


func pre_frame(dt: float) -> void:
	age += dt
	if rope != null:
		if not loose and rope.hand_fixed:
			_update_spool(dt)
			rope.hand_position = hand_position()
		rope.compute_forces()
	if body != null:
		tail.compute_forces()
		_x_frame_start = body.x


func _update_spool(dt: float) -> void:
	# Braçada: mão voltando à posição de pegada → trecho puxado vai para o chão.
	var ds := stroke - _stroke_prev
	_stroke_prev = stroke
	if ds < 0.0 and rope.length() > MIN_LENGTH:
		rope.feed(ds)
		pile -= ds
	# Soltar (dar linha): a linha corre quando a tensão vence a pegada.
	if grip < 0.98 and pile + spool > 0.05:
		var f_grip := grip * GRIP_MAX
		feed_speed += ((rope.tension_hand - f_grip) / FEED_MASS - FEED_DAMP * feed_speed) * dt
		feed_speed = maxf(feed_speed, 0.0)
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
		if body.x.y < 0.12:
			body.x.y = 0.12


func finalize(h: float) -> void:
	if body != null:
		body.finalize(h)
		tail.finalize(h)
	if rope != null:
		rope.finalize(h)


func post_frame(dt: float, h: float) -> void:
	if rope != null:
		rope.finish_tick(h)
		tension = lerpf(tension, rope.tension_hand if rope.hand_fixed else 0.0, 1.0 - exp(-12.0 * dt))
		# Sobra de linha na mão depois do corte: some quando recolhida.
		if body == null and rope.length() <= MIN_LENGTH + 0.05:
			rope = null
			line_renderer.bind(null, line_type)
	if body == null:
		return
	_collide_world()
	if not body.is_valid():
		push_warning("KiteRig: estado inválido, relançando.")
		if loose:
			queue_free()
		else:
			launch(hand_rest, maxf(rope.length(), 10.0), 45.0, Wind.get_direction())


func _collide_world() -> void:
	var motion := body.x - _x_frame_start
	body.resting = body.x.y <= 0.13
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
		EventBus.kite_crashed.emit(body.x)
	body.resting = true


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
	lost.adopt_loose(body, tail, kite_side)
	body = null
	tail = null
	wear.clear()
	kite_visual.unbind()
	tail_renderer.bind(null)
	line_renderer.bind(rope, line_type)
	line_cut.emit(self, cut_pos)
	return lost
