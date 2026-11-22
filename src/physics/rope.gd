class_name Rope
extends RefCounted
## Linha de pipa simulada como corrente de partículas XPBD ("small steps").
##
## - Cada segmento é um CABO: só resiste à tração (frouxo não empurra), com a
##   elasticidade real da linha (compliance = comprimento / EA).
## - Arrasto do vento por segmento (componente normal, cilindro Cd≈1,1) + peso:
##   é isso que faz a linha "fazer barriga" a favor do vento e cair quando frouxa.
## - Nó 0 = mão (cinemático). O último segmento liga ao cabresto da pipa (corpo
##   rígido), ou fica solto quando a linha foi cortada.
## - A linha entra/sai pela mão: o primeiro segmento cresce/encolhe e nós são
##   inseridos/removidos perto da mão, preservando o MATERIAL ao longo da linha.
##   s = coordenada de material (metros a partir da pipa), usada no desgaste.

const RHO := 1.225
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const CD_NORMAL := 1.1
const CF_TANGENT := 0.02

var type: LineType
var pos: PackedVector3Array = PackedVector3Array()
var prev: PackedVector3Array = PackedVector3Array()
var vel: PackedVector3Array = PackedVector3Array()
var acc: PackedVector3Array = PackedVector3Array()
var inv_mass: PackedFloat32Array = PackedFloat32Array()
var rest: PackedFloat32Array = PackedFloat32Array()
var lam: PackedFloat32Array = PackedFloat32Array()
## Coordenada de material de cada nó (m a partir da ponta da pipa).
var mat_s: PackedFloat32Array = PackedFloat32Array()

## Corpo preso na ponta (pipa) ou null.
var end_body: KiteRigidBody = null
var end_local := Vector3.ZERO
## Nó 0 preso à mão?
var hand_fixed: bool = true
var hand_position := Vector3.ZERO

var segment_target: float = 3.0
var max_nodes: int = 40
var min_nodes: int = 4

## Tensões medidas no último tick (N).
var tension_hand: float = 0.0
var tension_end: float = 0.0
var _lam_hand_sum: float = 0.0
var _lam_end_sum: float = 0.0
var _substeps_done: int = 0


func _init(line_type: LineType) -> void:
	type = line_type


func node_count() -> int:
	return pos.size()


func segment_count() -> int:
	return pos.size() if end_body != null else pos.size() - 1


func end_point() -> Vector3:
	return end_body.world_point(end_local) if end_body != null else pos[pos.size() - 1]


func length() -> float:
	var total := 0.0
	for r in rest:
		total += r
	return total


## Cria a linha reta de `a` (mão) até a pipa, com o comprimento total dado.
func setup(a: Vector3, body: KiteRigidBody, local_anchor: Vector3, total_length: float) -> void:
	end_body = body
	end_local = local_anchor
	hand_position = a
	var b := end_point()
	var n := clampi(int(round(total_length / segment_target)), min_nodes, max_nodes)
	var seg := total_length / float(n)
	pos.resize(n)
	rest.resize(n)
	for i in n:
		pos[i] = a.lerp(b, float(i) / float(n))
		rest[i] = seg
	prev = pos.duplicate()
	vel.resize(n)
	vel.fill(Vector3.ZERO)
	_rebuild_masses()


func _rebuild_masses() -> void:
	var n := pos.size()
	inv_mass.resize(n)
	acc.resize(n)
	lam.resize(segment_count())
	var seg_n := segment_count()
	for i in n:
		var l := 0.0
		if i < seg_n:
			l += rest[i] * 0.5
		if i > 0:
			l += rest[i - 1] * 0.5
		var m := maxf(type.mass_per_meter * l, 0.00005)
		inv_mass[i] = 1.0 / m
	if hand_fixed and n > 0:
		inv_mass[0] = 0.0
	_update_material_coords()


func _update_material_coords() -> void:
	var n := pos.size()
	mat_s.resize(n)
	var seg_n := segment_count()
	var s := 0.0
	if seg_n < n:  # ponta solta: último nó é material s=0
		mat_s[n - 1] = 0.0
		for i in range(n - 2, -1, -1):
			s += rest[i]
			mat_s[i] = s
	else:
		for i in range(n - 1, -1, -1):
			s += rest[i]
			mat_s[i] = s


