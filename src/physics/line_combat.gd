class_name LineCombat
extends RefCounted
## Cruzamento de linhas entre pipas diferentes.
##
## 1) Detecção (por tick): segmentos próximos (< DETECT_RADIUS) viram um CONTATO.
## 2) Contato (por subpasso): as linhas não se atravessam — cada contato guarda o
##    lado (normal) e empurra os dois segmentos para manter a folga. A tração das
##    linhas aperta uma contra a outra: é o "cruzou / enroscou". Atrito de Coulomb
##    no contato (μ médio das duas linhas): apertadas, elas pegam e escorregam.
## 3) Desgaste (por tick): energia de atrito E = μ·N·v_desliz·dt. Cada linha recebe
##    E × abrasão_da_outra / resistência_própria, espalhada pelo trecho de MATERIAL
##    dela que passou pelo ponto de contato. Quem dá linha (ou puxa rápido) passa
##    material novo pelo contato e espalha o desgaste; quem fica parado concentra
##    num ponto e é cortado. Linha esticada corta mais fácil.

## Contato ESPECULATIVO: todo par de trechos que pode se encontrar dentro do quadro
## (as linhas andam até ~0,6 m por quadro a 30 Hz numa puxada forte) já ganha um
## contato que guarda o LADO; ele só empurra quando encosta (restrição unilateral),
## mas é checado a cada subpasso — por isso as linhas não "pulam" uma pela outra
## entre dois quadros.
static var DEBUG_FLIPS := false
const DETECT_RADIUS := 0.7
const RELEASE_DISTANCE := 1.0
const CONTACT_GAP := 0.003
const BIN := 0.1
const DAMAGE_SCALE := 0.22
const GROUP := 4
const HOOK_GAP := 0.03
const MAX_PER_PAIR := 24
## Correção máxima por subpasso: contato que já veio atravessado (pego só no fim do
## quadro) volta aos poucos; contato especulativo (pego antes) corrige tudo.
const MAX_PUSH := 0.12
const MAX_PUSH_SPEC := 0.5
## Contato do lado errado (atravessado) só é largado se ficar absurdo de longe.
const GIVE_UP_DISTANCE := 4.0


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
	## Qual ponta está laçada: 0 = cabresto da pipa de `a`, 1 = da de `b` (−1 = antigo).
	var hook_side: int = -1
	## Criado depois de as linhas já terem passado uma pela outra (volta aos poucos).
	var crossed: bool = false
	## Encostadas de verdade no último tick (o contato especulativo existe antes).
	var touching: bool = false


var contacts: Array[Contact] = []
## Pipas que receberam pontos de apoio (cruzamentos encostados) no último tick.
var _pivot_rigs: Array = []
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

## Tem linha que conta para o contato: pipa no ar, pipa voada com a linha dela ou a
## sobra de linha na mão depois do corte (linha solta caindo não atravessa as outras).
static func _has_line(r: KiteRig) -> bool:
	return is_instance_valid(r) and r.rope != null and r.rope.pos.size() >= 2


func detect(rigs: Array[KiteRig]) -> void:
	for i in range(contacts.size() - 1, -1, -1):
		var c := contacts[i]
		if not (_has_line(c.a) and _has_line(c.b) and (c.a.is_flying() or c.b.is_flying())):
			contacts.remove_at(i)
		elif c.ia >= c.a.rope.segment_count() + 1 or c.ib >= c.b.rope.segment_count() + 1:
			contacts.remove_at(i)
	for i in rigs.size():
		var ra := rigs[i]
		if not _has_line(ra):
			continue
		for j in range(i + 1, rigs.size()):
			var rb := rigs[j]
			if not _has_line(rb) or not (ra.is_flying() or rb.is_flying()):
				continue
			_detect_pair(ra, rb)
			if ra.is_flying() and rb.is_flying():
				_detect_kite(ra, rb)
				_detect_kite(rb, ra)
	_dedupe()
	_prev_pts.clear()
	for r in rigs:
		if _has_line(r):
			var sv := r.rope.mat_s.duplicate()
			if r.rope.end_body != null:
				sv.append(0.0)
			_prev_pts[r] = [_rope_points(r.rope), sv]


