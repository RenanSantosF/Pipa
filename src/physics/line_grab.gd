class_name LineGrabs
extends RefCounted
## ENGANCHES: uma linha esticada (de uma pipa no ar) encostando em algo SOLTO de outra
## pipa:
##   * na LINHA de uma pipa voada (cortada) ou na própria pipa voada → APARAR: a linha
##     solta enrosca na sua; recolhendo, a pipa vem junto até a mão e ela é sua;
##   * na RABIOLA de outra pipa no ar → sem cerol a linha PEGA a rabiola e arrasta a
##     pipa pela rabiola (até o barbante arrebentar com um tranco forte); com cerol ela
##     CORTA a rabiola onde encostou (a pipa fica com a rabiola curta, mais arisca).
##
## O enganche é uma restrição de posição XPBD entre o ponto da coisa presa e o ponto da
## linha que pegou, na coordenada de MATERIAL `s` da linha (o ponto anda junto com a
## linha quando ela é recolhida ou solta). É resolvida nos dois lados com as massas de
## verdade: a pipa voada pesa e arrasta a linha de quem aparou; a pipa presa pela
## rabiola puxa a linha de quem pegou.

const KIND_LINE := 0
const KIND_KITE := 1
const KIND_TAIL := 2
## Distâncias de encosto (m): linha × linha solta, linha × pipa voada, linha × rabiola.
const CATCH_R := 0.18
const KITE_R := 0.3
const TAIL_R := 0.12
## Linha que corta rabiola (rapinha, cerol, chilena; a pura só pega).
const CUT_ABRASION := 0.3
## Força sustentada (N) que arrebenta o barbante da rabiola presa e por quanto tempo.
const TAIL_TEAR := 3.0
const TAIL_TEAR_TIME := 0.15
## Enganche chegou a esta distância (m de linha) da mão = pipa aparada.
const COLLECT_DIST := 1.6
## Rigidez do enganche (N/m) — linha enrolada em linha cede um pouco.
const STIFFNESS := 3000.0


class Grab:
	var catcher: KiteRig
	var target: KiteRig
	var kind: int = 0
	var index: int = 0
	var s: float = 0.0
	var force: float = 0.0
	var tear_t: float = 0.0
	var lam_sum: float = 0.0
	var pos := Vector3.ZERO


var grabs: Array[Grab] = []
## Acontecimentos do último tick: [tipo, catcher, target, posição].
##   "enroscou_voada" · "aparou" · "pegou_rabiola" · "cortou_rabiola" · "arrebentou_rabiola"
var events: Array = []
## Pedaços de rabiola cortados neste tick: [posições, velocidades, rig].
var cut_pieces: Array = []


func clear_for(rig: KiteRig) -> void:
	for i in range(grabs.size() - 1, -1, -1):
		if grabs[i].catcher == rig or grabs[i].target == rig:
			grabs.remove_at(i)


func grabbed_tail_of(rig: KiteRig) -> Grab:
	for g in grabs:
		if g.kind == KIND_TAIL and g.target == rig:
			return g
	return null


func _has(catcher: KiteRig, target: KiteRig) -> bool:
	for g in grabs:
		if g.target == target and (g.catcher == catcher or g.kind != KIND_TAIL):
			return true
	return false


static func _rope_pts(r: Rope) -> PackedVector3Array:
	var pts := r.pos.duplicate()
	if r.end_body != null:
		pts.append(r.end_point())
	return pts


## Ponto da linha na coordenada de material s: [trecho, t, posição] (trecho -1 = fora).
static func point_at(r: Rope, s: float) -> Array:
	var n := r.pos.size()
	var seg_n := r.segment_count()
	for i in seg_n:
		var sa := r.mat_s[i]
		var sb := r.mat_s[i + 1] if i + 1 < n else 0.0
		if sa >= s and s >= sb:
			var t := (sa - s) / maxf(sa - sb, 1e-5)
			var b := r.pos[i + 1] if i + 1 < n else r.end_point()
			return [i, t, r.pos[i].lerp(b, t)]
	return [-1, 0.0, Vector3.ZERO]


# --- Detecção (por tick) -----------------------------------------------------------

