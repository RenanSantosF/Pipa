class_name FlightLab
extends PanelContainer
## ÁREA DE TESTES do voo: ajusta ao vivo os parâmetros do KiteFlightModel sem
## reiniciar a partida (abre pelo ícone de tubo de ensaio). Mostra rumo, inclinação,
## velocidade, comando do cabresto e tração da pipa do jogador.

const PARAMS := [
	["E", "Velocidade (eficiência da vela)", 0.8, 3.5],
	["TURN_K", "Curva (giro por velocidade)", 0.15, 1.2],
	["TURN_V0", "Curva com pouca velocidade", 0.0, 12.0],
	["BANK_MAX", "Inclinação máx. do cabresto (rad)", 0.2, 1.1],
	["BANK_TAU", "Resposta do cabresto (s)", 0.04, 0.5],
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
	if not visible or rig == null or rig.flight == null:
		return
	var f := rig.flight
	_readout.text = "rumo %+4.0f°  inclinação %+3.0f°  velocidade %4.1f m/s  cabresto %+.2f  tração %4.1f N  linha %4.1f m" % [
		rad_to_deg(f.heading), rad_to_deg(f.bank), f.speed, f.steer, f.tension, rig.flying_length()]
