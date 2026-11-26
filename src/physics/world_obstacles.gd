class_name WorldObstacles
extends RefCounted
## Obstáculos do cenário para a física da pipa e da linha (docs/REVISAO_V5.md §5).
##
## Tipos de geometria:
##   CANOPY  — volume de folhagem (poroso: só arrasto, NÃO segura a linha);
##   CAPSULE — tronco, galho, poste, cruzeta, fio (segmento com raio);
##   BOX     — casa, laje, telhado, muro.
##
## ENCOSTAR ≠ ENROSCAR. Quando um trecho da linha encosta num obstáculo, ganha um
## NÓ DE CONTATO livre que fica na superfície (restrição unilateral resolvida a cada
## subpasso) e escorrega com atrito de Coulomb:
##   - ao longo do obstáculo (barrida no fio, no beiral, em volta do poste);
##   - através do contato (a linha corre por cima; razão de tensões ≤ e^(μθ)).
## O nó só PRENDE (enrosco) quando: o ângulo de abraçamento θ passa do limite do
## material (deu volta / caiu por cima e pendurou), ou o atrito estático segurou com
## tensão alta por um tempo (apertou). Solta quando θ volta a ser pequeno, quando um
## tranco quebra o galho, ou quando a linha escorrega para fora da ponta.
## Cada material tem sua regra (MATERIALS): nada de colisão genérica.

const CELL := 8.0
const MAX_CONTACTS := 32
## Linha solta (pipa cortada, sobra caída): menos nós de contato (só precisa deitar
## no telhado / pendurar no fio).
const MAX_CONTACTS_LOOSE := 10
## Nós de contato por obstáculo: fio/galho/poste (uma volta completa) e caixa (a
## linha deitada num telhado comprido e descendo pela beirada).
const MAX_PER_OBSTACLE := 4
const MAX_PER_BOX := 12
const LINE_RADIUS := 0.0015

enum Kind { CANOPY, CAPSULE, BOX }

## μ, θ para prender (rad), tensão de aperto (N), tempo de aperto (s), tranco que
## SOLTA mín/máx (N): no galho fino o galho quebra; no tronco/poste a linha
## desenrosca com o tranco (puxões fortes, mão sobre mão, ou andar mudando o ângulo).
const MATERIALS := {
	"galho": [0.62, 1.7, 5.0, 0.4, 8.0, 20.0],
	"árvore": [0.65, 2.4, 8.0, 0.6, 12.0, 24.0],
	"coqueiro": [0.5, 2.5, 9.0, 0.7, 12.0, 24.0],
	"poste": [0.42, 2.6, 12.0, 0.8, 13.0, 24.0],
	"cruzeta": [0.5, 2.1, 10.0, 0.6, 11.0, 20.0],
	"fio": [0.15, 99.0, 99.0, 99.0, 1000.0, 1000.0],   # nunca trava: pendura e escorrega ao longo
	"trave": [0.35, 2.6, 12.0, 0.8, 12.0, 22.0],
	"telhado": [0.55, 99.0, 10.0, 0.9, 1000.0, 1000.0],
	"muro": [0.5, 99.0, 11.0, 0.9, 1000.0, 1000.0],
	"pessoa": [0.5, 99.0, 99.0, 99.0, 1000.0, 1000.0],   # encosta e escorrega, nunca prende
}

## Cada entrada:
##  CANOPY:  [kind, centro, raio]
##  CAPSULE: [kind, a, b, raio, nome]
##  BOX:     [kind, AABB, nome]
var entries: Array = []
## Caixa envolvente de cada entrada e, sob demanda, as entradas que se sobrepõem a
## ela (fio que nasce dentro do poste, galho que sai do tronco, cruzeta no poste).
var _boxes: Array[AABB] = []
var _overlaps: Dictionary = {}
## Pessoas (vizinhos): cápsulas que andam, atualizadas a cada quadro (set_people).
var _dyn: PackedInt32Array = PackedInt32Array()


## Corpo dos vizinhos (pés de cada um): a linha encosta e escorrega neles em vez de
## atravessar o personagem.
func set_people(feet: Array, owners: Array = []) -> void:
	while _dyn.size() < feet.size():
		_dyn.append(entries.size())
		entries.append([Kind.CAPSULE, Vector3(0, -1000, 0), Vector3(0, -999, 0), 0.22, "pessoa", 0])
		_boxes.append(AABB(Vector3(0, -1001, 0), Vector3.ONE))
	for k in _dyn.size():
		var idx := _dyn[k]
		var e: Array = entries[idx]
		if k < feet.size():
			var f: Vector3 = feet[k]
			# Dono: a linha e a pipa do PRÓPRIO vizinho não batem no corpo dele (a
			# pipa nasce na mão, colada nele).
			e[5] = int(owners[k]) if k < owners.size() else 0
			e[1] = f + Vector3.UP * 0.32
			e[2] = f + Vector3.UP * 1.5
			_boxes[idx] = AABB(f + Vector3(-0.24, 0.08, -0.24), Vector3(0.48, 1.66, 0.48))
		else:
			e[1] = Vector3(0, -1000, 0)
			e[2] = Vector3(0, -999, 0)
			_boxes[idx] = AABB(Vector3(0, -1001, 0), Vector3.ONE)


## Cápsula de pessoa que é o dono desta linha/pipa (ignorada para ela).
func _own_body(idx: int, owner_id: int) -> bool:
	if owner_id == 0:
		return false
	var e: Array = entries[idx]
	return e.size() > 5 and int(e[5]) == owner_id


func _dyn_near(box: AABB, out: PackedInt32Array) -> PackedInt32Array:
	if _dyn.is_empty():
		return out
	var res := out
	var copied := false
	for idx in _dyn:
		if _boxes[idx].intersects(box):
			if not copied:
				res = out.duplicate()
				copied = true
			res.append(idx)
	return res
var _grid: Dictionary = {}
## Altura do topo mais alto de cada célula: linha acima disso nem é testada.
var _cell_top: Dictionary = {}
## Nome do último enrosco (para avisos/HUD).
var last_snag: String = ""
## A pipa consultada por último em kite_contact está dentro de uma copa?
var kite_in_canopy: bool = false


