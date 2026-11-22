class_name ArmIK
extends SkeletonModifier3D
## IK analítica de dois ossos (braço + antebraço) para as duas mãos, aplicada
## DEPOIS da animação (idle/andar). A mão direita vai até o ponto da linha
## simulado pela física; a esquerda segura a lata. Também esconde a cabeça
## em primeira pessoa (a câmera fica dentro dela).

var right_target := Vector3.ZERO
var left_target := Vector3.ZERO
var right_pole := Vector3.ZERO
var left_pole := Vector3.ZERO
var right_weight: float = 1.0
var left_weight: float = 1.0
var hide_head: bool = false

var _ru: int = -1
var _rl: int = -1
var _rh: int = -1
var _lu: int = -1
var _ll: int = -1
var _lh: int = -1
var _head: int = -1


func setup(sk: Skeleton3D) -> void:
	_ru = sk.find_bone("RightUpperArm")
	_rl = sk.find_bone("RightLowerArm")
	_rh = sk.find_bone("RightHand")
	_lu = sk.find_bone("LeftUpperArm")
	_ll = sk.find_bone("LeftLowerArm")
	_lh = sk.find_bone("LeftHand")
	_head = sk.find_bone("Head")


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if hide_head and _head >= 0:
		sk.set_bone_pose_scale(_head, Vector3.ONE * 0.001)
	var inv := sk.global_transform.affine_inverse()
	if _ru >= 0 and _rl >= 0 and _rh >= 0 and right_weight > 0.0:
		_solve(sk, _ru, _rl, _rh, inv * right_target, inv * right_pole, right_weight)
	if _lu >= 0 and _ll >= 0 and _lh >= 0 and left_weight > 0.0:
		_solve(sk, _lu, _ll, _lh, inv * left_target, inv * left_pole, left_weight)


func _solve(sk: Skeleton3D, upper: int, lower: int, hand: int, target: Vector3, pole: Vector3, weight: float) -> void:
	var gu := sk.get_bone_global_pose(upper)
	var gl := sk.get_bone_global_pose(lower)
	var gh := sk.get_bone_global_pose(hand)
	var a := gu.origin
	var b := gl.origin
	var c := gh.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.0001 or l2 < 0.0001:
		return
	var orig_target := c
	target = orig_target.lerp(target, weight)
	var to_t := target - a
	var dist := clampf(to_t.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.999)
	var dir := to_t.normalized() if to_t.length() > 0.0001 else (c - a).normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var pole_dir := pole - a
	pole_dir = pole_dir - dir * pole_dir.dot(dir)
	if pole_dir.length() < 0.0001:
		pole_dir = (b - a) - dir * (b - a).dot(dir)
	pole_dir = pole_dir.normalized()
	var elbow := a + dir * (l1 * cos_a) + pole_dir * (l1 * sqrt(maxf(1.0 - cos_a * cos_a, 0.0)))
	var r1 := _arc((b - a).normalized(), (elbow - a).normalized())
	sk.set_bone_global_pose(upper, Transform3D(Basis(r1) * gu.basis, a))
	var gl2 := sk.get_bone_global_pose(lower)
	var gh2 := sk.get_bone_global_pose(hand)
	var reach := a + dir * dist
	var r2 := _arc((gh2.origin - gl2.origin).normalized(), (reach - gl2.origin).normalized())
	sk.set_bone_global_pose(lower, Transform3D(Basis(r2) * gl2.basis, gl2.origin))


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) > 0.99999 or from.length() < 0.5 or to.length() < 0.5:
		return Quaternion.IDENTITY
	if from.dot(to) < -0.9999:
		var axis := from.cross(Vector3.UP)
		if axis.length() < 0.01:
			axis = from.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)
