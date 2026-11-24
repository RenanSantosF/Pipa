class_name PlayerIntent
extends RefCounted
## Intenções do jogador, independentes do dispositivo (gestos, teclado, rede).

## Movimento: x = direita, y = frente. Comprimento <= 1.
var move: Vector2 = Vector2.ZERO
## Rotação de câmera acumulada (graus) desde a última leitura.
var look_delta: Vector2 = Vector2.ZERO
## Dedo arrastando a câmera agora (a mola de volta para a pipa espera soltar).
var look_active: bool = false
## Braçada: quanto a mão está puxada (m). 0 = mão na posição de pegada.
var stroke: float = 0.0
## Pegada: 1 = segurando firme, 0 = mão aberta (a linha corre).
var grip: float = 1.0
## Enrolando na lata (m/s).
var reel_rate: float = 0.0
## DESBICO segurado: dedo encostou (lado de cada toque: −1 esquerda, +1 direita) …
var desbico_press: Array[float] = []
## … e quantas vezes soltou (retoma a linha).
var desbico_release: int = 0
## Força do desbico pedida pelo gesto (0..1; teclado = 1).
var desbico_intensity: float = 1.0
## Desbicos de toque completo (teclado/compatibilidade): lado de cada um.
var taps: Array[float] = []
## PUXÃO: toques no botão desde a última leitura e se o botão está segurado.
var pull_taps: int = 0
var pull_held: bool = false
## Desbicadas duplas pedidas de uma vez (teclado).
var double_taps: int = 0
## JOGAR para o lado (duplo toque): desbico forte + puxão na hora certa (lado ±1).
var throws: Array[float] = []
## GUIAR (dedo segurado): posição do dedo na tela (a pipa vira o bico para ele).
var guide_active: bool = false
var guide_finger := Vector2.ZERO
## Guiar por direção no mundo (testes/teclado): usado se guide_active for falso.
var guide_dir := Vector3.ZERO
var guide_amount: float = 0.0
## DESBICOS por toque desde a última leitura (os lados alternam sozinhos).
var desbico_toques: int = 0
## PUXÕES de recolher (arrastar de cima para baixo): tamanho de cada arrasto 0..1.
var recolhe: Array[float] = []
## Puxada contínua (segurar arrastado para baixo): 0..1 = ritmo da mão sobre mão.
var pull_rate: float = 0.0
## O toque virou arrasto logo no começo: aborta o desbico.
var cancel_desbico: bool = false
## Ciclos pedidos no HUD: tamanho da pipa / envergadura / rabiola.
var size_cycle: int = 0
var bow_cycle: int = 0
var tail_cycle: int = 0
## Modo do gesto atual (para feedback visual): "", "puxar", "soltar", "enrolar".
var gesture_mode: String = ""


func press_desbico(side: float) -> void:
	desbico_press.append(side)


func release_desbico() -> void:
	desbico_release += 1


func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
