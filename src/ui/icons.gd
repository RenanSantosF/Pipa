class_name Icons
extends RefCounted
## Ícones vetoriais desenhados em código (nítidos em qualquer tela, sem texto).

const GLASS := Color(0.06, 0.08, 0.11, 0.42)
const RIM := Color(1, 1, 1, 0.22)
const INK := Color(1, 1, 1, 0.92)
const ACCENT := Color(1.0, 0.78, 0.25)


static func glass_circle(ci: CanvasItem, c: Vector2, r: float, pressed: bool = false) -> void:
	ci.draw_circle(c, r, Color(GLASS, GLASS.a + (0.2 if pressed else 0.0)))
	ci.draw_arc(c, r - 0.75, 0.0, TAU, 48, RIM, 1.5, true)


## Pipa (losango com vareta e rabiola).
static func kite(ci: CanvasItem, c: Vector2, s: float, col: Color = INK, w: float = 2.0) -> void:
	var top := c + Vector2(0, -s)
	var right := c + Vector2(s * 0.75, -s * 0.15)
	var bottom := c + Vector2(0, s * 0.85)
	var left := c + Vector2(-s * 0.75, -s * 0.15)
	ci.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), col, w, true)
	ci.draw_line(top, bottom, Color(col, col.a * 0.6), w * 0.6, true)
	ci.draw_line(left, right, Color(col, col.a * 0.6), w * 0.6, true)
	var tail := PackedVector2Array()
	for i in 6:
		var t := float(i) / 5.0
		tail.append(bottom + Vector2(sin(t * 6.0) * s * 0.18, t * s * 0.7))
	ci.draw_polyline(tail, col, w * 0.7, true)


## Seta circular (recomeçar).
static func refresh(ci: CanvasItem, c: Vector2, r: float, col: Color = INK, w: float = 2.0) -> void:
	ci.draw_arc(c, r, -PI * 0.15, PI * 1.45, 24, col, w, true)
	var tip := c + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * r
	ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.45, -r * 0.05), tip + Vector2(-r * 0.2, -r * 0.45), tip + Vector2(-r * 0.05, r * 0.35)]), col)


## Carretel/lata com linha enrolada.
static func spool(ci: CanvasItem, c: Vector2, s: float, line_color: Color, col: Color = INK, w: float = 2.0) -> void:
	var rect := Rect2(c - Vector2(s * 0.6, s * 0.75), Vector2(s * 1.2, s * 1.5))
	ci.draw_rect(rect, col, false, w)
	for i in 4:
		var y := rect.position.y + rect.size.y * (0.25 + 0.17 * i)
		ci.draw_line(Vector2(rect.position.x + 2, y), Vector2(rect.end.x - 2, y - s * 0.12), line_color, w * 0.9, true)
	ci.draw_line(Vector2(rect.end.x, rect.position.y + s * 0.3), c + Vector2(s * 1.1, -s * 1.0), line_color, w * 0.8, true)


## Alto-falante (com ou sem som).
static func speaker(ci: CanvasItem, c: Vector2, s: float, on: bool, col: Color = INK, w: float = 2.0) -> void:
	var body := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.3), c + Vector2(-s * 0.4, -s * 0.3), c + Vector2(0.0, -s * 0.7),
		c + Vector2(0.0, s * 0.7), c + Vector2(-s * 0.4, s * 0.3), c + Vector2(-s * 0.8, s * 0.3)])
	ci.draw_colored_polygon(body, col)
	if on:
		ci.draw_arc(c + Vector2(s * 0.1, 0), s * 0.45, -0.9, 0.9, 12, col, w, true)
		ci.draw_arc(c + Vector2(s * 0.1, 0), s * 0.8, -0.9, 0.9, 12, col, w, true)
	else:
		ci.draw_line(c + Vector2(s * 0.3, -s * 0.4), c + Vector2(s * 0.9, s * 0.4), col, w, true)
		ci.draw_line(c + Vector2(s * 0.9, -s * 0.4), c + Vector2(s * 0.3, s * 0.4), col, w, true)


## Mão com toque (dica de gesto).
static func tap(ci: CanvasItem, c: Vector2, s: float, col: Color = INK) -> void:
	ci.draw_circle(c, s * 0.28, col)
	ci.draw_arc(c, s * 0.55, 0.0, TAU, 24, Color(col, col.a * 0.6), 2.0, true)
	ci.draw_arc(c, s * 0.85, 0.0, TAU, 24, Color(col, col.a * 0.3), 2.0, true)


static func arrow(ci: CanvasItem, from: Vector2, to: Vector2, col: Color = INK, w: float = 2.5) -> void:
	ci.draw_line(from, to, col, w, true)
	var d := (to - from).normalized()
	var p := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([to + d * 6.0, to - d * 6.0 + p * 6.0, to - d * 6.0 - p * 6.0]), col)


## Tesoura (corte).
static func scissors(ci: CanvasItem, c: Vector2, s: float, col: Color = INK) -> void:
	ci.draw_arc(c + Vector2(-s * 0.45, s * 0.45), s * 0.28, 0, TAU, 16, col, 2.0, true)
	ci.draw_arc(c + Vector2(s * 0.45, s * 0.45), s * 0.28, 0, TAU, 16, col, 2.0, true)
	ci.draw_line(c + Vector2(-s * 0.25, s * 0.25), c + Vector2(s * 0.6, -s * 0.7), col, 2.0, true)
	ci.draw_line(c + Vector2(s * 0.25, s * 0.25), c + Vector2(-s * 0.6, -s * 0.7), col, 2.0, true)


## Galho/árvore (enroscou).
static func snag(ci: CanvasItem, c: Vector2, s: float, col: Color = INK) -> void:
	ci.draw_line(c + Vector2(0, s), c + Vector2(0, -s * 0.2), col, 2.5, true)
	ci.draw_line(c + Vector2(0, s * 0.2), c + Vector2(-s * 0.6, -s * 0.5), col, 2.0, true)
	ci.draw_line(c + Vector2(0, 0), c + Vector2(s * 0.6, -s * 0.7), col, 2.0, true)
	kite(ci, c + Vector2(s * 0.55, -s * 0.85), s * 0.35, ACCENT, 1.5)


## Linha arrebentada.
static func snap(ci: CanvasItem, c: Vector2, s: float, col: Color = INK) -> void:
	ci.draw_line(c + Vector2(-s, s * 0.6), c + Vector2(-s * 0.15, -s * 0.05), col, 2.0, true)
	ci.draw_line(c + Vector2(s * 0.15, s * 0.05), c + Vector2(s, -s * 0.6), col, 2.0, true)
	for a in [0.4, 1.4, 2.4, 3.6, 4.6]:
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * s * 0.25, c + d * s * 0.5, ACCENT, 1.5, true)


## Vareta envergada (nível 0..2 = pouca/média/muita) com a espinha no meio.
static func bow(ci: CanvasItem, c: Vector2, s: float, level: int, col: Color = INK, w: float = 2.0) -> void:
	var sag := s * (0.15 + 0.28 * float(level))
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0 * 2.0 - 1.0
		pts.append(c + Vector2(t * s, sag * (t * t) - sag * 0.5))
	ci.draw_polyline(pts, col, w, true)
	ci.draw_line(c + Vector2(0, -s * 0.8), c + Vector2(0, s * 0.8), col, w * 0.8, true)
	for k in 3:
		var on := k <= level
		ci.draw_circle(c + Vector2(-s * 0.5 + s * 0.5 * float(k), s * 0.95), 2.2, ACCENT if on else Color(col, 0.35))
