class_name StreetBuilder
extends Node3D
## Gera o bairro a partir de uma seed:
##  - relevo (encosta + ondulações), aplainado só sob ruas e campinho;
##  - ruas curvas em níveis: principal, rua de cima, rua de baixo, ladeira e beco;
##  - casas viradas para cada rua acompanhando a curva + miolo de quadra caótico
##    no morro (muro de arrimo quando o terreno desce);
##  - árvores variadas (mangueira, coqueiro, eucalipto, bananeira) com folhas reais;
##  - postes reais (Poly Haven) com fios seguindo as ruas.
## Geometria estática agrupada por material e por fatia → poucas draw calls.

@export var seed_value: int = 2024

const SURFACES := {
	"asphalt": [0.1, 0.22], "sidewalk": [0.1, 0.45], "plaster": [0.85, 0.45], "muro": [0.6, 0.45],
	"roof": [0.2, 0.55], "laje": [0.15, 0.35], "brick": [0.1, 0.6], "ground": [0.25, 0.3],
	"dirt": [0.1, 0.18], "grass": [0.15, 0.2], "bark": [0.0, 0.9], "metal": [0.75, 0.6],
}
## Escala 1:1: poste urbano de ~10,5 m (cruzeta a 9,6 m), fios em 9,6 / 7,3 m.
const POLE_TOP := 7.8
const WIRE_HIGH := 7.2
const WIRE_LOW := 5.5
const FOLIAGE := {
	"mango": "res://assets/textures/foliage_cluster.png",
	"palm": "res://assets/textures/palm_frond.png",
	"banana": "res://assets/textures/banana_leaf.png",
	"ipe_amarelo": "res://assets/textures/foliage_cluster.png",
	"ipe_rosa": "res://assets/textures/foliage_cluster.png",
}
## Ipês floridos: a folhagem vira flor (amarela / rosa).
const FLOWERS := {"ipe_amarelo": Color(1.0, 0.8, 0.1), "ipe_rosa": Color(0.96, 0.46, 0.7)}
const TRUNK := Color(0.85, 0.8, 0.75)
const CHUNK := 45.0

# Grade do terreno.
const GX0 := -150.0
const GZ0 := -175.0
const GCELL := 3.0
const GW := 101
const GD := 117

## Material das copas por espécie (o World atualiza o vento).
var foliage_materials: Array[ShaderMaterial] = []
## Compatibilidade: material principal das copas.
var tree_material: ShaderMaterial
var obstacles := WorldObstacles.new()
## Onde o jogador e o vizinho começam (calculado pelo gerador).
var spawn_point := Vector3(0, 0, 55)
## Uma árvore grande perto do início (para as capturas de tela).
var showcase_tree := Vector3.ZERO
var _trees: TreeBuilder
var _spawn_guess := Vector3(0, 0, 55)
var bot_point := Vector3(40, 4, 25)

## Ruas: [pontos (Vector3 com altura), meia-largura, calçada, superfície]
var roads: Array = []

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _batches: Dictionary = {}
var _foliage_batches: Dictionary = {}
var _body: StaticBody3D
## Corpos de colisão por célula (24 m): com tudo num corpo só (3,4 mil caixas) o
## motor de física testava todas as caixas a cada passo do jogador.
var _cell_bodies: Dictionary = {}
var _shape_rids: Array[RID] = []
const COLLISION_CELL := 24.0


## Corpo estático da célula, direto no servidor de física (sem nós na cena: eram
## 3,4 mil CollisionShape3D só ocupando memória e tempo de carga).
func _collision_body_at(p: Vector3) -> RID:
	var key := Vector2i(floori(p.x / COLLISION_CELL), floori(p.z / COLLISION_CELL))
	if not _cell_bodies.has(key):
		var b := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(b, 1)
		PhysicsServer3D.body_set_collision_mask(b, 0)
		PhysicsServer3D.body_set_space(b, get_world_3d().space)
		PhysicsServer3D.body_attach_object_instance_id(b, _body.get_instance_id())
		_cell_bodies[key] = b
	return _cell_bodies[key]


func _exit_tree() -> void:
	for b in _cell_bodies.values():
		PhysicsServer3D.free_rid(b)
	_cell_bodies.clear()
	for sh in _shape_rids:
		PhysicsServer3D.free_rid(sh)
	_shape_rids.clear()
var _opaque_material: StandardMaterial3D
var _wire_points: PackedVector3Array = PackedVector3Array()
var _houses: HouseBuilder
var _road_grid: Dictionary = {}
var _occupied: Array = []   # [centro Vector2, raio]
var _pad := Rect2(-31, 38, 18, 34)
var _pad_h: float = 0.0


func _ready() -> void:
	add_to_group(&"street_builder")
	build()


