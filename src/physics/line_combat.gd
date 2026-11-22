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
const DAMAGE_SCALE := 0.54
const GROUP := 4


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


var contacts: Array[Contact] = []
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
	if not box_a.grow(DETECT_RADIUS).intersects(box_b):
		return
	var na := pa.size() - 1
	var nb := pb.size() - 1
	var ga := 0
	while ga < na:
		var ga_end := mini(ga + GROUP, na)
		var gbox_a := _aabb(pa, ga, ga_end).grow(DETECT_RADIUS)
		if gbox_a.intersects(box_b):
			var gb := 0
			while gb < nb:
				var gb_end := mini(gb + GROUP, nb)
				if gbox_a.intersects(_aabb(pb, gb, gb_end)):
					for ia in range(ga, ga_end):
						for ib in range(gb, gb_end):
							_test_segments(ra, rb, pa, pb, ia, ib)
				gb = gb_end
		ga = ga_end


func _test_segments(ra: KiteRig, rb: KiteRig, pa: PackedVector3Array, pb: PackedVector3Array, ia: int, ib: int) -> void:
	var res := closest_segments(pa[ia], pa[ia + 1], pb[ib], pb[ib + 1])
	var dist: float = res[2]
	if dist > DETECT_RADIUS:
		return
	var ta: float = res[0]
	var tb: float = res[1]
	var sa := ra.rope.material_at(ia, ta)
	var sb := rb.rope.material_at(ib, tb)
	for ex in contacts:
		if ex.a == ra and ex.b == rb and absf(ex.sa_prev - sa) < 1.0 and absf(ex.sb_prev - sb) < 1.0:
			return
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
	if d.length() > 0.00001:
		c.normal = d.normalized()
	else:
		c.normal = (pa[ia + 1] - pa[ia]).cross(pb[ib + 1] - pb[ib]).normalized()
	c.sa_prev = sa
	c.sb_prev = sb
	c.position = (p_a + p_b) * 0.5
	contacts.append(c)


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
		var na := ra.pos.size()
		var nb := rb.pos.size()
		var a0 := ra.pos[c.ia]
		var a1 := ra.pos[c.ia + 1] if c.ia + 1 < na else ra.end_point()
		var b0 := rb.pos[c.ib]
		var b1 := rb.pos[c.ib + 1] if c.ib + 1 < nb else rb.end_point()
		var pa := a0.lerp(a1, c.ta)
		var pb := b0.lerp(b1, c.tb)
		var d := pb - pa
		var sep := d.dot(c.normal)
		if sep >= CONTACT_GAP:
			var dl := d.length()
			if dl > 0.00001:
				c.normal = d / dl
			continue
		var wa0 := ra.inv_mass[c.ia]
		var wa1 := ra.inv_mass[c.ia + 1] if c.ia + 1 < na else 0.0
		var wb0 := rb.inv_mass[c.ib]
		var wb1 := rb.inv_mass[c.ib + 1] if c.ib + 1 < nb else 0.0
		var ua := 1.0 - c.ta
		var ub := 1.0 - c.tb
		var wsum := wa0 * ua * ua + wa1 * c.ta * c.ta + wb0 * ub * ub + wb1 * c.tb * c.tb
		if wsum <= 0.0:
			continue
		var lam := (CONTACT_GAP - sep) / wsum
		var nv := c.normal * lam
		ra.pos[c.ia] -= nv * (ua * wa0)
		if c.ia + 1 < na:
			ra.pos[c.ia + 1] -= nv * (c.ta * wa1)
		rb.pos[c.ib] += nv * (ub * wb0)
		if c.ib + 1 < nb:
			rb.pos[c.ib + 1] += nv * (c.tb * wb1)
		c.impulse += lam


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
		if pa.distance_to(pb) > RELEASE_DISTANCE:
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
			var energy := mu * c.force * c.slide * dt
			_wear(c.a, c.sa_prev, sa, energy * c.b.line_type.abrasion)
			_wear(c.b, c.sb_prev, sb, energy * c.a.line_type.abrasion)
		c.sa_prev = sa
		c.sb_prev = sb


func _wear(rig: KiteRig, s0: float, s1: float, energy: float) -> void:
	if energy <= 0.0:
		return
	var lt := rig.line_type
	var dmg := energy * DAMAGE_SCALE / lt.toughness
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
		var total: float = rig.wear.get(b, 0.0) + dmg * maxf(portion, 0.0)
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
