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

## Desbico da física real: [chave, rótulo, mín, máx, passo].
const PHYS_PARAMS := [
	["angle", "Ângulo de cada balanço (graus)", 20.0, 160.0, 1.0],
	["time", "Tempo de cada balanço (s)", 0.10, 0.80, 0.01],
	["stiff", "Firmeza da resposta", 4.0, 30.0, 0.5],
	["force", "Força do cabresto (×)", 0.3, 3.0, 0.05],
	["hold", "Segura o rumo sem mexer (s)", 0.5, 5.0, 0.1],
	["tug", "Puxadinha do toque (cm)", 2.0, 30.0, 0.5],
	["weight", "Peso da pipa (ar arrastado ×)", 0.0, 3.0, 0.1],
	["calm", "Calma (amortece balanço/tremida)", 0.2, 3.0, 0.1],
]
const PHYS_DEFAULTS := {"angle": 110.0, "time": 0.5, "stiff": 20.0, "force": 1.0, "hold": 1.4, "tug": 8.0,
	"weight": 1.0, "calm": 1.2}
## Arquivo novo na 0.22 (os padrões mudaram: valores salvos da 0.21 não valem mais).
const PHYS_FILE := "user://desbico_v22.cfg"

var rig: KiteRig
var _readout: Label
var _defaults := {}
var _phys_defaults := {}
var _phys_sliders := {}
var _phys_box: VBoxContainer
var _old_box: VBoxContainer


static func phys_param(key: String) -> float:
	match key:
		"angle": return KiteRig.DESB_ANGLE_DEG
		"time": return KiteRig.DESB_TIME
		"stiff": return KiteRig.DESB_WN
		"force": return KiteRig.DESB_FORCE
		"hold": return KiteRig.DESB_HOLD
		"tug": return LineHand.TUG_LEN * 100.0
		"weight": return KiteRigidBody.ADDED_MASS
		"calm": return KiteRig.ROT_DAMP_PHYSICAL
	return 0.0


static func set_phys_param(key: String, v: float) -> void:
	match key:
		"angle": KiteRig.DESB_ANGLE_DEG = v
		"time": KiteRig.DESB_TIME = v
		"stiff": KiteRig.DESB_WN = v
		"force": KiteRig.DESB_FORCE = v
		"hold": KiteRig.DESB_HOLD = v
		"tug": LineHand.TUG_LEN = v / 100.0
		"weight":
			KiteRigidBody.ADDED_MASS = v
			KiteRigidBody.ADDED_INERTIA = v * 1.2
		"calm": KiteRig.ROT_DAMP_PHYSICAL = v


static func _fmt(key: String, v: float) -> String:
	match key:
		"angle", "tug": return "%.0f" % v if key == "angle" else "%.1f" % v
		"time": return "%.2f" % v
	return "%.2f" % v


## Os valores escolhidos ficam salvos no aparelho (valem na próxima vez que abrir).
static func _load_phys() -> void:
	var cf := ConfigFile.new()
	if cf.load(PHYS_FILE) != OK:
		return
	for k in PHYS_DEFAULTS:
		if cf.has_section_key("desbico", k):
			set_phys_param(k, float(cf.get_value("desbico", k)))


static func _save_phys() -> void:
	var cf := ConfigFile.new()
	for k in PHYS_DEFAULTS:
		cf.set_value("desbico", k, phys_param(k))
	cf.save(PHYS_FILE)


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
	# --- Desbico da física real: barras com o valor (para o jogador dizer o ideal) ---
	_phys_box = VBoxContainer.new()
	_phys_box.add_theme_constant_override("separation", 2)
	box.add_child(_phys_box)
	var ph := Label.new()
	ph.text = "Desbico (física real) — ajuste e anote os números"
	ph.add_theme_font_size_override("font_size", 15)
	ph.modulate = Color(1.0, 0.9, 0.55)
	_phys_box.add_child(ph)
	_load_phys()
	for p in PHYS_PARAMS:
		var key: String = p[0]
		_phys_defaults[key] = PHYS_DEFAULTS[key]
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = p[1]
		lab.custom_minimum_size = Vector2(250, 0)
		lab.add_theme_font_size_override("font_size", 14)
		row.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = p[2]
		sl.max_value = p[3]
		sl.step = p[4]
		sl.value = phys_param(key)
		sl.custom_minimum_size = Vector2(240, 40)
		var val := Label.new()
		val.custom_minimum_size = Vector2(70, 0)
		val.add_theme_font_size_override("font_size", 16)
		val.text = _fmt(key, sl.value)
		sl.value_changed.connect(func(v: float) -> void:
			set_phys_param(key, v)
			val.text = _fmt(key, v)
			_save_phys())
		row.add_child(sl)
		row.add_child(val)
		_phys_box.add_child(row)
		_phys_sliders[key] = sl
	var preset := Button.new()
	preset.text = "Voltar ao padrão do desbico"
	preset.pressed.connect(func() -> void:
		for k in _phys_defaults:
			set_phys_param(k, _phys_defaults[k])
			(_phys_sliders[k] as HSlider).value = float(_phys_defaults[k])
		_save_phys())
	_phys_box.add_child(preset)
	# --- Modelo de voo antigo (valem com a física real desligada) ---
	_old_box = VBoxContainer.new()
	_old_box.add_theme_constant_override("separation", 4)
	box.add_child(_old_box)
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
		_old_box.add_child(row)
	var reset := Button.new()
	reset.text = "Voltar ao padrão"
	reset.pressed.connect(func() -> void:
		for k in _defaults:
			KiteFlightModel.set_param(k, _defaults[k])
		for c in _old_box.get_children():
			if c is HBoxContainer:
				var s2 := c.get_child(1) as HSlider
				var lab2 := c.get_child(0) as Label
				for p in PARAMS:
					if p[1] == lab2.text:
						s2.value = float(_defaults[p[0]]))
	_old_box.add_child(reset)
	visible = false


func _process(_delta: float) -> void:
	if not visible or rig == null:
		return
	if _phys_box != null:
		_phys_box.visible = GameConfig.physical_flight
		_old_box.visible = not GameConfig.physical_flight
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