func build() -> void:
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.02
	_houses = HouseBuilder.new(self, _rng)
	_trees = TreeBuilder.new(self, _rng)
	_body = StaticBody3D.new()
	_body.name = "WorldCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_opaque_material = StandardMaterial3D.new()
	_opaque_material.vertex_color_use_as_albedo = true
	_opaque_material.vertex_color_is_srgb = true
	_opaque_material.roughness = 0.9
	for sp: String in FOLIAGE:
		var m := ShaderMaterial.new()
		m.shader = load("res://src/world/tree_sway.gdshader")
		m.set_shader_parameter("leaves", load(FOLIAGE[sp]))
		if FLOWERS.has(sp):
			m.set_shader_parameter("flower_color", FLOWERS[sp])
			m.set_shader_parameter("flower_mix", 0.85)
		foliage_materials.append(m)
		if sp == "mango":
			tree_material = m

	_define_roads()
	var sp0 := _road_point_near(roads[0][0], 55.0)
	_spawn_guess = Vector3(sp0.x, 0.0, sp0.z)
	_build_terrain()
	_build_roads()
	_build_campinho()
	_build_spawn_house()
	_build_road_lots()
	_build_block_fill()
	_build_poles()
	_build_street_trees()
	_commit()


# --- API usada pelos construtores --------------------------------------------

func batch_for(z: float, surface: String = "plain") -> MeshBatch:
	var key := "%s|%d" % [surface, floori(z / CHUNK)]
	if not _batches.has(key):
		if SURFACES.has(surface):
			_batches[key] = MeshBatch.new(false, SURFACES[surface][0], true)
		else:
			_batches[key] = MeshBatch.new(false)
	return _batches[key]


func foliage_batch(z: float, species: String) -> MeshBatch:
	var key := "%s|%d" % [species, floori(z / CHUNK)]
	if not _foliage_batches.has(key):
		_foliage_batches[key] = MeshBatch.new(true)
	return _foliage_batches[key]


## `line_obstacle` falso: o objeto já tem um obstáculo próprio para a linha (cápsula do
## poste/tronco/trave). Duas formas sobrepostas para a mesma coisa faziam a linha
## ficar presa entre elas (cada uma empurrando o nó para dentro da outra).
func add_collider(xf: Transform3D, size: Vector3, line_obstacle: bool = true) -> void:
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size * 0.5)
	_shape_rids.append(shape)
	PhysicsServer3D.body_add_shape(_collision_body_at(xf.origin), shape, xf)
	if size.x > 60.0 or size.z > 60.0 or not line_obstacle:
		return
	# Obstáculo para a linha: caixa alinhada que envolve a caixa girada.
	var h := size * 0.5
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := xf * Vector3(h.x * sx, h.y * sy, h.z * sz)
				mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
				mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	obstacles.add_box((mn + mx) * 0.5, mx - mn)


# --- Relevo e ruas ---------------------------------------------------------------

## MORRO (v0.22): o terreno sobe ao longo das ruas (+Z) — as ruas são LADEIRAS — e
## desce para onde o vento leva a pipa (−Z). Você fica do meio para cima do morro: a
## pipa sai por cima dos telhados de baixo (soltar fica mais fácil).
const HILL_SLOPE := 0.2
func raw_height(x: float, z: float) -> float:
	return HILL_SLOPE * z + 0.03 * x + 1.2 * sin(z * 0.03 + x * 0.015) + 1.0 * _noise.get_noise_2d(x, z)


func _define_roads() -> void:
	var a := _polyline(_road_main, 160)
	var b := _polyline(_road_upper, 160)
	var c := _polyline(_road_lower, 160)
	_smooth_heights(a)
	_smooth_heights(b)
	_smooth_heights(c)
	roads.append([a, 3.5, 1.6, "asphalt"])
	roads.append([b, 3.2, 1.4, "asphalt"])
	roads.append([c, 3.2, 1.4, "asphalt"])
	# Ladeira: da principal (z = −20) até a de cima (z = −55).
	var pa := _road_point_near(a, -20.0)
	var pb := _road_point_near(b, -55.0)
	roads.append([_link(pa, pb, 22), 2.8, 1.0, "asphalt"])
	# Beco: da principal (z = 28) descendo até a de baixo (z = 12).
	var pc := _road_point_near(a, 28.0)
	var pd := _road_point_near(c, 12.0)
	roads.append([_link(pc, pd, 20), 1.5, 0.0, "laje"])
	for ri in roads.size():
		var pts: PackedVector3Array = roads[ri][0]
		for pi in pts.size():
			var key := Vector2i(floori(pts[pi].x / 10.0), floori(pts[pi].z / 10.0))
			if not _road_grid.has(key):
				_road_grid[key] = []
			(_road_grid[key] as Array).append([ri, pi])


func _road_main(t: float) -> Vector2:
	var z := lerpf(-170.0, 150.0, t)
	return Vector2(6.0 * sin(z / 40.0), z)


func _road_upper(t: float) -> Vector2:
	var z := lerpf(-170.0, 150.0, t)
	return Vector2(42.0 + 8.0 * sin(z / 35.0 + 1.0), z)


func _road_lower(t: float) -> Vector2:
	var z := lerpf(-170.0, 150.0, t)
	return Vector2(-40.0 + 7.0 * sin(z / 30.0 + 2.0), z)


