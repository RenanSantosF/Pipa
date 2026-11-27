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
## A linha desenroscou (tranco ou linha frouxa).
signal line_freed(rig: Node, what: String)
signal reset_requested
## A linha de `catcher` enroscou numa pipa voada (`kite`) / trouxe ela até a mão (aparou).
signal loose_kite_hooked(catcher: Node, kite: Node)
signal kite_caught(catcher: Node, kite: Node)
## A pipa voada enganchada escorregou da linha (puxão forte demais).
signal loose_kite_slipped(catcher: Node, kite: Node)
## A linha de `catcher` pegou a rabiola de `target` (sem cerol: arrasta pela rabiola).
signal tail_grabbed(catcher: Node, target: Node)
## A rabiola de `target` foi cortada (cerol) ou arrebentou presa na linha de `by`.
signal tail_cut(by: Node, target: Node, position: Vector3)
