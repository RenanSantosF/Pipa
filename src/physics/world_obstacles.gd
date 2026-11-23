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
		# Fios: segmento da linha × fio.
		if i + 1 < n:
			var q := rope.pos[i + 1]
			for idx in query(p):
				var e2: Array = entries[idx]
				if e2[0] != Kind.WIRE:
					continue
				var res := LineCombat.closest_segments(p, q, e2[1], e2[2])
				var dist: float = res[2]
				if dist < 0.04:
					var t: float = res[0]
					var cp := p.lerp(q, t)
					var wp: Vector3 = (e2[1] as Vector3).lerp(e2[2], res[1])
					var sep := cp - wp
					var dirv := sep.normalized() if sep.length() > 0.0001 else Vector3.UP
					var corr := dirv * (0.04 - dist)
					p += corr * (1.0 - t)
					rope.pos[i + 1] = q + corr * t
					v *= 0.3
					touched = true
					caught = "fio"
		if touched:
			rope.pos[i] = p
			rope.vel[i] = v
	return caught


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
