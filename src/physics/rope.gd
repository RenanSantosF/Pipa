class_name Rope
extends RefCounted
## Linha de pipa simulada como corrente de partículas XPBD ("small steps").
##
## - Cada segmento é um CABO: só resiste à tração (frouxo não empurra), com a
##   elasticidade real da linha (compliance = comprimento / EA).
## - Arrasto do vento por segmento (componente normal, cilindro Cd≈1,1) + peso:
##   é isso que faz a linha "fazer barriga" a favor do vento e cair quando frouxa.
## - Nó 0 = mão (cinemático). O último segmento liga ao cabresto da pipa (corpo
##   rígido), ou fica solto quando a linha foi cortada.
## - A linha entra/sai pela mão: o primeiro segmento cresce/encolhe e nós são
##   inseridos/removidos perto da mão, preservando o MATERIAL ao longo da linha.
##   s = coordenada de material (metros a partir da pipa), usada no desgaste.

const RHO := 1.225
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const CD_NORMAL := 1.1
## Multiplicador do arrasto do vento na linha. Era 2,2 (barriga exagerada para o
## visual); na física real é 1: com 2,2 a linha comprida engolia o tranco da mão e a
## pipa voava baixa e instável a 60 m (laboratório, v0.19).
static var LINE_BELLY := 1.0
const CF_TANGENT := 0.02

var type: LineType
## Varreduras do solver por subpasso (alternando o sentido).
var iterations: int = 1
var pos: PackedVector3Array = PackedVector3Array()
var prev: PackedVector3Array = PackedVector3Array()
var vel: PackedVector3Array = PackedVector3Array()
var acc: PackedVector3Array = PackedVector3Array()
var inv_mass: PackedFloat32Array = PackedFloat32Array()
var rest: PackedFloat32Array = PackedFloat32Array()
var lam: PackedFloat32Array = PackedFloat32Array()
## Coordenada de material de cada nó (m a partir da ponta da pipa).
var mat_s: PackedFloat32Array = PackedFloat32Array()
## Nós presos em obstáculos (galho, poste, fio): a linha desvia ali e desliza com atrito.
var pinned: PackedByteArray = PackedByteArray()
var pin_pos: PackedVector3Array = PackedVector3Array()
var pin_mu: PackedFloat32Array = PackedFloat32Array()
var pin_break: PackedFloat32Array = PackedFloat32Array()
var pin_obstacle: PackedInt32Array = PackedInt32Array()
## Contato com obstáculo (nó deslizante): normal do lado da superfície e tempo de aperto.
var c_normal: PackedVector3Array = PackedVector3Array()
var c_hold: PackedFloat32Array = PackedFloat32Array()
## Obstáculos (para a restrição de contato por subpasso).
var obstacles: WorldObstacles = null
## Posições no começo do quadro (detecção contínua contra obstáculos finos).
var frame_pos: PackedVector3Array = PackedVector3Array()
var frame_end := Vector3.ZERO
## Tensão de cada segmento no último tick (N).
var seg_tension: PackedFloat32Array = PackedFloat32Array()
var _lam_sum: PackedFloat32Array = PackedFloat32Array()

## Dono (instance id da KiteRig): o corpo do próprio vizinho não segura a linha dele.
var owner_id: int = 0
## Corpo preso na ponta (pipa) ou null.
var end_body: KiteRigidBody = null
var end_local := Vector3.ZERO
## Cabresto de linha (nó + 2 pernas): com ele, end_local é o NÓ, que escorrega nas
## pernas conforme a linha puxa (Bridle.update a cada subpasso).
var bridle: Bridle = null
## Ponta da linha (nó) no começo do subpasso, antes da pipa andar e do nó escorregar
## no cabresto: o deslocamento real da ponta para a detecção contínua de cruzamento.
var end_prev_world := Vector3.ZERO
## Nó 0 preso à mão?
var hand_fixed: bool = true
var hand_position := Vector3.ZERO
var _hand_from := Vector3.ZERO
## Restrição de alcance mão→pipa (comprimento total da linha) e seu multiplicador.
var _rest_total := 0.0
var _lam_tether := 0.0
var _tether_ok := true
var _hand_k := 0
var _hand_subs := 1

var segment_target: float = 3.0
var max_nodes: int = 40
var min_nodes: int = 4

## Tensões medidas no último tick (N).
var tension_hand: float = 0.0
var tension_end: float = 0.0
var _lam_hand_sum: float = 0.0
var _lam_end_sum: float = 0.0
var _substeps_done: int = 0


func _init(line_type: LineType) -> void:
	type = line_type
	iterations = GameConfig.rope_iterations()


