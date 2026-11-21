class_name KiteBody
extends Node3D
## Simulação física da pipa (integrador próprio, passo fixo com subpassos).
##
## Translação: força aerodinâmica de placa plana (força normal à vela, com perda
## de sustentação), arrasto parasita, arrasto da rabiola, gravidade, peso e
## arrasto da linha. A linha é uma restrição unilateral resolvida por KiteLine.
##
## Orientação: a pipa se alinha à linha esticada com o ângulo do cabresto, e gira
## em torno da linha (rumo) como um oscilador amortecido: a rabiola endireita,
## a turbulência desvia. Como a força normal inclina junto com o nariz, a pipa
## anda para onde aponta — e a puxada a acelera nessa direção (controle real de pipa).
##
## O nó fica na raiz da cena (coordenadas locais = mundo). A origem do nó é o
## ponto do cabresto, onde a linha se prende.

const RHO := 1.225
const G := 9.8
const MAX_SPEED := 40.0

@export var profile: KiteProfile
@export_range(1, 8) var substeps: int = 4
## Máscara de colisão com o mundo (camada 1 = "mundo").
@export_flags_3d_physics var collision_mask: int = 1

var line: KiteLine

# --- Estado (público para HUD, visual e, no futuro, rede) ---
var position_ws := Vector3.ZERO
var velocity := Vector3.ZERO
var mass: float = 0.045
## Eixo do nariz (local +Y) e normal da face voltada ao jogador (local +Z).
var spine := Vector3.UP
var normal := Vector3.BACK
var heading: float = 0.0
var heading_velocity: float = 0.0
var angle_of_attack: float = 0.0
var airspeed: float = 0.0
var resting: bool = false

var _last_air_dir := Vector3.FORWARD
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	if profile == null:
		profile = KiteProfile.new()
	mass = profile.mass
	position_ws = global_position
	_noise.seed = randi()
	_noise.frequency = 0.5
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ray.collision_mask = collision_mask


## Coloca a pipa no ar, a favor do vento, com a linha quase esticada.
func place_in_air(anchor: Vector3, line_length: float, elevation_deg: float = 45.0) -> void:
	var el := deg_to_rad(elevation_deg)
	var d := (Wind.get_direction() * cos(el) + Vector3.UP * sin(el)).normalized()
	position_ws = anchor + d * line_length * 0.98
	velocity = Vector3.ZERO
	heading = 0.0
	heading_velocity = 0.0
	resting = false
	var frame := _frame(d, 0.0, deg_to_rad(profile.bridle_angle_deg))
	spine = frame[0]
	normal = frame[1]
	_apply_transform()


func _physics_process(delta: float) -> void:
	var from := position_ws
	var dt := delta / float(substeps)
	for _i in substeps:
		_integrate(dt)
		if line:
			line.solve(self, dt)
	if line:
		line.finish_step(delta)
	_collide(from)
	_update_orientation(delta)
	_validate()
	_apply_transform()


func _integrate(dt: float) -> void:
	var w := Wind.sample(position_ws)
	var vrel := w - velocity
	var sp := vrel.length()
	airspeed = sp
	var q := 0.5 * RHO * sp * sp
	var force := Vector3(0.0, -G * mass, 0.0)
	if sp > 0.01:
		var vdir := vrel / sp
		_last_air_dir = vdir
		# Seno do ângulo de ataque: > 0 quando o vento bate na face da pipa.
		var sina := clampf(-vdir.dot(normal), -1.0, 1.0)
		var alpha := asin(sina)
		angle_of_attack = alpha
		force += -normal * (q * profile.area * normal_coefficient(alpha))
		force += vdir * (q * (profile.area * profile.cd0 + profile.tail_area * profile.tail_cd))
	if line and not line.is_broken:
		# Metade do peso da linha pendura na pipa; o vento empurra a linha a favor dele.
		force.y -= G * line.mass_per_meter * line.length * 0.5
		var ws := w.length()
		if ws > 0.01:
			force += w / ws * (0.5 * RHO * ws * ws * line.diameter * line.length * 0.25)
	velocity += force / mass * dt
	velocity = velocity.limit_length(MAX_SPEED)
	position_ws += velocity * dt


