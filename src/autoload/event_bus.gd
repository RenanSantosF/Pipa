extends Node
## Sinais globais do jogo. Autoload "EventBus".
## Use apenas para eventos que interessam a vários sistemas desacoplados
## (HUD, som, vibração, rede no futuro).

## A pipa bateu em algo: posição, velocidade do impacto (m/s) e superfície ("chão", "telhado", "folhas").
signal kite_crashed(position: Vector3, speed: float, surface: String)
signal kite_launched
signal line_snapped(position: Vector3)
## Uma linha cortou a outra (cerol). winner/loser são KiteRig.
signal line_cut(winner: Node, loser: Node)
## Pipa ou linha enroscou (árvore, poste, fio, telhado).
signal kite_snagged(rig: Node, what: String)
signal reset_requested
