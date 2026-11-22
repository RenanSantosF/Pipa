class_name KiteProfile
extends Resource
## Parâmetros físicos e visuais de uma pipa (corpo rígido + rabiola).
## Valores ajustados no protótipo (docs/FISICA_PIPA.md).

@export var display_name: String = "Pipa clássica"

@export_group("Vela")
## Altura (nariz → ponta de baixo) e largura (m).
@export var height: float = 0.62
@export var width: float = 0.5
## Massa (kg): papel de seda + varetas de bambu.
@export var mass: float = 0.045
## Ganho da força normal com fluxo colado / descolado (placa plana).
@export var cn_attached: float = 4.0
@export var cn_separated: float = 1.25
@export var stall_start_deg: float = 15.0
@export var stall_end_deg: float = 30.0
@export var cd0: float = 0.06
## Diedro (graus): a vela "embarrigada" que dá estabilidade lateral.
@export var dihedral_deg: float = 6.0
## Amortecimento aerodinâmico de rotação.
@export var rotational_damping: float = 0.08

@export_group("Cabresto")
## Posição do nó do cabresto ao longo da vareta, a partir do nariz (fração da altura).
## Mais perto do nariz = pipa mais "deitada" (sobe mais, puxa menos).
@export_range(0.05, 0.6) var tow_fraction: float = 0.22
## Distância do nó do cabresto até a vela (m).
@export var bridle_length: float = 0.22

@export_group("Rabiola")
@export var tail_length: float = 2.6
@export_range(2, 24) var tail_nodes: int = 10
@export var tail_mass: float = 0.02
@export var tail_area: float = 0.03
@export var tail_cd: float = 1.2
## Rabiola com cerol (poder de corte da rabiola; 0 = sem cerol).
@export var tail_abrasion: float = 0.0

@export_group("Visual")
@export var color_a: Color = Color(0.95, 0.78, 0.15)
@export var color_b: Color = Color(0.88, 0.2, 0.18)
@export var tail_color_a: Color = Color(0.95, 0.95, 0.95)
@export var tail_color_b: Color = Color(0.2, 0.45, 0.9)
