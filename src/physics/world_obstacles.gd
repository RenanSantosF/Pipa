class_name WorldObstacles
extends RefCounted
## Obstáculos do cenário para a física da pipa e da linha (mais leve que o motor
## de física do Godot para dezenas de nós por quadro): copas de árvore (esferas
## porosas), troncos e postes (cilindros), casas e muros (caixas) e fios (segmentos).
## Indexados numa grade 2D (XZ) para consultas rápidas.

const CELL := 8.0

enum Kind { CANOPY, CYLINDER, BOX, WIRE }

## Cada entrada: [Kind, dados...]
##  CANOPY:   [kind, centro, raio]
##  CYLINDER: [kind, base(x, y0, z), y1, raio, nome]
##  BOX:      [kind, AABB]
##  WIRE:     [kind, a, b]
var entries: Array = []
var _grid: Dictionary = {}


func add_canopy(center: Vector3, radius: float) -> void:
	_insert([Kind.CANOPY, center, radius], center - Vector3.ONE * radius, center + Vector3.ONE * radius)


func add_cylinder(base: Vector3, height: float, radius: float, what: String) -> void:
	_insert([Kind.CYLINDER, base, base.y + height, radius, what], base - Vector3(radius, 0, radius), base + Vector3(radius, height, radius))


func add_box(center: Vector3, size: Vector3) -> void:
	var box := AABB(center - size * 0.5, size)
	_insert([Kind.BOX, box], box.position, box.end)


func add_wire(a: Vector3, b: Vector3) -> void:
	var mn := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var mx := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	_insert([Kind.WIRE, a, b], mn, mx)


