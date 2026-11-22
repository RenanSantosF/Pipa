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
## Modo do gesto atual (para feedback visual): "", "puxar", "soltar", "enrolar".
var gesture_mode: String = ""


func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
