class_name PlayerIntent
extends RefCounted
## Intenções do jogador num frame, independentes do dispositivo de entrada.
## Produzido por InputRouter; consumido por FPController e KiteLine.
## (No multiplayer, é também o que será resumido e enviado ao servidor.)

## Movimento: x = direita, y = frente. Comprimento <= 1.
var move: Vector2 = Vector2.ZERO
## Rotação de câmera acumulada (graus) desde a última leitura.
var look_delta: Vector2 = Vector2.ZERO
## Segurando "puxar" (puxada de mão).
var pull: bool = false
## Segurando "soltar" (dar linha).
var release: bool = false
## Segurando "recolher" (enrolar linha na lata).
var reel: bool = false


## Retorna a rotação acumulada e zera o acumulador.
func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d


func is_handling_line() -> bool:
	return pull or release or reel
