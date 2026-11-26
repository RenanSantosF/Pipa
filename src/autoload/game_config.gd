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
## FÍSICA REAL da pipa do jogador (v0.18): corpo rígido + cabresto de linha + rabiola,
## controlada só pela mão na linha. Falso = modelo de voo antigo (v0.13–v0.17).
## Linha de comando: --oldflight volta ao modelo antigo.
var physical_flight: bool = true

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


## Ajustes de teste pela linha de comando (lidos uma vez): --substeps= --hz= --ropeit=
var _substeps_override := 0
var _hz_override := 0
var _ropeit_override := 0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--oldflight"):
		physical_flight = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--substeps="):
			_substeps_override = int(a.substr(11))
		elif a.begins_with("--hz="):
			_hz_override = int(a.substr(5))
		elif a.begins_with("--ropeit="):
			_ropeit_override = int(a.substr(9))
	# Celular começa no BAIXO (roda até em aparelho fraco, sem esquentar); o PC no ALTO.
	var q := Quality.LOW if OS.has_feature("mobile") else Quality.HIGH
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			q = clampi(int(a.substr(10)), 0, 2)   # testes: igual ao celular desde o início
	apply_quality(q)


## Qualidade gráfica e de física. Custos medidos no PC (5 pipas):
## física ~5 ms no ALTO; no BAIXO ~1/3 (30 Hz × 5 subpassos, menos nós de linha).
func apply_quality(q: int) -> void:
	quality = q
	var vp := get_viewport()
	match q:
		Quality.LOW:
			vp.scaling_3d_scale = 0.55
			vp.msaa_3d = Viewport.MSAA_DISABLED
			# 60 quadros/s com a física a 30 Hz: pipa, linha e rabiola são interpoladas.
			Engine.max_fps = 60
			Engine.physics_ticks_per_second = 30
		Quality.MEDIUM:
			vp.scaling_3d_scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
			Engine.max_fps = 60
			Engine.physics_ticks_per_second = 30
		Quality.HIGH:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			Engine.max_fps = 60
			Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 3
	if _hz_override > 0:
		Engine.physics_ticks_per_second = _hz_override
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
## BAIXO/MÉDIO rodam a física a 30 Hz. Na física real o tranco da mão tem que chegar
## na pipa pela linha e pela rabiola: com 4 subpassos a 30 Hz a linha "engolia" a
## puxadinha (bico girando ~40°/s); com 6, cada toque vira um balanço (~90°/s).
## Custo medido no PC com 2 vizinhos: 1,5 ms (4) → 2,0 ms (6).
func physics_substeps() -> int:
	if _substeps_override > 0:
		return _substeps_override
	return ([6, 6, 8] if physical_flight else [4, 5, 8])[quality]


## Varreduras do solver da linha por subpasso (física a 30 Hz precisa de ida e volta).
func rope_iterations() -> int:
	return _ropeit_override if _ropeit_override > 0 else 1


func shadows_enabled() -> bool:
	return quality != Quality.LOW


## Quantos vizinhos empinam junto.
func bot_count() -> int:
	return [2, 3, 4][quality]


## Nós máximos da linha (jogador / vizinhos).
func rope_max_nodes(local: bool) -> int:
	if local:
		return [22, 28, 36][quality]
	return [12, 16, 24][quality]


## Densidade das copas (cartões de folha por aglomerado).
func foliage_density() -> float:
	return [0.32, 0.6, 1.0][quality]


## Subdivisões do desenho da linha entre nós.
func line_subdivisions() -> int:
	return [3, 4, 5][quality]


## Distância máxima de desenho do cenário (m; 0 = sem limite) e da câmera.
func draw_distance() -> float:
	return [150.0, 220.0, 0.0][quality]


func camera_far() -> float:
	return [320.0, 500.0, 700.0][quality]


func shadow_distance() -> float:
	return 70.0 if quality == Quality.HIGH else 35.0