func node_count() -> int:
	return pos.size()


func segment_count() -> int:
	return pos.size() if end_body != null else pos.size() - 1


func end_point() -> Vector3:
	return end_body.world_point(end_local) if end_body != null else pos[pos.size() - 1]


func length() -> float:
	var total := 0.0
	for r in rest:
		total += r
	return total


## Cria a linha reta de `a` (mão) até a pipa, com o comprimento total dado.
func setup(a: Vector3, body: KiteRigidBody, local_anchor: Vector3, total_length: float) -> void:
	end_body = body
	end_local = local_anchor
	hand_position = a
	var b := end_point()
	var n := clampi(int(round(total_length / segment_target)), min_nodes, max_nodes)
	var seg := total_length / float(n)
	pos.resize(n)
	rest.resize(n)
	for i in n:
		pos[i] = a.lerp(b, float(i) / float(n))
		rest[i] = seg
	prev = pos.duplicate()
	vel.resize(n)
	vel.fill(Vector3.ZERO)
	_reset_pins(n)
	_rebuild_masses()


func _reset_pins(n: int) -> void:
	pinned.resize(n)
	pinned.fill(0)
	pin_pos.resize(n)
	pin_mu.resize(n)
	pin_break.resize(n)
	pin_obstacle.resize(n)
	pin_obstacle.fill(-1)
	c_normal.resize(n)
	c_normal.fill(Vector3.ZERO)
	c_hold.resize(n)
	c_hold.fill(0.0)


func pin_count() -> int:
	var c := 0
	for v in pinned:
		c += v
	return c


func contact_count() -> int:
	var c := 0
	for v in pin_obstacle:
		if v >= 0:
			c += 1
	return c


## Marca o nó i como nó de contato (deslizante) com o obstáculo idx.
func set_contact(i: int, idx: int, normal: Vector3) -> void:
	pin_obstacle[i] = idx
	c_normal[i] = normal
	c_hold[i] = 0.0


func clear_contact(i: int) -> void:
	var was := pinned[i] == 1
	pinned[i] = 0
	pin_obstacle[i] = -1
	c_hold[i] = 0.0
	if was:
		_rebuild_masses()


## Guarda as posições do começo do quadro (antes dos subpassos).
## Pontos de contato com outra linha neste tick (trecho, t): o desenho passa por
## eles em linha reta (a curva suave não pode "furar" a outra linha).
var render_kinks: PackedVector2Array = PackedVector2Array()


func add_render_kink(seg: int, t: float) -> void:
	render_kinks.append(Vector2(float(seg), t))


func snapshot_frame() -> void:
	render_kinks.resize(0)
	frame_pos = pos.duplicate()
	frame_end = end_point()
	# A mão anda suave DENTRO do tick (subpasso a subpasso), não aos saltos: com a
	# física a 30 Hz um salto de 20 cm num subpasso só era absorvido pelos nós leves
	# da linha e o tranco não chegava na pipa.
	_hand_from = pos[0] if pos.size() > 0 else hand_position
	_hand_k = 0
	_hand_subs = GameConfig.physics_substeps()
	_rest_total = 0.0
	for r in rest:
		_rest_total += r
	# Com a linha apoiada em fio/galho/telhado o caminho não é reto: a restrição de
	# alcance (distância reta mão→pipa) puxaria a pipa ATRAVÉS do obstáculo.
	_tether_ok = contact_count() == 0


## Insere um nó no índice i (entre i-1 e o antigo i). Mantém todos os arrays.
func insert_node(i: int, p: Vector3, v: Vector3, rest_before: float, rest_after: float) -> void:
	pos.insert(i, p)
	prev.insert(i, p - v / 600.0)
	vel.insert(i, v)
	pinned.insert(i, 0)
	pin_pos.insert(i, p)
	pin_mu.insert(i, 0.0)
	pin_break.insert(i, 0.0)
	pin_obstacle.insert(i, -1)
	c_normal.insert(i, Vector3.ZERO)
	c_hold.insert(i, 0.0)
	if frame_pos.size() == pos.size() - 1:
		frame_pos.insert(i, p)
	rest[i - 1] = rest_before
	rest.insert(i, rest_after)
	_rebuild_masses()


## Remove o nó i juntando os dois segmentos vizinhos.
func remove_node(i: int) -> void:
	if i <= 0 or i >= pos.size():
		return
	rest[i - 1] += rest[i] if i < rest.size() else 0.0
	if i < rest.size():
		rest.remove_at(i)
	pos.remove_at(i)
	prev.remove_at(i)
	vel.remove_at(i)
	pinned.remove_at(i)
	pin_pos.remove_at(i)
	pin_mu.remove_at(i)
	pin_break.remove_at(i)
	pin_obstacle.remove_at(i)
	c_normal.remove_at(i)
	c_hold.remove_at(i)
	if frame_pos.size() == pos.size() + 1:
		frame_pos.remove_at(i)
	_rebuild_masses()


