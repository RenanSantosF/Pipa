class_name World
extends Node3D
## Raiz do cenário: luz do sol de fim de tarde, ambiente e vento nas árvores.
## (Etapa 2: o ciclo tarde → pôr do sol entra aqui, num DayCycle separado.)

## Posição do sol dentro do HDRI (medida na imagem: u horizontal, elevação em graus).
const HDRI_SUN_U := 0.6003
const HDRI_SUN_ELEVATION := 19.07
## Giro do céu (graus) para o sol ficar ao lado/atrás do jogador, que olha a favor do vento.
@export var sky_yaw_deg: float = 0.0

@onready var sun: DirectionalLight3D = $Sun
@onready var street: StreetBuilder = $StreetBuilder


func _ready() -> void:
	_align_sun_with_sky()
	GameConfig.quality_changed.connect(_on_quality_changed)
	_on_quality_changed(GameConfig.quality)


## Gira o HDRI e aponta a luz direcional para o sol da foto (sombras batem com o céu).
func _align_sun_with_sky() -> void:
	var env: Environment = $WorldEnvironment.environment
	var yaw := deg_to_rad(sky_yaw_deg)
	env.sky_rotation = Vector3(0.0, yaw, 0.0)
	var az := (HDRI_SUN_U - 0.5) * TAU
	var el := deg_to_rad(HDRI_SUN_ELEVATION)
	# Mapeamento do panorama no Godot (medido renderizando o céu): u = atan2(-x, z)/2π + 0,5.
	var to_sun := Vector3(-sin(az) * cos(el), sin(el), cos(az) * cos(el))
	to_sun = Basis.from_euler(env.sky_rotation) * to_sun
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)


func sun_direction_to() -> Vector3:
	return -sun.global_basis.z * -1.0


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
