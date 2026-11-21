extends Node
## Sinais globais do jogo. Autoload "EventBus".
## Use apenas para eventos que interessam a vários sistemas desacoplados
## (HUD, som, rede no futuro). Lógica direta entre sistemas usa referências injetadas.

signal kite_crashed(position: Vector3)
signal kite_launched
signal line_snapped(position: Vector3)
signal reset_requested