func pin_node(i: int, where: Vector3, mu: float, break_force: float, obstacle: int) -> void:
	pinned[i] = 1
	pin_pos[i] = where
	pin_mu[i] = mu
	pin_break[i] = break_force
	pin_obstacle[i] = obstacle
	c_hold[i] = 0.0
	pos[i] = where
	prev[i] = where
	vel[i] = Vector3.ZERO
	_rebuild_masses()


## Solta o enrosco: o nó continua encostado (contato deslizante).
func unpin_node(i: int) -> void:
	pinned[i] = 0
	_rebuild_masses()


func _rebuild_masses() -> void:
	var n := pos.size()
	inv_mass.resize(n)
	acc.resize(n)
	lam.resize(segment_count())
	var seg_n := segment_count()
	for i in n:
		var l := 0.0
		if i < seg_n:
			l += rest[i] * 0.5
		if i > 0:
			l += rest[i - 1] * 0.5
		var m := maxf(type.mass_per_meter * l, 0.00005)
		inv_mass[i] = 1.0 / m
	if hand_fixed and n > 0:
		inv_mass[0] = 0.0
	if pinned.size() == n:
		for i in n:
			if pinned[i] == 1:
				inv_mass[i] = 0.0
	_update_material_coords()


func _update_material_coords() -> void:
	var n := pos.size()
	mat_s.resize(n)
	var seg_n := segment_count()
	var s := 0.0
	if seg_n < n:  # ponta solta: último nó é material s=0
		mat_s[n - 1] = 0.0
		for i in range(n - 2, -1, -1):
			s += rest[i]
			mat_s[i] = s
	else:
		for i in range(n - 1, -1, -1):
			s += rest[i]
			mat_s[i] = s


## Linha entrando (+) ou saindo (−) pela mão. Mantém o material do resto da linha.
func feed(delta_len: float) -> void:
	if pos.size() < 2 or not hand_fixed:
		return
	rest[0] = maxf(rest[0] + delta_len, 0.02)
	# Insere nós perto da mão quando o primeiro segmento fica longo.
	while rest[0] > segment_target * 1.5:
		if pos.size() >= max_nodes:
			_coarsen()
			continue
		var dir := pos[0] - pos[1]
		var dl := dir.length()
		dir = dir / dl if dl > 0.0001 else Vector3.UP
		var new_pos := pos[1] + dir * minf(segment_target, dl)
		insert_node(1, new_pos, vel[1], rest[0] - segment_target, segment_target)
	# Remove nós quando o primeiro segmento fica curto.
	# Recolhendo: o trecho junto da mão sai de qualquer contato (a mão puxa a linha
	# de cima do telhado/galho) e o nó é absorvido.
	while rest[0] < segment_target * 0.4 and pos.size() > min_nodes:
		if pin_obstacle[1] >= 0:
			clear_contact(1)
		remove_node(1)
	_update_material_coords()


## Junta nós alternados (linha muito comprida): dobra o tamanho do segmento.
func _coarsen() -> void:
	var i := 2
	while i < pos.size() - 1:
		if pinned[i] == 0 and pin_obstacle[i] < 0:
			remove_node(i)
		i += 1
	segment_target *= 2.0
	_rebuild_masses()


## Forças externas do tick (peso + arrasto aerodinâmico), aplicadas em todos os subpassos.
func compute_forces() -> void:
	var n := pos.size()
	for i in n:
		acc[i] = GRAVITY
	var seg_n := segment_count()
	var d := type.diameter
	for i in seg_n:
		var a := pos[i]
		var b := pos[i + 1] if i + 1 < n else end_point()
		var seg := b - a
		var l := seg.length()
		if l < 0.0001:
			continue
		var t := seg / l
		var vm := vel[i] if i + 1 >= n else (vel[i] + vel[i + 1]) * 0.5
		var vrel := Wind.sample((a + b) * 0.5) - vm
		var vt := t * vrel.dot(t)
		var vn := vrel - vt
		var f := vn * (0.5 * RHO * vn.length() * d * l * CD_NORMAL * LINE_BELLY)
		f += vt * (0.5 * RHO * vt.length() * PI * d * l * CF_TANGENT)
		acc[i] += f * (0.5 * inv_mass[i])
		if i + 1 < n:
			acc[i + 1] += f * (0.5 * inv_mass[i + 1])
	for i in n:
		var al := acc[i].length()
		if al > 300.0:
			acc[i] = acc[i] / al * 300.0
	_lam_hand_sum = 0.0
	_lam_end_sum = 0.0
	_lam_sum.resize(segment_count())
	_lam_sum.fill(0.0)
	_substeps_done = 0


