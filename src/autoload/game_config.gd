extends Node
## Configurações globais: qualidade gráfica, sensibilidade e opções do jogador.
## Autoload "GameConfig". Não conhece nenhuma cena do jogo.

signal quality_changed(quality: int)
signal settings_changed

enum Quality { LOW, MEDIUM, HIGH }

## Sensibilidade do mouse (graus por pixel) — usada nos testes no PC.
var mouse_sensitivity: float = 0.15
## Sensibilidade do toque (graus por pixel da tela virtual 1280x720).
var touch_sensitivity: float = 0.22
var invert_y: bool = false
## Assistência de mira: a câmera tende a acompanhar a pipa ao puxar/recolher.
var aim_assist: bool = true
var show_debug: bool = false
var sound_enabled: bool = true

var quality: int = Quality.MEDIUM

const _LINE_POINTS := {
	Quality.LOW: 14,
	Quality.MEDIUM: 20,
	Quality.HIGH: 28,
}
const _TAIL_POINTS := {
	Quality.LOW: 8,
	Quality.MEDIUM: 12,
	Quality.HIGH: 16,
}


func _ready() -> void:
	apply_quality(Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH)


func apply_quality(q: int) -> void:
	quality = q
	var vp := get_viewport()
	match q:
		Quality.LOW:
			vp.scaling_3d_scale = 0.7
			vp.msaa_3d = Viewport.MSAA_DISABLED
			Engine.max_fps = 30
		Quality.MEDIUM:
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
			Engine.max_fps = 60
		Quality.HIGH:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			Engine.max_fps = 60
	quality_changed.emit(q)


func cycle_quality() -> void:
	apply_quality((quality + 1) % 3)


func quality_name() -> String:
	return ["Baixa", "Média", "Alta"][quality]


func line_points() -> int:
	return _LINE_POINTS[quality]


func tail_points() -> int:
	return _TAIL_POINTS[quality]


## Subpassos XPBD por tick de física (mais = linha mais firme, mais CPU).
func physics_substeps() -> int:
	return [6, 8, 10][quality]


func shadows_enabled() -> bool:
	return quality != Quality.LOW


func shadow_distance() -> float:
	return 70.0 if quality == Quality.HIGH else 50.0