func detect(rigs: Array[KiteRig]) -> void:
	events.clear()
	cut_pieces.clear()
	for i in range(grabs.size() - 1, -1, -1):
		var g := grabs[i]
		var ok := is_instance_valid(g.catcher) and is_instance_valid(g.target) and g.catcher.is_flying() and g.target.body != null
		if ok and g.kind == KIND_TAIL:
			ok = g.target.is_flying() and g.target.tail != null and g.index < g.target.tail.pos.size()
		elif ok and g.kind == KIND_LINE:
			ok = g.target.rope != null and g.index < g.target.rope.pos.size()
		if not ok:
			grabs.remove_at(i)
	for c in rigs:
		if not c.is_flying():
			continue
		var cp := _rope_pts(c.rope)
		if cp.size() < 2:
			continue
		var cbox := LineCombat._aabb(cp, 0, cp.size() - 1).grow(0.5)
		for t in rigs:
			if t == c or t.body == null:
				continue
			if t.loose:
				if not _has(c, t):
					_detect_loose(c, cp, cbox, t)
			elif t.is_flying() and t.tail != null and t.tail.pos.size() > 1:
				if grabbed_tail_of(t) == null:
					_detect_tail(c, cp, cbox, t)


func _detect_loose(c: KiteRig, cp: PackedVector3Array, cbox: AABB, t: KiteRig) -> void:
	# A própria pipa voada encostando na linha.
	var kp := t.body.x
	if cbox.has_point(kp):
		for i in cp.size() - 1:
			var ab := cp[i + 1] - cp[i]
			var u := clampf((kp - cp[i]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			if (cp[i] + ab * u).distance_to(kp) < KITE_R:
				_add(c, t, KIND_KITE, 0, c.rope.material_at(i, u), kp)
				return
	if t.rope == null or t.rope.pos.size() < 2:
		return
	var tp := _rope_pts(t.rope)
	var tbox := LineCombat._aabb(tp, 0, tp.size() - 1).grow(CATCH_R)
	if not cbox.intersects(tbox):
		return
	for i in cp.size() - 1:
		var sb := LineCombat._aabb(cp, i, i + 1).grow(CATCH_R)
		if not sb.intersects(tbox):
			continue
		for j in tp.size() - 1:
			if not sb.intersects(LineCombat._aabb(tp, j, j + 1)):
				continue
			var r := LineCombat.closest_segments(cp[i], cp[i + 1], tp[j], tp[j + 1])
			if float(r[2]) < CATCH_R:
				var node := j if float(r[1]) < 0.5 else j + 1
				node = mini(node, t.rope.pos.size() - 1)
				_add(c, t, KIND_LINE, node, c.rope.material_at(i, float(r[0])), tp[j].lerp(tp[j + 1], float(r[1])))
				return


func _detect_tail(c: KiteRig, cp: PackedVector3Array, cbox: AABB, t: KiteRig) -> void:
	var tail := t.tail
	var tp := PackedVector3Array([tail.attach_point()])
	tp.append_array(tail.pos)
	var tbox := LineCombat._aabb(tp, 0, tp.size() - 1).grow(TAIL_R)
	if not cbox.intersects(tbox):
		return
	for i in cp.size() - 1:
		var sb := LineCombat._aabb(cp, i, i + 1).grow(TAIL_R)
		if not sb.intersects(tbox):
			continue
		for j in tp.size() - 1:
			if not sb.intersects(LineCombat._aabb(tp, j, j + 1)):
				continue
			var r := LineCombat.closest_segments(cp[i], cp[i + 1], tp[j], tp[j + 1])
			if float(r[2]) >= TAIL_R:
				continue
			var where := tp[j].lerp(tp[j + 1], float(r[1]))
			# Nó da rabiola (índice em tail.pos) mais perto do encosto.
			var node := clampi(j if float(r[1]) < 0.5 else j + 1, 1, tail.pos.size()) - 1
			if c.line_type.abrasion >= CUT_ABRASION:
				_cut_tail(t, maxi(node, 1), where, c)
			else:
				_add(c, t, KIND_TAIL, node, c.rope.material_at(i, float(r[0])), where)
			return


func _cut_tail(t: KiteRig, node: int, where: Vector3, by: KiteRig) -> void:
	var tail := t.tail
	if node >= tail.pos.size():
		return
	var piece := tail.pos.slice(node)
	var pv := tail.vel.slice(node)
	tail.cut_at(node)
	cut_pieces.append([piece, pv, t])
	events.append(["cortou_rabiola", by, t, where])


func _add(c: KiteRig, t: KiteRig, kind: int, index: int, s: float, where: Vector3) -> void:
	var g := Grab.new()
	g.catcher = c
	g.target = t
	g.kind = kind
	g.index = index
	g.s = s
	g.pos = where
	grabs.append(g)
	events.append(["pegou_rabiola" if kind == KIND_TAIL else "enroscou_voada", c, t, where])


# --- Restrição (por subpasso) ----------------------------------------------------

func solve(h: float) -> void:
	if grabs.is_empty():
		return
	var alpha := 1.0 / (STIFFNESS * h * h)
	for g in grabs:
		var cr := g.catcher.rope
		var pa: Array = point_at(cr, g.s)
		var i: int = pa[0]
		if i < 0:
			continue
		var t: float = pa[1]
		var pc: Vector3 = pa[2]
		var pt := Vector3.ZERO
		var wt := 0.0
		var r_body := Vector3.ZERO
		match g.kind:
			KIND_LINE:
				pt = g.target.rope.pos[g.index]
				wt = g.target.rope.inv_mass[g.index]
			KIND_KITE:
				r_body = g.target.body.q * g.target.body.tow_local
				pt = g.target.body.x + r_body
			KIND_TAIL:
				pt = g.target.tail.pos[g.index]
				wt = g.target.tail.inv_m
		var d := pc - pt
		var dist := d.length()
		if dist < 1e-5:
			continue
		var n := d / dist
		if g.kind == KIND_KITE:
			wt = g.target.body.inverse_mass_at(r_body, n)
		var wc := LineCombat._weight(cr, i, n) * (1.0 - t) * (1.0 - t) + LineCombat._weight(cr, i + 1, n) * t * t
		var lam := dist / (wt + wc + alpha)
		g.lam_sum += lam
		match g.kind:
			KIND_LINE:
				g.target.rope.pos[g.index] += n * (lam * wt)
			KIND_KITE:
				g.target.body.apply_correction(r_body, n * lam)
			KIND_TAIL:
				g.target.tail.pos[g.index] += n * (lam * wt)
		LineCombat._push(cr, i, -n * (lam * (1.0 - t)))
		LineCombat._push(cr, i + 1, -n * (lam * t))
		g.pos = pc


# --- Fim do tick -------------------------------------------------------------------

## Devolve as pipas voadas aparadas neste tick (recolhidas até a mão).
func post_frame(dt: float, h: float, substeps: int) -> Array:
	var collected: Array = []
	var done: Array = []
	var k := 1.0 / (h * h * float(maxi(substeps, 1)))
	for gi in range(grabs.size() - 1, -1, -1):
		var g := grabs[gi]
		g.force = g.lam_sum * k
		g.lam_sum = 0.0
		var cr := g.catcher.rope
		if g.kind == KIND_TAIL:
			if g.force > TAIL_TEAR:
				g.tear_t += dt
				if g.tear_t > TAIL_TEAR_TIME:
					var tg := g.target
					var node := maxi(g.index, 1)
					var piece := tg.tail.pos.slice(node)
					var pv := tg.tail.vel.slice(node)
					tg.tail.cut_at(node)
					cut_pieces.append([piece, pv, tg])
					events.append(["arrebentou_rabiola", g.catcher, tg, g.pos])
					grabs.remove_at(gi)
			else:
				g.tear_t = maxf(g.tear_t - dt, 0.0)
		elif cr.length() - g.s < COLLECT_DIST and not done.has(g.target):
			events.append(["aparou", g.catcher, g.target, g.pos])
			collected.append([g.catcher, g.target])
			done.append(g.target)
	for tgt in done:
		clear_for(tgt)
	return collected
