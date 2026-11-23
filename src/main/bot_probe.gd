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
		print("BOTS t=%4.0f contatos=%d%s" % [_t, main.physics_world.combat.contacts.size(), line])
	if _t > 70.0:
		print("BOTS cortes: ", _cuts)
		get_tree().quit(0)
