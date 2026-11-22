class_name TeenCharacter
extends Node3D
## Personagem do jogo: a skin "teen_01" (do projeto Rua 10, rigada no Mixamo)
## com idle/andar do Mixamo e IK nos braços para segurar a linha e a lata.
##
## Otimização: uma malha, textura limitada a 1024 px no import, animações em
## loop com trilha do quadril "no lugar", malha corrigida compartilhada entre
## instâncias, sombras só do corpo. Em primeira pessoa a cabeça é escondida.

const MODEL_PATH := "res://assets/characters/teen_01/teen_01.fbx"
const ANIM_PATHS := {
	&"idle": "res://assets/animations/mixamo/Breathing Idle.fbx",
	&"walk": "res://assets/animations/mixamo/Walking.fbx",
	&"back": "res://assets/animations/mixamo/Run Backward.fbx",
}
const TARGET_HEIGHT := 1.64
const HIPS_TRACK := "%GeneralSkeleton:Hips"
const WALK_ANIM_SPEED := 1.25

static var _mesh_cache: Dictionary = {}
static var _lib_cache: AnimationLibrary

@export var first_person: bool = false:
	set(v):
		first_person = v
		if _ik:
			_ik.hide_head = v

## Entradas (mundo).
var right_hand_target := Vector3.ZERO
var line_tension: float = 0.0
## m/s da lata (+ enrolando, − soltando).
var reel_speed: float = 0.0

var model: Node3D
var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var anim: AnimationPlayer
var eye_height: float = 1.55
var lata: Node3D

var _ik: ArmIK
var _speed: float = 0.0
var _current: StringName = &""
var _spin: float = 0.0
var _short_line: MeshInstance3D
var _ok: bool = false


func _ready() -> void:
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_warning("TeenCharacter: skin não encontrada, usando corpo simples.")
		_build_fallback()
	else:
		_build_model(scene)
	_build_lata()


func _build_model(scene: PackedScene) -> void:
	model = scene.instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI  # Mixamo olha para +Z; o jogo usa −Z
	add_child(model)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		var found := model.find_children("*", "Skeleton3D", true, false)
		if found.size() > 0:
			skeleton = found[0] as Skeleton3D
	if skeleton == null:
		push_warning("TeenCharacter: esqueleto não encontrado.")
		return
	body_mesh = _find_body_mesh()
	_fix_rest_offset()
	var height := body_mesh.get_aabb().size.y if body_mesh else 1.8
	model.scale = Vector3.ONE * (TARGET_HEIGHT / maxf(height, 0.1))
	var hips := skeleton.find_bone("Hips")
	if hips >= 0:
		skeleton.motion_scale = maxf(skeleton.get_bone_global_rest(hips).origin.y, 0.1)
	for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	model.add_child(anim)
	anim.add_animation_library(&"", _library())
	_play(&"idle")

	_ik = ArmIK.new()
	_ik.name = "ArmIK"
	skeleton.add_child(_ik)
	_ik.setup(skeleton)
	_ik.hide_head = first_person

	var head := skeleton.find_bone("Head")
	if head >= 0:
		eye_height = (skeleton.get_bone_global_rest(head).origin.y * model.scale.y) + 0.07
	_ok = true


## Animações compartilhadas entre todos os personagens (carregadas uma vez).
static func _library() -> AnimationLibrary:
	if _lib_cache:
		return _lib_cache
	_lib_cache = AnimationLibrary.new()
	for key: StringName in ANIM_PATHS:
		var path: String = ANIM_PATHS[key]
		var a := _extract_animation(path)
		if a:
			_lib_cache.add_animation(key, a)
	return _lib_cache


