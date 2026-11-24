class_name TreeBuilder
extends RefCounted
## Árvores urbanas brasileiras geradas por ramificação (docs/REVISAO_V5.md §6):
##   tronco afunilado e levemente torto, base alargada e caiada (cal branca, como
##   nas calçadas), 3–6 galhos primários na forquilha, 2–3 secundários em cada um,
##   e a copa feita de aglomerados de folhas nas pontas dos galhos (volume real,
##   mais escura por dentro e embaixo).
## Tamanhos P/M/G: 5–7 m, 8–11 m, 12–15 m. Os galhos viram cápsulas de colisão
## (é neles que a linha enrosca); a folhagem é volume poroso.

const HEIGHTS := [[5.0, 7.0], [8.0, 11.0], [12.0, 15.0]]
const CAL := Color(0.93, 0.93, 0.9)
const CURB := Color(0.72, 0.71, 0.68)

## forquilha (fração da altura), nº de primários, elevação dos primários (graus),
## largura da copa, folhagem, tom, probabilidade de tamanho [P, M, G].
const SPECIES := {
	"mangueira": {"fork": 0.26, "prim": [4, 6], "el": [28.0, 52.0], "crown": 1.0, "leaf": "mango", "tint": Color(0.78, 0.9, 0.8), "size": [0.15, 0.45, 0.4]},
	"sibipiruna": {"fork": 0.3, "prim": [4, 6], "el": [18.0, 36.0], "crown": 1.2, "leaf": "mango", "tint": Color(1.0, 1.0, 0.9), "size": [0.2, 0.5, 0.3]},
	"oiti": {"fork": 0.22, "prim": [5, 6], "el": [32.0, 58.0], "crown": 0.95, "leaf": "mango", "tint": Color(0.72, 0.84, 0.72), "size": [0.35, 0.5, 0.15]},
	"ipe_amarelo": {"fork": 0.34, "prim": [3, 4], "el": [40.0, 64.0], "crown": 0.85, "leaf": "ipe_amarelo", "tint": Color(1, 1, 1), "size": [0.3, 0.5, 0.2]},
	"ipe_rosa": {"fork": 0.34, "prim": [3, 4], "el": [40.0, 64.0], "crown": 0.85, "leaf": "ipe_rosa", "tint": Color(1, 1, 1), "size": [0.3, 0.5, 0.2]},
}

var _sb: StreetBuilder
var _rng: RandomNumberGenerator


func _init(sb: StreetBuilder, rng: RandomNumberGenerator) -> void:
	_sb = sb
	_rng = rng


func _pick_size(weights: Array) -> int:
	var r := _rng.randf()
	var acc := 0.0
	for i in 3:
		acc += float(weights[i])
		if r < acc:
			return i
	return 2


