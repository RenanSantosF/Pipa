class_name HUD
extends Control
## HUD minimalista, só símbolos:
##  - bússola de vento (canto superior esquerdo): seta relativa à câmera + força;
##  - cápsula no topo: ícone de carretel + metros de linha no ar, anel de tensão
##    (verde → amarelo → vermelho) e pontinhos vermelhos de desgaste;
##  - avisos curtos com ícone (cortou, cortaram, enroscou, arrebentou).

@onready var debug_overlay: DebugOverlay = $DebugOverlay

var rig: KiteRig
var world: KitePhysicsWorld
var _toast_icon: String = ""
var _toast_text: String = ""
var _toast_time: float = 0.0
var _toast_color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.line_snapped.connect(func(_p: Vector3) -> void: toast("snap", "arrebentou", Color(1, 0.5, 0.4)))
	EventBus.line_cut.connect(_on_line_cut)
	EventBus.kite_snagged.connect(_on_snagged)
	EventBus.line_freed.connect(func(r: Node, _w: String) -> void:
		if r == rig:
			toast("snag", "soltou", Color(0.6, 1.0, 0.6), 1.6))
	EventBus.loose_kite_hooked.connect(func(c: Node, _k: Node) -> void:
		if c == rig:
			toast("cut", "enroscou a voada! recolhe", Color(0.6, 0.9, 1.0), 2.5))
	EventBus.loose_kite_slipped.connect(func(c: Node, _k: Node) -> void:
		if c == rig:
			toast("snag", "puxou forte: a voada soltou", Color(1.0, 0.8, 0.35), 2.5))
	EventBus.kite_caught.connect(func(c: Node, _k: Node) -> void:
		if c == rig:
			toast("cut", "aparou!", Color(0.55, 1.0, 0.55), 3.0))
	EventBus.tail_grabbed.connect(func(c: Node, t: Node) -> void:
		if t == rig:
			toast("snag", "pegaram sua rabiola", Color(1.0, 0.8, 0.35), 2.5)
		elif c == rig:
			toast("snag", "pegou a rabiola!", Color(0.55, 1.0, 0.55), 2.5))
	EventBus.tail_cut.connect(func(by: Node, t: Node, _p: Vector3) -> void:
		if t == rig:
			toast("cut", "cortaram sua rabiola", Color(1.0, 0.45, 0.4), 2.5)
		elif by == rig:
			toast("cut", "cortou a rabiola!", Color(0.55, 1.0, 0.55), 2.5))


func setup(p_rig: KiteRig, p_world: KitePhysicsWorld) -> void:
	rig = p_rig
	world = p_world
	debug_overlay.rig = p_rig
	debug_overlay.world = p_world


func _on_line_cut(winner: Node, loser: Node) -> void:
	if winner == rig:
		toast("cut", "cortou!", Color(0.55, 1.0, 0.55))
	elif loser == rig:
		toast("cut", "cortaram", Color(1.0, 0.45, 0.4))


func _on_snagged(r: Node, _what: String) -> void:
	if r == rig:
		toast("snag", "enroscou", Color(1.0, 0.8, 0.35))


## Mostra um aviso curto (ícone + 1 palavra).
func toast(icon: String, text: String, color: Color = Color.WHITE, duration: float = 2.5) -> void:
	_toast_icon = icon
	_toast_text = text
	_toast_color = color
	_toast_time = duration


func show_message(text: String, duration: float = 2.0) -> void:
	toast("", text, Color.WHITE, duration)


var _redraw_t: float = 0.0