## Coeficiente de força normal de uma placa plana (com perda de sustentação suave).
func normal_coefficient(alpha: float) -> float:
	var a := absf(alpha)
	var attached := profile.cn_attached * sin(a) * cos(a)
	var separated := profile.cn_separated * sin(a)
	var x := clampf((rad_to_deg(a) - profile.stall_start_deg) / maxf(profile.stall_end_deg - profile.stall_start_deg, 0.1), 0.0, 1.0)
	var blend := x * x * (3.0 - 2.0 * x)
	return lerpf(attached, separated, blend) * signf(alpha)


func _collide(from: Vector3) -> void:
	if position_ws.y < 0.05:
		position_ws.y = 0.05
		velocity.y = maxf(velocity.y, 0.0)
		velocity *= 0.6
		_set_resting(true)
		return
	var motion := position_ws - from
	if motion.length_squared() < 1e-8:
		return
	_ray.from = from
	_ray.to = position_ws + motion.normalized() * 0.08
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		_set_resting(false)
		return
	var n: Vector3 = hit["normal"]
	var p: Vector3 = hit["position"]
	position_ws = p + n * 0.08
	var vn := velocity.dot(n)
	if vn < 0.0:
		velocity -= n * vn
	velocity *= 0.6
	_set_resting(true)


func _set_resting(value: bool) -> void:
	if value and not resting:
		EventBus.kite_crashed.emit(position_ws)
	resting = value


func _update_orientation(delta: float) -> void:
	var taut := 0.0
	var anchor := position_ws - Vector3.UP
	if line and not line.is_broken:
		taut = line.tautness
		anchor = line.anchor_position
	var to_kite := position_ws - anchor
	var d_line := to_kite.normalized() if to_kite.length() > 0.01 else Vector3.UP

	# Rumo: oscilador amortecido em torno da linha.
	var q := 0.5 * RHO * airspeed * airspeed
	_noise_t += delta
	var turb := profile.turbulence_sensitivity * q * clampf(_noise.get_noise_1d(_noise_t * 1.0) * 1.7, -1.0, 1.0)
	var slack := 1.0 - taut
	var acc := -profile.tail_stability * q * sin(heading) * (0.3 + 0.7 * taut)
	acc += -profile.heading_damping * heading_velocity + turb * (1.0 + slack * 2.0)
	heading_velocity += acc * delta
	heading = wrapf(heading + heading_velocity * delta, -PI, PI)

	# Direção de referência: linha (esticada) ou vento relativo (frouxa, "paraquedas").
	var d := d_line
	if taut < 1.0 and airspeed > 0.5:
		d = (d_line * taut + _last_air_dir * slack)
		d = d.normalized() if d.length() > 0.01 else d_line
	var frame := _frame(d, heading, deg_to_rad(profile.bridle_angle_deg))
	var rate := lerpf(profile.orient_rate_slack, profile.orient_rate_taut, taut)
	var k := 1.0 - exp(-rate * delta)
	spine = spine.slerp(frame[0], k).normalized()
	normal = normal.slerp(frame[1], k)
	normal = (normal - spine * normal.dot(spine)).normalized()


## Base da pipa a partir da direção da linha d (mão → pipa), rumo psi e cabresto b.
## Retorna [nariz, normal].
func _frame(d: Vector3, psi: float, b: float) -> Array[Vector3]:
	var u0 := Vector3.UP - d * Vector3.UP.dot(d)
	if u0.length() < 0.001:
		u0 = -Wind.get_direction()
	u0 = u0.normalized()
	var s0 := u0.rotated(d, psi)
	var s := (s0 * cos(b) - d * sin(b)).normalized()
	var n := (-d * cos(b) - s0 * sin(b)).normalized()
	return [s, n]


func _validate() -> void:
	if position_ws.is_finite() and velocity.is_finite() and spine.is_finite() and normal.is_finite():
		return
	push_warning("KiteBody: estado inválido, reposicionando a pipa.")
	var anchor := line.anchor_position if line else Vector3(0, 1.5, 0)
	var length := line.length if line else 20.0
	place_in_air(anchor, length)


func _apply_transform() -> void:
	var x := spine.cross(normal).normalized()
	global_transform = Transform3D(Basis(x, spine, normal), position_ws)


## Altura acima do chão (m).
func get_altitude() -> float:
	return position_ws.y - Wind.GROUND_LEVEL
