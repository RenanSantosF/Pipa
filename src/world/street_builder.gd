class_name StreetBuilder
extends Node3D
## Gera o bairro a partir de uma seed: rua, calçadas, lotes com casas, campinho,
## terreno baldio, postes com fios, árvores e quarteirões ao fundo.
##
## Toda a geometria estática é agrupada em poucas malhas por "fatia" (chunk) da rua,
## com cor por vértice e um único material → poucas draw calls e culling por fatia.
## Colisões: um único StaticBody3D com caixas.
## Etapa 2 substituirá as primitivas por modelos .glb mantendo esta organização.

@export var seed_value: int = 1987
@export var street_half_width: float = 3.5
@export var sidewalk_width: float = 2.0
@export var lot_depth: float = 15.0
@export var street_extent: float = 110.0
@export var chunk_size: float = 45.0

const ASPHALT := Color(0.25, 0.25, 0.26)
const SIDEWALK := Color(0.66, 0.64, 0.60)
const CURB := Color(0.78, 0.77, 0.74)
const GROUND := Color(0.47, 0.45, 0.33)
const DIRT := Color(0.62, 0.46, 0.32)
const GRASS := Color(0.42, 0.52, 0.26)
const POLE := Color(0.72, 0.72, 0.70)
const TRUNK := Color(0.38, 0.27, 0.18)
const LEAVES := [Color(0.27, 0.45, 0.18), Color(0.33, 0.50, 0.20), Color(0.22, 0.40, 0.17), Color(0.38, 0.52, 0.22)]

## Material das árvores (o World atualiza os parâmetros de vento).
var tree_material: ShaderMaterial

var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {}       # chunk -> MeshBatch (opaco)
var _tree_batches: Dictionary = {}  # chunk -> MeshBatch (copas, com UV de balanço)
var _body: StaticBody3D
var _opaque_material: StandardMaterial3D
var _wire_points: PackedVector3Array = PackedVector3Array()
var _houses: HouseBuilder


func _ready() -> void:
	build()


func build() -> void:
	_rng.seed = seed_value
	_houses = HouseBuilder.new(self, _rng)
	_body = StaticBody3D.new()
	_body.name = "WorldCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)

	_opaque_material = StandardMaterial3D.new()
	_opaque_material.vertex_color_use_as_albedo = true
	_opaque_material.vertex_color_is_srgb = true
	_opaque_material.roughness = 0.92
	_opaque_material.metallic_specular = 0.3
	tree_material = ShaderMaterial.new()
	tree_material.shader = load("res://src/world/tree_sway.gdshader")

	_build_ground()
	_build_street()
	_build_lots(1.0)
	_build_lots(-1.0)
	_build_poles()
	_build_sidewalk_trees()
	_build_background_blocks()
	_commit()


# --- API usada pelos construtores ---------------------------------------------

func batch_for(z: float) -> MeshBatch:
	var key := floori(z / chunk_size)
	if not _batches.has(key):
		_batches[key] = MeshBatch.new(false)
	return _batches[key]


func tree_batch_for(z: float) -> MeshBatch:
	var key := floori(z / chunk_size)
	if not _tree_batches.has(key):
		_tree_batches[key] = MeshBatch.new(true)
	return _tree_batches[key]


func add_collider(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)


## Árvore com tronco e copa de 2–3 "bolas". A copa balança no shader.
func add_tree(base: Vector3, canopy_radius: float, height: float) -> void:
	var b := batch_for(base.z)
	var trunk_h := height * 0.62
	b.add_cylinder(Transform3D(Basis.IDENTITY, base + Vector3(0, trunk_h * 0.5, 0)), 0.13, trunk_h, 7, TRUNK)
	add_collider(Transform3D(Basis.IDENTITY, base + Vector3(0, trunk_h * 0.5, 0)), Vector3(0.26, trunk_h, 0.26))
	var tb := tree_batch_for(base.z)
	var phase := _rng.randf() * TAU
	var leaves: Color = LEAVES[_rng.randi() % LEAVES.size()]
	var top := base + Vector3(0, height, 0)
	var lumps := 2 + _rng.randi() % 2
	for _i in lumps:
		var off := Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.4, 0.3), _rng.randf_range(-0.6, 0.6)) * canopy_radius
		var r := canopy_radius * _rng.randf_range(0.7, 1.0)
		var weight := 0.12 + 0.05 * height
		tb.add_sphere(top + off, Vector3(r, r * 0.8, r), 9, 6, leaves.darkened(_rng.randf() * 0.12), Vector2(weight, phase))
	add_collider(Transform3D(Basis.IDENTITY, top), Vector3.ONE * canopy_radius * 1.6)