func _polyline(f: Callable, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var p: Vector2 = f.call(float(i) / float(n))
		out.append(Vector3(p.x, raw_height(p.x, p.y), p.y))
	return out


func _smooth_heights(pts: PackedVector3Array) -> void:
	for _pass in 4:
		var hs := PackedFloat32Array()
		for i in pts.size():
			var s := 0.0
			var c := 0
			for k in range(maxi(i - 5, 0), mini(i + 6, pts.size())):
				s += pts[k].y
				c += 1
			hs.append(s / float(c))
		for i in pts.size():
			pts[i] = Vector3(pts[i].x, hs[i], pts[i].z)


func _road_point_near(pts: PackedVector3Array, z: float) -> Vector3:
	var best := pts[0]
	for p in pts:
		if absf(p.z - z) < absf(best.z - z):
			best = p
	return best


func _link(from: Vector3, to: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var side := (to - from).cross(Vector3.UP).normalized()
	for i in n + 1:
		var t := float(i) / float(n)
		var p := from.lerp(to, t) + side * sin(t * PI) * 4.0
		p.y = lerpf(from.y, to.y, t * t * (3.0 - 2.0 * t))
		out.append(p)
	return out


## [distância horizontal, altura da rua, índice da rua, tangente] da rua mais próxima.
func nearest_road(x: float, z: float, max_cells: int = 2) -> Array:
	var best_d := INF
	var best_h := 0.0
	var best_r := -1
	var best_t := Vector3.FORWARD
	var gx := floori(x / 10.0)
	var gz := floori(z / 10.0)
	for dx in range(-max_cells, max_cells + 1):
		for dz in range(-max_cells, max_cells + 1):
			var key := Vector2i(gx + dx, gz + dz)
			if not _road_grid.has(key):
				continue
			for e in _road_grid[key]:
				var pts: PackedVector3Array = roads[e[0]][0]
				var i: int = e[1]
				var p := pts[i]
				var d := Vector2(p.x - x, p.z - z).length()
				if d < best_d:
					best_d = d
					best_h = p.y
					best_r = e[0]
					var j := mini(i + 1, pts.size() - 1)
					var k := maxi(i - 1, 0)
					best_t = (pts[j] - pts[k]).normalized()
	return [best_d, best_h, best_r, best_t]


func _build_terrain() -> void:
	# Campinho: platô na altura média do terreno.
	_pad_h = raw_height(_pad.get_center().x, _pad.get_center().y) - 0.3
	var hs := PackedFloat32Array()
	hs.resize(GW * GD)
	for iz in GD:
		for ix in GW:
			var x := GX0 + ix * GCELL
			var z := GZ0 + iz * GCELL
			var h := raw_height(x, z)
			var nr := nearest_road(x, z)
			if nr[2] >= 0:
				var road: Array = roads[nr[2]]
				var inner: float = road[1] + road[2] + 0.6
				var w := 1.0 - _smoothstep(inner, inner + 6.0, nr[0])
				h = lerpf(h, nr[1], w)
			var dp := maxf(maxf(_pad.position.x - x, x - _pad.end.x), maxf(_pad.position.y - z, z - _pad.end.y))
			if dp < 5.0:
				h = lerpf(h, _pad_h, 1.0 - _smoothstep(0.0, 5.0, dp))
			hs[iz * GW + ix] = h
	Ground.origin = Vector2(GX0, GZ0)
	Ground.cell = GCELL
	Ground.w = GW
	Ground.d = GD
	Ground.heights = hs
	# Malha (por fatias de Z), normais suaves pelo gradiente.
	var chunk_rows := 15
	var iz0 := 0
	while iz0 < GD - 1:
		var iz1 := mini(iz0 + chunk_rows, GD - 1)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for iz in range(iz0, iz1):
			for ix in GW - 1:
				var q := [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]
				for k in [0, 1, 2, 0, 2, 3]:
					var g: Vector2i = q[k]
					_terrain_vertex(st, g.x, g.y)
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Terreno_%d" % iz0
		mi.mesh = st.commit()
		mi.material_override = _surface_material("ground")
		add_child(mi)
		iz0 = iz1
	# Colisão do terreno.
	var hm := HeightMapShape3D.new()
	hm.map_width = GW
	hm.map_depth = GD
	hm.map_data = hs
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.position = Vector3(GX0 + (GW - 1) * GCELL * 0.5, 0.0, GZ0 + (GD - 1) * GCELL * 0.5)
	cs.scale = Vector3(GCELL, 1.0, GCELL)
	_body.add_child(cs)


func _terrain_vertex(st: SurfaceTool, ix: int, iz: int) -> void:
	var h := Ground.heights
	var x := GX0 + ix * GCELL
	var z := GZ0 + iz * GCELL
	var y := h[iz * GW + ix]
	var hl := h[iz * GW + maxi(ix - 1, 0)]
	var hr := h[iz * GW + mini(ix + 1, GW - 1)]
	var hd := h[maxi(iz - 1, 0) * GW + ix]
	var hu := h[mini(iz + 1, GD - 1) * GW + ix]
	var n := Vector3(hl - hr, 2.0 * GCELL, hd - hu).normalized()
	var g := clampf(0.5 + _noise.get_noise_2d(x * 3.0, z * 3.0), 0.0, 1.0)
	st.set_color(Color(0.92, 0.88, 0.82).lerp(Color(0.62, 0.78, 0.45), g * 0.7))
	st.set_normal(n)
	st.set_uv(Vector2(x, z))
	st.add_vertex(Vector3(x, y, z))


static func _smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _build_roads() -> void:
	for road in roads:
		var pts: PackedVector3Array = road[0]
		var half: float = road[1]
		var sw: float = road[2]
		var surf: String = road[3]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var t := (b - a)
			t.y = 0.0
			t = t.normalized()
			var n := t.cross(Vector3.UP).normalized()
			var na := n
			var nb := n
			if i + 2 < pts.size():
				var t2 := pts[i + 2] - b
				t2.y = 0.0
				nb = t2.normalized().cross(Vector3.UP).normalized().lerp(n, 0.5).normalized()
			var zc := (a.z + b.z) * 0.5
			_strip(batch_for(zc, surf), a, b, na, nb, -half, half, 0.04)
			if sw > 0.0:
				for s in [-1.0, 1.0]:
					var o0: float = s * half
					var o1: float = s * (half + sw)
					_strip(batch_for(zc, "sidewalk"), a, b, na, nb, minf(o0, o1), maxf(o0, o1), 0.17)
					_curb(batch_for(zc, "sidewalk"), a, b, na, nb, o0, float(s))


func _surf_y(p: Vector3) -> float:
	return Ground.height_at(p.x, p.z)


func _strip(bt: MeshBatch, a: Vector3, b: Vector3, na: Vector3, nb: Vector3, o0: float, o1: float, lift: float) -> void:
	var p0 := a + na * o0
	var p1 := a + na * o1
	var p2 := b + nb * o1
	var p3 := b + nb * o0
	p0.y = _surf_y(p0) + lift
	p1.y = _surf_y(p1) + lift
	p2.y = _surf_y(p2) + lift
	p3.y = _surf_y(p3) + lift
	var nrm := (p1 - p0).cross(p3 - p0).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	bt.add_quad(p0, p1, p2, p3, nrm, Color.WHITE)


func _curb(bt: MeshBatch, a: Vector3, b: Vector3, na: Vector3, nb: Vector3, o: float, s: float) -> void:
	var p0 := a + na * o
	var p1 := b + nb * o
	var y0 := _surf_y(p0)
	var y1 := _surf_y(p1)
	var n := -na * s
	bt.add_quad(Vector3(p0.x, y0 + 0.02, p0.z), Vector3(p1.x, y1 + 0.02, p1.z), Vector3(p1.x, y1 + 0.17, p1.z), Vector3(p0.x, y0 + 0.17, p0.z), n, Color(0.9, 0.9, 0.88))


# --- Lotes e casas -----------------------------------------------------------------

func _free_at(c: Vector2, r: float) -> bool:
	if _pad.grow(r).has_point(c):
		return false
	for o in _occupied:
		if (o[0] as Vector2).distance_to(c) < float(o[1]) + r:
			return false
	return true


func _build_road_lots() -> void:
	for ri in [0, 1, 2, 3]:
		var road: Array = roads[ri]
		var pts: PackedVector3Array = road[0]
		var front: float = road[1] + road[2]
		for side in [-1.0, 1.0]:
			var acc := _rng.randf_range(0.0, 6.0)
			var width := _rng.randf_range(6.0, 11.0)
			for i in range(1, pts.size() - 1):
				acc += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
				if acc < width:
					continue
				acc = 0.0
				_place_lot(pts, i, float(side), front, width, ri)
				width = _rng.randf_range(6.0, 11.0)


func _place_lot(pts: PackedVector3Array, i: int, side: float, front: float, width: float, ri: int) -> void:
	var p := pts[i]
	var t := pts[i + 1] - pts[i - 1]
	t.y = 0.0
	t = t.normalized()
	var out := t.cross(Vector3.UP).normalized() * side
	var depth := _rng.randf_range(10.0, 13.0)
	var center := p + out * (front + depth * 0.5)
	var c2 := Vector2(center.x, center.z)
	if not _free_at(c2, maxf(width, depth) * 0.42):
		return
	# Não invade outra rua.
	var back := p + out * (front + depth)
	var nr := nearest_road(back.x, back.z)
	if nr[2] != ri and nr[2] >= 0 and float(nr[0]) < float(roads[nr[2]][1]) + float(roads[nr[2]][2]) + 1.0:
		return
	var nr2 := nearest_road(center.x, center.z)
	if nr2[2] != ri and nr2[2] >= 0 and float(nr2[0]) < float(roads[nr2[2]][1]) + float(roads[nr2[2]][2]) + 3.0:
		return
	_occupied.append([c2, maxf(width, depth) * 0.45])
	# Ladeira: o lote fica na altura do ponto MAIS ALTO do terreno embaixo dele e o
	# embasamento (muro de arrimo) desce até o mais baixo — a casa não flutua do lado
	# de baixo nem afunda do lado de cima.
	var z_axis := out.cross(Vector3.UP).normalized()
	var gmax := -INF
	var gmin := INF
	for fd in [front, front + depth * 0.5, front + depth]:
		for fw in [-0.5, 0.0, 0.5]:
			var q: Vector3 = p + out * float(fd) + z_axis * (float(fw) * width)
			var gh := Ground.height_at(q.x, q.z)
			gmax = maxf(gmax, gh)
			gmin = minf(gmin, gh)
	var drop := gmax - gmin
	var basis := Basis(out, Vector3.UP, -z_axis)
	if basis.determinant() < 0.0:
		basis = Basis(out, Vector3.UP, z_axis)
	var origin := Vector3(p.x, gmax + 0.17, p.z)
	_houses.build(Transform3D(basis, origin), width, front, depth, drop, true)


## Miolo das quadras: casas empilhadas no morro, viradas para a rua mais próxima.
func _build_block_fill() -> void:
	var x := -135.0
	while x < 140.0:
		var z := -165.0
		while z < 145.0:
			var px := x + _rng.randf_range(-3.0, 3.0)
			var pz := z + _rng.randf_range(-3.0, 3.0)
			var far := absf(px) > 75.0
			if _rng.randf() < (0.6 if far else 0.97):
				var nr := nearest_road(px, pz, 3)
				var clear: bool = nr[2] < 0 or float(nr[0]) > float(roads[nr[2]][1]) + float(roads[nr[2]][2]) + 6.0
				var w := _rng.randf_range(6.0, 9.0)
				if clear and _free_at(Vector2(px, pz), w * 0.36):
					_occupied.append([Vector2(px, pz), w * 0.36])
					var t: Vector3 = nr[3] if nr[2] >= 0 else Vector3.FORWARD
					t.y = 0.0
					t = t.normalized().rotated(Vector3.UP, _rng.randf_range(-0.25, 0.25))
					var out := t.cross(Vector3.UP).normalized()
					var depth := _rng.randf_range(7.0, 10.0)
					var gmin := INF
					var gmax := -INF
					for cx in [-0.5, 0.5]:
						for cz in [-0.5, 0.5]:
							var q: Vector3 = Vector3(px, 0, pz) + out * (float(cx) * depth) + t * (float(cz) * w)
							var gh := Ground.height_at(q.x, q.z)
							gmin = minf(gmin, gh)
							gmax = maxf(gmax, gh)
					var origin := Vector3(px, gmax, pz) - out * (depth * 0.5)
					var basis := Basis(out, Vector3.UP, out.cross(Vector3.UP).normalized())
					_houses.build(Transform3D(basis, origin), w, 0.0, depth, gmax - gmin, not far)
			z += 7.5
		x += 8.0


## Casa do jogador: laje de 2 andares ao lado da rua principal, do meio para cima do
## morro. Você começa EM CIMA DA LAJE (a pipa sai por cima dos telhados de baixo).
var _spawn_laje := Vector3.ZERO
func _build_spawn_house() -> void:
	var pts: PackedVector3Array = roads[0][0]
	var i := 1
	for k in range(1, pts.size() - 1):
		if absf(pts[k].z - 55.0) < absf(pts[i].z - 55.0):
			i = k
	var p := pts[i]
	var t := pts[i + 1] - pts[i - 1]
	t.y = 0.0
	t = t.normalized()
	var out := t.cross(Vector3.UP).normalized()
	var front: float = float(roads[0][1]) + float(roads[0][2]) + 0.3
	var width := 8.0
	var depth := 8.0
	var z_axis := out.cross(Vector3.UP).normalized()
	var gmax := -INF
	var gmin := INF
	for fd in [front, front + depth * 0.5, front + depth]:
		for fw in [-0.5, 0.0, 0.5]:
			var q: Vector3 = p + out * float(fd) + z_axis * (float(fw) * width)
			gmax = maxf(gmax, Ground.height_at(q.x, q.z))
			gmin = minf(gmin, Ground.height_at(q.x, q.z))
	var basis := Basis(out, Vector3.UP, -z_axis)
	if basis.determinant() < 0.0:
		basis = Basis(out, Vector3.UP, z_axis)
	var origin := p + out * front
	origin.y = gmax + 0.17
	var xf := Transform3D(basis, origin)
	var top := _houses.build_laje(xf, width, depth, 2, gmax - gmin)
	var c := origin + out * (depth * 0.5)
	_occupied.append([Vector2(c.x, c.z), depth * 0.6])
	_spawn_laje = xf * Vector3(depth * 0.45, top + 0.15, 0.0)


func _build_campinho() -> void:
	var c := _pad.get_center()
	var y := _pad_h
	var zc := c.y
	batch_for(zc, "dirt").add_box(Transform3D(Basis.IDENTITY, Vector3(c.x, y + 0.03, c.y)), Vector3(_pad.size.x - 2.0, 0.04, _pad.size.y - 3.0), Color.WHITE)
	var white := Color(0.95, 0.95, 0.92)
	for gz in [_pad.position.y + 2.5, _pad.end.y - 2.5]:
		for dx in [-1.5, 1.5]:
			var post := Vector3(c.x + float(dx), y + 1.0, float(gz))
			batch_for(zc).add_cylinder(Transform3D(Basis.IDENTITY, post), 0.05, 2.0, 6, white)
			add_collider(Transform3D(Basis.IDENTITY, post), Vector3(0.1, 2.0, 0.1), false)
			obstacles.add_cylinder(Vector3(post.x, y, post.z), 2.0, 0.06, "trave")
		batch_for(zc).add_box(Transform3D(Basis.IDENTITY, Vector3(c.x, y + 2.0, float(gz))), Vector3(3.1, 0.1, 0.1), white)
	_occupied.append([c, maxf(_pad.size.x, _pad.size.y) * 0.5])
	for i in 2:   # duas mangueiras na beira do campinho (antes eram seis)
		var tz := _pad.position.y + 4.0 + (_pad.size.y - 8.0) * float(i)
		var tx := _pad.position.x - 1.0
		add_tree(Vector3(tx, Ground.height_at(tx, tz), tz), "mango")


# --- Árvores -------------------------------------------------------------------

## Árvore de uma espécie ("" = sorteia). base.y = chão. street = na calçada
## (pé caiado e canteiro).
func add_tree(base: Vector3, species: String = "", street: bool = false) -> void:
	# Corredor livre a favor do vento a partir de onde o jogador começa (para a
	# pipa subir da mão sem cair direto numa copa).
	var rel := Vector3(base.x - _spawn_guess.x, 0.0, base.z - _spawn_guess.z)
	var wd := Wind.get_direction()
	var along := rel.dot(wd)
	var across := absf(rel.dot(wd.cross(Vector3.UP)))
	if rel.length() < 6.0 or (along > -4.0 and along < 45.0 and across < 9.0 + along * 0.15):
		return
	if species == "":
		var r := _rng.randf()
		if r < 0.22:
			species = "mangueira"
		elif r < 0.4:
			species = "sibipiruna"
		elif r < 0.55:
			species = "oiti"
		elif r < 0.65:
			species = "ipe_amarelo"
		elif r < 0.72:
			species = "ipe_rosa"
		elif r < 0.87 or street:
			species = "palm"
		else:
			species = "banana"
	match species:
		"mango":
			species = "mangueira"
		"eucalyptus":
			species = "sibipiruna"
	match species:
		"palm":
			_tree_palm(base, _rng.randf_range(7.0, 11.0))
		"banana":
			_tree_banana(base)
		_:
			var h := _trees.build(base, species, -1, street)
			if h > 9.0 and showcase_tree == Vector3.ZERO and base.distance_to(spawn_point) < 90.0:
				showcase_tree = base


func _tree_palm(base: Vector3, h: float) -> void:
	var b := batch_for(base.z, "bark")
	var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.8, 2.2)
	var prev := base
	var segs := 6
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var p := base + Vector3(0, h * t, 0) + lean * t * t
		var d := p - prev
		b.add_cylinder(Transform3D(Basis(_arc(Vector3.UP, d.normalized())), (p + prev) * 0.5), 0.17 - 0.04 * t, d.length() + 0.05, 7, Color(0.95, 0.92, 0.85))
		prev = p
	obstacles.add_cylinder(base, h, 0.18, "coqueiro")
	add_collider(Transform3D(Basis.IDENTITY, base + Vector3(0, h * 0.5, 0)), Vector3(0.34, h, 0.34), false)
	var fb := foliage_batch(base.z, "palm")
	var phase := _rng.randf() * TAU
	var n := 11 + _rng.randi() % 4
	for i in n:
		var ang := TAU * float(i) / float(n) + _rng.randf_range(-0.2, 0.2)
		var outd := Vector3(cos(ang), 0, sin(ang))
		var droop := _rng.randf_range(-0.15, 0.75)
		var dir := (outd * cos(droop) + Vector3.DOWN * sin(droop) + Vector3.UP * 0.25).normalized()
		var length := _rng.randf_range(3.0, 4.2)
		var right := dir.cross(Vector3.UP).normalized()
		var center := prev + dir * (length * 0.5)
		fb.add_card_rect(center, right, dir, 1.3, length, (Vector3.UP * 0.6 + outd).normalized(), Color(1, 1, 1).darkened(_rng.randf() * 0.15), Vector2(0.35, phase))
	obstacles.add_canopy(prev, 2.6)


func _tree_banana(base: Vector3) -> void:
	var h := _rng.randf_range(1.6, 2.6)
	batch_for(base.z, "plain").add_cylinder(Transform3D(Basis.IDENTITY, base + Vector3(0, h * 0.5, 0)), 0.12, h, 7, Color(0.45, 0.55, 0.3))
	var fb := foliage_batch(base.z, "banana")
	var phase := _rng.randf() * TAU
	var top := base + Vector3(0, h, 0)
	for i in 8:
		var ang := TAU * float(i) / 8.0 + _rng.randf_range(-0.3, 0.3)
		var outd := Vector3(cos(ang), 0, sin(ang))
		var dir := (outd * 0.75 + Vector3.UP * _rng.randf_range(0.2, 0.9)).normalized()
		var length := _rng.randf_range(1.8, 2.5)
		fb.add_card_rect(top + dir * (length * 0.5), dir.cross(Vector3.UP).normalized(), dir, 0.75, length, Vector3.UP, Color(1, 1, 1), Vector2(0.3, phase))
	obstacles.add_canopy(top + Vector3.UP * 0.6, 1.4)


## Copa feita de cartões de folhagem num elipsoide, voltados para fora.
func _canopy_cards(fb: MeshBatch, center: Vector3, r: float, color: Color, sway: Vector2) -> void:
	var count := clampi(int(r * r * 10.0), 6, 44)
	for _i in count:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 1.0), _rng.randf_range(-1, 1)).normalized()
		var pos := center + dir * Vector3(r, r * 0.8, r) * _rng.randf_range(0.35, 0.95)
		var out := (pos - center).normalized()
		var right := out.cross(Vector3.UP)
		if right.length() < 0.1:
			right = Vector3.RIGHT
		right = right.normalized().rotated(out, _rng.randf_range(-0.8, 0.8))
		var up := (right.cross(out).normalized() * -1.0 + out * 0.6).normalized()
		fb.add_card(pos, right, up, r * _rng.randf_range(0.8, 1.15), out, color.lightened(_rng.randf_range(0.0, 0.12)), sway)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) > 0.9999:
		return Quaternion.IDENTITY
	return Quaternion(from, to)