static func _extract_animation(path: String) -> Animation:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("TeenCharacter: animação não encontrada: " + path)
		return null
	var inst := scene.instantiate()
	var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var result: Animation = null
	if player and player.get_animation_list().size() > 0:
		var src := player.get_animation(player.get_animation_list()[0])
		result = src.duplicate(true) as Animation
		for ti in range(result.get_track_count() - 1, -1, -1):
			if not String(result.track_get_path(ti)).begins_with("%GeneralSkeleton:"):
				result.remove_track(ti)
		# No lugar: quem move o corpo é a física do jogador.
		var tr := result.find_track(NodePath(HIPS_TRACK), Animation.TYPE_POSITION_3D)
		if tr >= 0 and result.track_get_key_count(tr) > 0:
			var first: Vector3 = result.track_get_key_value(tr, 0)
			for k in result.track_get_key_count(tr):
				var v: Vector3 = result.track_get_key_value(tr, k)
				result.track_set_key_value(tr, k, Vector3(first.x, v.y, first.z))
		result.loop_mode = Animation.LOOP_LINEAR
	inst.free()
	return result


func _play(name_: StringName) -> void:
	if anim == null or _current == name_ or not anim.has_animation(name_):
		return
	_current = name_
	anim.play(name_, 0.3)


## Velocidade horizontal do corpo (m/s) → idle/andar.
func set_locomotion(speed: float) -> void:
	_speed = speed


func _process(delta: float) -> void:
	if anim:
		if _speed > 0.25:
			_play(&"walk")
			anim.speed_scale = clampf(_speed / WALK_ANIM_SPEED, 0.5, 1.6)
		else:
			_play(&"idle")
			anim.speed_scale = 1.0
	var gt := global_transform
	var fwd := -gt.basis.z
	var right := gt.basis.x
	# Lata na mão esquerda, na frente da barriga, inclinada para a pipa.
	var lata_pos := gt.origin + Vector3.UP * 1.02 + fwd * 0.3 - right * 0.13
	if lata:
		_spin += reel_speed / 0.06 * delta
		var to_hand := (right_hand_target - lata_pos)
		var axis := to_hand.normalized() if to_hand.length() > 0.05 else fwd
		lata.global_transform = Transform3D(Basis(_arc_q(Vector3.UP, axis)) * Basis(Vector3.UP, _spin), lata_pos)
		_update_short_line(lata_pos + axis * 0.06, right_hand_target)
	if _ik:
		var shoulder_h := Vector3.UP * 1.35
		# O alvo da IK é o punho: recua ~8 cm para a PALMA ficar sobre a linha.
		var shoulder := gt.origin + shoulder_h + right * 0.18
		_ik.right_target = right_hand_target - (right_hand_target - shoulder).normalized() * 0.08
		_ik.left_target = lata_pos - right * 0.02 - fwd * 0.03
		_ik.right_pole = gt.origin + shoulder_h + right * 0.6 - Vector3.UP * 0.5 + gt.basis.z * 0.3
		_ik.left_pole = gt.origin + shoulder_h - right * 0.6 - Vector3.UP * 0.5 + gt.basis.z * 0.3


func _build_lata() -> void:
	lata = Node3D.new()
	lata.name = "Lata"
	lata.top_level = true
	add_child(lata)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.78, 0.79, 0.81)
	metal.metallic = 0.8
	metal.roughness = 0.35
	_cyl(lata, 0.05, 0.11, metal, 0.0)
	var label := StandardMaterial3D.new()
	label.albedo_color = Color(0.86, 0.22, 0.16)
	_cyl(lata, 0.0505, 0.025, label, -0.04)
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.95, 0.93, 0.86)
	_cyl(lata, 0.06, 0.07, wrap, 0.012)
	_short_line = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0015, 0.0015, 1.0)
	_short_line.mesh = bm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.95, 0.93, 0.86)
	_short_line.material_override = lm
	_short_line.top_level = true
	_short_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_short_line)


func _cyl(parent: Node3D, r: float, h: float, mat: Material, y: float) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	mi.position = Vector3(0, y, 0)
	parent.add_child(mi)