# --- Partes do bairro -----------------------------------------------------------

func _build_ground() -> void:
	var b := batch_for(0.0)
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.01, 0)), Vector3(500, 0.02, 500), GROUND)
	add_collider(Transform3D(Basis.IDENTITY, Vector3(0, -1.0, 0)), Vector3(500, 2.0, 500))


func _build_street() -> void:
	var w := street_half_width
	var sw := sidewalk_width
	var z := -street_extent
	while z < street_extent:
		var seg_len := minf(chunk_size * 0.5, street_extent - z)
		var zc := z + seg_len * 0.5
		var b := batch_for(zc)
		b.add_box(_xf(Vector3(0, 0.01, zc)), Vector3(w * 2.0, 0.02, seg_len), ASPHALT)
		for s in [-1.0, 1.0]:
			var x := float(s) * (w + sw * 0.5)
			b.add_box(_xf(Vector3(x, 0.075, zc)), Vector3(sw, 0.15, seg_len), SIDEWALK)
			b.add_box(_xf(Vector3(float(s) * (w + 0.06), 0.08, zc)), Vector3(0.12, 0.16, seg_len), CURB)
			add_collider(_xf(Vector3(x, 0.075, zc)), Vector3(sw, 0.15, seg_len))
		z += seg_len
	# Remendos de asfalto e bueiros.
	for _i in 18:
		var pz := _rng.randf_range(-street_extent, street_extent)
		var px := _rng.randf_range(-w + 0.6, w - 0.6)
		var size := Vector3(_rng.randf_range(0.6, 2.2), 0.005, _rng.randf_range(0.6, 2.0))
		batch_for(pz).add_box(_xf(Vector3(px, 0.022, pz)), size, ASPHALT.darkened(_rng.randf_range(0.1, 0.25)))


func _build_lots(side: float) -> void:
	var front := street_half_width + sidewalk_width
	var z := -street_extent
	var special_done := false
	while z < street_extent - 6.0:
		# Campinho do lado esquerdo, perto de onde o jogador começa.
		if side < 0.0 and not special_done and z >= 6.0:
			_build_campinho(front, z, 34.0)
			z += 34.0
			special_done = true
			continue
		# Terreno baldio do lado direito.
		if side > 0.0 and not special_done and z >= -34.0:
			_build_vacant_lot(side, front, z, 12.0)
			z += 12.0
			special_done = true
			continue
		var width := minf(_rng.randf_range(9.0, 12.0), street_extent - z)
		if width < 6.0:
			break
		_houses.build(side, z, width, front, lot_depth)
		z += width


