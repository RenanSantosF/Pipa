class_name World
extends Node3D
## Raiz do cenário: luz do sol de fim de tarde, ambiente e vento nas árvores.
## (Etapa 2: o ciclo tarde → pôr do sol entra aqui, num DayCycle separado.)

## Direção para onde a luz do sol viaja (sol baixo, a oeste, levemente atrás do jogador).
@export var sun_direction: Vector3 = Vector3(-0.75, -0.42, -0.5)

@onready var sun: DirectionalLight3D = $Sun
@onready var street: StreetBuilder = $StreetBuilder


func _ready() -> void:
	sun.basis = Basis.looking_at(sun_direction.normalized(), Vector3.UP)
	GameConfig.quality_changed.connect(_on_quality_changed)
	_on_quality_changed(GameConfig.quality)


func _on_quality_changed(_q: int) -> void:
	sun.shadow_enabled = GameConfig.shadows_enabled()
	sun.directional_shadow_max_distance = GameConfig.shadow_distance()


func _process(_delta: float) -> void:
	var mat := street.tree_material
	if mat == null:
		return
	mat.set_shader_parameter("wind_direction", Wind.get_direction())
	mat.set_shader_parameter("wind_strength", Wind.get_reference_speed() * 0.045)
	mat.set_shader_parameter("gust", Wind.get_gust_factor())