func _build_street_trees() -> void:
	for ri in [0, 1, 2]:
		var road: Array = roads[ri]
		var pts: PackedVector3Array = road[0]
		var off: float = road[1] + road[2] * 0.6
		for side in [-1.0, 1.0]:
			var acc := _rng.randf_range(0.0, 30.0)
			var gap := _rng.randf_range(45.0, 80.0)   # poucas árvores na rua (v0.22)
			for i in range(1, pts.size() - 1):
				acc += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
				if acc < gap:
					continue
				acc = 0.0
				gap = _rng.randf_range(45.0, 80.0)
				var t := (pts[i + 1] - pts[i - 1])
				t.y = 0.0
				var n := t.normalized().cross(Vector3.UP).normalized() * float(side)
				var p := pts[i] + n * off
				if not _pad.has_point(Vector2(p.x, p.z)):
					add_tree(Vector3(p.x, Ground.height_at(p.x, p.z) + 0.17, p.z), "", true)


# --- Postes e fios -------------------------------------------------------------

func _build_poles() -> void:
	for ri in [0, 1, 2, 3]:
		var road: Array = roads[ri]
		var pts: PackedVector3Array = road[0]
		var off: float = road[1] + road[2] - 0.4
		var tops: Array[Vector3] = []
		var acc := 0.0
		var k := 0
		for i in range(1, pts.size() - 1):
			acc += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			if acc < 30.0 and i != 1:
				continue
			acc = 0.0
			var t := pts[i + 1] - pts[i - 1]
			t.y = 0.0
			t = t.normalized()
			var n := t.cross(Vector3.UP).normalized()
			var p := pts[i] + n * off
			var base := Vector3(p.x, Ground.height_at(p.x, p.z), p.z)
			add_collider(Transform3D(Basis.IDENTITY, base + Vector3(0, POLE_TOP * 0.5, 0)), Vector3(0.3, POLE_TOP, 0.3), false)
			obstacles.add_cylinder(base, POLE_TOP, 0.14, "poste")
			# Cruzeta em duas metades que começam na superfície do poste (não por dentro).
			obstacles.add_capsule(base - n * 0.2 + Vector3.UP * (WIRE_HIGH - 0.08), base - n * 1.0 + Vector3.UP * (WIRE_HIGH - 0.08), 0.05, "cruzeta")
			obstacles.add_capsule(base + n * 0.2 + Vector3.UP * (WIRE_HIGH - 0.08), base + n * 1.0 + Vector3.UP * (WIRE_HIGH - 0.08), 0.05, "cruzeta")
			_concrete_pole(base, n, k)
			tops.append(base)
			k += 1
			if _rng.randf() < 0.5:
				var hp := pts[i] - n * (off + _rng.randf_range(4.0, 7.0))
				_add_wire(base + n * -0.9 + Vector3.UP * WIRE_HIGH, Vector3(hp.x, Ground.height_at(hp.x, hp.z) + 3.2, hp.z), 0.5)
		for i in range(tops.size() - 1):
			var a := tops[i]
			var c := tops[i + 1]
			var na := _pole_cross(pts, a)
			var nc := _pole_cross(pts, c)
			for dx in [-0.9, 0.0, 0.9]:
				_add_wire(a + na * float(dx) + Vector3.UP * WIRE_HIGH, c + nc * float(dx) + Vector3.UP * WIRE_HIGH, 0.45)
			_add_wire(a + Vector3.UP * WIRE_LOW, c + Vector3.UP * WIRE_LOW, 0.6)