func _build_campinho(front: float, z0: float, length: float) -> void:
	var depth := 17.0
	var cx := -(front + depth * 0.5)
	var zc := z0 + length * 0.5
	var b := batch_for(zc)
	b.add_box(_xf(Vector3(cx, 0.012, zc)), Vector3(depth, 0.02, length), GRASS.darkened(0.1))
	b.add_box(_xf(Vector3(cx, 0.02, zc)), Vector3(depth - 3.0, 0.02, length - 4.0), DIRT)
	# Traves (golzinho) nas duas pontas.
	var white := Color(0.95, 0.95, 0.92)
	for gz in [z0 + 2.5, z0 + length - 2.5]:
		var g := float(gz)
		for dx in [-1.5, 1.5]:
			var post := Vector3(cx + float(dx), 1.0, g)
			b.add_cylinder(_xf(post), 0.05, 2.0, 6, white)
			add_collider(_xf(post), Vector3(0.1, 2.0, 0.1))
		b.add_box(_xf(Vector3(cx, 2.0, g)), Vector3(3.1, 0.1, 0.1), white)
	# Mureta baixa e quebrada na frente.
	var muro := Color(0.7, 0.68, 0.64)
	b.add_box(_xf(Vector3(-(front + 0.08), 0.4, z0 + 6.0)), Vector3(0.15, 0.8, 12.0), muro)
	add_collider(_xf(Vector3(-(front + 0.08), 0.4, z0 + 6.0)), Vector3(0.15, 0.8, 12.0))
	b.add_box(_xf(Vector3(-(front + 0.08), 0.4, z0 + length - 7.0)), Vector3(0.15, 0.8, 14.0), muro)
	add_collider(_xf(Vector3(-(front + 0.08), 0.4, z0 + length - 7.0)), Vector3(0.15, 0.8, 14.0))
	# Árvores em volta.
	for i in 5:
		var tz := z0 + 2.0 + (length - 4.0) * float(i) / 4.0
		add_tree(Vector3(-(front + depth - 1.5), 0, tz), _rng.randf_range(1.8, 2.6), _rng.randf_range(4.0, 5.5))


func _build_vacant_lot(side: float, front: float, z0: float, width: float) -> void:
	var zc := z0 + width * 0.5
	var b := batch_for(zc)
	b.add_box(_xf(Vector3(side * (front + lot_depth * 0.5), 0.012, zc)), Vector3(lot_depth, 0.02, width), GRASS.lightened(0.05))
	var tb := tree_batch_for(zc)
	for _i in 14:
		var p := Vector3(side * (front + _rng.randf_range(1.0, lot_depth - 1.0)), 0.2, _rng.randf_range(z0 + 0.5, z0 + width - 0.5))
		var r := _rng.randf_range(0.4, 0.9)
		var c: Color = LEAVES[_rng.randi() % LEAVES.size()]
		tb.add_sphere(p, Vector3(r, r * 0.7, r), 7, 4, c.lightened(0.12), Vector2(0.1, _rng.randf() * TAU))
	# Entulho.
	for _i in 4:
		var p := Vector3(side * (front + _rng.randf_range(2.0, lot_depth - 2.0)), 0.2, _rng.randf_range(z0 + 1.0, z0 + width - 1.0))
		b.add_box(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), Vector3(_rng.randf_range(0.5, 1.2), 0.4, _rng.randf_range(0.4, 0.9)), Color(0.6, 0.55, 0.5))
	add_tree(Vector3(side * (front + lot_depth - 3.0), 0, zc), 2.4, 5.0)


func _build_poles() -> void:
	var x := street_half_width + sidewalk_width - 0.45
	var spacing := 33.0
	var tops: Array[Vector3] = []
	var z := -street_extent + 6.0
	while z < street_extent:
		var b := batch_for(z)
		var base := Vector3(x, 0, z)
		b.add_cylinder(_xf(base + Vector3(0, 4.5, 0)), 0.13, 9.0, 8, POLE)
		add_collider(_xf(base + Vector3(0, 4.5, 0)), Vector3(0.26, 9.0, 0.26))
		b.add_box(_xf(base + Vector3(0, 8.4, 0)), Vector3(1.8, 0.1, 0.1), POLE.darkened(0.2))
		# Braço de luminária para a rua.
		b.add_box(_xf(base + Vector3(-0.9, 7.4, 0)), Vector3(1.8, 0.07, 0.07), POLE.darkened(0.3))
		b.add_box(_xf(base + Vector3(-1.75, 7.3, 0)), Vector3(0.45, 0.14, 0.22), Color(0.3, 0.3, 0.32))
		if _rng.randf() < 0.35:
			b.add_cylinder(_xf(base + Vector3(0.35, 7.6, 0)), 0.28, 0.8, 8, Color(0.45, 0.47, 0.5))
		tops.append(base)
		z += spacing
	for i in range(tops.size() - 1):
		var a := tops[i]
		var c := tops[i + 1]
		for dx in [-0.8, 0.0, 0.8]:
			_add_wire(a + Vector3(float(dx), 8.47, 0), c + Vector3(float(dx), 8.47, 0), 0.45)
		_add_wire(a + Vector3(0.14, 6.4, 0), c + Vector3(0.14, 6.4, 0), 0.6)
	# Ramais até algumas casas do outro lado da rua.
	for i in tops.size():
		if _rng.randf() < 0.6:
			var from := tops[i] + Vector3(-0.8, 8.47, 0)
			var to := Vector3(-(street_half_width + sidewalk_width + _rng.randf_range(3.5, 5.0)), 3.2, tops[i].z + _rng.randf_range(-4.0, 4.0))
			_add_wire(from, to, 0.5)


