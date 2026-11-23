extends Node
## Campo de vento determinístico. Autoload "Wind".
##
## O vento depende só de (seed, tempo, posição). No multiplayer o servidor
## enviará seed + tempo e todos os clientes calcularão o mesmo vento.
##
## Modelo:
##  - direção base com variação lenta (ruído);
##  - rajadas (ruído de baixa frequência no tempo);
##  - gradiente de altura (lei de potência, terreno suburbano);
##  - bloqueio perto do chão (casas/muros) e turbulência na altura dos telhados.

signal wind_settings_changed

## Azimute para ONDE o vento sopra, em graus (0 = -Z, 90 = +X).
var base_direction_deg: float = 0.0
## Velocidade de referência a 10 m de altura (m/s).
var base_speed: float = 6.5
## Intensidade das rajadas (0 = vento constante).
var gust_strength: float = 0.3
## Variação máxima da direção (graus).
var direction_wander_deg: float = 15.0

const REF_HEIGHT := 10.0
const SHEAR_EXPONENT := 0.25
const GROUND_LEVEL := 0.0
const ROOF_HEIGHT := 6.0

var seed_value: int = 20260
var _time: float = 0.0
var _gust_noise := FastNoiseLite.new()
var _dir_noise := FastNoiseLite.new()
var _turb_noise := FastNoiseLite.new()

# Valores cacheados por tick físico (evita recalcular ruídos por amostra).
var _cached_dir := Vector3(0, 0, -1)
var _cached_gust := 1.0


func _ready() -> void:
	process_physics_priority = -100  # atualiza antes de todos os outros nós
	set_seed(seed_value)
	_update_cache()


func set_seed(s: int) -> void:
	seed_value = s
	_setup_noise(_gust_noise, s, 0.08)
	_setup_noise(_dir_noise, s + 101, 0.015)
	_setup_noise(_turb_noise, s + 202, 0.5)
	wind_settings_changed.emit()


func _setup_noise(n: FastNoiseLite, s: int, freq: float) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 2


## Sincroniza o relógio do vento (usado pela rede no futuro).
func set_time(t: float) -> void:
	_time = t
	_update_cache()


func get_time() -> float:
	return _time


func _physics_process(delta: float) -> void:
	_time += delta
	_update_cache()


func _update_cache() -> void:
	var ang := deg_to_rad(base_direction_deg + direction_wander_deg * 2.0 * _dir_noise.get_noise_1d(_time))
	_cached_dir = Vector3(sin(ang), 0.0, -cos(ang))
	# get_noise_1d fica aproximadamente em [-0.6, 0.6]; normalizamos para ~[-1, 1].
	var g := clampf(_gust_noise.get_noise_1d(_time) * 1.7, -1.0, 1.0)
	_cached_gust = maxf(0.2, 1.0 + gust_strength * g)


## Direção horizontal (normalizada) para onde o vento sopra.
func get_direction() -> Vector3:
	return _cached_dir


## Fator de rajada atual (1.0 = vento médio).
func get_gust_factor() -> float:
	return _cached_gust


## Velocidade média do vento na altura h (sem turbulência).
func get_speed_at_height(h: float) -> float:
	var hh := maxf(h - GROUND_LEVEL, 0.5)
	var shear := pow(hh / REF_HEIGHT, SHEAR_EXPONENT)
	var ground_block := clampf(hh / 3.0, 0.6, 1.0)
	return base_speed * _cached_gust * shear * ground_block


## Vetor de vento (m/s) na posição do mundo.
func sample(world_pos: Vector3) -> Vector3:
	var h := world_pos.y - Ground.height_at(world_pos.x, world_pos.z)
	var speed := get_speed_at_height(h)
	var turb_amount := 0.07 + 0.22 * exp(-pow((h - ROOF_HEIGHT) / 4.0, 2.0))
	var sx := world_pos.x * 0.04
	var sz := world_pos.z * 0.04
	var t := _time * 0.8
	var turb := Vector3(
		_turb_noise.get_noise_3d(sx, t, sz),
		_turb_noise.get_noise_3d(sx + 57.0, t, sz) * 0.5,
		_turb_noise.get_noise_3d(sx, t, sz + 113.0)
	) * (1.7 * speed * turb_amount)
	return _cached_dir * speed + turb


## Vento de referência ao nível dos olhos, para o indicador do HUD.
func get_reference_speed() -> float:
	return get_speed_at_height(REF_HEIGHT)