func predict(h: float) -> void:
	var n := pos.size()
	for i in n:
		prev[i] = pos[i]
		if inv_mass[i] > 0.0:
			vel[i] += acc[i] * h
			pos[i] += vel[i] * h
	if hand_fixed and n > 0:
		_hand_k += 1
		var f := clampf(float(_hand_k) / float(maxi(_hand_subs, 1)), 0.0, 1.0)
		pos[0] = _hand_from.lerp(hand_position, f)
	for i in n:
		if pinned[i] == 1:
			pos[i] = pin_pos[i]
	if bridle != null and end_body != null and n > 0:
		end_local = bridle.update(pos[n - 1])
	lam.fill(0.0)
	_lam_tether = 0.0


func solve(h: float) -> void:
	var n := pos.size()
	var seg_n := segment_count()
	var inv_h2 := 1.0 / (h * h)
	var ea := type.axial_stiffness
	# Varredura mão→pipa e, com física mais lenta (30 Hz), também pipa→mão: os nós
	# da linha são muito mais leves que a pipa, e uma varredura só deixa o tranco da
	# mão "morrer" na linha (a linha estica em vez de puxar a pipa).
	for it in iterations:
		if it % 2 == 0:
			for i in seg_n:
				_solve_segment(i, n, inv_h2, ea)
		else:
			for i in range(seg_n - 1, -1, -1):
				_solve_segment(i, n, inv_h2, ea)
	# Alcance (long-range attachment): a pipa nunca fica mais longe da mão do que o
	# comprimento da linha (+ elasticidade). Os nós da linha são ~80× mais leves que
	# a pipa e o solver em cadeia converge devagar: sem isto a linha "esticava" 20–30%
	# num tranco e o puxão não chegava na pipa. A distância reta é sempre ≤ ao
	# caminho da linha, então isto só age com a linha esticada (nunca atrapalha
	# linha com barriga ou apoiada em fio/galho).
	if hand_fixed and end_body != null and n > 0 and _rest_total > 0.0 and _tether_ok:
		var r := end_body.q * end_local
		var d := end_body.x + r - pos[0]
		var l := d.length()
		var c := l - _rest_total
		if c > 0.0 and l > 0.00001:
			var nrm := d / l
			var w := end_body.inverse_mass_at(r, nrm)
			var alpha_t := _rest_total / ea * inv_h2
			var dl := (-c - alpha_t * _lam_tether) / (w + alpha_t)
			_lam_tether += dl
			end_body.apply_correction(r, nrm * dl)
	# Chão.
	for i in n:
		var p := pos[i]
		var gy := Ground.height_at(p.x, p.z) + 0.035
		if p.y < gy:
			p.y = gy
			pos[i] = p
			var pv := prev[i]
			prev[i] = Vector3(lerpf(pv.x, p.x, 0.3), pv.y, lerpf(pv.z, p.z, 0.3))
	if seg_n > 0:
		_lam_hand_sum += lam[0] + _lam_tether
		_lam_end_sum += lam[seg_n - 1] + _lam_tether
	if obstacles != null:
		obstacles.solve_contacts(self)
	if _lam_sum.size() != seg_n:
		_lam_sum.resize(seg_n)
		_lam_sum.fill(0.0)
	for i in seg_n:
		_lam_sum[i] += lam[i] + _lam_tether
	_substeps_done += 1


func _solve_segment(i: int, n: int, inv_h2: float, ea: float) -> void:
	var alpha := rest[i] / ea * inv_h2
	if i + 1 < n:
		var d := pos[i + 1] - pos[i]
		var l := d.length()
		var c := l - rest[i]
		if c <= 0.0:
			return
		var wsum := inv_mass[i] + inv_mass[i + 1]
		if wsum <= 0.0:
			return
		var nrm := d / l
		var dl := (-c - alpha * lam[i]) / (wsum + alpha)
		lam[i] += dl
		pos[i] -= nrm * (dl * inv_mass[i])
		pos[i + 1] += nrm * (dl * inv_mass[i + 1])
	else:
		var r := end_body.q * end_local
		var a := end_body.x + r
		var d := a - pos[i]
		var l := d.length()
		var c := l - rest[i]
		if c <= 0.0 or l < 0.00001:
			return
		var nrm := d / l
		var wsum := inv_mass[i] + end_body.inverse_mass_at(r, nrm)
		var dl := (-c - alpha * lam[i]) / (wsum + alpha)
		lam[i] += dl
		pos[i] -= nrm * (dl * inv_mass[i])
		end_body.apply_correction(r, nrm * dl)