func _add_wire(a: Vector3, b: Vector3, sag: float) -> void:
	var segments := 10
	var prev := a
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		_wire_points.append(prev)
		_wire_points.append(p)
		prev = p


func _build_sidewalk_trees() -> void:
	for s in [-1.0, 1.0]:
		var z := -street_extent + _rng.randf_range(4.0, 12.0)
		while z < street_extent - 4.0:
			# Evita o campinho (que já tem árvores) e os postes.
			var near_pole := fmod(absf(z + street_extent - 6.0), 33.0) < 3.0
			if not near_pole:
				var x := float(s) * (street_half_width + sidewalk_width * 0.55)
				add_tree(Vector3(x, 0.15, z), _rng.randf_range(1.3, 1.9), _rng.randf_range(3.2, 4.2))
			z += _rng.randf_range(14.0, 26.0)


func _build_background_blocks() -> void:
	# Quarteirões atrás dos lotes (sem detalhe) — preenchem o horizonte.
	var inner := street_half_width + sidewalk_width + lot_depth + 4.0
	for s in [-1.0, 1.0]:
		var x := inner
		while x < 95.0:
			var z := -170.0
			while z < 170.0:
				if _rng.randf() < 0.8:
					_simple_house(Vector3(float(s) * (x + 5.0), 0, z + 5.0))
				z += 11.0
			x += 14.0
	# Casas no fim da rua (fecham a vista nas duas pontas).
	for zs in [-1.0, 1.0]:
		var z := float(zs) * (street_extent + 9.0)
		while absf(z) < 175.0:
			var x := -inner + 4.0
			while x < inner - 4.0:
				if _rng.randf() < 0.85:
					_simple_house(Vector3(x, 0, z))
				x += 11.0
			z += float(zs) * 13.0


func _simple_house(c: Vector3) -> void:
	var b := batch_for(c.z)
	var w := _rng.randf_range(7.0, 10.0)
	var d := _rng.randf_range(7.0, 9.0)
	var h := 2.9 if _rng.randf() < 0.7 else 5.8
	var color: Color = HouseBuilder.WALL_COLORS[_rng.randi() % HouseBuilder.WALL_COLORS.size()]
	color = color.darkened(_rng.randf_range(0.05, 0.2))
	b.add_box(_xf(c + Vector3(0, h * 0.5, 0)), Vector3(d, h, w), color)
	add_collider(_xf(c + Vector3(0, h * 0.5, 0)), Vector3(d, h, w))
	if _rng.randf() < 0.55:
		var roof: Color = HouseBuilder.ROOF_COLORS[_rng.randi() % HouseBuilder.ROOF_COLORS.size()]
		b.add_box(_xf(c + Vector3(0, h + 0.45, 0)), Vector3(d * 0.85, 0.9, w * 0.9), roof)
	else:
		b.add_cylinder(_xf(c + Vector3(d * 0.2, h + 0.45, w * 0.2)), 0.5, 0.9, 8, HouseBuilder.WATER_TANK)


func _commit() -> void:
	for key in _batches:
		var mesh := (_batches[key] as MeshBatch).commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d" % key
		mi.mesh = mesh
		mi.material_override = _opaque_material
		add_child(mi)
	for key in _tree_batches:
		var mesh := (_tree_batches[key] as MeshBatch).commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Trees_%d" % key
		mi.mesh = mesh
		mi.material_override = tree_material
		mi.extra_cull_margin = 1.0
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


static func _xf(origin: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin)
