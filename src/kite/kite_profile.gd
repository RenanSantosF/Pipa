class_name KiteProfile
extends Resource
## Parâmetros físicos e visuais de uma pipa de combate brasileira (losango, 3 varetas).
## Ver docs/REVISAO_V5.md.
##
## Geometria (vista de frente, nariz para cima):
##   - vareta vertical (espinha) do nariz até a ponta de baixo;
##   - travessa principal ENVERGADA no ponto mais largo do losango (cross_at);
##   - travessa inferior, mais curta e menos envergada (lower_at), que segura a
##     parte de baixo da vela.
## A envergadura (bow) define o DIEDRO real da vela — e o diedro decide como a pipa
## responde ao desbico (muita envergadura = desbico fino; pouca = braçada longa).

enum Size { P, M, G }
enum Bow { POUCA, MEDIA, MUITA }

const SIZE_HEIGHT := [0.50, 0.65, 0.80]
const SIZE_NAMES := ["P", "M", "G"]
const BOW_FRACTION := [0.045, 0.085, 0.13]   # flecha / meia-envergadura
const BOW_NAMES := ["pouca", "média", "muita"]

@export var display_name: String = "Pipa clássica"

@export_group("Vela")
## Altura (nariz → ponta de baixo) e largura (m).
@export var height: float = 0.65
@export var width: float = 0.5
## Travessa envergada = borda de cima do papel, fração da altura a partir da
## CABEÇA (ponta de cima da vareta, que fica acima do papel).
@export_range(0.15, 0.5) var cross_at: float = 0.31
## "Ombros" (onde os lados retos viram o V de baixo) e a vareta de baixo.
@export_range(0.4, 0.85) var lower_at: float = 0.63
## Meia-largura nos ombros / meia-largura da travessa.
@export_range(0.6, 1.0) var shoulder: float = 0.92
## Envergadura: quanto as pontas da travessa principal vão para trás (m).
@export var bow: float = 0.051
## Massa (kg): papel de seda + 3 varetas de bambu + cola + cabresto.
@export var mass: float = 0.030
## Sustentação potencial (Helmbold, alongamento ~1,7) e de vórtice (Polhamus parcial).
@export var lift_kp: float = 2.3
@export var lift_kv: float = 1.6
## Estol: começa / termina (graus). Asa de baixo alongamento estola tarde.
@export var stall_start_deg: float = 32.0
@export var stall_end_deg: float = 46.0
## Força normal da placa descolada (CN = k·sen α).
@export var cn_separated: float = 1.17
## Arrasto parasita (papel, varetas, bainha).
@export var cd0: float = 0.05
## Amortecimento aerodinâmico residual de rotação (o principal vem de ω×r por meia-vela).
@export var rotational_damping: float = 0.05
## Curso da flexão assimétrica das varetas no desbico (rad de diedro a mais num lado).
@export var flex_asym: float = 0.35
## Momento da vela torta na folga (gira o bico): pouca envergadura = vareta mais
## mole e torta → gira mais (pipa arisca); muita = gira menos (desbico fino).
@export var spin_coef: float = 0.11

@export_group("Cabresto")
## Posição do nó do cabresto ao longo da vareta, a partir da CABEÇA (fração da
## altura). Mais para cima = pipa mais "deitada" (sobe mais, puxa menos).
@export_range(0.0, 0.6) var tow_fraction: float = 0.18
## Distância do nó do cabresto até a vela (m).
@export var bridle_length: float = 0.24
## Quanto a perna do cabresto carregada no desbico desloca o ponto de tração (fração da largura).
@export var bridle_shift: float = 0.25

@export_group("Rabiola")
@export var tail_length: float = 2.6
@export_range(2, 24) var tail_nodes: int = 10
@export var tail_mass: float = 0.04
@export var tail_area: float = 0.03
@export var tail_cd: float = 1.2
## Rabiola com cerol (poder de corte da rabiola; 0 = sem cerol).
@export var tail_abrasion: float = 0.0

@export_group("Visual")
@export var color_a: Color = Color(0.08, 0.52, 0.24)
@export var color_b: Color = Color(0.07, 0.07, 0.07)
@export var tail_color_a: Color = Color(0.95, 0.95, 0.95)
@export var tail_color_b: Color = Color(0.2, 0.45, 0.9)
## Desenho do papel: 0 = metades, 1 = faixas, 2 = olho, 3 = xis (estilo Jamaica).
@export_range(0, 3) var pattern: int = 3
## Terceira cor (o xis / detalhes).
@export var color_c: Color = Color(0.98, 0.84, 0.12)

var size_class: int = Size.M
var bow_class: int = Bow.MEDIA


## Diedro de cada meia-vela (rad) dado pela envergadura da travessa principal.
func dihedral() -> float:
	return atan2(bow, width * 0.5)


## Ajusta tamanho (P/M/G) mantendo as proporções e a massa realista.
func apply_size(s: int) -> void:
	size_class = clampi(s, 0, 2)
	var h0 := height
	height = SIZE_HEIGHT[size_class]
	width = height * 0.77
	# Cabresto um pouco mais alto na pequena (rabiola pesa mais para ela).
	tow_fraction = [0.145, 0.18, 0.18][size_class]
	var k := height / h0
	# Área cresce com h²; varetas com h (mais grossas na grande): ≈ h^2,2.
	mass *= pow(k, 2.2)
	bridle_length *= k
	tail_length *= k
	tail_mass *= pow(k, 1.5)
	tail_area *= pow(k, 1.6)
	apply_bow(bow_class)


func apply_bow(b: int) -> void:
	bow_class = clampi(b, 0, 2)
	bow = BOW_FRACTION[bow_class] * width * 0.5 * 2.2
	# Vareta mais arqueada tem mais curso para fechar no desbico.
	flex_asym = 0.25 + 1.2 * BOW_FRACTION[bow_class]
	spin_coef = 0.11 * sqrt(BOW_FRACTION[1] / BOW_FRACTION[bow_class])


func describe() -> String:
	return "%s · %d cm · envergadura %s" % [SIZE_NAMES[size_class], int(round(height * 100.0)), BOW_NAMES[bow_class]]
