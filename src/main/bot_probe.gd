extends Node
## Teste dos vizinhos:  -- --botprobe
## A pipa do jogador fica no ar (parada); os 4 vizinhos sobem e tentam cortar.

var main
var _t: float = 0.0
var _cuts: Array = []


func start(p_main) -> void:
	main = p_main
	main.input_router.autopilot = true
	var r: KiteRig = main.player_rig
	r.launch(main.player.global_position + Vector3(0.2, 1.18, -0.3), 35.0, 55.0, Wind.get_direction())
	main.player.rig = null
	r.hand_rest = main.player.global_position + Vector3(0.2, 1.18, -0.3)
	EventBus.line_cut.connect(func(w: Node, l: Node) -> void: _cuts.append([_t, (w as KiteRig).display_name, (l as KiteRig).display_name]))


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 30.0 and fmod(_t, 0.5) < delta:
		for b in main.bots:
			var bb: BotFlyer = b
			var rr := bb.rig
			if rr and rr.body:
				print("BOTDBG t=%4.1f %s est=%d alt_mão=%.1f T=%.2f L=%.1f contatos=%d presa=%s ar=%.1f perfil=%s" % [_t, rr.display_name, bb._state, rr.body.x.y - rr.hand_position().y, rr.tension, rr.flying_length(), rr.rope.contact_count() if rr.rope else -1, str(rr.snagged), rr.body.airspeed, rr.profile.describe()])
	if fmod(_t, 5.0) < delta:
		var pr: KiteRig = main.player_rig
		var line := ""
		for b in main.bots:
			var bot: BotFlyer = b
			var r := bot.rig
			var d := -1.0
			if r and r.is_flying() and pr.is_flying():
				d = 999.0
				for p in pr.rope.pos:
					d = minf(d, p.distance_to(r.body.x))
			line += " | %s est=%d alt=%.0f L=%.0f dist_linha=%.1f" % [r.display_name if r else "-", bot._state, (r.body.x.y - Ground.height_at(r.body.x.x, r.body.x.z)) if r and r.body else -1.0, r.flying_length() if r else 0.0, d]
		var nr := 0
		var nn := 0
		var nc := 0
		for rg in (main.physics_world as KitePhysicsWorld).rigs:
			if rg.rope != null:
				nr += 1
				nn += rg.rope.pos.size()
				nc += rg.rope.contact_count()
		print("BOTS t=%4.0f física=%.1fms cenário=%.1fms contatos=%d linhas=%d nós=%d nós_contato=%d%s" % [_t, main.physics_world.frame_ms, main.physics_world.world_ms, main.physics_world.combat.contacts.size(), nr, nn, nc, line])
	if _t > 70.0:
		print("BOTS cortes: ", _cuts)
		get_tree().quit(0)