## Linha entrando (+) ou saindo (−) pela mão. Mantém o material do resto da linha.
func feed(delta_len: float) -> void:
	if pos.size() < 2 or not hand_fixed:
		return
	rest[0] = maxf(rest[0] + delta_len, 0.02)
	# Insere nós perto da mão quando o primeiro segmento fica longo.
	while rest[0] > segment_target * 1.5:
		if pos.size() >= max_nodes:
			_coarsen()
			continue
		var dir := pos[0] - pos[1]
		var dl := dir.length()
		dir = dir / dl if dl > 0.0001 else Vector3.UP
		var new_pos := pos[1] + dir * minf(segment_target, dl)
		pos.insert(1, new_pos)
		prev.insert(1, new_pos - (vel[1] / 600.0))
		vel.insert(1, vel[1])
		rest.insert(1, segment_target)
		rest[0] -= segment_target
		_rebuild_masses()
	# Remove nós quando o primeiro segmento fica curto.
	while rest[0] < segment_target * 0.4 and pos.size() > min_nodes:
		rest[0] += rest[1]
		pos.remove_at(1)
		prev.remove_at(1)
		vel.remove_at(1)
		rest.remove_at(1)
		_rebuild_masses()
	_update_material_coords()


## Junta nós alternados (linha muito comprida): dobra o tamanho do segmento.
func _coarsen() -> void:
	var i := 2
	while i < pos.size() - 1:
		rest[i - 1] += rest[i]
		pos.remove_at(i)
		prev.remove_at(i)
		vel.remove_at(i)
		rest.remove_at(i)
		i += 1
	segment_target *= 2.0
	_rebuild_masses()


## Forças externas do tick (peso + arrasto aerodinâmico), aplicadas em todos os subpassos.
func compute_forces() -> void:
	var n := pos.size()
	for i in n:
		acc[i] = GRAVITY
	var seg_n := segment_count()
	var d := type.diameter
	for i in seg_n:
		var a := pos[i]
		var b := pos[i + 1] if i + 1 < n else end_point()
		var seg := b - a
		var l := seg.length()
		if l < 0.0001:
			continue
		var t := seg / l
		var vm := vel[i] if i + 1 >= n else (vel[i] + vel[i + 1]) * 0.5
		var vrel := Wind.sample((a + b) * 0.5) - vm
		var vt := t * vrel.dot(t)
		var vn := vrel - vt
		var f := vn * (0.5 * RHO * vn.length() * d * l * CD_NORMAL)
		f += vt * (0.5 * RHO * vt.length() * PI * d * l * CF_TANGENT)
		acc[i] += f * (0.5 * inv_mass[i])
		if i + 1 < n:
			acc[i + 1] += f * (0.5 * inv_mass[i + 1])
	for i in n:
		var al := acc[i].length()
		if al > 300.0:
			acc[i] = acc[i] / al * 300.0
	_lam_hand_sum = 0.0
	_lam_end_sum = 0.0
	_substeps_done = 0


func predict(h: float) -> void:
	var n := pos.size()
	for i in n:
		prev[i] = pos[i]
		if inv_mass[i] > 0.0:
			vel[i] += acc[i] * h
			pos[i] += vel[i] * h
	if hand_fixed and n > 0:
		pos[0] = hand_position
	lam.fill(0.0)


