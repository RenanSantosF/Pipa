class_name Viewmodel
extends Node3D
## Braços, mãos e lata de linha em primeira pessoa (espaço da câmera).
## Etapa 1: montados com primitivas. Para trocar por um modelo .glb no futuro,
## mantenha os nós públicos (right_hand, left_hand, hand_anchor, spool, can_exit).

const SKIN := Color(0.80, 0.58, 0.43)
const CAN_METAL := Color(0.78, 0.79, 0.81)
const CAN_LABEL := Color(0.86, 0.22, 0.16)
const LINE_COLOR := Color(0.96, 0.94, 0.87)
const SPOOL_RADIUS_FULL := 0.064
const SPOOL_RADIUS_EMPTY := 0.052

var right_hand: Node3D
var left_hand: Node3D
## Ponto de onde a linha sai, entre o polegar e o indicador da mão direita.
var hand_anchor: Node3D
## Lata (gira ao soltar/recolher).
var spool: Node3D
## Borda da lata de onde a linha sai (não gira).
var can_exit: Node3D
## Trecho de linha entre a lata e a mão direita.
var short_line: MeshInstance3D
var right_rest: Vector3 = Vector3(0.17, -0.19, -0.40)
var left_rest: Vector3 = Vector3(-0.19, -0.235, -0.40)

var _spool_base := Basis()
var _spool_wrap: MeshInstance3D
var _skin_mat: StandardMaterial3D

@onready var animator: ViewmodelAnimator = $Animator


func _ready() -> void:
	_build()
	animator.setup(self)


func set_spool_spin(angle: float) -> void:
	spool.basis = _spool_base * Basis(Vector3.UP, angle)


## 1 = lata cheia de linha, 0 = vazia.
func set_spool_fill(fraction: float) -> void:
	var r := lerpf(SPOOL_RADIUS_EMPTY, SPOOL_RADIUS_FULL, clampf(fraction, 0.0, 1.0))
	var s := r / SPOOL_RADIUS_FULL
	_spool_wrap.scale = Vector3(s, 1.0, s)


func _build() -> void:
	_skin_mat = _mat(SKIN, 0.75)

	# --- Mão direita (segura a linha) ---
	right_hand = Node3D.new()
	right_hand.name = "RightHand"
	right_hand.position = right_rest
	add_child(right_hand)
	_sphere(right_hand, Vector3.ZERO, 0.045, Vector3(1.0, 0.85, 1.25), _skin_mat)
	_capsule(right_hand, Vector3(-0.036, 0.018, -0.022), 0.012, 0.05, Vector3(0.3, 0.2, -1.0), _skin_mat)
	_capsule(right_hand, Vector3(0.07, -0.11, 0.16), 0.034, 0.36, Vector3(0.12, -0.2, 0.3), _skin_mat)
	hand_anchor = Node3D.new()
	hand_anchor.name = "HandAnchor"
	hand_anchor.position = Vector3(-0.012, 0.036, -0.03)
	right_hand.add_child(hand_anchor)

	# --- Mão esquerda (segura a lata) ---
	left_hand = Node3D.new()
	left_hand.name = "LeftHand"
	left_hand.position = left_rest
	add_child(left_hand)

	var axis := Vector3(0.25, 0.3, -1.0).normalized()  # eixo da lata, apontando para a frente
	_spool_base = Basis(Quaternion(Vector3.UP, axis))
	spool = Node3D.new()
	spool.name = "Spool"
	spool.position = Vector3(0.0, 0.045, -0.02)
	spool.basis = _spool_base
	left_hand.add_child(spool)

	var metal := _mat(CAN_METAL, 0.35)
	metal.metallic = 0.8
	_cylinder(spool, Vector3(0, 0, 0), 0.05, 0.11, metal)
	_cylinder(spool, Vector3(0, -0.04, 0), 0.0505, 0.025, _mat(CAN_LABEL, 0.6))
	_spool_wrap = _cylinder(spool, Vector3(0, 0.012, 0), SPOOL_RADIUS_FULL, 0.07, _mat(LINE_COLOR, 0.9))
	# Marca na linha enrolada para que a rotação seja visível.
	var knot := MeshInstance3D.new()
	var knot_mesh := BoxMesh.new()
	knot_mesh.size = Vector3(0.012, 0.06, 0.006)
	knot.mesh = knot_mesh
	knot.material_override = _mat(Color(0.3, 0.25, 0.2), 0.9)
	knot.position = Vector3(0.0, 0.0, 0.061)
	knot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spool_wrap.add_child(knot)

	can_exit = Node3D.new()
	can_exit.name = "CanExit"
	var up_on_can := _spool_base * Vector3.BACK
	can_exit.position = spool.position + axis * 0.05 + up_on_can.normalized() * -0.06
	left_hand.add_child(can_exit)

	_sphere(left_hand, Vector3(-0.025, -0.01, 0.03), 0.048, Vector3(1.1, 0.9, 1.3), _skin_mat)
	_capsule(left_hand, Vector3(-0.07, -0.12, 0.18), 0.034, 0.36, Vector3(-0.12, -0.2, 0.3), _skin_mat)

	# --- Linha entre a lata e a mão ---
	short_line = MeshInstance3D.new()
	short_line.name = "ShortLine"
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.0015, 0.0015, 1.0)
	short_line.mesh = line_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = LINE_COLOR
	short_line.material_override = line_mat
	short_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	short_line.top_level = true
	add_child(short_line)


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _setup_instance(mi: MeshInstance3D, parent: Node3D, pos: Vector3, mat: Material) -> void:
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _sphere(parent: Node3D, pos: Vector3, radius: float, scl: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	mi.mesh = m
	_setup_instance(mi, parent, pos, mat)
	mi.scale = scl
	return mi


func _capsule(parent: Node3D, pos: Vector3, radius: float, height: float, dir: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	mi.mesh = m
	_setup_instance(mi, parent, pos, mat)
	mi.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	return mi


func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 20
	m.rings = 1
	mi.mesh = m
	_setup_instance(mi, parent, pos, mat)
	return mi
