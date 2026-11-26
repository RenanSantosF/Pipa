class_name TailChain
extends RefCounted
## Rabiola: corrente de partículas (tiras de plástico amarradas num barbante),
## presa na ponta de baixo da pipa por uma restrição com o corpo rígido.
## O arrasto e o peso dela geram o torque que endireita a pipa quando a linha
## fica frouxa ("desbicar") e estabilizam o balanço lateral.

const RHO := 1.225
const GRAVITY := Vector3(0.0, -9.8, 0.0)

var body: KiteRigidBody
var profile: KiteProfile
var pos: PackedVector3Array = PackedVector3Array()
var prev: PackedVector3Array = PackedVector3Array()
var vel: PackedVector3Array = PackedVector3Array()
var acc: PackedVector3Array = PackedVector3Array()
var seg_len: float = 0.26
var inv_m: float = 500.0
var node_area: float = 0.003
## Rabiola enganchada (fio/galho): índice do nó preso, -1 = solta.
var pinned_index: int = -1
var pin_pos := Vector3.ZERO
var pin_time: float = 0.0
var _clock: float = 0.0
## Tremulação desta rabiola (1 = cheia). Na pipa física a rabiola puxa a pipa de
## verdade, então a tremulação é menor (as tiras balançam mais no desenho).
var flutter_scale: float = 1.0
## Passadas do solver da rabiola por subpasso (a pipa física precisa da rabiola
## firme: uma passada só deixava a corrente elástica e o tranco não chegava nela).
var iterations: int = 1
static var ITER_OVERRIDE := 0
## Aceleração da tremulação em S (m/s² com 6 m/s de vento).
const FLUTTER_ACC := 9.0
## Escala da tremulação (laboratório).
static var FLUTTER_SCALE := 1.0


func _init(p_body: KiteRigidBody, p_profile: KiteProfile, length_mult: float = 1.0) -> void:
	body = p_body
	profile = p_profile
	var n := profile.tail_nodes
	seg_len = profile.tail_length * length_mult / float(n)
	inv_m = 1.0 / maxf(profile.tail_mass / float(n), 0.0001)
	node_area = profile.tail_area / float(n)
	reset()


func reset() -> void:
	var n := profile.tail_nodes
	var a := attach_point()
	pos.resize(n)
	vel.resize(n)
	acc.resize(n)
	for i in n:
		pos[i] = a + Vector3.DOWN * seg_len * float(i + 1)
		vel[i] = Vector3.ZERO
	prev = pos.duplicate()


func attach_point() -> Vector3:
	return body.world_point(body.tail_local)


## Vento no começo do tick (o arrasto em si é resolvido a cada subpasso, abaixo).
var _wind := Vector3.ZERO


## Posições no começo do tick (o desenho interpola entre elas e as atuais).
var tick_prev: PackedVector3Array = PackedVector3Array()


func compute_forces() -> void:
	_wind = Wind.sample(attach_point())
	tick_prev = pos.duplicate()


## Arrasto SEMI-IMPLÍCITO a cada subpasso: v' = (v + g·h + k·h·vento)/(1 + k·h),
## k = ½ρ·Cd·A·|v_rel|/m. Estável e igual com física a 30 ou 60 Hz (o arrasto
## explícito por tick fazia a rabiola puxar diferente conforme a taxa de física).
func predict(h: float) -> void:
	var c := 0.5 * RHO * profile.tail_cd * node_area * inv_m
	# Tremulação: as tiras soltam vórtices e a rabiola ondula em S (onda que corre da
	# pipa para a ponta, mais forte e rápida com mais vento) — não fica uma vara reta.
	_clock += h
	var ws := _wind.length()
	var wdir := _wind / ws if ws > 0.3 else Vector3.FORWARD
	var amp := flutter_scale * FLUTTER_SCALE * FLUTTER_ACC * clampf(ws / 6.0, 0.3, 1.3) * clampf(ws / 6.0, 0.3, 1.3)
	var om := 5.0 + 1.2 * ws
	var n := pos.size()
	for i in n:
		prev[i] = pos[i]
		var v := vel[i]
		var k := c * (_wind - v).length() * h
		v = (v + GRAVITY * h + _wind * k) / (1.0 + k)
		if i > 0 and amp > 0.0:
			var along := pos[i] - pos[i - 1]
			var side := along.cross(wdir)
			if side.length_squared() < 1e-6:
				side = along.cross(Vector3.UP)
			if side.length_squared() > 1e-6:
				side = side.normalized()
				var ramp := float(i) / float(n)
				v += side * (amp * (0.35 + ramp) * sin(om * _clock - float(i) * 0.85)) * h
		vel[i] = v
		pos[i] += v * h


func solve(_h: float) -> void:
	var n := pos.size()
	if n == 0:
		return
	var iters := ITER_OVERRIDE if ITER_OVERRIDE > 0 else iterations
	for _it in iters:
		_solve_once(n)
	if pinned_index >= 0 and pinned_index < n:
		pos[pinned_index] = pin_pos


func _solve_once(n: int) -> void:
	# Primeiro segmento: corpo rígido ↔ partícula.
	var r := body.q * body.tail_local
	var a := body.x + r
	var d := pos[0] - a
	var l := d.length()
	if l > seg_len and l > 0.00001:
		var nrm := d / l
		# Pipa guiada pelo modelo de voo: a rabiola já entra no peso dele; ela segue
		# a pipa sem empurrá-la (senão o puxão da rabiola contava duas vezes).
		var wb := 0.0 if body.kinematic else body.inverse_mass_at(r, nrm)
		var wsum := inv_m + wb
		var dl := -(l - seg_len) / wsum
		pos[0] += nrm * (dl * inv_m)
		if not body.kinematic:
			body.apply_correction(r, -nrm * dl)
	for i in range(1, n):
		var dd := pos[i] - pos[i - 1]
		var ll := dd.length()
		if ll <= seg_len or ll < 0.00001:
			continue
		var nn := dd / ll
		var corr := nn * ((ll - seg_len) * 0.5)
		pos[i] -= corr
		pos[i - 1] += corr
	for i in n:
		var p := pos[i]
		var gy := Ground.height_at(p.x, p.z) + 0.01
		if p.y < gy:
			p.y = gy
			pos[i] = p


## Rabiola engancha em fio ou galho; solta com tranco forte ou com o tempo (balançando).
func try_snag(obstacles: WorldObstacles, pull: float, dt: float) -> void:
	if pinned_index >= 0:
		pin_time -= dt
		if pin_time <= 0.0 or pull > 11.0:
			pinned_index = -1
		return
	for i in range(pos.size() - 1, maxi(pos.size() - 5, 0) - 1, -1):
		if obstacles.tail_hit(pos[i]):
			pinned_index = i
			pin_pos = pos[i]
			pin_time = randf_range(1.5, 7.0)
			return


func finalize(h: float) -> void:
	var inv_h := 1.0 / h
	for i in pos.size():
		vel[i] = (pos[i] - prev[i]) * inv_h
