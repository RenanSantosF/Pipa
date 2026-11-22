extends Node
## Sinais globais do jogo. Autoload "EventBus".
## Use apenas para eventos que interessam a vários sistemas desacoplados
## (HUD, som, vibração, rede no futuro).

signal kite_crashed(position: Vector3)
signal kite_launched
signal line_snapped(position: Vector3)
## Uma linha cortou a outra (cerol). winner/loser são KiteRig.
signal line_cut(winner: Node, loser: Node)
signal reset_requested
