# Análise da física da pipa (antes da v0.18)

## 1. Bibliotecas open source avaliadas

Os três projetos foram clonados e o código e a licença foram lidos.

| Projeto | Dimensão | Linguagem | Android | Licença | Veredito |
|---|---|---|---|---|---|
| **Cuberact Library** (CRope2D) | **2D** (Node2D, RigidBody2D) | binário GDExtension fechado | **não** (só macOS, Windows, Linux, Web) | gratuita até publicar; **jogo comercial paga** | não serve: 2D, sem Android, sem código para adaptar. O exemplo `kite.gd` aplica forças inventadas (senos), não aerodinâmica |
| **GDNative-Ropesim** | **2D** (Vector2 em todo o C++) | C++ GDExtension (Godot 4.3+) + GDScript | sim (arm64/x86_64) | MIT | não roda em 3D. O algoritmo (Verlet + restrição de segmento + rigidez + vento) é um subconjunto do que o projeto já tem |
| **Verlet Rope 4** | 3D | GDScript (Godot 4) | sim (é GDScript) | MIT | roda, mas: comprimento fixo, sem medir tensão, pontas presas são cinemáticas e o objeto da ponta é **posicionado** na ponta da corda (acoplamento de mão única — justamente o "mover a pipa artificialmente" que não queremos) |

Conclusão: nenhuma das três tem o que falta. A linha do projeto (`src/physics/rope.gd`) já é
mais completa: XPBD com elasticidade real da linha (complacência = comprimento/EA), tração
medida em cada trecho, comprimento variável com coordenada de material (necessária para o
desgaste/corte), acoplamento nos dois sentidos com corpo rígido, contato com cenário e com
outras linhas. Aproveitamos a ideia de "relaxação por subpasso" (já usada) e mantemos a
linha atual. O que estava errado não era a linha.

## 2. Como estava (v0.13–v0.17)

| Sistema | Script | Situação |
|---|---|---|
| Voo da pipa do jogador | `src/physics/kite_flight_model.gd` | **modelo de ponto cinemático**: a cada subpasso calcula rumo/velocidade por regras e ESCREVE a posição e a orientação da pipa (projetada na esfera da linha). É a "física simplificada que move a pipa artificialmente" |
| Corpo da pipa | `src/physics/kite_rigid_body.gd` | corpo rígido com aerodinâmica por meia-vela (sustentação, arrasto, estol, centro de pressão que anda), diedro da envergadura, relaxação da vareta pela tração. Usado de verdade só pelos vizinhos; o do jogador estava em modo `kinematic` (só translação). Tem também **atalhos artificiais**: servo de giro (`_apply_steer`/`steer_correct`), empurrão (`push_accel`) e torque de giro comandado (`spin_bias`) |
| Cabresto | `KiteRigidBody.tow_local` + `KiteRig.bridle_offset` | **ponto fixo** no corpo (como uma vara); o "deslocamento do cabresto" era um atuador mexido pela mão, não linha |
| Linha | `src/physics/rope.gd` | boa (ver acima); a tração da pipa do jogador era SUBSTITUÍDA pela calculada no modelo de voo |
| Rabiola | `src/physics/tail_chain.gd` | partículas com arrasto; na pipa do jogador não puxava a pipa (desacoplada) |
| Mão / controles | `src/physics/kite_hand.gd`, `src/player/fp_controller.gd`, `src/input/gesture_controls.gd` | toque/arrasto viravam comandos diretos do modelo de voo (`tap()`, `steer`) |
| Corte | `src/physics/line_combat.gd` | contato linha × linha com atrito; desgaste ∝ μ · força normal · deslizamento — já considera contato, tensão e movimento relativo |
| Simulação | `src/physics/kite_physics_world.gd` | subpassos XPBD de todas as pipas juntas |

## 3. O que muda (por etapas)

1. **Cena de teste isolada** `src/lab/physics_lab.tscn` + `src/lab/physics_lab.gd`: chão plano,
   vento controlado, uma pipa, sem cidade. Sondas headless medem equilíbrio, tração, puxão,
   folga, aparar/soltar, desbico e cabresto.
2. **Cabresto de verdade** (`src/physics/bridle.gd` + `rope.gd`): a linha é amarrada num
   **nó** preso à pipa por **duas pernas de linha** (na cabeça da vareta e embaixo). O nó
   escorrega nas pernas conforme a linha puxa; a posição dele em relação ao centro de
   massa decide o ângulo de ataque, a inclinação e a estabilidade. (Primeiro foi feito
   como partícula leve; no laboratório ela só transmitia ~20% da tração no passo de
   física do celular, então virou nó sem massa em equilíbrio — exato para um cabresto
   de ~1 g numa pipa de 30 g. Ver docs/V18.md §4.)
3. **Pipa física** (`kite_rig.gd`, `kite_rigid_body.gd`): a pipa do jogador volta a ser corpo
   rígido de verdade (forças e torques: peso, sustentação/arrasto por meia-vela, linha pelo
   cabresto, rabiola acoplada). Sem servo, sem empurrão, sem posição escrita.
4. **Controles só pela linha** (`kite_hand.gd`, `fp_controller.gd`): toque = puxadinha (o
   braço dá folga e estica a linha em ~0,25 s); arrastar para baixo = braçada que recolhe;
   arrastar para cima = abrir a mão (a linha corre com a tração); aparar/soltar = mudar o
   comprimento da linha.
5. **Corte**: o contato passa a ver o nó do cabresto como ponta da linha (laço no cabresto).
6. **Integração** no jogo e no teste automático do CI, mantendo o modo anterior disponível
   até a física nova ser validada.

## 4. Resultado

Feito na 0.18 — medições, achados e limites em `docs/V18.md`.
