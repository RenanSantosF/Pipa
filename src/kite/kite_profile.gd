class_name KiteProfile
extends Resource
## Parâmetros físicos e visuais de um modelo de pipa.
## Edite o .tres em src/kite/profiles/ para ajustar o comportamento sem mexer em código.

@export var display_name: String = "Pipa clássica"

@export_group("Física")
## Massa (kg). Pipa de papel de seda + varetas de bambu: 30–60 g.
@export var mass: float = 0.045
## Área da vela (m²).
@export var area: float = 0.15
## Arrasto parasita da vela (atrito, varetas).
@export var cd0: float = 0.06
## Inclinação do cabresto (graus). Maior = pipa mais "deitada", sobe mais e puxa menos.
@export var bridle_angle_deg: float = 20.0
## Ganho da força normal com fluxo colado (ângulos de ataque pequenos).
@export var cn_attached: float = 4.0
## Força normal com fluxo descolado (ângulos grandes, após a perda de sustentação).
@export var cn_separated: float = 1.25
## Faixa (graus) onde ocorre a perda de sustentação.
@export var stall_start_deg: float = 15.0
@export var stall_end_deg: float = 30.0

@export_group("Rabiola")
## Comprimento visual da rabiola (m).
@export var tail_length: float = 2.6
## Área e coeficiente de arrasto da rabiola.
@export var tail_area: float = 0.012
@export var tail_cd: float = 1.0
## Quanto a rabiola endireita a pipa (rigidez do rumo). Rabiola curta = pipa "doida".
@export var tail_stability: float = 4.5

@export_group("Comportamento")
## Amortecimento do rumo (rotação em torno da linha).
@export var heading_damping: float = 5.5
## Sensibilidade à turbulência (balanço lateral).
@export var turbulence_sensitivity: float = 2.0
## Rapidez com que a pipa se alinha à linha esticada / frouxa (1/s).
@export var orient_rate_taut: float = 18.0
@export var orient_rate_slack: float = 3.0

@export_group("Visual")
@export var size: Vector2 = Vector2(0.5, 0.62)
@export var color_a: Color = Color(0.95, 0.78, 0.15)
@export var color_b: Color = Color(0.88, 0.2, 0.18)
@export var tail_color_a: Color = Color(0.95, 0.95, 0.95)
@export var tail_color_b: Color = Color(0.2, 0.45, 0.9)
