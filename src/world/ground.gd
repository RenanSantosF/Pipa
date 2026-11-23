class_name Ground
extends RefCounted
## Altura do terreno (grade compartilhada): usada pelo gerador do bairro, pela física
## da linha/pipa (chão), pelo vento (altura acima do chão) e pela colisão do jogador.

static var origin := Vector2.ZERO
static var cell: float = 3.0
static var w: int = 0
static var d: int = 0
static var heights: PackedFloat32Array = PackedFloat32Array()


static func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var gx := (x - origin.x) / cell
	var gz := (z - origin.y) / cell
	var ix := clampi(floori(gx), 0, w - 2)
	var iz := clampi(floori(gz), 0, d - 2)
	var fx := clampf(gx - ix, 0.0, 1.0)
	var fz := clampf(gz - iz, 0.0, 1.0)
	var h00 := heights[iz * w + ix]
	var h10 := heights[iz * w + ix + 1]
	var h01 := heights[(iz + 1) * w + ix]
	var h11 := heights[(iz + 1) * w + ix + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
