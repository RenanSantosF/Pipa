class_name LineCombat
extends RefCounted
## Cruzamento de linhas entre pipas diferentes.
##
## 1) Detecção (por tick): segmentos próximos (< DETECT_RADIUS) viram um CONTATO.
## 2) Contato (por subpasso): as linhas não se atravessam — cada contato guarda o
##    lado (normal) e empurra os dois segmentos para manter a folga. A tração das
##    linhas aperta uma contra a outra: é o "cruzou / enroscou".
## 3) Desgaste (por tick): energia de atrito E = μ·N·v_desliz·dt. Cada linha recebe
##    E × abrasão_da_outra / resistência_própria, espalhada pelo trecho de MATERIAL
##    dela que passou pelo ponto de contato. Quem dá linha (ou puxa rápido) passa
##    material novo pelo contato e espalha o desgaste; quem fica parado concentra
##    num ponto e é cortado. Linha esticada corta mais fácil.

const DETECT_RADIUS := 0.15
const RELEASE_DISTANCE := 0.6
const CONTACT_GAP := 0.003
const BIN := 0.1
const DAMAGE_SCALE := 0.22
const GROUP := 4
const HOOK_GAP := 0.03
const MAX_PER_PAIR := 8


class Contact:
	var a: KiteRig
	var b: KiteRig
	var ia: int = 0
	var ib: int = 0
	var ta: float = 0.0
	var tb: float = 0.0
	var normal := Vector3.UP
	var sa_prev: float = 0.0
	var sb_prev: float = 0.0
	var impulse: float = 0.0
	## Leituras do último tick (som, vibração, HUD).
	var force: float = 0.0
	var slide: float = 0.0
	var position := Vector3.ZERO
	var age: float = 0.0
	## A linha de um chegou na pipa do outro e laçou no cabresto.
	var hooked: bool = false


var contacts: Array[Contact] = []
## Posições do quadro anterior (para pegar linhas que se atravessam entre quadros).
var _prev_pts: Dictionary = {}
const CROSS_RADIUS := 2.0
## Pedidos de corte do último tick: [rig, s_material].
var cut_requests: Array = []


func clear_for(rig: KiteRig) -> void:
	for i in range(contacts.size() - 1, -1, -1):
		if contacts[i].a == rig or contacts[i].b == rig:
			contacts.remove_at(i)


# --- Detecção ----------------------------------------------------------------

func detect(rigs: Array[KiteRig]) -> void:
	for i in range(contacts.size() - 1, -1, -1):
		var c := contacts[i]
		if not (is_instance_valid(c.a) and is_instance_valid(c.b) and c.a.is_flying() and c.b.is_flying()):
			contacts.remove_at(i)
	for i in rigs.size():
		var ra := rigs[i]
		if not ra.is_flying():
			continue
		for j in range(i + 1, rigs.size()):
			var rb := rigs[j]
			if not rb.is_flying():
				continue
			_detect_pair(ra, rb)
	_prev_pts.clear()
	for r in rigs:
		if r.is_flying():
			var sv := r.rope.mat_s.duplicate()
			if r.rope.end_body != null:
				sv.append(0.0)
			_prev_pts[r] = [_rope_points(r.rope), sv]


func _rope_points(r: Rope) -> PackedVector3Array:
	var pts := r.pos.duplicate()
	if r.end_body != null:
		pts.append(r.end_point())
	return pts


