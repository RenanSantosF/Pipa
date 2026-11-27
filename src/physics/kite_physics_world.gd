class_name KitePhysicsWorld
extends Node
## Roda a simulação de TODAS as pipas juntas, em subpassos XPBD, para que o
## cruzamento de linhas seja resolvido de forma estável.
##
## Ordem por tick: controladores escrevem as entradas (prioridade menor) →
## pre_frame (carretel, forças) → detecção de contatos → N subpassos
## [prever → restrições internas → contatos → velocidades] → desgaste/corte.

signal line_cut(winner: KiteRig, loser: KiteRig, position: Vector3)

## Tempo que uma pipa voada fica no mundo.
const LOOSE_LIFETIME := 45.0

var rigs: Array[KiteRig] = []
var combat := LineCombat.new()
## Enganches: aparar pipa voada; pegar/cortar rabiola.
var grabs := LineGrabs.new()
var frame_ms: float = 0.0
## Parte do quadro gasta com o cenário (contatos da linha com obstáculos).
var world_ms: float = 0.0
var obstacles: WorldObstacles
var _world_tick := 0


func _ready() -> void:
	process_physics_priority = 0


func register(rig: KiteRig) -> void:
	if not rigs.has(rig):
		rigs.append(rig)
		rig.line_cut.connect(_on_rig_cut)


