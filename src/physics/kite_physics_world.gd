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
var frame_ms: float = 0.0
var obstacles: WorldObstacles


func _ready() -> void:
	process_physics_priority = 0


func register(rig: KiteRig) -> void:
	if not rigs.has(rig):
		rigs.append(rig)
		rig.line_cut.connect(_on_rig_cut)


func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_collect_new_rigs()
	var sub := GameConfig.physics_substeps()
	var h := dt / float(sub)
	for r in rigs:
		r.pre_frame(dt)
	combat.detect(rigs)
	for _i in sub:
		for r in rigs:
			r.predict(h)
		for r in rigs:
			r.solve(h)
		combat.solve(h)
		for r in rigs:
			r.finalize(h)
	combat.post_frame(dt, h, sub)
	_collide_with_world()
	for r in rigs:
		r.post_frame(dt, h)
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
	for r in rigs:
		if r.rope != null:
			var snag := obstacles.update_rope(r.rope, dt)
			if snag != "" and r.is_flying():
				EventBus.kite_snagged.emit(r, snag)
		if r.is_flying():
			r.try_snag(obstacles, dt)
			r.tail.try_snag(obstacles, r.rope.tension_end, dt)
		elif r.loose and r.body != null:
			r.try_snag(obstacles, dt)


func _opponent_in_contact(rig: KiteRig) -> KiteRig:
	for c in combat.contacts:
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
			if r.age > LOOSE_LIFETIME or far:
				combat.clear_for(r)
				rigs.remove_at(i)
				r.queue_free()


## Contato mais forte agora (para som/vibração/HUD).
func strongest_contact_for(rig: KiteRig) -> LineCombat.Contact:
	var best: LineCombat.Contact = null
	for c in combat.contacts:
		if (c.a == rig or c.b == rig) and (best == null or c.force * c.slide > best.force * best.slide):
			best = c
	return best