func _detect_pair(ra: KiteRig, rb: KiteRig) -> void:
	var pa := _rope_points(ra.rope)
	var pb := _rope_points(rb.rope)
	var box_a := _aabb(pa, 0, pa.size() - 1)
	var box_b := _aabb(pb, 0, pb.size() - 1)
	if not box_a.grow(CROSS_RADIUS).intersects(box_b):
		return
	var prev_a: Array = _prev_pts.get(ra, [])
	var prev_b: Array = _prev_pts.get(rb, [])
	var na := pa.size() - 1
	var nb := pb.size() - 1
	var ga := 0
	while ga < na:
		var ga_end := mini(ga + GROUP, na)
		var gbox_a := _aabb(pa, ga, ga_end).grow(CROSS_RADIUS)
		if gbox_a.intersects(box_b):
			var gb := 0
			while gb < nb:
				var gb_end := mini(gb + GROUP, nb)
				if gbox_a.intersects(_aabb(pb, gb, gb_end)):
					for ia in range(ga, ga_end):
						for ib in range(gb, gb_end):
							_test_segments(ra, rb, pa, pb, ia, ib, prev_a, prev_b)
				gb = gb_end
		ga = ga_end


func _test_segments(ra: KiteRig, rb: KiteRig, pa: PackedVector3Array, pb: PackedVector3Array, ia: int, ib: int,
		prev_a: Array, prev_b: Array) -> void:
	var res := closest_segments(pa[ia], pa[ia + 1], pb[ib], pb[ib + 1])
	var dist: float = res[2]
	var ta: float = res[0]
	var tb: float = res[1]
	var crossed_normal := Vector3.ZERO
	if dist > DETECT_RADIUS:
		# Atravessou entre quadros? (o lado de uma linha em relação à outra trocou)
		if dist > CROSS_RADIUS or prev_a.is_empty() or prev_b.is_empty() or ta <= 0.0 or ta >= 1.0 or tb <= 0.0 or tb >= 1.0:
			return
		var now_d := pb[ib].lerp(pb[ib + 1], tb) - pa[ia].lerp(pa[ia + 1], ta)
		# Mesmo ponto do MATERIAL no quadro anterior (funciona mesmo dando linha).
		var old_d := _point_at_s(prev_b, rb.rope.material_at(ib, tb)) - _point_at_s(prev_a, ra.rope.material_at(ia, ta))
		if old_d.dot(now_d) >= 0.0 or old_d.length() > CROSS_RADIUS:
			return
		crossed_normal = old_d.normalized()
	var sa := ra.rope.material_at(ia, ta)
	var sb := rb.rope.material_at(ib, tb)
	var pair_count := 0
	for ex in contacts:
		if ex.a == ra and ex.b == rb:
			pair_count += 1
			if (ex.ia == ia and ex.ib == ib) or (absf(ex.sa_prev - sa) < 1.0 and absf(ex.sb_prev - sb) < 1.0):
				return
	if pair_count >= MAX_PER_PAIR:
		return  # linhas deitadas uma sobre a outra: poucos contatos bastam
	var c := Contact.new()
	c.a = ra
	c.b = rb
	c.ia = ia
	c.ib = ib
	c.ta = ta
	c.tb = tb
	var p_a := pa[ia].lerp(pa[ia + 1], ta)
	var p_b := pb[ib].lerp(pb[ib + 1], tb)
	var d := p_b - p_a
	if crossed_normal != Vector3.ZERO:
		c.normal = crossed_normal  # volta cada linha para o lado de onde veio
	elif d.length() > 0.00001:
		c.normal = d.normalized()
	else:
		c.normal = (pa[ia + 1] - pa[ia]).cross(pb[ib + 1] - pb[ib]).normalized()
	c.sa_prev = sa
	c.sb_prev = sb
	c.position = (p_a + p_b) * 0.5
	contacts.append(c)


## Posição de um ponto do material da linha (s) nas posições guardadas [pontos, s].
static func _point_at_s(stored: Array, s: float) -> Vector3:
	var pts: PackedVector3Array = stored[0]
	var sv: PackedFloat32Array = stored[1]
	var n := mini(pts.size(), sv.size())
	if n == 0:
		return Vector3.ZERO
	if s >= sv[0]:
		return pts[0]
	for i in n - 1:
		if sv[i] >= s and sv[i + 1] <= s:
			var t := (sv[i] - s) / maxf(sv[i] - sv[i + 1], 0.0001)
			return pts[i].lerp(pts[i + 1], t)
	return pts[n - 1]