## Só a parte das pipas do detect (fim do tick): a linha que encostou na vela
## durante o tick laça já, com as posições finais (e o varrido desde o começo).
func detect_kites(rigs: Array[KiteRig]) -> void:
	for i in rigs.size():
		var ra := rigs[i]
		if not ra.is_flying() or not _has_line(ra):
			continue
		for j in range(i + 1, rigs.size()):
			var rb := rigs[j]
			if rb.is_flying() and _has_line(rb):
				_detect_kite(ra, rb)
				_detect_kite(rb, ra)


## A linha de `other` encostou na PIPA de `owner` (vela, varetas ou linhas da
## cabeça): ela não atravessa o papel — engancha na armação e escorrega até o
## cabresto (laçou). Vira um contato "laçado" no ponto do cabresto da pipa.
func _detect_kite(owner: KiteRig, other: KiteRig) -> void:
	var body := owner.body
	if body == null or owner.rope == null or owner.rope.end_body != body:
		return
	for ex in contacts:
		if ex.hooked and ((ex.a == owner and ex.b == other) or (ex.a == other and ex.b == owner)):
			return   # já laçada
	var pts := _rope_points(other.rope)
	var reach := owner.profile.height * 0.75
	var n: Vector3 = body.q * Vector3.BACK
	var inv := body.q.inverse()
	var prev: Array = _prev_pts.get(other, [])
	var prev_pts: PackedVector3Array = prev[0] if not prev.is_empty() else PackedVector3Array()
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		# Perto da pipa? (distância do centro ao trecho)
		var ab := b - a
		var t := clampf((body.x - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		if (a + ab * t).distance_to(body.x) > reach:
			continue
		var hit := _segment_hits_sail(body, inv, n, a, b)
		if not hit and prev_pts.size() == pts.size():
			# Passou inteira pela vela entre dois ticks: testa a posição anterior também
			# e o "varrido" (meio do trecho antes → agora).
			hit = _segment_hits_sail(body, inv, n, prev_pts[j], prev_pts[j + 1]) \
				or _segment_hits_sail(body, inv, n, (prev_pts[j] + prev_pts[j + 1]) * 0.5, (a + b) * 0.5)
		if not hit:
			continue
		var c := Contact.new()
		c.a = owner
		c.b = other
		c.ia = owner.rope.segment_count() - 1
		c.ta = 1.0
		c.ib = j
		c.tb = t
		c.hooked = true
		c.hook_side = 0
		c.normal = n
		c.sa_prev = owner.rope.material_at(c.ia, 1.0)
		c.sb_prev = other.rope.material_at(j, t)
		c.position = body.x
		contacts.append(c)
		return


## O trecho a–b atravessa o plano da vela dentro do contorno da pipa?
static func _segment_hits_sail(body: KiteRigidBody, inv: Quaternion, n: Vector3, a: Vector3, b: Vector3) -> bool:
	var da := (a - body.x).dot(n)
	var db := (b - body.x).dot(n)
	if da * db > 0.0 and minf(absf(da), absf(db)) > 0.02:
		return false
	var t := clampf(da / (da - db), 0.0, 1.0) if absf(da - db) > 1e-6 else 0.5
	var lp: Vector3 = inv * (a.lerp(b, t) - body.x)
	return Geometry2D.is_point_in_polygon(Vector2(lp.x, lp.y), _outline(body))


static func _outline(body: KiteRigidBody) -> PackedVector2Array:
	var out := PackedVector2Array()
	for cnr in body.corners:
		out.append(Vector2(cnr.x, cnr.y))
	return out


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
	if dist > CROSS_RADIUS:
		return
	var crossed_normal := Vector3.ZERO
	if dist > DETECT_RADIUS:
		# Longe agora: atravessou entre quadros? (perto, os contatos antecipados já
		# guardam o lado a cada subpasso)
		if prev_a.is_empty() or prev_b.is_empty():
			return
		var cx := _crossed_between_frames(ra, rb, pa, pb, ia, ib, prev_a, prev_b)
		if cx.is_empty():
			return
		crossed_normal = cx[0]
		ta = cx[1]
		tb = cx[2]
	var sa := ra.rope.material_at(ia, ta)
	var sb := rb.rope.material_at(ib, tb)
	var pair_count := 0
	for ex in contacts:
		if ex.a == ra and ex.b == rb:
			pair_count += 1
			if (ex.ia == ia and ex.ib == ib) or (absf(ex.sa_prev - sa) < 0.5 and absf(ex.sb_prev - sb) < 0.5):
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
		c.crossed = true
	elif d.length() > 0.00001:
		c.normal = d.normalized()
	else:
		c.normal = (pa[ia + 1] - pa[ia]).cross(pb[ib + 1] - pb[ib]).normalized()
	c.sa_prev = sa
	c.sb_prev = sb
	c.position = (p_a + p_b) * 0.5
	contacts.append(c)


## Os trechos ia (de A) e ib (de B) trocaram de LADO desde o quadro anterior? Mede o
## lado pela normal comum (ea × eb) no ponto de cruzamento das retas, com os mesmos
## pontos do MATERIAL no quadro anterior (deslizar ao longo das linhas — dar linha,
## recolher, relar — não muda o lado; só atravessar muda). Devolve [normal do lado
## antigo, ta, tb] ou [] se não atravessou.
func _crossed_between_frames(ra: KiteRig, rb: KiteRig, pa: PackedVector3Array, pb: PackedVector3Array,
		ia: int, ib: int, prev_a: Array, prev_b: Array) -> Array:
	var ea := pa[ia + 1] - pa[ia]
	var eb := pb[ib + 1] - pb[ib]
	var cr := ea.cross(eb)
	var crl := cr.length()
	if crl < 0.2 * ea.length() * eb.length():
		return []  # quase paralelas: o lado não é bem definido
	var n := cr / crl
	var lp := _line_params(pa[ia], ea, pb[ib], eb)
	if lp.x < -0.02 or lp.x > 1.02 or lp.y < -0.02 or lp.y > 1.02:
		return []
	lp = lp.clamp(Vector2(0.01, 0.01), Vector2(0.99, 0.99))
	var qa := pa[ia] + ea * lp.x
	var qb := pb[ib] + eb * lp.y
	var side_now := (qb - qa).dot(n)
	var oa := _point_at_s(prev_a, ra.rope.material_at(ia, lp.x))
	var ob := _point_at_s(prev_b, rb.rope.material_at(ib, lp.y))
	var side_old := (ob - oa).dot(n)
	if side_old * side_now >= 0.0 or absf(side_old) > CROSS_RADIUS:
		return []
	return [n * signf(side_old), lp.x, lp.y]


## Parâmetros (s, t) dos pontos mais próximos entre as RETAS p1 + s·d1 e p2 + t·d2.
static func _line_params(p1: Vector3, d1: Vector3, p2: Vector3, d2: Vector3) -> Vector2:
	var r := p1 - p2
	var a := d1.dot(d1)
	var b := d1.dot(d2)
	var c := d1.dot(r)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var den := a * e - b * b
	if absf(den) < 1e-12:
		return Vector2(-1.0, -1.0)
	return Vector2((b * f - c * e) / den, (a * f - b * c) / den)


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

## Contatos do mesmo par no MESMO ponto (pela posição atual, em material): com as
## linhas deitadas uma sobre a outra, vários contatos escorregavam para o mesmo lugar e
## empurravam juntos — passavam do ponto, as linhas tremiam a milímetros e trocavam
## de lado. Fica um por ponto (o que aperta mais).
func _dedupe() -> void:
	var seen := {}
	for i in range(contacts.size() - 1, -1, -1):
		var c := contacts[i]
		if c.hooked or c.a.rope == null or c.b.rope == null:
			continue
		if c.ia >= c.a.rope.segment_count() or c.ib >= c.b.rope.segment_count():
			continue
		var sa := c.a.rope.material_at(c.ia, c.ta)
		var sb := c.b.rope.material_at(c.ib, c.tb)
		var key := Vector4i(c.a.get_instance_id() % 100000, c.b.get_instance_id() % 100000, int(roundf(sa * 4.0)), int(roundf(sb * 4.0)))
		if seen.has(key):
			var k: int = seen[key]
			var other := contacts[k]
			if c.impulse > other.impulse or c.crossed:
				contacts[k] = c
			contacts.remove_at(i)
			# índices acima de i andaram uma casa
			for kk in seen:
				if int(seen[kk]) > i:
					seen[kk] = int(seen[kk]) - 1
		else:
			seen[key] = i


func solve(h: float) -> void:
	var used := {}
	var occ := {}
	for c in contacts:
		if not c.hooked:
			occ[_occ_key(c, c.ia, c.ib)] = c
	for c in contacts:
		_refresh(c, occ)
		if not c.hooked and c.ia < c.a.rope.segment_count() and c.ib < c.b.rope.segment_count():
			# Um contato só empurra por ponto em cada subpasso.
			var key := Vector4i(c.a.get_instance_id() % 100000, c.b.get_instance_id() % 100000,
				int(roundf(c.a.rope.material_at(c.ia, c.ta) * 4.0)), int(roundf(c.b.rope.material_at(c.ib, c.tb) * 4.0)))
			if used.has(key):
				continue
			used[key] = true
		var ra := c.a.rope
		var rb := c.b.rope
		var pa_pts := ra.segment_points(c.ia)
		var pb_pts := rb.segment_points(c.ib)
		var pa := pa_pts[0].lerp(pa_pts[1], c.ta)
		var pb := pb_pts[0].lerp(pb_pts[1], c.tb)
		var d := pb - pa
		if not c.hooked and not c.crossed:
			# LADO medido de forma CONTÍNUA no subpasso: compara a separação no começo
			# do subpasso (posições já sem atravessar) com a de agora, na mesma direção.
			# Se o sinal trocou, as linhas passaram uma pela outra neste subpasso → o
			# contato as devolve para o lado de onde vieram. Sem memória de orientação
			# (que podia se inverter quando os pontos mais próximos pulavam de trecho).
			var da_s := _disp(ra, c.ia, h).lerp(_disp(ra, c.ia + 1, h), c.ta)
			var db_s := _disp(rb, c.ib, h).lerp(_disp(rb, c.ib + 1, h), c.tb)
			var d_prev := (pb - db_s) - (pa - da_s)
			var n_before := c.normal
			var interior := c.ta > 0.0 and c.ta < 1.0 and c.tb > 0.0 and c.tb < 1.0
			var ea := pa_pts[1] - pa_pts[0]
			var eb := pb_pts[1] - pb_pts[0]
			var cr := ea.cross(eb)
			var crl := cr.length()
			if interior and crl > 0.25 * sqrt(ea.length_squared() * eb.length_squared()):
				var n := cr / crl
				var f_old := d_prev.dot(n)
				if absf(f_old) > 1e-6:
					c.normal = n * signf(f_old)
				elif n.dot(c.normal) != 0.0:
					c.normal = n * signf(n.dot(c.normal))
			elif d_prev.length() > 1e-5:
				# Ponta de trecho ou quase paralelas: a separação do começo do subpasso.
				c.normal = d_prev.normalized()
			if DEBUG_FLIPS and n_before.dot(c.normal) < -0.2:
				print("FLIP n %d/%d t=%.2f/%.2f interior=%s par=%s |dprev|=%.4f |d|=%.4f dot=%.2f" % [c.ia, c.ib, c.ta, c.tb, str(interior), str(crl <= 0.25 * sqrt(ea.length_squared() * eb.length_squared())), d_prev.length(), d.length(), n_before.dot(c.normal)])
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
				# O ponto principal está separado, mas em linhas deitadas uma na outra
				# as pontas da sobreposição podem não estar.
				_push_overlap(c, nrm)
				continue
			# Atravessou muito (puxada forte): volta em alguns subpassos, sem explodir.
			violation = minf(CONTACT_GAP - sep, MAX_PUSH if c.crossed else MAX_PUSH_SPEC)
			if sep > 0.0:
				c.crossed = false
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
		c.a.pushed_by_line = true
		c.b.pushed_by_line = true
		_push(ra, c.ia, -nv * ua)
		_push(ra, c.ia + 1, -nv * c.ta)
		_push(rb, c.ib, nv * ub)
		_push(rb, c.ib + 1, nv * c.tb)
		c.impulse += lam
		if c.hooked:
			continue
		# Linhas QUASE PARALELAS (deitadas uma sobre a outra): o ponto mais próximo não é
		# definido e um contato num ponto só não protege o resto do trecho. Os trechos
		# são retos: se as duas PONTAS da parte sobreposta ficam do lado certo, o trecho
		# inteiro fica. Empurra também nessas duas pontas, com a mesma normal.
		_push_overlap(c, nrm)
		# Atrito de Coulomb entre as linhas: o deslizamento relativo do subpasso é
		# limitado por μ × (correção normal). Linhas apertadas "pegam" e escorregam
		# com resistência (relo), em vez de deslizar livres.
		var mu := (c.a.line_type.friction + c.b.line_type.friction) * 0.5
		var da := _disp(ra, c.ia, h).lerp(_disp(ra, c.ia + 1, h), c.ta)
		var db := _disp(rb, c.ib, h).lerp(_disp(rb, c.ib + 1, h), c.tb)
		var rel := db - da
		var tang := rel - nrm * rel.dot(nrm)
		var tl := tang.length()
		if tl > 1e-7:
			var lt := minf(tl / wsum, mu * lam)
			var tdir := tang / tl
			_push(ra, c.ia, tdir * (lt * ua))
			_push(ra, c.ia + 1, tdir * (lt * c.ta))
			_push(rb, c.ib, -tdir * (lt * ub))
			_push(rb, c.ib + 1, -tdir * (lt * c.tb))


## Linhas QUASE PARALELAS (deitadas uma sobre a outra): o ponto mais próximo não é
## definido e um contato num ponto só não protege o resto do trecho. Os trechos são
## retos: se as duas PONTAS da parte sobreposta ficam do lado certo, o trecho inteiro
## fica. Empurra nessas duas pontas, com a mesma normal do contato.
func _push_overlap(c: Contact, nrm: Vector3) -> void:
	var ra := c.a.rope
	var rb := c.b.rope
	var pa_pts := ra.segment_points(c.ia)
	var pb_pts := rb.segment_points(c.ib)
	var ea := pa_pts[1] - pa_pts[0]
	var eb := pb_pts[1] - pb_pts[0]
	var la := ea.length_squared()
	var lb := eb.length_squared()
	if la < 1e-8 or lb < 1e-8 or ea.cross(eb).length() >= 0.25 * sqrt(la * lb):
		return
	var u0 := clampf((pb_pts[0] - pa_pts[0]).dot(ea) / la, 0.0, 1.0)
	var u1 := clampf((pb_pts[1] - pa_pts[0]).dot(ea) / la, 0.0, 1.0)
	for uv in [minf(u0, u1), maxf(u0, u1)]:
		var ue: float = uv
		if absf(ue - c.ta) < 0.02:
			continue
		var qa: Vector3 = pa_pts[0] + ea * ue
		var ve := clampf((qa - pb_pts[0]).dot(eb) / lb, 0.0, 1.0)
		var lam := _push_point(ra, rb, c.ia, c.ib, ue, ve, nrm, c.crossed)
		if lam > 0.0:
			c.impulse += lam
			c.a.pushed_by_line = true
			c.b.pushed_by_line = true


## Garante a separação ≥ CONTACT_GAP ao longo de `nrm` no ponto (ta, tb) dos trechos
## ia/ib. Devolve o multiplicador aplicado.
func _push_point(ra: Rope, rb: Rope, ia: int, ib: int, ta: float, tb: float, nrm: Vector3, crossed: bool) -> float:
	var pa_pts := ra.segment_points(ia)
	var pb_pts := rb.segment_points(ib)
	var sep := (pb_pts[0].lerp(pb_pts[1], tb) - pa_pts[0].lerp(pa_pts[1], ta)).dot(nrm)
	if sep >= CONTACT_GAP:
		return 0.0
	var violation := minf(CONTACT_GAP - sep, MAX_PUSH if crossed else MAX_PUSH_SPEC)
	var ua := 1.0 - ta
	var ub := 1.0 - tb
	var wsum := _weight(ra, ia, -nrm) * ua * ua + _weight(ra, ia + 1, -nrm) * ta * ta \
		+ _weight(rb, ib, nrm) * ub * ub + _weight(rb, ib + 1, nrm) * tb * tb
	if wsum <= 0.0:
		return 0.0
	var lam := violation / wsum
	var nv := nrm * lam
	_push(ra, ia, -nv * ua)
	_push(ra, ia + 1, -nv * ta)
	_push(rb, ib, nv * ub)
	_push(rb, ib + 1, nv * tb)
	return lam


## Deslocamento do ponto `idx` da linha neste subpasso.
static func _disp(r: Rope, idx: int, h: float) -> Vector3:
	if idx < r.pos.size():
		return r.pos[idx] - r.prev[idx]
	if r.end_body != null:
		if r.end_prev_world != Vector3.ZERO:
			return r.end_point() - r.end_prev_world
		return r.end_body.point_velocity(r.end_body.q * r.end_local) * h
	return Vector3.ZERO


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
static func _occ_key(c: Contact, ia: int, ib: int) -> String:
	return "%d:%d:%d:%d" % [c.a.get_instance_id(), c.b.get_instance_id(), ia, ib]


func _refresh(c: Contact, occ = null) -> void:
	var seg_a := c.a.rope.segment_count()
	var seg_b := c.b.rope.segment_count()
	if c.hooked and c.hook_side >= 0:
		# Laçada: uma ponta fica no cabresto; a outra linha escorrega até o ponto
		# dela mais perto do cabresto.
		var owner_rope := c.a.rope if c.hook_side == 0 else c.b.rope
		var other_rope := c.b.rope if c.hook_side == 0 else c.a.rope
		var pe := owner_rope.end_point()
		var j := clampi(c.ib if c.hook_side == 0 else c.ia, 0, other_rope.segment_count() - 1)
		var tt := 0.0
		for _k in 3:
			var sp := other_rope.segment_points(j)
			var ab: Vector3 = sp[1] - sp[0]
			tt = clampf((pe - sp[0]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			if tt <= 0.0 and j > 0:
				j -= 1
			elif tt >= 1.0 and j < other_rope.segment_count() - 1:
				j += 1
			else:
				break
		if c.hook_side == 0:
			c.ia = seg_a - 1
			c.ta = 1.0
			c.ib = j
			c.tb = tt
		else:
			c.ib = seg_b - 1
			c.tb = 1.0
			c.ia = j
			c.ta = tt
		return
	c.ia = clampi(c.ia, 0, seg_a - 1)
	c.ib = clampi(c.ib, 0, seg_b - 1)
	for _k in 2:
		var pa := c.a.rope.segment_points(c.ia)
		var pb := c.b.rope.segment_points(c.ib)
		var res := closest_segments(pa[0], pa[1], pb[0], pb[1])
		c.ta = res[0]
		c.tb = res[1]
		# Trechos QUASE PARALELOS (linhas deitadas uma na outra): o ponto mais próximo
		# vive batendo na ponta do trecho e todos os contatos escorregariam para o
		# mesmo lugar, deixando o resto da sobreposição desprotegido. O contato fica
		# no par dele (o empurrão nas duas pontas da sobreposição cobre o par inteiro);
		# os pares vizinhos têm os contatos deles.
		var ea: Vector3 = pa[1] - pa[0]
		var eb: Vector3 = pb[1] - pb[0]
		if ea.cross(eb).length() < 0.25 * sqrt(ea.length_squared() * eb.length_squared()):
			break
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
	# Chegou na pipa (ponta com corpo), ENCOSTADA → laça no cabresto.
	if not c.hooked and c.touching:
		if c.a.rope.end_body != null and c.ia == seg_a - 1 and c.ta >= 0.999:
			c.hooked = true
			c.hook_side = 0
		elif c.b.rope.end_body != null and c.ib == seg_b - 1 and c.tb >= 0.999:
			c.hooked = true
			c.hook_side = 1


# --- Desgaste (por tick) -------------------------------------------------------

func post_frame(dt: float, h: float, substeps: int) -> void:
	cut_requests.clear()
	for r in _pivot_rigs:
		if is_instance_valid(r):
			(r as KiteRig).line_pivots = []
	_pivot_rigs.clear()
	# Contatos do mesmo par que escorregaram para o mesmo lugar viram um só (senão
	# esgotam o limite por par e um cruzamento novo ficaria sem contato).
	for i in range(contacts.size() - 1, 0, -1):
		var ci := contacts[i]
		if ci.hooked:
			continue
		for j in i:
			var cj := contacts[j]
			if cj.hooked or cj.a != ci.a or cj.b != ci.b:
				continue
			if absf(cj.sa_prev - ci.sa_prev) < 0.25 and absf(cj.sb_prev - ci.sb_prev) < 0.25:
				# Fica o que está apertando mais (o outro é cópia velha).
				if ci.impulse > cj.impulse:
					contacts[j] = ci
				contacts.remove_at(i)
				break
	# Um laço por par e por ponta basta (contatos que escorregaram até a mesma ponta).
	var seen := {}
	for i in range(contacts.size() - 1, -1, -1):
		var hc := contacts[i]
		if not hc.hooked:
			continue
		var owner: KiteRig = hc.a if hc.hook_side == 0 else hc.b
		var other: KiteRig = hc.b if hc.hook_side == 0 else hc.a
		var key := str(owner.get_instance_id()) + ">" + str(other.get_instance_id())
		if seen.has(key):
			contacts.remove_at(i)
		else:
			seen[key] = true
	for i in range(contacts.size() - 1, -1, -1):
		var c := contacts[i]
		var ra := c.a.rope
		var rb := c.b.rope
		var pa_pts := ra.segment_points(c.ia)
		var pb_pts := rb.segment_points(c.ib)
		var pa := pa_pts[0].lerp(pa_pts[1], c.ta)
		var pb := pb_pts[0].lerp(pb_pts[1], c.tb)
		if not c.hooked:
			# Só larga o contato com as linhas SEPARADAS do lado certo (ou uma escapou
			# pela ponta da mão); do lado errado o contato continua empurrando de volta.
			var dd := pb - pa
			var dl := dd.length()
			var at_end := (c.ia == 0 and c.ta <= 0.0) or (c.ib == 0 and c.tb <= 0.0)
			if dl > RELEASE_DISTANCE and (dd.dot(c.normal) > 0.0 or at_end or dl > GIVE_UP_DISTANCE):
				contacts.remove_at(i)
				continue
		c.age += dt
		c.position = (pa + pb) * 0.5
		c.force = c.impulse / (h * h * float(substeps))
		c.touching = c.hooked or c.force > 0.005 or pa.distance_to(pb) < 0.02
		if c.touching or pa.distance_to(pb) < 0.25:
			# Perto: as duas linhas são desenhadas RETAS ali (a curva suave entre os nós
			# estufava e passava por dentro da outra linha, mesmo separadas na física).
			ra.add_render_kink(c.ia, c.ta)
			rb.add_render_kink(c.ib, c.tb)
		if c.touching:
			if not c.hooked:
				# A pipa de cada um passa a girar em volta deste cruzamento.
				c.a.line_pivots.append([c.ia, c.ta, c.b.get_instance_id()])
				c.b.line_pivots.append([c.ib, c.tb, c.a.get_instance_id()])
				if not _pivot_rigs.has(c.a):
					_pivot_rigs.append(c.a)
				if not _pivot_rigs.has(c.b):
					_pivot_rigs.append(c.b)
		c.impulse = 0.0
		var sa := ra.material_at(c.ia, c.ta)
		var sb := rb.material_at(c.ib, c.tb)
		var rel := ra.velocity_at(c.ia, c.ta) - rb.velocity_at(c.ib, c.tb)
		c.slide = (rel - c.normal * rel.dot(c.normal)).length()
		if c.hooked:
			# Laçada: o laço "serra" — as pipas balançam e a linha esfrega no laço
			# mesmo sem escorregar de verdade (mais tensão = mais esfrega).
			c.slide = maxf(c.slide, 0.25 + 0.03 * c.force)
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