## Poste de concreto procedural (~150 triângulos, entra no lote da rua: nenhuma
## chamada de desenho a mais). O modelo importado tinha 26–35 mil triângulos em
## 13–27 peças POR POSTE — era boa parte do peso da cena no celular.
func _concrete_pole(base: Vector3, n: Vector3, k: int) -> void:
	var b := batch_for(base.z, "plain")
	var concrete := Color(0.66, 0.65, 0.62)
	var up := Vector3.UP
	# Fuste afunilado (base enterrada um pouco).
	b.add_frustum(base - up * 0.2, base + up * POLE_TOP, 0.17, 0.095, 6, concrete.darkened(0.08), concrete)
	# Cruzeta de cima (madeira escura) com 3 isoladores, e a de baixo (rede secundária).
	var t := n.cross(up).normalized()
	var ch := base + up * (WIRE_HIGH - 0.08)
	b.add_box(Transform3D(Basis(n, up, t), ch), Vector3(2.1, 0.1, 0.09), Color(0.36, 0.3, 0.24))
	for dx in [-0.9, 0.0, 0.9]:
		var ip := ch + n * float(dx) + up * 0.05
		b.add_frustum(ip, ip + up * 0.14, 0.045, 0.03, 5, Color(0.86, 0.86, 0.82))
	var cl := base + up * (WIRE_LOW - 0.05)
	b.add_box(Transform3D(Basis(n, up, t), cl + t * 0.12), Vector3(0.5, 0.08, 0.08), Color(0.3, 0.3, 0.3))
	# Um transformador de vez em quando.
	if k % 4 == 2:
		var tp := base + up * (WIRE_LOW + 0.9) + t * 0.42
		b.add_box(Transform3D(Basis(n, up, t), tp), Vector3(0.55, 0.85, 0.5), Color(0.42, 0.47, 0.44))
		b.add_box(Transform3D(Basis(n, up, t), tp + up * 0.48), Vector3(0.5, 0.06, 0.45), Color(0.3, 0.33, 0.31))