static func _aabb(pts: PackedVector3Array, from: int, to: int) -> AABB:
	var mn := pts[from]
	var mx := mn
	for i in range(from + 1, to + 1):
		var p := pts[i]
		mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	return AABB(mn, mx - mn)


## Pontos mais próximos entre dois segmentos (Ericson). Retorna [s, t, distância].
static func closest_segments(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-10 and e <= 1e-10:
		return [0.0, 0.0, r.length()]
	if a <= 1e-10:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-10:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return [s, t, c1.distance_to(c2)]


# --- Resolução (subpasso) ----------------------------------------------------

func solve(_h: float) -> void:
	for c in contacts:
		_refresh(c)
		var ra := c.a.rope
		var rb := c.b.rope
		var pa_pts := ra.segment_points(c.ia)
		var pb_pts := rb.segment_points(c.ib)
		var pa := pa_pts[0].lerp(pa_pts[1], c.ta)
		var pb := pb_pts[0].lerp(pb_pts[1], c.tb)
		var d := pb - pa
		var nrm := c.normal
		var violation := 0.0
		if c.hooked:
			var dl := d.length()
			if dl <= HOOK_GAP or dl < 0.00001:
				continue
			nrm = -d / dl          # puxa os dois pontos um para o outro
			violation = dl - HOOK_GAP
		else:
			var sep := d.dot(nrm)
			if sep >= CONTACT_GAP:
				var dl2 := d.length()
				if dl2 > 0.00001:
					c.normal = d / dl2
				continue
			violation = CONTACT_GAP - sep
		# Pesos generalizados (nós da linha ou corpo rígido da pipa na ponta).
		var ua := 1.0 - c.ta
		var ub := 1.0 - c.tb
		var wa0 := _weight(ra, c.ia, -nrm) * ua * ua
		var wa1 := _weight(ra, c.ia + 1, -nrm) * c.ta * c.ta
		var wb0 := _weight(rb, c.ib, nrm) * ub * ub
		var wb1 := _weight(rb, c.ib + 1, nrm) * c.tb * c.tb
		var wsum := wa0 + wa1 + wb0 + wb1
		if wsum <= 0.0:
			continue
		var lam := violation / wsum
		var nv := nrm * lam
		_push(ra, c.ia, -nv * ua)
		_push(ra, c.ia + 1, -nv * c.ta)
		_push(rb, c.ib, nv * ub)
		_push(rb, c.ib + 1, nv * c.tb)
		c.impulse += lam


## Massa inversa do ponto `idx` da linha (o índice depois do último nó é o cabresto).
static func _weight(r: Rope, idx: int, dir: Vector3) -> float:
	if idx < r.pos.size():
		return r.inv_mass[idx]
	if r.end_body != null:
		return r.end_body.inverse_mass_at(r.end_body.q * r.end_local, dir)
	return 0.0


static func _push(r: Rope, idx: int, corr: Vector3) -> void:
	if idx < r.pos.size():
		r.pos[idx] += corr * r.inv_mass[idx]
	elif r.end_body != null:
		r.end_body.apply_correction(r.end_body.q * r.end_local, corr)


## Recalcula os parâmetros do contato, deslizando para segmentos vizinhos.
func _refresh(c: Contact) -> void:
	var seg_a := c.a.rope.segment_count()
	var seg_b := c.b.rope.segment_count()
	c.ia = clampi(c.ia, 0, seg_a - 1)
	c.ib = clampi(c.ib, 0, seg_b - 1)
	for _k in 2:
		var pa := c.a.rope.segment_points(c.ia)
		var pb := c.b.rope.segment_points(c.ib)
		var res := closest_segments(pa[0], pa[1], pb[0], pb[1])
		c.ta = res[0]
		c.tb = res[1]
		var moved := false
		if c.ta <= 0.0 and c.ia > 0:
			c.ia -= 1
			moved = true
		elif c.ta >= 1.0 and c.ia < seg_a - 1:
			c.ia += 1
			moved = true
		if c.tb <= 0.0 and c.ib > 0:
			c.ib -= 1
			moved = true
		elif c.tb >= 1.0 and c.ib < seg_b - 1:
			c.ib += 1
			moved = true
		if not moved:
			break
	# Chegou na pipa (ponta com corpo) → laça no cabresto.
	if not c.hooked:
		if c.a.rope.end_body != null and c.ia == seg_a - 1 and c.ta >= 0.999:
			c.hooked = true
		elif c.b.rope.end_body != null and c.ib == seg_b - 1 and c.tb >= 0.999:
			c.hooked = true


# --- Desgaste (por tick) -------------------------------------------------------

func post_frame(dt: float, h: float, substeps: int) -> void:
	cut_requests.clear()
	for i in range(contacts.size() - 1, -1, -1):
		var c := contacts[i]
		var ra := c.a.rope
		var rb := c.b.rope
		var pa_pts := ra.segment_points(c.ia)
		var pb_pts := rb.segment_points(c.ib)
		var pa := pa_pts[0].lerp(pa_pts[1], c.ta)
		var pb := pb_pts[0].lerp(pb_pts[1], c.tb)
		if not c.hooked and pa.distance_to(pb) > RELEASE_DISTANCE:
			contacts.remove_at(i)
			continue
		c.age += dt
		c.position = (pa + pb) * 0.5
		c.force = c.impulse / (h * h * float(substeps))
		c.impulse = 0.0
		var sa := ra.material_at(c.ia, c.ta)
		var sb := rb.material_at(c.ib, c.tb)
		var rel := ra.velocity_at(c.ia, c.ta) - rb.velocity_at(c.ib, c.tb)
		c.slide = (rel - c.normal * rel.dot(c.normal)).length()
		if c.force > 0.01:
			var mu := (c.a.line_type.friction + c.b.line_type.friction) * 0.5
			# Cruzamento em X fechado (perpendicular) corta bem mais que linhas quase paralelas.
			var ta := (pa_pts[1] - pa_pts[0]).normalized()
			var tb := (pb_pts[1] - pb_pts[0]).normalized()
			var angle_f := 0.3 + 0.7 * ta.cross(tb).length()
			var energy := mu * c.force * c.slide * dt * angle_f
			_wear(c.a, c.sa_prev, sa, energy * c.b.line_type.abrasion * c.b.spool_quality)
			_wear(c.b, c.sb_prev, sb, energy * c.a.line_type.abrasion * c.a.spool_quality)
		c.sa_prev = sa
		c.sb_prev = sb


func _wear(rig: KiteRig, s0: float, s1: float, energy: float) -> void:
	if energy <= 0.0:
		return
	var lt := rig.line_type
	var dmg := energy * DAMAGE_SCALE / (lt.toughness * rig.spool_quality)
	var lo := minf(s0, s1)
	var hi := maxf(s0, s1)
	var span := hi - lo
	var threshold := 1.0 - 0.6 * clampf(rig.tension / lt.break_tension, 0.0, 1.0)
	var b0 := floori(lo / BIN)
	var b1 := floori(hi / BIN)
	for b in range(b0, b1 + 1):
		var portion := 1.0
		if span > 0.0001:
			portion = (minf(hi, (b + 1) * BIN) - maxf(lo, b * BIN)) / span
		var total: float = rig.wear.get(b, 0.0) + dmg * maxf(portion, 0.0) / rig.bin_strength(b)
		rig.wear[b] = total
		if total >= threshold:
			cut_requests.append([rig, (float(b) + 0.5) * BIN])
			return


## Maior desgaste atual da linha (0..1+) — HUD/som.
static func max_wear(rig: KiteRig) -> float:
	var m := 0.0
	for k in rig.wear:
		m = maxf(m, rig.wear[k])
	return m