func solve(h: float) -> void:
	var n := pos.size()
	var seg_n := segment_count()
	var inv_h2 := 1.0 / (h * h)
	var ea := type.axial_stiffness
	for i in seg_n:
		var alpha := rest[i] / ea * inv_h2
		if i + 1 < n:
			var d := pos[i + 1] - pos[i]
			var l := d.length()
			var c := l - rest[i]
			if c <= 0.0:
				continue
			var wsum := inv_mass[i] + inv_mass[i + 1]
			if wsum <= 0.0:
				continue
			var nrm := d / l
			var dl := (-c - alpha * lam[i]) / (wsum + alpha)
			lam[i] += dl
			pos[i] -= nrm * (dl * inv_mass[i])
			pos[i + 1] += nrm * (dl * inv_mass[i + 1])
		else:
			var r := end_body.q * end_local
			var a := end_body.x + r
			var d := a - pos[i]
			var l := d.length()
			var c := l - rest[i]
			if c <= 0.0 or l < 0.00001:
				continue
			var nrm := d / l
			var wsum := inv_mass[i] + end_body.inverse_mass_at(r, nrm)
			var dl := (-c - alpha * lam[i]) / (wsum + alpha)
			lam[i] += dl
			pos[i] -= nrm * (dl * inv_mass[i])
			end_body.apply_correction(r, nrm * dl)
	# Chão.
	for i in n:
		var p := pos[i]
		if p.y < 0.02:
			p.y = 0.02
			pos[i] = p
			var pv := prev[i]
			prev[i] = Vector3(lerpf(pv.x, p.x, 0.3), pv.y, lerpf(pv.z, p.z, 0.3))
	if seg_n > 0:
		_lam_hand_sum += lam[0]
		_lam_end_sum += lam[seg_n - 1]
	_substeps_done += 1


func finalize(h: float) -> void:
	var n := pos.size()
	var inv_h := 1.0 / h
	for i in n:
		vel[i] = (pos[i] - prev[i]) * (inv_h * 0.9995)


## Converte os multiplicadores acumulados em tensões (N).
func finish_tick(h: float) -> void:
	if _substeps_done == 0:
		return
	var k := -1.0 / (h * h * float(_substeps_done))
	tension_hand = maxf(_lam_hand_sum * k, 0.0)
	tension_end = maxf(_lam_end_sum * k, 0.0)


## Posição e velocidade do material da linha no parâmetro t do segmento i.
func segment_points(i: int) -> Array[Vector3]:
	var a := pos[i]
	var b := pos[i + 1] if i + 1 < pos.size() else end_point()
	return [a, b]


func material_at(i: int, t: float) -> float:
	var sa := mat_s[i]
	var sb := mat_s[i + 1] if i + 1 < pos.size() else 0.0
	return lerpf(sa, sb, t)


func velocity_at(i: int, t: float) -> Vector3:
	var va := vel[i]
	var vb: Vector3
	if i + 1 < pos.size():
		vb = vel[i + 1]
	else:
		vb = end_body.point_velocity(end_body.q * end_local) if end_body != null else va
	return va.lerp(vb, t)


## Corta a linha na coordenada de material s_cut.
## Esta linha fica com o lado da mão (ponta solta); retorna a linha do lado da pipa.
func split_at(s_cut: float) -> Rope:
	var n := pos.size()
	var seg_n := segment_count()
	var k := -1
	for i in seg_n:
		var sb := mat_s[i + 1] if i + 1 < n else 0.0
		if mat_s[i] >= s_cut and sb <= s_cut:
			k = i
			break
	if k < 0:
		k = seg_n - 1
	var sa := mat_s[k]
	var sb2 := mat_s[k + 1] if k + 1 < n else 0.0
	var t := clampf((sa - s_cut) / maxf(sa - sb2, 0.0001), 0.0, 1.0)
	var pts := segment_points(k)
	var cut_pos := pts[0].lerp(pts[1], t)
	var cut_vel := velocity_at(k, t)

	var kite_side := Rope.new(type)
	kite_side.hand_fixed = false
	kite_side.end_body = end_body
	kite_side.end_local = end_local
	kite_side.segment_target = segment_target
	kite_side.pos.append(cut_pos)
	kite_side.vel.append(cut_vel)
	kite_side.rest.append(rest[k] * (1.0 - t))
	for i in range(k + 1, n):
		kite_side.pos.append(pos[i])
		kite_side.vel.append(vel[i])
		if i < seg_n:
			kite_side.rest.append(rest[i])
	kite_side.prev = kite_side.pos.duplicate()
	kite_side._rebuild_masses()

	# Este lado: nós 0..k + ponto do corte, ponta solta.
	pos.resize(k + 1)
	vel.resize(k + 1)
	pos.append(cut_pos)
	vel.append(cut_vel)
	var new_rest := PackedFloat32Array()
	for i in k:
		new_rest.append(rest[i])
	new_rest.append(maxf(rest[k] * t, 0.02))
	rest = new_rest
	end_body = null
	prev = pos.duplicate()
	_rebuild_masses()
	return kite_side