## Planta uma árvore. size_class −1 = sorteia pela espécie. Retorna a altura.
func build(base: Vector3, species: String, size_class: int = -1, street: bool = true) -> float:
	var sp: Dictionary = SPECIES.get(species, SPECIES["mangueira"])
	var sc := size_class if size_class >= 0 else _pick_size(sp["size"])
	var hr: Array = HEIGHTS[sc]
	var h := _rng.randf_range(hr[0], hr[1])
	var bark := _sb.batch_for(base.z, "bark")
	var plain := _sb.batch_for(base.z, "plain")
	var fb := _sb.foliage_batch(base.z, sp["leaf"])
	var up := Vector3.UP
	var fork_h: float = h * float(sp["fork"]) * _rng.randf_range(0.85, 1.15)
	fork_h = clampf(fork_h, 1.9, 4.5)
	var r0 := clampf(h * 0.021, 0.1, 0.34)
	var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * h * _rng.randf_range(0.0, 0.035)
	var phase := _rng.randf() * TAU

	# Tronco: base alargada (raízes), meio, forquilha — levemente torto.
	var p_flare := base + up * 0.35
	var p_mid := base + up * (fork_h * 0.55) + lean * 0.45 + Vector3(_rng.randf_range(-0.06, 0.06), 0, _rng.randf_range(-0.06, 0.06))
	var p_fork := base + up * fork_h + lean
	bark.add_frustum(base + Vector3.DOWN * 0.05, p_flare, r0 * 1.45, r0 * 1.05, 8, Color.WHITE)
	bark.add_frustum(p_flare, p_mid, r0 * 1.05, r0 * 0.88, 8, Color.WHITE)
	bark.add_frustum(p_mid, p_fork, r0 * 0.88, r0 * 0.74, 8, Color.WHITE)
	if street:
		# Caiação (cal) no pé da árvore + canteiro na calçada.
		plain.add_frustum(base + Vector3.DOWN * 0.04, p_flare, r0 * 1.47 + 0.006, r0 * 1.07 + 0.006, 8, CAL)
		plain.add_frustum(p_flare, base.lerp(p_mid, 0.9 / maxf(fork_h * 0.55, 1.0)), r0 * 1.07 + 0.006, r0 * 1.0 + 0.006, 8, CAL)
		var cs := 0.55
		for k in 4:
			var ang := PI * 0.5 * float(k)
			var c := base + Vector3(cos(ang), 0.0, sin(ang)) * cs + up * 0.05
			var xf := Transform3D(Basis(up, ang), c)
			plain.add_box(xf, Vector3(0.07, 0.1, cs * 2.0 + 0.07), CURB)
	_sb.add_collider(Transform3D(Basis.IDENTITY, base + up * (fork_h * 0.5)), Vector3(r0 * 2.0, fork_h, r0 * 2.0))
	_sb.obstacles.add_capsule(base, p_fork, r0, "árvore")

	# Galhos primários e secundários; aglomerados de folhas nas pontas.
	var crown_r := (h - fork_h) * 0.62 * float(sp["crown"])
	var crown_top := base.y + h
	var tint: Color = sp["tint"]
	var n_p := _rng.randi_range(sp["prim"][0], sp["prim"][1])
	var az0 := _rng.randf() * TAU
	for k in n_p:
		var az := az0 + TAU * float(k) / float(n_p) + _rng.randf_range(-0.35, 0.35)
		var el := deg_to_rad(_rng.randf_range(sp["el"][0], sp["el"][1]))
		var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var l1 := crown_r * _rng.randf_range(0.75, 1.0) / maxf(cos(el), 0.45)
		l1 = minf(l1, (h - fork_h) * 0.95)
		var r1 := r0 * _rng.randf_range(0.5, 0.62)
		var mid := p_fork + dir * (l1 * 0.5)
		var dir2 := (dir + up * _rng.randf_range(0.15, 0.4)).normalized()
		var tip := mid + dir2 * (l1 * 0.5)
		tip.y = minf(tip.y, crown_top - crown_r * 0.35)
		bark.add_frustum(p_fork, mid, r1, r1 * 0.78, 6, Color.WHITE)
		bark.add_frustum(mid, tip, r1 * 0.78, r1 * 0.5, 6, Color.WHITE)
		_sb.obstacles.add_capsule(p_fork, mid, r1, "árvore")
		_sb.obstacles.add_capsule(mid, tip, r1 * 0.78, "galho" if r1 * 0.78 < 0.07 else "árvore")
		_cluster(fb, tip + dir2 * 0.25, crown_r * _rng.randf_range(0.36, 0.5), tint, base, fork_h, h, phase)
		var n_s := _rng.randi_range(2, 3)
		for j in n_s:
			var from := p_fork.lerp(tip, _rng.randf_range(0.45, 0.85))
			var sd := dir2.rotated(up, _rng.randf_range(0.45, 0.95) * (1.0 if j % 2 == 0 else -1.0))
			sd = (sd + up * _rng.randf_range(0.1, 0.5)).normalized()
			var l2 := l1 * _rng.randf_range(0.38, 0.55)
			var s_tip := from + sd * l2
			s_tip.y = minf(s_tip.y, crown_top - crown_r * 0.3)
			var r2 := r1 * 0.45
			bark.add_frustum(from, s_tip, r2, r2 * 0.45, 5, Color.WHITE)
			_sb.obstacles.add_capsule(from, s_tip, r2, "galho")
			_cluster(fb, s_tip + sd * 0.2, crown_r * _rng.randf_range(0.3, 0.42), tint, base, fork_h, h, phase)
	# Miolo e topo da copa (preenche o volume).
	var cc := Vector3(p_fork.x, base.y + fork_h + (h - fork_h) * 0.58, p_fork.z)
	_cluster(fb, cc, crown_r * 0.62, tint.darkened(0.12), base, fork_h, h, phase)
	_cluster(fb, Vector3(cc.x, crown_top - crown_r * 0.45, cc.z), crown_r * 0.48, tint, base, fork_h, h, phase)
	return h


## Aglomerado de folhas: cartões num elipsoide, voltados para fora, mais escuros
## embaixo e por dentro da copa (oclusão).
func _cluster(fb: MeshBatch, center: Vector3, r: float, tint: Color, base: Vector3, fork_h: float, h: float, phase: float) -> void:
	r = maxf(r, 0.6)
	var height_frac := clampf((center.y - base.y - fork_h) / maxf(h - fork_h, 0.5), 0.0, 1.0)
	var col := tint.darkened(0.28 * (1.0 - height_frac))
	# Menos cartões (maiores) no celular: mesma silhueta, bem menos sobreposição.
	var dens := GameConfig.foliage_density()
	var count := clampi(int(r * r * 8.0 * dens), 4, 34)
	var grow := 1.0 / sqrt(maxf(dens, 0.2)) * 0.85 + 0.15
	for _i in count:
		var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.55, 1.0), _rng.randf_range(-1, 1)).normalized()
		var depth := _rng.randf_range(0.3, 1.0)
		var pos := center + d * Vector3(r, r * 0.75, r) * depth
		var out := (pos - center).normalized()
		var right := out.cross(Vector3.UP)
		if right.length() < 0.1:
			right = Vector3.RIGHT
		right = right.normalized().rotated(out, _rng.randf_range(-0.8, 0.8))
		var upv := (right.cross(out).normalized() * -1.0 + out * 0.6).normalized()
		# Cartões do miolo mais escuros (luz que não chega lá dentro).
		var shade := col.darkened(0.22 * (1.0 - depth)).lightened(_rng.randf_range(0.0, 0.1))
		var sway := Vector2(0.12 + 0.25 * height_frac * depth, phase)
		fb.add_card(pos, right, upv, r * _rng.randf_range(0.75, 1.1) * grow, out, shade, sway)
	_sb.obstacles.add_canopy(center, r * 0.85)
