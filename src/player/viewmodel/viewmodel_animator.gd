class_name ViewmodelAnimator
extends Node
## Animação procedural das mãos: puxada, soltar (lata gira, linha corre),
## recolher (mão gira em volta da lata), tremor com a tensão e atraso ao girar a câmera.
## Lê o ESTADO da linha (KiteLine), não a entrada — mostra o que acontece de fato.

var line: KiteLine
var kite: Node3D

var _vm: Viewmodel
var _right_offset := Vector3.ZERO
var _left_offset := Vector3.ZERO
var _sway := Vector3.ZERO
var _spin: float = 0.0
var _time: float = 0.0
var _prev_forward := Vector3.FORWARD
var _noise := FastNoiseLite.new()


func setup(vm: Viewmodel) -> void:
	_vm = vm
	_noise.frequency = 1.0
	var cam := _vm.get_parent() as Node3D
	if cam:
		_prev_forward = -cam.global_basis.z


func _process(delta: float) -> void:
	if _vm == null:
		return
	var cam := _vm.get_parent() as Node3D
	if cam == null:
		return
	_time += delta

	var pull_amount := 0.0
	var payout := 0.0
	var tension := 0.0
	var kite_dir := Vector3(0.0, 0.5, -1.0).normalized()
	if line:
		pull_amount = line.pull_offset / maxf(line.pull_stroke, 0.01)
		payout = line.payout_speed
		tension = line.tension
		if kite and not line.is_broken:
			var to_kite := kite.global_position - cam.global_position
			if to_kite.length() > 0.1:
				kite_dir = (cam.global_basis.inverse() * to_kite).normalized()
		_vm.set_spool_fill(1.0 - (line.length - line.min_length) / maxf(line.max_length - line.min_length, 1.0))
	var t_norm := clampf(tension / 12.0, 0.0, 1.0)

	# Mão direita
	var r_target := Vector3(0.02, -0.07, 0.2) * pull_amount
	r_target += kite_dir * (0.035 * t_norm)
	r_target += Vector3(_noise.get_noise_2d(_time * 30.0, 0.0), _noise.get_noise_2d(0.0, _time * 30.0), 0.0) * (0.008 * t_norm)
	if payout > 0.05:
		r_target += Vector3(0.0, 0.015, -0.03)
	elif payout < -0.05:
		var a := _time * 11.0
		r_target += Vector3(-0.1, -0.02, 0.0) + Vector3(cos(a), sin(a), 0.0) * 0.03
	_right_offset = _right_offset.lerp(r_target, 1.0 - exp(-14.0 * delta))
	_vm.right_hand.position = _vm.right_rest + _right_offset

	# Mão esquerda (lata)
	var l_target := kite_dir * (0.02 * t_norm) + Vector3(0.0, -0.02, 0.05) * pull_amount * 0.5
	_left_offset = _left_offset.lerp(l_target, 1.0 - exp(-10.0 * delta))
	_vm.left_hand.position = _vm.left_rest + _left_offset

	# Lata gira conforme a linha sai/entra (velocidade angular = v / r).
	_spin += payout / Viewmodel.SPOOL_RADIUS_FULL * delta
	_spin = wrapf(_spin, -TAU, TAU)
	_vm.set_spool_spin(_spin)

	# Atraso (sway) ao girar a câmera.
	var forward := -cam.global_basis.z
	var prev_local := cam.global_basis.inverse() * _prev_forward
	_prev_forward = forward
	var sway_target := Vector3(clampf(prev_local.x * 0.8, -0.04, 0.04), clampf(prev_local.y * 0.8, -0.04, 0.04), 0.0)
	_sway = _sway.lerp(sway_target, 1.0 - exp(-10.0 * delta))
	_vm.position = _sway

	_update_short_line(cam)


func _update_short_line(cam: Node3D) -> void:
	var a := _vm.can_exit.global_position
	var b := _vm.hand_anchor.global_position
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var up := cam.global_basis.y
	if absf((d / l).dot(up)) > 0.98:
		up = cam.global_basis.x
	_vm.short_line.global_transform = Transform3D(
		Basis.looking_at(d, up) * Basis.from_scale(Vector3(1.0, 1.0, l)), (a + b) * 0.5)