func add_canopy(center: Vector3, radius: float) -> void:
	_insert([Kind.CANOPY, center, radius], center - Vector3.ONE * radius, center + Vector3.ONE * radius)


func add_capsule(a: Vector3, b: Vector3, radius: float, what: String) -> void:
	var mn := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * radius
	var mx := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * radius
	_insert([Kind.CAPSULE, a, b, radius, what], mn, mx)


## Compatibilidade: cilindro vertical (tronco, poste, trave).
func add_cylinder(base: Vector3, height: float, radius: float, what: String) -> void:
	add_capsule(base, base + Vector3.UP * height, radius, what)


func add_wire(a: Vector3, b: Vector3) -> void:
	add_capsule(a, b, 0.008, "fio")


func add_box(center: Vector3, size: Vector3, what: String = "telhado") -> void:
	var box := AABB(center - size * 0.5, size)
	_insert([Kind.BOX, box, what], box.position, box.end)


func _insert(e: Array, mn: Vector3, mx: Vector3) -> void:
	var idx := entries.size()
	entries.append(e)
	_boxes.append(AABB(mn, mx - mn))
	for gx in range(floori(mn.x / CELL), floori(mx.x / CELL) + 1):
		for gz in range(floori(mn.z / CELL), floori(mx.z / CELL) + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			var arr: PackedInt32Array = _grid[key]
			arr.append(idx)
			_grid[key] = arr
			_cell_top[key] = maxf(_cell_top.get(key, -INF), mx.y)


## Algum obstáculo da célula de p chega até a altura de p (+ folga)?
func below_top(p: Vector3, margin: float = 0.3) -> bool:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if p.y < float(_cell_top.get(key, -INF)) + margin:
		return true
	for idx in _dyn:
		if _boxes[idx].grow(margin + 1.0).has_point(p):
			return true
	return false


func query(p: Vector3) -> PackedInt32Array:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var base: PackedInt32Array = _grid.get(key, PackedInt32Array())
	return _dyn_near(AABB(p, Vector3.ZERO).grow(1.5), base) if not _dyn.is_empty() else base


## Obstáculos das células tocadas pelo trecho a–b (um trecho longo de linha pode
## atravessar a divisa de células: só o meio não basta).
func query_segment(a: Vector3, b: Vector3) -> PackedInt32Array:
	var ka := Vector2i(floori(a.x / CELL), floori(a.z / CELL))
	var kb := Vector2i(floori(b.x / CELL), floori(b.z / CELL))
	var seg_box := AABB(a, Vector3.ZERO).expand(b).grow(1.5)
	if ka == kb:
		var base: PackedInt32Array = _grid.get(ka, PackedInt32Array())
		return _dyn_near(seg_box, base) if not _dyn.is_empty() else base
	var out := PackedInt32Array()
	for gx in range(mini(ka.x, kb.x), maxi(ka.x, kb.x) + 1):
		for gz in range(mini(ka.y, kb.y), maxi(ka.y, kb.y) + 1):
			for idx in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
				if not out.has(idx):
					out.append(idx)
	return _dyn_near(seg_box, out) if not _dyn.is_empty() else out


## Altura do topo do que houver em (x, z): laje/telhado (caixas) ou o chão.
func top_at(x: float, z: float) -> float:
	var y := Ground.height_at(x, z)
	for idx in query(Vector3(x, 0, z)):
		var e: Array = entries[idx]
		if e[0] == Kind.BOX:
			var box: AABB = e[1]
			if x > box.position.x and x < box.end.x and z > box.position.z and z < box.end.z and box.size.y > 1.0:
				y = maxf(y, box.end.y)
	return y


static func material(what: String) -> Array:
	return MATERIALS.get(what, MATERIALS["telhado"])


func entry_name(idx: int) -> String:
	var e: Array = entries[idx]
	match e[0]:
		Kind.CAPSULE:
			return e[4]
		Kind.BOX:
			return e[2]
	return "árvore"


# --- Geometria ---------------------------------------------------------------

## Ponto mais próximo no eixo da cápsula: [ponto, t].
static func _axis_point(a: Vector3, b: Vector3, p: Vector3) -> Array:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return [a + ab * t, t]


## Normal (⟂ ao eixo) de p em relação à cápsula; `fallback` se p está no eixo.
static func _capsule_side(a: Vector3, b: Vector3, p: Vector3, fallback: Vector3) -> Vector3:
	var ax := (b - a).normalized()
	var q: Vector3 = _axis_point(a, b, p)[0]
	var d := p - q
	d -= ax * d.dot(ax)
	if d.length() > 1e-5:
		return d.normalized()
	var f := fallback - ax * fallback.dot(ax)
	return f.normalized() if f.length() > 1e-5 else ax.cross(Vector3.UP).normalized()


## Segmento × caixa: [t de entrada, ponto na face, normal da face] ou [].
static func _segment_box(a: Vector3, b: Vector3, box: AABB) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var normal := Vector3.ZERO
	for axis in 3:
		var o := a[axis]
		var dv := d[axis]
		var mn := box.position[axis]
		var mx := box.end[axis]
		if absf(dv) < 1e-6:
			if o < mn or o > mx:
				return []
			continue
		var ta := (mn - o) / dv
		var tb := (mx - o) / dv
		var n := Vector3.ZERO
		n[axis] = -1.0
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
			n[axis] = 1.0
		if ta > t0:
			t0 = ta
			normal = n
		t1 = minf(t1, tb)
		if t0 > t1:
			return []
	if normal == Vector3.ZERO:
		return []  # começa dentro (o nó comum resolve)
	return [t0, a + d * t0 + normal * 0.003, normal]


## Saída pela face indicada pela normal guardada (se for de face); senão a mais próxima.
static func _box_exit_side(box: AABB, p: Vector3, nrm: Vector3) -> Array:
	for axis in 3:
		if absf(nrm[axis]) > 0.9:
			var s := signf(nrm[axis])
			if axis == 1 and s < 0.0:
				break
			var out := p
			out[axis] = (box.end[axis] if s > 0.0 else box.position[axis]) + s * 0.003
			var n := Vector3.ZERO
			n[axis] = s
			return [out, n]
	return _box_exit(box, p)


## Saída de um ponto dentro da caixa pela face por onde ele entrou (vindo de `from`);
## se `from` também está dentro, a face mais perto.
static func _box_exit_from(box: AABB, p: Vector3, from: Vector3) -> Array:
	if not box.has_point(from):
		var hit := _segment_box(from, p, box)
		if not hit.is_empty():
			var n: Vector3 = hit[2]
			var out := p
			var axis := 0 if absf(n.x) > 0.5 else (1 if absf(n.y) > 0.5 else 2)
			out[axis] = (box.end[axis] if n[axis] > 0.0 else box.position[axis]) + n[axis] * 0.003
			return [out, n]
	return _box_exit(box, p)


## Face de saída mais próxima de um ponto dentro da caixa: [ponto na face, normal].
static func _box_exit(box: AABB, p: Vector3) -> Array:
	var best := INF
	var out := p
	var nrm := Vector3.UP
	for axis in 3:
		for s in [-1.0, 1.0]:
			if axis == 1 and s < 0.0:
				continue  # nunca empurra para dentro do chão
			var face := box.end[axis] if s > 0.0 else box.position[axis]
			var dist := absf(face - p[axis])
			if dist < best:
				best = dist
				out = p
				out[axis] = face + s * 0.003
				nrm = Vector3.ZERO
				nrm[axis] = s
	return [out, nrm]


# --- Linha: restrição por subpasso -------------------------------------------

func _overlaps_of(idx: int) -> PackedInt32Array:
	if _overlaps.has(idx):
		return _overlaps[idx]
	if _dyn.has(idx):
		return PackedInt32Array()   # pessoa anda: sem vizinhos fixos
	var out := PackedInt32Array()
	# Vizinhos que se sobrepõem OU estão a menos de 30 cm (laje logo acima do corpo
	# da casa, fio que nasce no poste): o nó apoiado num não pode entrar no outro.
	var box := _boxes[idx].grow(0.3)
	for gx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for gz in range(floori(box.position.z / CELL), floori(box.end.z / CELL) + 1):
			for j in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
				if j != idx and not out.has(j) and (entries[j] as Array)[0] != Kind.CANOPY and _boxes[j].intersects(box):
					out.append(j)
	_overlaps[idx] = out
	return out


## Nó de contato também não pode ficar dentro de um obstáculo vizinho que se
## sobrepõe ao seu (senão a linha "passa por dentro" do poste ao apoiar no fio), nem
## dentro de outra caixa ali perto (escorregou do corpo da casa para dentro da laje).
func _push_out_of_overlaps(idx: int, p: Vector3) -> Vector3:
	for j in _overlaps_of(idx):
		if not _boxes[j].grow(0.02).has_point(p):
			continue
		var o: Array = entries[j]
		match o[0]:
			Kind.CAPSULE:
				var r: float = float(o[3]) + LINE_RADIUS
				var q: Vector3 = _axis_point(o[1], o[2], p)[0]
				var d := p - q
				var dl := d.length()
				if dl < r:
					p = q + _capsule_side(o[1], o[2], p, Vector3.UP) * (r + 0.001)
			Kind.BOX:
				var bx: AABB = o[1]
				if bx.size.y > 0.3 and bx.has_point(p):
					p = _box_exit(bx, p)[0]
	return p


## Chamado pela Rope no fim de cada subpasso: mantém os nós de contato na
## superfície do obstáculo e aplica atrito de Coulomb ao deslizar.
func solve_contacts(rope: Rope) -> void:
	var n := rope.pos.size()
	for i in range(1, n):
		var idx := rope.pin_obstacle[i]
		if idx < 0 or rope.pinned[i] == 1 or idx >= entries.size():
			continue
		var e: Array = entries[idx]
		var p := rope.pos[i]
		var corr := Vector3.ZERO
		var nrm := rope.c_normal[i]
		var mu := 0.5
		match e[0]:
			Kind.CAPSULE:
				var a: Vector3 = e[1]
				var b: Vector3 = e[2]
				var r: float = float(e[3]) + LINE_RADIUS
				mu = material(e[4])[0]
				var q: Vector3 = _axis_point(a, b, p)[0]
				var ax := (b - a).normalized()
				var d := p - q
				d -= ax * d.dot(ax)
				# A linha apoia do lado oposto à resultante das duas pernas (bissetriz):
				# é esse o lado da superfície em que o nó fica. Só segue a bissetriz
				# enquanto ela aperta contra o obstáculo do lado guardado — assim o nó
				# não "dá a volta" por baixo e a linha não atravessa.
				var nxt := rope.pos[i + 1] if i + 1 < n else rope.end_point()
				# LADO da linha em relação ao fio/galho (invariante topológico): sinal na
				# normal comum (corda da linha × eixo). A normal do contato pode girar em
				# volta do obstáculo (a linha escorrega pela superfície), mas nunca passar
				# para o outro meio-círculo — por mais forte que se puxe.
				var chord := nxt - rope.pos[i - 1]
				var ns := chord.cross(ax)
				var has_side := ns.length() > 0.3 * chord.length()
				if has_side:
					ns = ns.normalized()
					if ns.dot(nrm) < 0.0:
						ns = -ns
				var bis := (rope.pos[i - 1] - p).normalized() + (nxt - p).normalized()
				bis -= ax * bis.dot(ax)
				var pressing := false
				if bis.length() > 0.05:
					var nt := -bis.normalized()
					if nt.dot(nrm) > 0.0:
						nrm = nt
						pressing = true
				if has_side and nrm.dot(ns) < 0.2:
					nrm = (nrm - ns * (nrm.dot(ns) - 0.2)).normalized()
				var side := d.dot(nrm)
				if pressing and side < r:
					corr = nrm * r - d          # apoiada: fica na superfície, do lado da linha
				elif side < r:
					corr = nrm * (r - side)     # dentro / do outro lado: volta para o lado guardado
			Kind.BOX:
				var box: AABB = e[1]
				mu = material(e[2])[0]
				if box.has_point(p):
					# Sai pela face do lado em que a linha já estava (muro fino: puxar
					# forte não faz a linha sair pelo outro lado).
					var ex := _box_exit_side(box, p, nrm)
					corr = (ex[0] as Vector3) - p
					nrm = ex[1]
		if corr == Vector3.ZERO:
			rope.c_normal[i] = nrm
			var po := _push_out_of_overlaps(idx, p)
			if po != p:
				rope.pos[i] = po
			continue
		p += corr
		# Atrito de Coulomb posicional: o deslocamento tangencial do subpasso é
		# limitado por μ × (correção normal). Parado → atrito estático segura.
		var dn := corr.length()
		var disp := p - rope.prev[i]
		var tang := disp - nrm * disp.dot(nrm)
		var tl := tang.length()
		if tl > 1e-7:
			if tl <= mu * dn * 1.25:
				p -= tang
			else:
				p -= tang * (mu * dn / tl)
		rope.pos[i] = _push_out_of_overlaps(idx, p)
		rope.c_normal[i] = nrm


# --- Linha: por quadro ---------------------------------------------------------

## Detecta contatos novos, decide enrosco/soltura e o deslizamento através dos
## contatos. Retorna o nome do que ENROSCOU agora ("" se nada).
func update_rope(rope: Rope, dt: float) -> String:
	rope.obstacles = self
	_foliage_drag(rope, dt)
	var snag := _update_contacts(rope, dt)
	_absorb_nodes(rope)
	if rope.contact_count() < (MAX_CONTACTS if rope.hand_fixed else MAX_CONTACTS_LOOSE):
		_detect(rope)
	return snag


## Folhagem: arrasto poroso nos nós dentro da copa (a linha atravessa devagar).
func _foliage_drag(rope: Rope, dt: float) -> void:
	var start := 1 if rope.hand_fixed else 0
	for i in range(start, rope.pos.size()):
		if rope.inv_mass[i] <= 0.0:
			continue
		var p := rope.pos[i]
		if not below_top(p):
			continue
		for idx in query(p):
			if not _boxes[idx].has_point(p):
				continue
			var e: Array = entries[idx]
			if e[0] == Kind.CANOPY and p.distance_to(e[1]) < float(e[2]):
				var k := exp(-3.5 * dt)
				var v := rope.vel[i] * k
				rope.prev[i] = p - v * dt
				rope.vel[i] = v
				break


## Nós comuns que entraram num obstáculo viram nós de contato (com atrito).
func _absorb_nodes(rope: Rope) -> void:
	var start := 1 if rope.hand_fixed else 0
	for i in range(start, rope.pos.size()):
		if rope.pin_obstacle[i] >= 0:
			continue
		var p := rope.pos[i]
		if not below_top(p):
			continue
		for idx in query(p):
			if not _boxes[idx].has_point(p) or _own_body(idx, rope.owner_id):
				continue
			# Nó DENTRO de casa/muro sempre vira contato (sem limite: linha dentro da
			# caixa é pior do que um nó a mais); no fio/galho respeita o limite.
			var e0: Array = entries[idx]
			var inside_box: bool = e0[0] == Kind.BOX and (e0[1] as AABB).has_point(p)
			if not inside_box and (rope.contact_count() >= MAX_CONTACTS or _contacts_on(rope, idx) >= _limit_for(idx)):
				continue
			var e: Array = entries[idx]
			match e[0]:
				Kind.CAPSULE:
					var q: Vector3 = _axis_point(e[1], e[2], p)[0]
					if p.distance_to(q) < float(e[3]) + LINE_RADIUS:
						var sn := _capsule_side(e[1], e[2], p, rope.vel[i] * -1.0)
						rope.set_contact(i, idx, sn)
						rope.pos[i] = q + sn * (float(e[3]) + LINE_RADIUS + 0.001)   # já na superfície
				Kind.BOX:
					var box: AABB = e[1]
					if box.has_point(p):
						# Sai pelo lado de onde o nó veio (posição do começo do quadro), não
						# pela face mais perto (que podia ser a de baixo do telhado).
						var ex := _box_exit_from(box, p, rope.frame_pos[i] if rope.frame_pos.size() == rope.pos.size() else p)
						rope.set_contact(i, idx, ex[1] as Vector3)
						rope.pos[i] = ex[0]
			if rope.pin_obstacle[i] >= 0:
				break


## Segmentos que cruzam um obstáculo ganham um nó de contato no ponto de toque.
## Teste contínuo: compara com as posições do começo do quadro (mesmo material),
## para a linha não atravessar um fio de 1 cm entre dois quadros.
## Um trecho pode cruzar VÁRIOS obstáculos no mesmo quadro (3 fios lado a lado):
## cada um ganha o seu nó. Trecho que já encosta num obstáculo por uma ponta também
## é testado (a linha que dá a volta no fio, ou desce do telhado cortando o canto).
func _detect(rope: Rope) -> void:
	var n := rope.pos.size()
	var seg_n := rope.segment_count()
	var has_prev := rope.frame_pos.size() == n
	var hits: Array = []   # [i, t, ponto, idx, normal]
	for i in seg_n:
		var a := rope.pos[i]
		var b := rope.pos[i + 1] if i + 1 < n else rope.end_point()
		var mid := (a + b) * 0.5
		var low := Vector3(mid.x, minf(a.y, b.y), mid.z)
		if not (below_top(low, 1.6) or below_top(Vector3(a.x, low.y, a.z), 1.6) or below_top(Vector3(b.x, low.y, b.z), 1.6)):
			continue
		var ids := query_segment(a, b)
		if ids.is_empty():
			continue
		var a0 := a
		var b0 := b
		if has_prev:
			a0 = rope.frame_pos[i]
			b0 = rope.frame_pos[i + 1] if i + 1 < n else rope.frame_end
		var seg_len := maxf(a.distance_to(b), 0.001)
		# Caixa envolvente do trecho (agora e no começo do quadro): filtro barato antes
		# dos testes de verdade.
		var smin := Vector3(minf(minf(a.x, b.x), minf(a0.x, b0.x)), minf(minf(a.y, b.y), minf(a0.y, b0.y)), minf(minf(a.z, b.z), minf(a0.z, b0.z)))
		var smax := Vector3(maxf(maxf(a.x, b.x), maxf(a0.x, b0.x)), maxf(maxf(a.y, b.y), maxf(a0.y, b0.y)), maxf(maxf(a.z, b.z), maxf(a0.z, b0.z)))
		var seg_box := AABB(smin, smax - smin).grow(0.05)
		for idx in ids:
			if not _boxes[idx].intersects(seg_box) or _own_body(idx, rope.owner_id):
				continue
			# Ponta do trecho que já é nó de contato neste obstáculo (−1 = nenhuma).
			var start_on := i > 0 and rope.pin_obstacle[i] == idx
			var end_on := i + 1 < n and rope.pin_obstacle[i + 1] == idx
			var e: Array = entries[idx]
			var hit: Array = []
			match e[0]:
				Kind.CAPSULE:
					var ca: Vector3 = e[1]
					var cb: Vector3 = e[2]
					var r: float = float(e[3]) + LINE_RADIUS
					if start_on and end_on:
						# Dois nós no mesmo fio/galho: se ficaram em lados muito diferentes
						# (a linha deu a volta), o trecho reto entre eles cortaria o fio —
						# ganha um nó no meio, na superfície.
						var n1: Vector3 = rope.c_normal[i]
						var n2: Vector3 = rope.c_normal[i + 1]
						if n1.dot(n2) < 0.0 and _contacts_on(rope, idx) < MAX_PER_OBSTACLE:
							var mpt := (a + b) * 0.5
							var q: Vector3 = _axis_point(ca, cb, mpt)[0]
							var nm := n1 + n2
							var axn := (cb - ca).normalized()
							nm -= axn * nm.dot(axn)
							if nm.length() < 1e-3:
								nm = _capsule_side(ca, cb, mpt, n1)
							nm = nm.normalized()
							hit = [0.5, q + nm * (r + 0.001), nm]
					else:
						var res := LineCombat.closest_segments(a, b, ca, cb)
						var t: float = res[0]
						# Perto do nó que já está neste obstáculo: é o próprio contato.
						var near_node := (start_on and t * seg_len < 0.12) or (end_on and (1.0 - t) * seg_len < 0.12)
						var sp := a.lerp(b, t)
						var ap := ca.lerp(cb, res[1])
						# Lado da linha em relação ao obstáculo medido na NORMAL COMUM (⟂ às
						# duas direções): é o sinal dela que troca quando uma atravessa a outra.
						var nc := (b - a).cross(cb - ca)
						if nc.length() < 1e-6:
							nc = _capsule_side(ca, cb, sp, Vector3.UP)
						nc = nc.normalized()
						var s_now := (sp - ap).dot(nc)
						var s_old := s_now
						if has_prev:
							s_old = (a0.lerp(b0, t) - ap).dot(nc)
						var from_side := nc * (1.0 if s_old >= 0.0 else -1.0)
						if float(res[2]) < r and not near_node:
							hit = [t, ap + from_side * (r + 0.001), from_side]
						elif has_prev and float(res[2]) < 4.0 and s_old * s_now < 0.0:
							# Atravessou entre quadros (puxada forte): o cruzamento das RETAS tem
							# que cair dentro dos dois trechos (com folga nas pontas).
							var lp := LineCombat._line_params(a, b - a, ca, cb - ca)
							var tt := clampf(lp.x, 0.0, 1.0)
							var far_node := not ((start_on and tt * seg_len < 0.12) or (end_on and (1.0 - tt) * seg_len < 0.12))
							if far_node and lp.x > -0.05 and lp.x < 1.05 and lp.y > -0.02 and lp.y < 1.02:
								var apx := ca.lerp(cb, clampf(lp.y, 0.0, 1.0))
								hit = [tt, apx + from_side * (r + 0.001), from_side]
				Kind.BOX:
					var box: AABB = e[1]
					if box.size.y > 0.3:
						# Testa contra a caixa um pouco MENOR: as pontas apoiadas na superfície
						# (nó de contato nesta ou numa caixa vizinha) não contam; cortar o canto
						# por dentro ou atravessar a caixa conta.
						var bh := _seg_box_inside(a, b, box)
						if not bh.is_empty():
							hit = bh
						elif has_prev and not (start_on or end_on):
							# Passou inteira por um muro/telhado entre dois quadros: o meio do
							# trecho "varreu" a caixa → contato na face por onde entrou.
							var sw := _segment_box((a0 + b0) * 0.5, (a + b) * 0.5, box.grow(0.01))
							if not sw.is_empty():
								hit = [0.5, sw[1], sw[2]]
			if hit.is_empty():
				continue
			if _contacts_on(rope, idx) >= _limit_for(idx):
				continue
			hits.append([i, float(hit[0]), hit[1], idx, hit[2]])
	# Insere do fim para o começo (os índices anteriores não mudam). No mesmo trecho,
	# do maior t para o menor (o trecho vai encurtando a cada nó inserido).
	hits.sort_custom(func(x, y) -> bool: return x[0] > y[0] or (x[0] == y[0] and x[1] > y[1]))
	var last_i := -1
	var last_t := 1.0
	for h in hits:
		if rope.contact_count() >= MAX_CONTACTS:
			break
		var i: int = h[0]
		# Fração para dividir o comprimento de repouso (o nó vai para o ponto de toque;
		# perto das pontas só não deixa um trecho minúsculo).
		var t: float = clampf(h[1], 0.06, 0.94)
		if i != last_i:
			last_i = i
			last_t = 1.0
		if t >= last_t - 0.03:
			continue   # dois toques quase no mesmo ponto do trecho
		var frac := t / last_t
		var l := rope.rest[i]
		rope.insert_node(i + 1, h[2], rope.velocity_at(i, frac), l * frac, l * (1.0 - frac))
		rope.set_contact(i + 1, h[3], h[4])
		last_t = t


## Trecho a–b entra na caixa (encolhida um pouco)? [t em a→b, ponto, normal].
## O nó novo vai para a QUINA por onde a linha deveria dobrar (entre a face de
## entrada e a de saída) — assim a linha apoiada na parede passa a dobrar na beirada
## do telhado/muro em vez de cortar o canto por dentro.
static func _seg_box_inside(a: Vector3, b: Vector3, box: AABB) -> Array:
	var shrink := minf(0.025, minf(box.size.x, minf(box.size.y, box.size.z)) * 0.2)
	var inner := box.grow(-shrink)
	var e1 := _segment_box(a, b, inner)
	var e2 := _segment_box(b, a, inner)
	if e1.is_empty() and e2.is_empty():
		return []
	if e1.is_empty() or e2.is_empty():
		# Uma ponta já está dentro: nó na face por onde a outra entra.
		var ee: Array = e1 if not e1.is_empty() else e2
		var nn: Vector3 = ee[2]
		var tt: float = ee[0] if not e1.is_empty() else 1.0 - float(ee[0])
		if tt <= 0.002 or tt >= 0.998:
			return []
		return [tt, (ee[1] as Vector3) + nn * shrink, nn]
	var t_in: float = e1[0]
	var t_out: float = 1.0 - float(e2[0])
	if t_out - t_in < 0.002:
		return []
	var n_in: Vector3 = e1[2]
	var n_out: Vector3 = e2[2]
	var tm := (t_in + t_out) * 0.5
	var d := a.lerp(b, tm)
	var ax_in := _axis_of(n_in)
	var ax_out := _axis_of(n_out)
	if ax_in != ax_out:
		var p := d
		p[ax_in] = box.end[ax_in] if n_in[ax_in] > 0.0 else box.position[ax_in]
		p[ax_out] = box.end[ax_out] if n_out[ax_out] > 0.0 else box.position[ax_out]
		var n := (n_in + n_out).normalized()
		return [tm, p + n * 0.004, n]
	# Entra e sai por faces opostas (atravessou um muro inteiro): passa por cima /
	# pela lateral mais perto.
	var best := INF
	var out := d
	var nrm := Vector3.UP
	for axis in 3:
		if axis == ax_in:
			continue
		for sg in [-1.0, 1.0]:
			if axis == 1 and sg < 0.0:
				continue
			var face: float = box.end[axis] if sg > 0.0 else box.position[axis]
			var dist := absf(face - d[axis])
			if dist < best:
				best = dist
				out = d
				out[axis] = face + sg * 0.004
				nrm = Vector3.ZERO
				nrm[axis] = sg
	return [tm, out, nrm]


static func _axis_of(n: Vector3) -> int:
	if absf(n.x) >= absf(n.y) and absf(n.x) >= absf(n.z):
		return 0
	return 1 if absf(n.y) >= absf(n.z) else 2


func _limit_for(idx: int) -> int:
	return MAX_PER_BOX if (entries[idx] as Array)[0] == Kind.BOX else MAX_PER_OBSTACLE


func _contacts_on(rope: Rope, idx: int) -> int:
	var c := 0
	for v in rope.pin_obstacle:
		if v == idx:
			c += 1
	return c


func _deviation(rope: Rope, i: int) -> float:
	var n := rope.pos.size()
	var p := rope.pos[i]
	var prev_p := rope.pos[i - 1]
	var next_p := rope.pos[i + 1] if i + 1 < n else rope.end_point()
	var u1 := (prev_p - p).normalized()
	var u2 := (next_p - p).normalized()
	return PI - acos(clampf(u1.dot(u2), -1.0, 1.0))


## Nome do que a linha DESENROSCOU no último quadro ("" se nada) — aviso no HUD.
var last_freed: String = ""


func _update_contacts(rope: Rope, dt: float) -> String:
	var snagged_now := ""
	var freed_now := ""
	var i := rope.pos.size() - 1
	while i >= 1:
		var idx := rope.pin_obstacle[i]
		if idx < 0 or idx >= entries.size():
			i -= 1
			continue
		var n := rope.pos.size()
		var has_next := i + 1 < n or rope.end_body != null
		if not has_next:
			rope.clear_contact(i)
			i -= 1
			continue
		var e: Array = entries[idx]
		var what := entry_name(idx)
		var mat := material(what)
		var dev := _deviation(rope, i)
		var t_hand: float = rope.seg_tension[i - 1] if i - 1 < rope.seg_tension.size() else 0.0
		var t_kite: float = rope.seg_tension[i] if i < rope.seg_tension.size() else 0.0
		var t_max := maxf(t_hand, t_kite)
		var p := rope.pos[i]
		var off_surface := _surface_gap(e, p)
		var slipped_off := false
		if e[0] == Kind.CAPSULE:
			var tt: float = _axis_point(e[1], e[2], p)[1]
			if tt <= 0.0 or tt >= 1.0:
				# Escorregou até a ponta deste trecho: se o fio/galho continua (trecho
				# seguinte da catenária, galho que sai do tronco), passa o contato para ele.
				var nb := _capsule_neighbor(idx, tt >= 1.0)
				if nb >= 0:
					rope.pin_obstacle[i] = nb
					idx = nb
					e = entries[idx]
					off_surface = _surface_gap(e, p)
				else:
					slipped_off = off_surface > 0.01
		if rope.pinned[i] == 1:
			# ENROSCADO: solta quando endireita, com um tranco forte (quebra o galho /
			# desenrosca do tronco) ou dando linha: frouxa, sem dar volta, ela cai fora.
			if t_max < 0.6 and dev < 1.4:
				rope.c_hold[i] += dt
			else:
				rope.c_hold[i] = maxf(rope.c_hold[i] - dt, 0.0)
			if dev < 0.05 or slipped_off:
				rope.unpin_node(i)
			elif t_max > rope.pin_break[i]:
				rope.unpin_node(i)
				rope.c_hold[i] = -2.0   # soltou no tranco: não prende de novo logo
				freed_now = what
			elif rope.c_hold[i] > 0.35:
				rope.unpin_node(i)
				rope.c_hold[i] = -1.5   # caiu fora com a linha frouxa
				freed_now = what
			else:
				_capstan(rope, i, dev, t_hand, t_kite, rope.pin_mu[i], dt)
				i -= 1
				continue
		# CONTATO DESLIZANTE. Linha reta deitada no meio de um telhado/laje não precisa
		# de nó de contato (só apoia): solta para não esgotar o limite da caixa.
		var flat_on_top: bool = e[0] == Kind.BOX and dev < 0.03 and rope.c_normal[i].y > 0.9
		if flat_on_top and i < rope.rest.size() and rope.rest[i - 1] + rope.rest[i] < rope.segment_target * 1.6:
			# Nó a mais no meio do telhado com a linha reta: some (os vizinhos apoiam).
			rope.clear_contact(i)
			rope.remove_node(i)
			i -= 1
			continue
		if (dev < 0.04 and off_surface > 0.01) or slipped_off or off_surface > 0.35 or flat_on_top:
			rope.clear_contact(i)
			# Nó criado só para o contato (trecho curto) volta a ser um segmento só.
			if i < rope.rest.size() and minf(rope.rest[i - 1], rope.rest[i]) < rope.segment_target * 0.7:
				rope.remove_node(i)
			i -= 1
			continue
		# Regras de enrosco do material.
		var speed := rope.vel[i].length()
		var hold := rope.c_hold[i]
		if hold < 0.0:
			hold = minf(hold + dt, 0.0)
		elif dev > 0.5 and t_max > float(mat[2]) and speed < 0.08:
			hold += dt
		else:
			hold = maxf(hold - dt * 2.0, 0.0)
		rope.c_hold[i] = hold
		if hold >= 0.0 and (dev > float(mat[1]) or hold > float(mat[3])):
			rope.pin_node(i, p, float(mat[0]), randf_range(float(mat[4]), float(mat[5])), idx)
			snagged_now = what
			last_snag = what
		else:
			# A linha corre por cima do obstáculo (atrito cinético, cabrestante).
			_capstan(rope, i, dev, t_hand, t_kite, float(mat[0]), dt)
		i -= 1
	return snagged_now


## Trecho de cápsula que continua a cápsula idx pela ponta b (forward) ou a; −1 se não há.
func _capsule_neighbor(idx: int, forward: bool) -> int:
	var e: Array = entries[idx]
	var tip: Vector3 = e[2] if forward else e[1]
	for j in [idx + 1, idx - 1]:
		if j < 0 or j >= entries.size():
			continue
		var o: Array = entries[j]
		if o[0] != Kind.CAPSULE:
			continue
		if (o[1] as Vector3).distance_to(tip) < 0.02 or (o[2] as Vector3).distance_to(tip) < 0.02:
			return j
	return -1


## Distância do nó até a superfície (>0 = afastado).
func _surface_gap(e: Array, p: Vector3) -> float:
	match e[0]:
		Kind.CAPSULE:
			var q: Vector3 = _axis_point(e[1], e[2], p)[0]
			return p.distance_to(q) - float(e[3]) - LINE_RADIUS
		Kind.BOX:
			var box: AABB = e[1]
			var c := p.clamp(box.position, box.end)
			return p.distance_to(c)
	return 1.0


## Cabrestante: o material da linha só passa pelo contato se um lado vencer o
## outro × e^(μθ). Transfere comprimento de repouso entre os dois trechos.
func _capstan(rope: Rope, i: int, dev: float, t_hand: float, t_kite: float, mu: float, dt: float) -> void:
	if i >= rope.rest.size():
		return
	var ratio := exp(mu * dev)
	var move := 0.0
	if t_kite > t_hand * ratio + 0.05:
		move = minf((t_kite - t_hand * ratio) * 0.8, 6.0) * dt          # pipa puxa linha
	elif t_hand > t_kite * ratio + 0.05:
		move = -minf((t_hand - t_kite * ratio) * 0.8, 6.0) * dt         # mão puxa linha
	if move != 0.0:
		move = clampf(move, -(rope.rest[i] - 0.05), rope.rest[i - 1] - 0.05)
		rope.rest[i - 1] -= move
		rope.rest[i] += move
	# O trecho vizinho acabou: o próximo nó comum chega ao contato e a sobra
	# continua passando (a linha inteira corre por cima, não só um segmento).
	if rope.rest[i - 1] < 0.12 and i - 1 > 0 and rope.pin_obstacle[i - 1] < 0 and rope.pinned[i - 1] == 0:
		rope.remove_node(i - 1)
	elif i < rope.rest.size() and rope.rest[i] < 0.12 and i + 1 < rope.pos.size() and rope.pin_obstacle[i + 1] < 0 and rope.pinned[i + 1] == 0:
		rope.remove_node(i + 1)


# --- Pipa e rabiola -------------------------------------------------------------

## Contato da PIPA com o cenário. Empurra para fora de galhos/postes/fios (quica e
## escorrega) e retorna [nome, ponto] só quando ela PRENDE de verdade:
##  - o fio/galho passou entre o cabresto e a vela (o cabresto enganchou);
##  - entrou fundo na copa, devagar (presa na folhagem).
func kite_contact(body: KiteRigidBody, knot: Vector3, anchors: PackedVector3Array, dt: float, owner_id: int = 0) -> Array:
	kite_in_canopy = false
	var x := body.x
	var rad := body.profile.height * 0.45
	for idx in query(x):
		if _own_body(idx, owner_id):
			continue
		var e: Array = entries[idx]
		match e[0]:
			Kind.CANOPY:
				var c: Vector3 = e[1]
				var r: float = e[2]
				var depth := r - x.distance_to(c)
				if depth > 0.0:
					kite_in_canopy = true
					# Folhagem freia a pipa; fundo e devagar = presa.
					body.v *= exp(-4.0 * dt)
					body.w *= exp(-3.0 * dt)
					if depth > r * 0.35 and body.airspeed < 2.5:
						return ["árvore", x]
			Kind.CAPSULE:
				var a: Vector3 = e[1]
				var b: Vector3 = e[2]
				var cr: float = e[3]
				# Cabresto enganchado: o eixo cruza os triângulos do cabresto.
				for k in anchors.size():
					var a1 := anchors[k]
					var a2 := anchors[(k + 1) % anchors.size()]
					if _segment_triangle(a, b, knot, a1, a2):
						return [e[4], x]
				var q: Vector3 = _axis_point(a, b, x)[0]
				var d := x - q
				var dist := d.length()
				if dist < cr + rad * 0.5 and dist > 1e-5:
					var nrm := d / dist
					body.x = q + nrm * (cr + rad * 0.5)
					var vn := body.v.dot(nrm)
					if vn < 0.0:
						body.v -= nrm * vn * 1.4   # quica
					body.v *= 0.85
	return []


## Movimento CONTÍNUO da pipa guiada pelo modelo de voo, de p até np (subpasso),
## como uma esfera de raio `rad`: não atravessa poste, fio, galho, tronco nem casa —
## para no ponto de toque e escorrega pela superfície com o que sobrar do movimento.
## Retorna [ponto final, normal do toque (ZERO = livre), nome do obstáculo].
func kite_sweep(p: Vector3, np: Vector3, rad: float) -> Array:
	var out := np
	var nrm := Vector3.ZERO
	var what := ""
	if not (below_top(p, rad + 0.5) or below_top(np, rad + 0.5)):
		return [out, nrm, what]
	var ids := query_segment(p, np)
	for _pass in 2:
		var hit_any := false
		for idx in ids:
			var e: Array = entries[idx]
			match e[0]:
				Kind.CAPSULE:
					var ca: Vector3 = e[1]
					var cb: Vector3 = e[2]
					var rr: float = float(e[3]) + rad
					var res := LineCombat.closest_segments(p, out, ca, cb)
					if float(res[2]) >= rr:
						continue
					# Ponto de entrada: busca binária no trecho p→out.
					var lo := 0.0
					var hi: float = res[0]
					if _dist_axis(ca, cb, p) < rr:
						hi = 0.0
					for _k in 6:
						var mid := (lo + hi) * 0.5
						if _dist_axis(ca, cb, p.lerp(out, mid)) < rr:
							hi = mid
						else:
							lo = mid
					var entry := p.lerp(out, lo)
					var q: Vector3 = _axis_point(ca, cb, entry)[0]
					var n := _capsule_side(ca, cb, entry, (p - out).normalized())
					# Escorrega: tira do resto do movimento a parte que entra na superfície.
					var rest := out - entry
					var into := rest.dot(n)
					if into < 0.0:
						rest -= n * into
					var cand := entry + rest
					var qd: Vector3 = _axis_point(ca, cb, cand)[0]
					var dc := cand - qd
					if dc.length() < rr:
						cand = qd + _capsule_side(ca, cb, cand, n) * (rr + 0.002)
					out = cand
					nrm = n
					what = e[4]
					hit_any = true
				Kind.BOX:
					var box: AABB = e[1]
					if box.size.y < 0.3:
						continue
					var gb := box.grow(rad)
					if not gb.has_point(out):
						continue
					var bh := _segment_box(p, out, gb)
					var n2: Vector3
					if bh.is_empty():
						var ex := _box_exit(gb, out)
						out = ex[0]
						n2 = ex[1]
					else:
						n2 = bh[2]
						var axis := 0 if absf(n2.x) > 0.5 else (1 if absf(n2.y) > 0.5 else 2)
						var face := gb.end[axis] if n2[axis] > 0.0 else gb.position[axis]
						out[axis] = face + n2[axis] * 0.004
					nrm = n2
					what = e[2]
					hit_any = true
		if not hit_any:
			break
	return [out, nrm, what]


## Empurra a pipa (esfera de raio `rad`) para fora de poste, fio, galho e casa —
## depois das restrições da linha (a linha apoiada no telhado não a puxa para dentro).
## Caixas encostadas (corpo da casa + laje, muro + casa): sai para o ponto mais perto
## que não esteja dentro de NENHUMA delas (senão sair de uma jogava dentro da outra).
func kite_push_out(p: Vector3, rad: float) -> Vector3:
	if not below_top(p, rad + 0.3):
		return p
	var ids := query(p)
	for idx in ids:
		var e: Array = entries[idx]
		if e[0] != Kind.CAPSULE or not _boxes[idx].grow(rad).has_point(p):
			continue
		var rr: float = float(e[3]) + rad
		var q: Vector3 = _axis_point(e[1], e[2], p)[0]
		if p.distance_to(q) < rr:
			p = q + _capsule_side(e[1], e[2], p, Vector3.UP) * (rr + 0.002)
	var inside: Array[AABB] = []
	for idx in ids:
		var e2: Array = entries[idx]
		if e2[0] == Kind.BOX:
			var box: AABB = e2[1]
			if box.size.y >= 0.3 and box.grow(rad).has_point(p):
				inside.append(box.grow(rad))
	if inside.is_empty():
		return p
	var best := p + Vector3.UP * 50.0
	var best_d := INF
	for gb in inside:
		for axis in 3:
			for sg in [-1.0, 1.0]:
				if axis == 1 and sg < 0.0:
					continue
				var c := p
				c[axis] = (gb.end[axis] if sg > 0.0 else gb.position[axis]) + sg * 0.004
				var d := c.distance_squared_to(p)
				if d >= best_d:
					continue
				var free := true
				for other in inside:
					if other.has_point(c):
						free = false
						break
				if free:
					best = c
					best_d = d
	if best_d == INF:
		# Cercada: sobe acima da caixa mais alta.
		var top := p.y
		for gb2 in inside:
			top = maxf(top, gb2.end.y + 0.004)
		best = Vector3(p.x, top, p.z)
	return best


static func _dist_axis(a: Vector3, b: Vector3, p: Vector3) -> float:
	return p.distance_to(_axis_point(a, b, p)[0])


## Segmento × triângulo (Möller–Trumbore).
static func _segment_triangle(p0: Vector3, p1: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var d := p1 - p0
	var e1 := b - a
	var e2 := c - a
	var h := d.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-9:
		return false
	var f := 1.0 / det
	var s := p0 - a
	var u := f * s.dot(h)
	if u < 0.0 or u > 1.0:
		return false
	var qv := s.cross(e1)
	var v := f * d.dot(qv)
	if v < 0.0 or u + v > 1.0:
		return false
	var t := f * e2.dot(qv)
	return t >= 0.0 and t <= 1.0


## A rabiola (plástico mole) engancha quando enrola num galho ou fio.
func tail_hit(p: Vector3) -> bool:
	for idx in query(p):
		var e: Array = entries[idx]
		match e[0]:
			Kind.CAPSULE:
				var q: Vector3 = _axis_point(e[1], e[2], p)[0]
				if String(e[4]) in ["fio", "galho", "cruzeta"] and p.distance_to(q) < float(e[3]) + 0.04:
					return true
			Kind.CANOPY:
				if p.distance_to(e[1]) < float(e[2]) * 0.55:
					return true
	return false