func _process(delta: float) -> void:
	_toast_time = maxf(_toast_time - delta, 0.0)
	# Redesenha a ~12 Hz (o HUD é só leitura; redesenhar todo quadro pesa no celular).
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.08
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# --- Vento ---
	var wc := Vector2(46, 46)
	Icons.glass_circle(self, wc, 28.0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var local := cam.global_basis.inverse() * Wind.get_direction()
		var v := Vector2(local.x, local.z)
		if v.length() > 0.01:
			v = v.normalized()
			var speed := Wind.get_reference_speed()
			var alen := 10.0 + clampf(speed / 10.0, 0.0, 1.0) * 10.0
			Icons.arrow(self, wc - v * alen, wc + v * alen, Icons.INK, 2.5)
			_text_center(font, wc + Vector2(0, 44), "%d" % roundi(speed), 15, Color(1, 1, 1, 0.85))
	if rig == null:
		return
	# --- Cápsula da linha ---
	var cx := size.x * 0.5
	var cap := Rect2(cx - 92, 12, 184, 40)
	draw_style_box(_capsule_style(), cap)
	Icons.spool(self, Vector2(cap.position.x + 24, cap.position.y + 21), 10.0, rig.line_type.color, Icons.INK, 1.5)
	_text_center(font, Vector2(cap.position.x + 66, cap.position.y + 27), "%dm" % roundi(rig.flying_length()), 17, Icons.INK)
	# Anel de tensão.
	var rc := Vector2(cap.end.x - 26, cap.position.y + 20)
	var frac := clampf(rig.tension / rig.line_type.break_tension, 0.0, 1.0)
	draw_arc(rc, 13.0, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 4.0, true)
	var tcol := Color(0.45, 0.95, 0.55).lerp(Color(1.0, 0.85, 0.3), clampf(frac * 2.0, 0.0, 1.0)).lerp(Color(1.0, 0.3, 0.25), clampf(frac * 2.0 - 1.0, 0.0, 1.0))
	if frac > 0.01:
		draw_arc(rc, 13.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, tcol, 4.0, true)
	Icons.kite(self, rc + Vector2(0, -1), 5.5, Color(1, 1, 1, 0.8), 1.2)
	# Desgaste da linha (pontinhos).
	var wear := clampf(LineCombat.max_wear(rig), 0.0, 1.0)
	if wear > 0.02:
		var n := ceili(wear * 5.0)
		for i in 5:
			var col := Color(1.0, 0.35, 0.3, 0.95) if i < n else Color(1, 1, 1, 0.18)
			draw_circle(Vector2(cap.position.x + 104 + i * 9, cap.position.y + 20), 3.0, col)
	# Linha no chão (pequeno, só quando existe).
	if rig.pile > 0.5:
		_text_center(font, Vector2(cx, cap.end.y + 16), "↓%dm" % roundi(rig.pile), 13, Color(1, 1, 1, 0.6))
	# --- Cabo de guerra do cruzamento (desgaste: você × rival) ---
	if world:
		var c := world.strongest_contact_for(rig)
		if c != null:
			var rival: KiteRig = c.b if c.a == rig else c.a
			var mine := clampf(LineCombat.max_wear(rig), 0.0, 1.0)
			var theirs := clampf(LineCombat.max_wear(rival), 0.0, 1.0)
			var dy := cap.end.y + 10.0
			var bar := Rect2(cx - 120, dy, 240, 26)
			draw_style_box(_capsule_style(), bar)
			Icons.scissors(self, Vector2(cx, dy + 13), 7.0, Icons.ACCENT)
			draw_rect(Rect2(cx - 108, dy + 10, 90, 6), Color(1, 1, 1, 0.15))
			draw_rect(Rect2(cx - 18 - 90 * mine, dy + 10, 90 * mine, 6), Color(1.0, 0.35, 0.3))
			draw_rect(Rect2(cx + 18, dy + 10, 90, 6), Color(1, 1, 1, 0.15))
			draw_rect(Rect2(cx + 18, dy + 10, 90 * theirs, 6), Color(0.45, 1.0, 0.55))
			draw_circle(Vector2(cx - 112, dy + 13), 3.0, rig.line_type.color)
			draw_circle(Vector2(cx + 112, dy + 13), 3.0, rival.line_type.color)
	# --- Aviso ---
	if _toast_time > 0.0:
		var a := clampf(_toast_time / 0.4, 0.0, 1.0)
		var tc := Vector2(cx, cap.end.y + 52)
		var box := Rect2(tc - Vector2(80, 20), Vector2(160, 40))
		var st := _capsule_style()
		st.bg_color = Color(st.bg_color, st.bg_color.a * a)
		draw_style_box(st, box)
		var ic := Color(_toast_color, a)
		match _toast_icon:
			"cut":
				Icons.scissors(self, tc + Vector2(-52, 0), 11.0, ic)
			"snag":
				Icons.snag(self, tc + Vector2(-52, 0), 11.0, ic)
			"snap":
				Icons.snap(self, tc + Vector2(-52, 0), 11.0, ic)
		_text_center(font, tc + Vector2(12 if _toast_icon != "" else 0, 6), _toast_text, 17, Color(1, 1, 1, a))


func _capsule_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Icons.GLASS
	st.set_corner_radius_all(20)
	st.border_color = Icons.RIM
	st.set_border_width_all(1)
	st.anti_aliasing = true
	return st


func _text_center(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(pos.x - w * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