func _pole_cross(pts: PackedVector3Array, p: Vector3) -> Vector3:
	var best := 0
	for i in pts.size():
		if Vector2(pts[i].x - p.x, pts[i].z - p.z).length() < Vector2(pts[best].x - p.x, pts[best].z - p.z).length():
			best = i
	var t := pts[mini(best + 1, pts.size() - 1)] - pts[maxi(best - 1, 0)]
	t.y = 0.0
	return t.normalized().cross(Vector3.UP).normalized()


func _add_wire(a: Vector3, b: Vector3, sag: float) -> void:
	var segments := 10
	var prev := a
	# Para a linha, o fio começa/termina 25 cm antes das pontas (que ficam dentro do
	# poste ou na parede da casa): obstáculos sobrepostos prendiam a linha entre eles.
	var trim := 0.25 / maxf(a.distance_to(b), 0.5)
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		_wire_points.append(prev)
		_wire_points.append(p)
		var t0 := float(i - 1) / float(segments)
		var pa := prev
		var pb := p
		if t0 < trim:
			pa = a.lerp(b, trim) + Vector3.DOWN * sag * 4.0 * trim * (1.0 - trim)
		if t > 1.0 - trim:
			var t1 := 1.0 - trim
			pb = a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		obstacles.add_wire(pa, pb)
		prev = p