func _insert(e: Array, mn: Vector3, mx: Vector3) -> void:
	var idx := entries.size()
	entries.append(e)
	for gx in range(floori(mn.x / CELL), floori(mx.x / CELL) + 1):
		for gz in range(floori(mn.z / CELL), floori(mx.z / CELL) + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			var arr: PackedInt32Array = _grid[key]
			arr.append(idx)
			_grid[key] = arr


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


func query(p: Vector3) -> PackedInt32Array:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	return _grid.get(key, PackedInt32Array())


## Colide os nós da linha com o cenário (por quadro, depois dos subpassos).
## Retorna o nome do que prendeu a linha ("" se nada).
func collide_rope(rope: Rope) -> String:
	var caught := ""
	var n := rope.pos.size()
	var start := 1 if rope.hand_fixed else 0
	for i in range(start, n):
		var p := rope.pos[i]
		var v := rope.vel[i]
		var touched := false
		for idx in query(p):
			var e: Array = entries[idx]
			match e[0]:
				Kind.CANOPY:
					var c: Vector3 = e[1]
					var r: float = e[2]
					var d := p - c
					if d.length() < r:
						# Folhagem porosa: a linha entra e fica presa nos galhos.
						v *= 0.12
						p += d.normalized() * (r - d.length()) * 0.15
						touched = true
						caught = "árvore"
				Kind.CYLINDER:
					var base: Vector3 = e[1]
					var y1: float = e[2]
					var rr: float = e[3] + 0.01
					if p.y > base.y and p.y < y1:
						var h := Vector2(p.x - base.x, p.z - base.z)
						if h.length() < rr:
							var out := h.normalized() * rr if h.length() > 0.0001 else Vector2(rr, 0)
							p = Vector3(base.x + out.x, p.y, base.z + out.y)
							v *= 0.4
							touched = true
							caught = e[4]
				Kind.BOX:
					var box: AABB = e[1]
					if box.has_point(p):
						p = _push_out_of_box(box, p)
						v *= 0.35
						touched = true
						if caught == "":
							caught = "telhado"
		if touched:
			rope.pos[i] = p
			rope.vel[i] = v
	return caught


const MAX_PINS := 6

## Enroscar de verdade: um trecho da linha que cruza copa/poste/fio ganha um nó
## preso naquele ponto (a linha desvia: 3 pontos). O nó desliza com atrito de
## cabrestante (razão de tensões e^(μθ)) e solta quando a linha se endireita ou
## quando um tranco quebra o galho. Retorna o nome do que prendeu agora ("" se nada).
func wrap_rope(rope: Rope, dt: float) -> String:
	_update_pins(rope, dt)
	if rope.pin_count() >= MAX_PINS:
		return ""
	var n := rope.pos.size()
	var seg_n := rope.segment_count()
	for i in seg_n:
		var a := rope.pos[i]
		var b := rope.pos[i + 1] if i + 1 < n else rope.end_point()
		var mid := (a + b) * 0.5
		for idx in query(mid):
			if rope.pin_obstacle.has(idx):
				continue  # um nó por obstáculo
			var hit := _segment_hit(a, b, idx)
			if hit.is_empty():
				continue
			var t: float = hit[0]
			# Não prende colado na mão nem no cabresto.
			if (i == 0 and rope.hand_fixed and t < 0.25) or (i == seg_n - 1 and t > 0.85):
				continue
			var l := rope.rest[i]
			rope.insert_node(i + 1, hit[1], rope.vel[i], l * t, l * (1.0 - t))
			rope.pin_node(i + 1, hit[1], hit[2], hit[3], idx)
			return hit[4]
	return ""


## [t, ponto, μ, força_de_quebra, nome] ou [].
func _segment_hit(a: Vector3, b: Vector3, idx: int) -> Array:
	var e: Array = entries[idx]
	match e[0]:
		Kind.CANOPY:
			var c: Vector3 = e[1]
			var r: float = e[2]
			var ab := b - a
			var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var q := a + ab * t
			if q.distance_to(c) < r * 0.7:
				return [t, q, 0.9, randf_range(9.0, 26.0), "árvore"]
		Kind.CYLINDER:
			var base: Vector3 = e[1]
			var top := Vector3(base.x, e[2], base.z)
			var rad: float = e[3]
			var res := LineCombat.closest_segments(a, b, base, top)
			if float(res[2]) < rad:
				var sp := a.lerp(b, res[0])
				var ap := base.lerp(top, res[1])
				var hdir := Vector3(sp.x - ap.x, 0.0, sp.z - ap.z)
				if hdir.length() < 0.001:
					hdir = (b - a).cross(Vector3.UP)
				return [res[0], ap + hdir.normalized() * (rad + 0.012), 0.45, 1000.0, e[4]]
		Kind.BOX:
			var box: AABB = e[1]
			if box.size.y < 0.5:
				return []
			var hit := _segment_box(a, b, box.grow(0.02))
			if not hit.is_empty():
				return [hit[0], hit[1], 0.7, 1000.0, "telhado"]
		Kind.WIRE:
			var wa: Vector3 = e[1]
			var wb: Vector3 = e[2]
			var res2 := LineCombat.closest_segments(a, b, wa, wb)
			if float(res2[2]) < 0.035:
				var sp2 := a.lerp(b, res2[0])
				var wp := wa.lerp(wb, res2[1])
				var off := sp2 - wp
				off = off.normalized() if off.length() > 0.0005 else Vector3.UP
				return [res2[0], wp + off * 0.012, 0.3, 1000.0, "fio"]
	return []


func _update_pins(rope: Rope, dt: float) -> void:
	var i := rope.pos.size() - 1
	while i >= 1:
		if rope.pinned[i] == 0:
			i -= 1
			continue
		var n := rope.pos.size()
		var p := rope.pos[i]
		var has_next := i + 1 < n or rope.end_body != null
		if not has_next:
			rope.unpin_node(i)
			i -= 1
			continue
		var prev_p := rope.pos[i - 1]
		var next_p := rope.pos[i + 1] if i + 1 < n else rope.end_point()
		var u1 := (prev_p - p).normalized()
		var u2 := (next_p - p).normalized()
		var dev := PI - acos(clampf(u1.dot(u2), -1.0, 1.0))
		var t_hand: float = rope.seg_tension[i - 1] if i - 1 < rope.seg_tension.size() else 0.0
		var t_kite: float = rope.seg_tension[i] if i < rope.seg_tension.size() else 0.0
		var release := false
		var oi := rope.pin_obstacle[i]
		if oi >= 0 and oi < entries.size():
			var e: Array = entries[oi]
			match e[0]:
				Kind.CANOPY:
					var c: Vector3 = e[1]
					var ab := next_p - prev_p
					var t := clampf((c - prev_p).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					release = (prev_p + ab * t).distance_to(c) > float(e[2]) * 0.85
				Kind.CYLINDER:
					var base: Vector3 = e[1]
					var res := LineCombat.closest_segments(prev_p, next_p, base, Vector3(base.x, e[2], base.z))
					release = float(res[2]) > float(e[3]) + 0.02
				Kind.WIRE:
					release = dev < 0.05
				Kind.BOX:
					release = _segment_box(prev_p, next_p, (e[1] as AABB).grow(-0.03)).is_empty() and dev < 0.6
		if dev < 0.02 or maxf(t_hand, t_kite) > rope.pin_break[i]:
			release = true
		if release:
			rope.unpin_node(i)
			rope.remove_node(i)
			i -= 1
			continue
		# Cabrestante: a linha só desliza se um lado vencer o outro × e^(μθ).
		var ratio := exp(rope.pin_mu[i] * dev)
		var move := 0.0
		if t_kite > t_hand * ratio + 0.05:
			move = minf((t_kite - t_hand * ratio) * 0.6, 4.0) * dt          # pipa puxa linha
		elif t_hand > t_kite * ratio + 0.05:
			move = -minf((t_hand - t_kite * ratio) * 0.6, 4.0) * dt         # mão puxa linha
		if move != 0.0 and i < rope.rest.size():
			move = clampf(move, -(rope.rest[i] - 0.05), rope.rest[i - 1] - 0.05)
			rope.rest[i - 1] -= move
			rope.rest[i] += move
		i -= 1


## A pipa encostou em algo que prende? Retorna [nome, ponto] ou [].
func kite_snag_test(x: Vector3) -> Array:
	for idx in query(x):
		var e: Array = entries[idx]
		match e[0]:
			Kind.CANOPY:
				var c: Vector3 = e[1]
				if x.distance_to(c) < float(e[2]) + 0.1:
					return ["árvore", x]
			Kind.CYLINDER:
				var base: Vector3 = e[1]
				if x.y > base.y and x.y < float(e[2]) + 0.3:
					if Vector2(x.x - base.x, x.z - base.z).length() < float(e[3]) + 0.25:
						return [e[4], x]
			Kind.WIRE:
				var res := LineCombat.closest_segments(x, x, e[1], e[2])
				if float(res[2]) < 0.22:
					return ["fio", x]
	return []


## Segmento × caixa (teste de lajes): [t de entrada, ponto na face] ou [].
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
		return []  # começa dentro (o empurrão por nó resolve)
	return [t0, a + d * t0 + normal * 0.02]


static func _push_out_of_box(box: AABB, p: Vector3) -> Vector3:
	var dx0 := p.x - box.position.x
	var dx1 := box.end.x - p.x
	var dy1 := box.end.y - p.y
	var dz0 := p.z - box.position.z
	var dz1 := box.end.z - p.z
	var m := minf(minf(dx0, dx1), minf(dy1, minf(dz0, dz1)))
	if m == dy1:
		return Vector3(p.x, box.end.y + 0.01, p.z)
	if m == dx0:
		return Vector3(box.position.x - 0.01, p.y, p.z)
	if m == dx1:
		return Vector3(box.end.x + 0.01, p.y, p.z)
	if m == dz0:
		return Vector3(p.x, p.y, box.position.z - 0.01)
	return Vector3(p.x, p.y, box.end.z + 0.01)