func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_collect_new_rigs()
	# Corpo dos vizinhos como obstáculo para a linha (anda junto com eles).
	if obstacles != null:
		var feet: Array = []
		var owners: Array = []
		for n in get_tree().get_nodes_in_group(&"people"):
			feet.append((n as Node3D).global_position)
			var orig = n.get("rig")
			owners.append((orig as KiteRig).get_instance_id() if orig is KiteRig else 0)
		obstacles.set_people(feet, owners)
	var sub := GameConfig.physics_substeps()
	var h := dt / float(sub)
	for r in rigs:
		r.pre_frame(dt)
	combat.detect(rigs)
	grabs.detect(rigs)
	for _i in sub:
		var dbg_r: KiteRig = debug_rope_rig if is_instance_valid(debug_rope_rig) and debug_rope_rig.rope != null else null
		Rope.dbg_rope = dbg_r.rope if dbg_r else null
		var dbg0 := dbg_r.rope.pos.duplicate() if dbg_r else PackedVector3Array()
		for r in rigs:
			r.predict(h)
		if dbg_r:
			_dbg_phase("predict", dbg_r, dbg0)
		for r in rigs:
			r.solve(h)
			r.pushed_by_line = false
		if dbg_r:
			_dbg_phase("solve", dbg_r, dbg0)
		# Enganches antes do contato linha × linha: o contato tem a palavra final (um
		# enganche puxando a linha não pode arrastá-la através de outra linha).
		grabs.solve(h)
		combat.solve(h)
		if dbg_r:
			_dbg_phase("contato", dbg_r, dbg0)
		# O cenário é rígido: depois do empurra-empurra entre linhas, os nós apoiados
		# em fio/poste/telhado voltam para fora (uma linha não empurra a outra para
		# dentro da casa).
		if LineCombat.DEBUG_TRACE:
			for c in combat.contacts:
				if c.ia < c.a.rope.segment_count() and c.ib < c.b.rope.segment_count():
					var qa := c.a.rope.segment_points(c.ia)
					var qb := c.b.rope.segment_points(c.ib)
					print("TRACE   depois do contato sep=%.3f" % (qb[0].lerp(qb[1], c.tb) - qa[0].lerp(qa[1], c.ta)).dot(c.normal))
		for r in rigs:
			if r.rope != null and r.rope.obstacles != null and r.pushed_by_line:
				r.rope.obstacles.solve_contacts(r.rope)
			if r.rope != null and r.rope.obstacles != null:
				# Pipa do jogador (modelo de voo): também é sólida para o cenário depois
				# das restrições da linha.
				if r.flight != null and r.body != null and not r.snagged:
					var po := r.rope.obstacles.kite_push_out(r.body.x, r.flight.kite_radius())
					if po != r.body.x:
						r.body.x = po
				elif r.body != null and not r.snagged and not r.held:
					# Pipa física: sólida para o MESMO cenário da linha (casas, fios,
					# postes). Só com o colisor do Godot ela podia parar dentro da laje do
					# telhado que a linha enxerga — e a linha entrava junto com ela.
					var rad := maxf(r.profile.height * 0.32, 0.14)
					var po2 := r.rope.obstacles.kite_push_out(r.body.x, rad)
					if po2 != r.body.x:
						var nrm := (po2 - r.body.x).normalized()
						r.body.x = po2
						var vn := r.body.v.dot(nrm)
						if vn < 0.0:
							r.body.v -= nrm * vn
		if LineCombat.DEBUG_TRACE:
			for c in combat.contacts:
				if c.ia < c.a.rope.segment_count() and c.ib < c.b.rope.segment_count():
					var qa := c.a.rope.segment_points(c.ia)
					var qb := c.b.rope.segment_points(c.ib)
					print("TRACE   depois do cenário sep=%.3f" % (qb[0].lerp(qb[1], c.tb) - qa[0].lerp(qa[1], c.ta)).dot(c.normal))
		if dbg_r:
			_dbg_phase("cenário", dbg_r, dbg0)
		for r in rigs:
			r.finalize(h)
		if dbg_r:
			_dbg_phase("final", dbg_r, dbg0)
	combat.post_frame(dt, h, sub)
	# A linha que encostou na pipa neste tick já laça agora (não no tick seguinte).
	combat.detect_kites(rigs)
	var collected := grabs.post_frame(dt, h, sub)
	_grab_events(collected)
	var tw := Time.get_ticks_usec()
	_collide_with_world()
	world_ms = float(Time.get_ticks_usec() - tw) / 1000.0
	var dbg_post: KiteRig = debug_rope_rig if is_instance_valid(debug_rope_rig) and debug_rope_rig.rope != null else null
	var dbg_p0 := dbg_post.rope.pos.duplicate() if dbg_post else PackedVector3Array()
	for r in rigs:
		r.post_frame(dt, h)
	if dbg_post and dbg_post.rope != null:
		_dbg_phase("pós-tick(n%d→%d)" % [dbg_p0.size(), dbg_post.rope.pos.size()], dbg_post, dbg_p0)
	# Cortes por atrito (quem cortou = dono da outra linha do contato).
	for req in combat.cut_requests:
		var loser: KiteRig = req[0]
		if not loser.is_flying():
			continue
		var winner := _opponent_in_contact(loser)
		combat.clear_for(loser)
		var s: float = req[1]
		loser.cut(clampf(s, 0.05, loser.rope.length() - 0.05))
		if winner:
			EventBus.line_cut.emit(winner, loser)
	# Linha arrebentada por tração (na mão).
	for r in rigs:
		if r.is_flying() and r.tension > r.line_type.break_tension:
			combat.clear_for(r)
			r.cut(r.rope.length() - 0.3)
			EventBus.line_snapped.emit(r.hand_rest)
	_cleanup()
	frame_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _collide_with_world() -> void:
	if obstacles == null:
		var sb := get_tree().get_first_node_in_group(&"street_builder")
		if sb == null:
			return
		obstacles = sb.get("obstacles")
	var dt := get_physics_process_delta_time()
	_world_tick += 1
	for r in rigs:
		if r.rope != null:
			# Linha solta (pipa voada / sobra caída): cenário a cada 2 quadros.
			if not r.rope.hand_fixed and (_world_tick + r.get_instance_id()) % 2 == 0:
				continue
			obstacles.last_freed = ""
			var snag := obstacles.update_rope(r.rope, dt * (1.0 if r.rope.hand_fixed else 2.0))
			if snag != "" and r.is_flying():
				EventBus.kite_snagged.emit(r, snag)
			if obstacles.last_freed != "" and r.is_flying():
				EventBus.line_freed.emit(r, obstacles.last_freed)
		if r.tail != null and r.body != null:
			_tail_collide(r.tail)
		if r.is_flying():
			r.try_snag(obstacles, dt)
			r.tail.try_snag(obstacles, r.rope.tension_end, dt)
		elif r.loose and r.body != null:
			r.try_snag(obstacles, dt)