# --- Finalização ---------------------------------------------------------------

func _commit() -> void:
	var materials := {}
	for key: String in _batches:
		var mesh := (_batches[key] as MeshBatch).commit()
		if mesh == null:
			continue
		var surface := key.get_slice("|", 0)
		if not materials.has(surface):
			materials[surface] = _surface_material(surface)
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_" + key.replace("|", "_")
		mi.mesh = mesh
		mi.material_override = materials[surface]
		mi.visibility_range_end = GameConfig.draw_distance()
		if GameConfig.quality == GameConfig.Quality.LOW:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var species := FOLIAGE.keys()
	for key: String in _foliage_batches:
		var mesh := (_foliage_batches[key] as MeshBatch).commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Copa_" + key.replace("|", "_")
		mi.mesh = mesh
		mi.material_override = foliage_materials[species.find(key.get_slice("|", 0))]
		mi.extra_cull_margin = 1.0
		if GameConfig.quality < GameConfig.Quality.HIGH:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = [100.0, 160.0, 0.0][GameConfig.quality]
		add_child(mi)
	if _wire_points.size() > 0:
		var im := ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.08, 0.08, 0.08)
		im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for p in _wire_points:
			im.surface_add_vertex(p)
		im.surface_end()
		var wires := MeshInstance3D.new()
		wires.name = "Wires"
		wires.mesh = im
		wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wires)
	# Pontos de partida.
	var a: PackedVector3Array = roads[0][0]
	if _spawn_laje == Vector3.ZERO:
		var sp := _road_point_near(a, 55.0)
		spawn_point = Vector3(sp.x, Ground.height_at(sp.x, sp.z) + 0.1, sp.z)
	else:
		spawn_point = _spawn_laje
	var b: PackedVector3Array = roads[1][0]
	var bp := _road_point_near(b, 25.0)
	bot_point = Vector3(bp.x - 4.0, Ground.height_at(bp.x - 4.0, bp.z) + 0.2, bp.z)


