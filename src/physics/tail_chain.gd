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


func _init(p_body: KiteRigidBody, p_profile: KiteProfile) -> void:
	body = p_body
	profile = p_profile
	var n := profile.tail_nodes
	seg_len = profile.tail_length / float(n)
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


func compute_forces() -> void:
	var wind := Wind.sample(attach_point())
	for i in pos.size():
		var vrel := wind - vel[i]
		var f := vrel * (0.5 * RHO * vrel.length() * profile.tail_cd * node_area)
		var a := GRAVITY + f * inv_m
		var al := a.length()
		acc[i] = a / al * 400.0 if al > 400.0 else a


func predict(h: float) -> void:
	for i in pos.size():
		prev[i] = pos[i]
		vel[i] += acc[i] * h
		pos[i] += vel[i] * h


func solve(_h: float) -> void:
	var n := pos.size()
	if n == 0:
		return
	# Primeiro segmento: corpo rígido ↔ partícula.
	var r := body.q * body.tail_local
	var a := body.x + r
	var d := pos[0] - a
	var l := d.length()
	if l > seg_len and l > 0.00001:
		var nrm := d / l
		var wsum := inv_m + body.inverse_mass_at(r, nrm)
		var dl := -(l - seg_len) / wsum
		pos[0] += nrm * (dl * inv_m)
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
		if p.y < 0.01:
			p.y = 0.01
			pos[i] = p


func finalize(h: float) -> void:
	var inv_h := 1.0 / h
	for i in pos.size():
		vel[i] = (pos[i] - prev[i]) * inv_h
