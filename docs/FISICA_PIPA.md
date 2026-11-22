# Física da pipa, da linha, da rabiola e do corte (v2)

Tudo é simulado junto num único solver **XPBD com subpassos** ("small steps"):
6/8/10 subpassos por tick de 60 Hz (qualidade baixa/média/alta).
Código: `src/physics/`. Protótipo de validação: Python (mesmo modelo), antes do port.

## 1. Linha (`rope.gd`)

- Corrente de partículas; cada segmento é um **cabo unilateral**: só resiste à tração.
  Frouxa, a linha não empurra a pipa — ela cai, faz curva, ondula.
- **Elasticidade real**: compliance do segmento = comprimento / EA (EA ≈ 800–950 N).
- **Barriga**: arrasto do vento por segmento, só na componente normal ao segmento
  (cilindro, Cd ≈ 1,1) + atrito tangencial pequeno + peso da linha (0,4–0,55 g/m).
  Linha mais grossa (cerol) faz mais barriga. Linha comprida com barriga "não responde":
  a braçada primeiro estica a barriga — efeito emergente, igual ao real.
- **Material**: cada nó carrega a coordenada de material *s* (metros a partir da pipa).
  A linha entra e sai pela mão (o primeiro segmento cresce/encolhe e nós são inseridos
  ou removidos perto da mão), sem "teleportar" material.
- Tensão = multiplicador de Lagrange do segmento / h² (na mão e no cabresto).

## 2. Pipa (`kite_rigid_body.gd`)

Corpo rígido 6DOF (posição, quaternion, velocidades linear e angular), inércia de placa.

- Duas meias-velas com **diedro** (6°): estabilidade lateral, como a pipa "embarrigada".
- Cada meia-vela é uma **placa plana**: força normal `q·A·Cn(α)`;
  `Cn = lerp(4·sinα·cosα, 1,25·sinα, smoothstep(15°, 30°, α))` → perda de sustentação.
- **Centro de pressão móvel**: de 1/4 da corda no bordo de ataque (α pequeno) até o
  centro (α = 90°), na direção do escoamento sobre a vela.
- **Cabresto** = ponto de reboque fixo no corpo (22% da altura a partir do nariz, 22 cm à
  frente da vela). O equilíbrio entre centro de pressão, cabresto, peso e rabiola dá o
  ângulo de ataque (~15°) e a elevação (~55°) sozinho.
- Velocidade local inclui ω×r e há amortecimento aerodinâmico de rotação.

### Comportamentos emergentes (validados no protótipo)
| Situação | Resultado |
|---|---|
| Linha esticada, nariz para o lado/baixo | **embica**: mergulha na direção do nariz |
| Dar linha (mão aberta) | perde tensão, cai de "paraquedas", a rabiola gira o nariz para cima (**desbica**) |
| Segurar de novo | volta a puxar e sobe forte |
| Braçada com nariz para cima | ganha velocidade e sobe |
| Vento fraco (3 m/s) | não se sustenta |

## 3. Rabiola (`tail_chain.gd`)

Corrente de partículas (tiras de plástico) presa na ponta de baixo por uma restrição
**com o corpo rígido** — o arrasto e o peso dela voltam para a pipa como torque.
É ela que endireita a pipa com a linha frouxa e segura o balanço. Rabiola curta = pipa
mais "doida" (o bot usa uma mais curta). `tail_abrasion` > 0 = rabiola com cerol.

## 4. Mão, braçada, lata (`kite_rig.gd`)

- **Braçada**: a mão (nó 0) recua até 0,75 m a até 6 m/s. Quando a mão volta para pegar
  de novo, a outra mão segura: o trecho puxado vai para o **chão** (`pile`).
- **Dar linha**: a pegada vira atrito (0–40 N). Se a tensão vence a pegada, a linha corre
  (com inércia da linha + lata girando). Sai primeiro a linha do chão, depois a da lata.
- **Recolher**: enrola primeiro a linha do chão; depois puxa a linha que voa, mais devagar
  quanto maior a tensão.
- Tensão acima do limite da linha → **arrebenta na mão**.

## 5. Cruzamento e corte (`line_combat.gd`)

1. **Detecção** por tick (AABB → grupos de 4 segmentos → segmento×segmento).
2. **Contato** por subpasso: cada contato guarda a normal (o lado) e mantém uma folga de
   3 mm — as linhas não se atravessam; a tração aperta uma contra a outra. O contato
   desliza para os segmentos vizinhos conforme as linhas correm.
3. **Desgaste** por tick: `E = μ·N·v_desliz·dt` (N = força do contato).
   Cada linha recebe `E × abrasão_da_outra / resistência_própria`, **espalhado pelo
   trecho de material dela que passou pelo contato** (bins de 10 cm).
   - Quem **dá linha** ou **puxa rápido** passa material novo pelo contato → espalha o
     próprio desgaste e concentra o do adversário.
   - Quem fica parado concentra o desgaste num ponto → é cortado.
   - Linha esticada corta mais fácil (limite cai até 40% com a tensão).
4. **Corte**: a linha é dividida no material; a pipa com o trecho do lado dela vira
   "pipa voada" (simulada até sair do mapa); a sobra fica na mão e pode ser recolhida.

### Tipos de linha (`src/physics/lines/*.tres`)
| Linha | Abrasão | Resistência | Ruptura | Observação |
|---|---|---|---|---|
| Pura | 0,02 | 0,6 | 40 N | praticamente sem chance contra cerol |
| Rapinha | 0,35 | 0,8 | 36 N | revestimento leve |
| Cerol | 0,75 | 1,0 | 34 N | |
| Cerol fino | 0,95 | 1,1 | 32 N | |
| Chilena | 1,4 | 1,45 | 30 N | a mais cortante, mais pesada |

Tempo típico de corte com o adversário parado e você puxando a ~2 m/s com 2 N de contato:
chilena × pura ≈ 0,6 s · cerol × cerol ≈ 2 s · pura × pura ≈ 40 s.

> Cerol e linha chilena são proibidos e perigosos na vida real (causam acidentes graves).
> No jogo eles existem apenas como mecânica de combate.

## 6. Teste automático (CI)
`src/main/autotest.gd`: voo de 30 s (sustentação, dar linha, braçadas, recolher) e
combate determinístico em X (chilena × pura → a pura tem que ser cortada).