func finalize(h: float) -> void:
	var n := pos.size()
	var inv_h := 1.0 / h
	for i in n:
		vel[i] = (pos[i] - prev[i]) * (inv_h * 0.9995)


## Converte os multiplicadores acumulados em tensões (N).
func finish_tick(h: float) -> void:
	if _substeps_done == 0:
		return
	var k := -1.0 / (h * h * float(_substeps_done))
	tension_hand = maxf(_lam_hand_sum * k, 0.0)
	tension_end = maxf(_lam_end_sum * k, 0.0)
	if bridle != null:
		bridle.finish_tick(tension_end)
	seg_tension.resize(_lam_sum.size())
	for i in _lam_sum.size():
		seg_tension[i] = maxf(_lam_sum[i] * k, 0.0)


## Posição e velocidade do material da linha no parâmetro t do segmento i.
func segment_points(i: int) -> Array[Vector3]:
	var a := pos[i]
	var b := pos[i + 1] if i + 1 < pos.size() else end_point()
	return [a, b]


func material_at(i: int, t: float) -> float:
	var sa := mat_s[i]
	var sb := mat_s[i + 1] if i + 1 < pos.size() else 0.0
	return lerpf(sa, sb, t)


func velocity_at(i: int, t: float) -> Vector3:
	var va := vel[i]
	var vb: Vector3
	if i + 1 < pos.size():
		vb = vel[i + 1]
	else:
		vb = end_body.point_velocity(end_body.q * end_local) if end_body != null else va
	return va.lerp(vb, t)


## Corta a linha na coordenada de material s_cut.
## Esta linha fica com o lado da mão (ponta solta); retorna a linha do lado da pipa.
func split_at(s_cut: float) -> Rope:
	var n := pos.size()
	var seg_n := segment_count()
	var k := -1
	for i in seg_n:
		var sb := mat_s[i + 1] if i + 1 < n else 0.0
		if mat_s[i] >= s_cut and sb <= s_cut:
			k = i
			break
	if k < 0:
		k = seg_n - 1
	var sa := mat_s[k]
	var sb2 := mat_s[k + 1] if k + 1 < n else 0.0
	var t := clampf((sa - s_cut) / maxf(sa - sb2, 0.0001), 0.0, 1.0)
	var pts := segment_points(k)
	var cut_pos := pts[0].lerp(pts[1], t)
	var cut_vel := velocity_at(k, t)

	var kite_side := Rope.new(type)
	kite_side.hand_fixed = false
	kite_side.end_body = end_body
	kite_side.end_local = end_local
	kite_side.bridle = bridle
	kite_side.segment_target = segment_target
	kite_side.pos.append(cut_pos)
	kite_side.vel.append(cut_vel)
	kite_side.rest.append(rest[k] * (1.0 - t))
	for i in range(k + 1, n):
		kite_side.pos.append(pos[i])
		kite_side.vel.append(vel[i])
		if i < seg_n:
			kite_side.rest.append(rest[i])
	kite_side.prev = kite_side.pos.duplicate()
	kite_side._reset_pins(kite_side.pos.size())
	kite_side._rebuild_masses()

	# Este lado: nós 0..k + ponto do corte, ponta solta.
	pos.resize(k + 1)
	vel.resize(k + 1)
	pos.append(cut_pos)
	vel.append(cut_vel)
	var new_rest := PackedFloat32Array()
	for i in k:
		new_rest.append(rest[i])
	new_rest.append(maxf(rest[k] * t, 0.02))
	rest = new_rest
	end_body = null
	bridle = null
	prev = pos.duplicate()
	var old_pinned := pinned.duplicate()
	var old_pp := pin_pos.duplicate()
	var old_mu := pin_mu.duplicate()
	var old_br := pin_break.duplicate()
	var old_ob := pin_obstacle.duplicate()
	var old_cn := c_normal.duplicate()
	var old_ch := c_hold.duplicate()
	_reset_pins(pos.size())
	frame_pos = PackedVector3Array()
	for i in mini(k + 1, old_pinned.size()):
		pinned[i] = old_pinned[i]
		pin_pos[i] = old_pp[i]
		pin_mu[i] = old_mu[i]
		pin_break[i] = old_br[i]
		pin_obstacle[i] = old_ob[i]
		c_normal[i] = old_cn[i]
		c_hold[i] = old_ch[i]
	_rebuild_masses()
	return kite_side