## Ponto na calçada da rua `ri` perto de z (lado +1/−1), no chão.
func sidewalk_spot(ri: int, z: float, side: float) -> Vector3:
	var pts: PackedVector3Array = roads[ri][0]
	var best := 1
	for i in range(1, pts.size() - 1):
		if absf(pts[i].z - z) < absf(pts[best].z - z):
			best = i
	var t := pts[best + 1] - pts[best - 1]
	t.y = 0.0
	var n := t.normalized().cross(Vector3.UP).normalized() * side
	var p: Vector3 = pts[best] + n * (float(roads[ri][1]) + float(roads[ri][2]) * 0.5)
	return Vector3(p.x, Ground.height_at(p.x, p.z) + 0.2, p.z)


func _surface_material(surface: String) -> Material:
	if not SURFACES.has(surface):
		return _opaque_material
	var base := "res://assets/textures/%s/" % surface
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "diff.jpg")
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var low := GameConfig.quality == GameConfig.Quality.LOW
	# Qualidade baixa: só a cor (sem mapa de normal nem de rugosidade = 2 leituras
	# de textura a menos por pixel em toda parede/chão; de longe quase não se nota).
	m.normal_enabled = not low
	if not low:
		m.normal_texture = load(base + "nor.jpg")
		m.roughness_texture = load(base + "arm.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0 if not low else 0.85
	m.metallic_specular = 0.3
	var sc: float = SURFACES[surface][1]
	m.uv1_scale = Vector3(sc, sc, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if low else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