## A rabiola é sólida para o cenário: cada nó varre o caminho do tick (do começo do
## tick até agora) contra poste, fio, galho e casa e desliza na superfície (a rabiola
## atravessava o poste).
func _tail_collide(tail: TailChain) -> void:
	var n := tail.pos.size()
	if tail.tick_prev.size() != n:
		return
	for i in n:
		var p := tail.pos[i]
		var res := obstacles.kite_sweep(tail.tick_prev[i], p, 0.03)
		var nrm: Vector3 = res[1]
		if nrm == Vector3.ZERO:
			continue
		tail.pos[i] = res[0]
		var vn := tail.vel[i].dot(nrm)
		if vn < 0.0:
			tail.vel[i] -= nrm * vn
		tail.vel[i] *= 0.8


func _opponent_in_contact(rig: KiteRig) -> KiteRig:
	for c in combat.contacts:
		if not c.touching:
			continue
		if c.a == rig:
			return c.b
		if c.b == rig:
			return c.a
	return null


func _on_rig_cut(_rig: KiteRig, _pos: Vector3) -> void:
	pass


## Pipas voadas criadas por cortes entram na simulação automaticamente.
func _collect_new_rigs() -> void:
	for n in get_tree().get_nodes_in_group(&"kite_rigs"):
		var r := n as KiteRig
		if r and not rigs.has(r):
			register(r)


func _cleanup() -> void:
	for i in range(rigs.size() - 1, -1, -1):
		var r := rigs[i]
		if not is_instance_valid(r):
			rigs.remove_at(i)
			continue
		if r.loose and r.body != null:
			var far := Vector2(r.body.x.x, r.body.x.z).length() > 260.0
			# Pipa voada presa numa linha não some (vai ser aparada ou cair).
			var hooked := false
			for g in grabs.grabs:
				if g.target == r:
					hooked = true
			if (r.age > LOOSE_LIFETIME and not hooked) or far:
				combat.clear_for(r)
				grabs.clear_for(r)
				rigs.remove_at(i)
				r.queue_free()


## Eventos dos enganches → avisos; pipas aparadas saem do céu (ficam com quem aparou);
## pedaços de rabiola cortados caem sozinhos.
func _grab_events(collected: Array) -> void:
	for ev in grabs.events:
		match ev[0]:
			"enroscou_voada":
				EventBus.loose_kite_hooked.emit(ev[1], ev[2])
			"aparou":
				EventBus.kite_caught.emit(ev[1], ev[2])
			"pegou_rabiola":
				EventBus.tail_grabbed.emit(ev[1], ev[2])
			"cortou_rabiola", "arrebentou_rabiola":
				EventBus.tail_cut.emit(ev[1], ev[2], ev[3])
			"soltou_voada":
				EventBus.loose_kite_slipped.emit(ev[1], ev[2])
	for pc in grabs.cut_pieces:
		var rg: KiteRig = pc[2]
		var fr := FallingRibbon.new()
		fr.setup(pc[0], pc[1], rg.profile, rg.tail.seg_len if rg.tail else 0.3)
		add_child(fr)
	for pair in collected:
		var t: KiteRig = pair[1]
		if is_instance_valid(t):
			combat.clear_for(t)
			grabs.clear_for(t)
			rigs.erase(t)
			t.queue_free()


## Contato mais forte agora (para som/vibração/HUD).
## Depuração: mostra quanto cada fase do subpasso mexe na linha desta pipa.
var debug_rope_rig: KiteRig = null
func _dbg_phase(phase: String, r: KiteRig, p0: PackedVector3Array) -> void:
	var mv := 0.0
	var mk := -1
	for k in mini(p0.size(), r.rope.pos.size()):
		var d := r.rope.pos[k].distance_to(p0[k])
		if d > mv:
			mv = d
			mk = k
	if mv > 0.3:
		print("FASE %s: %.2f m no nó %d/%d (obst=%d pin=%d m⁻¹=%.1f rest=%.2f/%.2f)" % [phase, mv, mk, r.rope.pos.size(), r.rope.pin_obstacle[mk], r.rope.pinned[mk], r.rope.inv_mass[mk],
			r.rope.rest[mk - 1] if mk > 0 else -1.0, r.rope.rest[mk] if mk < r.rope.rest.size() else -1.0])


func strongest_contact_for(rig: KiteRig) -> LineCombat.Contact:
	var best: LineCombat.Contact = null
	for c in combat.contacts:
		if c.touching and (c.a == rig or c.b == rig) and (best == null or c.force * c.slide > best.force * best.slide):
			best = c
	return best