func _update_short_line(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	_short_line.global_transform = Transform3D(Basis.looking_at(d, up) * Basis.from_scale(Vector3(1, 1, l)), (a + b) * 0.5)


static func _arc_q(from: Vector3, to: Vector3) -> Quaternion:
	return ArmIK._arc(from.normalized(), to.normalized())


func _find_body_mesh() -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_size := 0
	for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null and m.skin != null and m.mesh.surface_get_array_len(0) > best_size:
			best_size = m.mesh.surface_get_array_len(0)
			best = m
	return best


## Corrige pose de descanso deslocada da malha e braços em A-pose (como no Rua 10).
## A malha corrigida é guardada em cache e compartilhada entre os personagens.
func _fix_rest_offset() -> void:
	if body_mesh == null or body_mesh.skin == null:
		return
	var skin := body_mesh.skin
	for i in skin.get_bind_count():
		var bone := skeleton.find_bone(skin.get_bind_name(i))
		if bone < 0 or skeleton.get_bone_parent(bone) != -1:
			continue
		var mesh_space := skin.get_bind_pose(i).affine_inverse().origin
		var offset := mesh_space - skeleton.get_bone_global_rest(bone).origin
		if offset.length() > 0.01:
			var rest := skeleton.get_bone_rest(bone)
			rest.origin += offset
			skeleton.set_bone_rest(bone, rest)
			skeleton.set_bone_pose_position(bone, rest.origin)
		break
	if _mesh_cache.has("mesh"):
		body_mesh.mesh = _mesh_cache["mesh"]
		body_mesh.skin = _mesh_cache["skin"]
		return
	_fix_arm_binds()
	_mesh_cache["mesh"] = body_mesh.mesh
	_mesh_cache["skin"] = body_mesh.skin


func _fix_arm_binds() -> void:
	var skin := body_mesh.skin
	var mesh := body_mesh.mesh as ArrayMesh
	if mesh == null:
		return
	var xforms: Array[Transform3D] = []
	var has_diff := false
	for i in skin.get_bind_count():
		var bname := String(skin.get_bind_name(i))
		var bidx := skeleton.find_bone(bname)
		var is_arm := bname.contains("Arm") or bname.contains("Hand") or bname.contains("Index") \
			or bname.contains("Middle") or bname.contains("Ring") or bname.contains("Little") or bname.contains("Thumb")
		if bidx >= 0 and is_arm:
			var m := skeleton.get_bone_global_rest(bidx) * skin.get_bind_pose(i)
			xforms.append(m)
			if m.origin.length_squared() > 0.0004 or absf(m.basis.get_rotation_quaternion().w - 1.0) > 0.01:
				has_diff = true
		else:
			xforms.append(Transform3D.IDENTITY)
	if not has_diff:
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var has_n := normals.size() == verts.size()
	var per := bones.size() / maxi(verts.size(), 1)
	for i in verts.size():
		var v := verts[i]
		var n := normals[i] if has_n else Vector3.UP
		var vn := Vector3.ZERO
		var nn := Vector3.ZERO
		var tw := 0.0
		for j in per:
			var b := bones[i * per + j]
			var w := weights[i * per + j]
			if w > 0.0001 and b < xforms.size():
				var m: Transform3D = xforms[b]
				vn += (m * v) * w
				if has_n:
					nn += (m.basis * n) * w
				tw += w
		if tw > 0.0001:
			verts[i] = vn / tw
			if has_n and nn.length_squared() > 0.0001:
				normals[i] = nn.normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	if has_n:
		arrays[Mesh.ARRAY_NORMAL] = normals
	var mat := mesh.surface_get_material(0)
	var new_mesh := ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat:
		new_mesh.surface_set_material(0, mat)
	for s in range(1, mesh.get_surface_count()):
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		new_mesh.surface_set_material(s, mesh.surface_get_material(s))
	body_mesh.mesh = new_mesh
	var new_skin := skin.duplicate() as Skin
	for i in new_skin.get_bind_count():
		var bidx := skeleton.find_bone(new_skin.get_bind_name(i))
		if bidx >= 0:
			new_skin.set_bind_pose(i, skeleton.get_bone_global_rest(bidx).affine_inverse())
	body_mesh.skin = new_skin


func _build_fallback() -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.22
	cm.height = 1.6
	mi.mesh = cm
	mi.position.y = 0.8
	add_child(mi)
	eye_height = 1.55
