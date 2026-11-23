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
## Fechamento dos dedos (0 aberta … 1 fechada na linha/lata).
var right_curl: float = 1.0
var left_curl: float = 0.75
## Sentido da curvatura (ajustado olhando a renderização).
const CURL_SIGN := -1.0
const FINGERS := ["Index", "Middle", "Ring", "Little"]
const JOINTS := [["Proximal", 65.0], ["Intermediate", 80.0], ["Distal", 50.0]]
var _fingers: Dictionary = {}

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
	for side in ["Right", "Left"]:
		var list: Array = []
		for f in FINGERS:
			for j in JOINTS:
				list.append([sk.find_bone(side + f + j[0]), j[1]])
		_fingers[side] = [list, sk.find_bone(side + "IndexProximal"), sk.find_bone(side + "LittleProximal"),
			sk.find_bone(side + "ThumbProximal"), sk.find_bone(side + "ThumbDistal")]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var inv := sk.global_transform.affine_inverse()
	if _ru >= 0 and _rl >= 0 and _rh >= 0 and right_weight > 0.0:
		_solve(sk, _ru, _rl, _rh, inv * right_target, inv * right_pole, right_weight)
	if _lu >= 0 and _ll >= 0 and _lh >= 0 and left_weight > 0.0:
		_solve(sk, _lu, _ll, _lh, inv * left_target, inv * left_pole, left_weight)
	_curl(sk, "Right", right_curl, 1.0)
	_curl(sk, "Left", left_curl, 1.0)


## Dobra os dedos em torno do eixo dos nós dos dedos (indicador → mindinho).
func _curl(sk: Skeleton3D, side: String, amount: float, mirror: float) -> void:
	if not _fingers.has(side):
		return
	var data: Array = _fingers[side]
	var i1: int = data[1]
	var i5: int = data[2]
	if i1 < 0 or i5 < 0 or amount <= 0.0:
		return
	var axis := (sk.get_bone_global_pose(i5).origin - sk.get_bone_global_pose(i1).origin).normalized()
	if axis.length() < 0.5:
		return
	for entry in data[0]:
		var b: int = entry[0]
		if b < 0:
			continue
		var g := sk.get_bone_global_pose(b)
		var r := Basis(axis, deg_to_rad(float(entry[1])) * amount * CURL_SIGN * mirror)
		sk.set_bone_global_pose(b, Transform3D(r * g.basis, g.origin))
	# Polegar fecha por cima.
	for tb in [data[3], data[4]]:
		if tb >= 0:
			var gt := sk.get_bone_global_pose(tb)
			sk.set_bone_global_pose(tb, Transform3D(Basis(axis, deg_to_rad(25.0) * amount * CURL_SIGN * mirror) * gt.basis, gt.origin))


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
