class_name LineType
extends Resource
## Tipo de linha (material). Define como ela voa (peso, diâmetro, elasticidade)
## e como se comporta no cruzamento com outra linha (abrasão e resistência ao desgaste).
##
## Modelo de corte (ver docs/FISICA_PIPA.md): no cruzamento, a energia de atrito
## E = μ·N·v_desliz·dt desgasta cada linha proporcionalmente à ABRASÃO da outra
## e inversamente à própria RESISTÊNCIA. O desgaste se espalha pelo trecho de
## material que passou pelo ponto de contato: quem dá linha ou puxa rápido espalha
## o próprio desgaste; quem fica parado concentra o desgaste num ponto e é cortado.

@export var display_name: String = "Linha pura"
## Poder de corte (0 = linha sem cerol).
@export_range(0.0, 3.0) var abrasion: float = 0.0
## Resistência ao desgaste por atrito.
@export_range(0.1, 3.0) var toughness: float = 0.6
## Tração que arrebenta a linha (N).
@export var break_tension: float = 40.0
## Massa por metro (kg/m).
@export var mass_per_meter: float = 0.0004
## Diâmetro (m) — mais grossa = mais arrasto do vento (mais barriga).
@export var diameter: float = 0.0006
## Rigidez axial EA (N): quanto maior, menos a linha estica.
@export var axial_stiffness: float = 900.0
## Coeficiente de atrito no cruzamento.
@export var friction: float = 0.3
@export var color: Color = Color(0.96, 0.95, 0.9)
## Brilho/aspereza visual do revestimento.
@export var coated: bool = false
