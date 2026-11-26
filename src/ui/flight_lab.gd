class_name FlightLab
extends PanelContainer
## ÁREA DE TESTES do voo (abre pelo ícone de tubo de ensaio).
## No topo: a chave FÍSICA REAL (v0.18: corpo rígido + cabresto de linha + rabiola,
## controlada só pela mão na linha) × modelo de voo antigo, e as medidas da física
## (tração na mão, nas pernas do cabresto, ângulo de ataque, arqueamento da travessa).
## Abaixo: os parâmetros do modelo de voo antigo (valem com a física real desligada).

const PARAMS := [
	["SWING_AMP", "Desbico: tamanho do balanço (rad)", 0.3, 1.8],
	["SWING_TAU", "Desbico: tempo do balanço (s)", 0.08, 0.7],
	["TUG_DV", "Desbico: arrancada do toque (m/s)", 0.0, 6.0],
	["TAP_RESET", "Desbico: pausa que recomeça (s)", 0.2, 1.0],
	["E", "Velocidade (eficiência da vela)", 0.8, 3.5],
	["TURN_K", "Guiar: curva (giro por velocidade)", 0.15, 1.2],
	["TURN_V0", "Guiar: curva com pouca velocidade", 0.0, 12.0],
	["BANK_MAX", "Guiar: inclinação do cabresto (rad)", 0.2, 1.1],
	["BANK_TAU", "Guiar: resposta do cabresto (s)", 0.04, 0.5],
	["SPEED_TAU", "Inércia da velocidade (s)", 0.08, 1.2],
	["PULL_GAIN", "Força do puxão", 0.3, 3.5],
	["UP_RESTORE", "Rabiola endireita o bico", 0.0, 1.5],
	["G", "Peso (freia subindo)", 0.5, 6.0],
]

var rig: KiteRig
var _readout: Label
var _defaults := {}


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.86)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = "Área de testes do voo"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var phys := Button.new()
	phys.custom_minimum_size = Vector2(0, 44)
	phys.add_theme_font_size_override("font_size", 16)
	var upd := func() -> void:
		phys.text = "Física real: LIGADA (toque para o modelo antigo)" if GameConfig.physical_flight \
			else "Física real: DESLIGADA (modelo antigo — toque para ligar)"
	upd.call()
	phys.pressed.connect(func() -> void:
		GameConfig.physical_flight = not GameConfig.physical_flight
		upd.call()
		EventBus.reset_requested.emit())
	box.add_child(phys)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 13)
	_readout.modulate = Color(0.75, 0.9, 1.0)
	box.add_child(_readout)
	for p in PARAMS:
		var key: String = p[0]
		_defaults[key] = KiteFlightModel.param(key)
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = p[1]
		lab.custom_minimum_size = Vector2(250, 0)
		lab.add_theme_font_size_override("font_size", 13)
		row.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = p[2]
		sl.max_value = p[3]
		sl.step = (float(p[3]) - float(p[2])) / 100.0
		sl.value = float(KiteFlightModel.param(key))
		sl.custom_minimum_size = Vector2(220, 34)
		var val := Label.new()
		val.custom_minimum_size = Vector2(54, 0)
		val.text = "%.2f" % sl.value
		sl.value_changed.connect(func(v: float) -> void:
			KiteFlightModel.set_param(key, v)
			val.text = "%.2f" % v)
		row.add_child(sl)
		row.add_child(val)
		box.add_child(row)
	var reset := Button.new()
	reset.text = "Voltar ao padrão"
	reset.pressed.connect(func() -> void:
		for k in _defaults:
			KiteFlightModel.set_param(k, _defaults[k])
		for c in box.get_children():
			if c is HBoxContainer:
				var s2 := c.get_child(1) as HSlider
				var lab2 := c.get_child(0) as Label
				for p in PARAMS:
					if p[1] == lab2.text:
						s2.value = float(_defaults[p[0]]))
	box.add_child(reset)
	visible = false


func _process(_delta: float) -> void:
	if not visible or rig == null:
		return
	if rig.physical and rig.body != null and rig.rope != null:
		var b := rig.body
		var br := rig.rope.bridle
		_readout.text = "rumo %+4.0f°  ataque %3.0f°  vento na pipa %4.1f m/s  velocidade %4.1f m/s\ntração mão %4.1f N  pernas do cabresto %4.1f / %4.1f N  travessa %2.0f°/%2.0f°  linha %4.1f m" % [
			rad_to_deg(rig.heading()), rad_to_deg(b.angle_of_attack), b.airspeed, b.v.length(), rig.tension,
			br.leg_tension[0] if br else 0.0, br.leg_tension[1] if br else 0.0,
			rad_to_deg(b.half_dihedral(0)), rad_to_deg(b.half_dihedral(1)), rig.flying_length()]
		return
	if rig.flight == null:
		return
	var f := rig.flight
	_readout.text = "rumo %+4.0f°  giro %+4.0f°/s  inclinação %+3.0f°  velocidade %4.1f m/s\ncabresto %+.2f  toques %d (%s)  tração %4.1f N  linha %4.1f m" % [
		rad_to_deg(f.heading), rad_to_deg(f.yaw_rate), rad_to_deg(f.bank), f.speed, f.steer, f.taps,
		"esq" if f.swing_side < 0.0 else ("dir" if f.swing_side > 0.0 else "-"), f.tension, rig.flying_length()]
