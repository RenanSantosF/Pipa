# Revisão completa: voo, desbico e mundo (v0.5)

Este documento foi escrito **antes** de alterar o código. Ele analisa cada sistema
da versão 0.4 e explica, tecnicamente, o que estava errado na *lógica* (não nos
parâmetros) e como cada sistema foi reescrito.

---

## 0. Mapa da arquitetura (0.4)

```
Entrada (gestos/teclado) → PlayerIntent → FPController ─┐
Bot (BotFlyer) ─────────────────────────────────────────┤→ KiteHand → KiteRig (entradas)
                                                         │
KitePhysicsWorld (60 Hz, 6–10 subpassos XPBD)            │
  ├─ KiteRig.pre_frame   (carretel, forças)              │
  ├─ LineCombat.detect   (contatos linha×linha)          │
  ├─ subpassos: KiteRigidBody / Rope / TailChain / contatos
  ├─ LineCombat.post_frame (desgaste, corte)
  └─ WorldObstacles.collide_rope + wrap_rope (cenário)
StreetBuilder → terreno, ruas, casas, árvores, postes, fios + WorldObstacles
```

O núcleo numérico (XPBD em subpassos, linha unilateral, corpo rígido 6DOF,
coordenada de material, desgaste por energia de atrito) está correto e foi
**mantido**. Os problemas estão nas camadas que *usam* esse núcleo.

---

## 1. Desbico — REESCRITO

### O que a 0.4 fazia
`KiteHand` decidia um rumo-alvo (`steer_target`, 40°–100°) e `KiteRig.predict`
aplicava um **torque PD artificial** em torno do eixo da linha até o bico chegar
nesse rumo (`STEER_KP`, `STEER_KD`). Ou seja: **a pipa era girada diretamente**,
como um sprite, por uma força que não existe no mundo real.

### Por que isso está errado
1. **Não é físico.** Nada liga a mão ao rumo da pipa a não ser a linha. Um torque
   "mágico" ignora tensão, vento, envergadura e cabresto: a pipa vira igual com
   linha frouxa ou esticada, com vento forte ou fraco.
2. **Muda o rumo de forma permanente.** Um controlador PD segura o alvo; ao
   soltar, a pipa fica apontada para o novo lado e "foge" para lá. Por isso a 0.4
   parecia *direcionar* a pipa e não *desbicar*.
3. **Lado escolhido pelo estado** (inverte se passou 0,5 s) em vez de pelo dedo:
   o jogador não controla para que lado vai.
4. **Envergadura não participava**: `bow` só existia no visual.

### Como funciona agora (física pura)
O desbico é uma **sequência de entradas físicas** que a mão realmente produz:

| Fase (s)        | Mão / linha                         | Efeito físico na pipa |
|-----------------|-------------------------------------|-----------------------|
| 0 – 0,07 folga  | mão avança 20–25 cm → tensão cai    | cabresto deixa de segurar o ângulo: o bico "cai" (ângulo de ataque diminui) |
| 0 – 0,25 lado   | puxão lateral carrega UMA perna do cabresto | ponto de tração desloca para o lado → torque T·sen(b)·Δx em torno da normal: o bico gira para esse lado |
| 0 – 0,25 vela   | a vareta envergada daquele lado flexiona | meia-vela do lado fecha (diedro ↑), a outra abre: o **centro de sustentação** desloca lateralmente e surge força lateral |
| 0,07 – 0,20 tranco | mão puxa 45 cm rápido → pico de tensão | ângulo de ataque sobe, a sustentação (que agora aponta para o lado do bico) acelera a pipa: a "braçada" |
| 0,20 – 0,55 retorno | tudo volta ao neutro            | diedro (envergadura) + rabiola restauram o rumo: a pipa **oscila de volta** à trajetória |

* **Toque à esquerda** (metade esquerda da tela / botão esquerdo / A) → desbico para a esquerda.
* **Toque à direita** (metade direita / botão direito / D) → desbico para a direita.
* **Toque duplo** (2º toque em até 0,28 s) → **desbicada dupla**: o primeiro toque já
  sai na hora para o lado dele (sem atraso), e o segundo encadeia o lado oposto
  logo após o tranco. A ordem (E→D ou D→E) depende portanto do último lado usado.
  No teclado, Espaço faz a dupla começando pelo lado contrário ao último.
* Toques seguidos para o mesmo lado acumulam (a pipa vai mais longe), porque cada
  um chega antes do retorno terminar. Nada segura o rumo: soltou, ela volta.

### Envergadura (por que muda tudo)
A envergadura `bow` (quanto as pontas das varetas horizontais vão para trás)
passa a definir o **diedro real** da vela: `diedro = atan(bow / meia_envergadura)`.
* **Mais envergada** → diedro maior → momento restaurador lateral maior e menos
  área projetada: o desbico é **fino e curto** (vira rápido e volta logo, pipa estável).
* **Menos envergada** → diedro menor → restauração fraca: o desbico **abre mais,
  braçada longa**, pipa mais arisca e difícil de segurar.
* A flexão assimétrica máxima também depende da envergadura (vareta mais arqueada
  tem mais curso para fechar), então a "inclinação no desbico" muda junto.
O jogador escolhe a envergadura (pouca / média / muita) no HUD.

---

## 2. Física de voo — REESCRITA

### O que a 0.4 fazia
Placa plana com coeficiente de força normal `Cn(α)` (4·sen α·cos α colado →
1,25·sen α descolado). A sustentação e o arrasto só existiam implicitamente.

### Por que precisa mudar
* `4·sen α·cos α` é a curva de uma asa de grande alongamento (inclinação ≈ 4/rad).
  Uma pipa tem **alongamento ≈ 1** (envergadura² / área). Asas assim têm
  inclinação de sustentação bem menor (≈ 1,7/rad, Helmbold) mais **sustentação de
  vórtice** não linear (Polhamus), e estolam tarde (~35–40°). Com o modelo antigo a
  pipa tinha sustentação demais em α pequeno e ficava "colada" no zênite.
* Sem arrasto induzido explícito, a pipa não perdia energia ao subir de frente
  para o vento, então não "voltava devagar".
* Sem turbulência na escala da pipa, ela ficava parada demais sem comando.

### Como funciona agora
Por meia-vela (cada uma com seu diedro e sua velocidade local, incluindo ω×r):
* `CL(α) = Kp·sen α·cos²α + Kv·cos α·sen²α` (Polhamus, Kp ≈ 1,9 para AR≈1,1;
  Kv ≈ π) com transição suave para placa descolada `CN = 1,17·sen α` após o estol.
* `CD(α) = CD0 + CL·tan α` (força normal + arrasto induzido de baixo alongamento)
  — cresce com a velocidade (q = ½ρv²) **e** com a inclinação excessiva.
* Força = q·A·(CL·**l̂** + CD·**v̂**), com **l̂** ⟂ ao vento no plano da normal: a
  sustentação é calculada *a partir* do vento e do ângulo da vela; o ângulo vem do
  equilíbrio com a **tensão da linha** no cabresto.
* Centro de pressão móvel (¼ → ½ corda com α) e diedro por meia-vela dão as
  estabilidades de arfagem e lateral.
* **Zênite**: quando a pipa sobe toda contra o vento, o vento relativo fica quase
  paralelo à vela → α → 0 → CL cai e CD domina: ela perde velocidade e volta
  devagar para a janela de vento. Isso emerge do modelo, sem regra especial.
* **Oscilação natural**: turbulência atmosférica (ruído 3D de alta frequência
  proporcional à velocidade e à rugosidade do bairro) + dinâmica da rabiola.

---

## 3. Modelo visual da pipa — REESCRITO

A 0.4 tinha 8 triângulos chapados, linhas sem sombreamento e varetas-caixa.
Agora: pipa **losango** tradicional brasileira de combate com 3 varetas (espinha +
travessa principal envergada no ponto mais largo + travessa inferior), vela em
malha subdividida que **curva junto com a envergadura** (e flexiona no desbico),
papel de seda translúcido (luz atravessa), bainha, varetas de bambu cilíndricas
aparecendo por trás do papel, cabresto de 3 pernas, sombreamento suave perto das
varetas (profundidade), sombra projetada e tremulação de vento na GPU
(proporcional à velocidade do ar). Tamanhos P / M / G = 50 / 65 / 80 cm.

---

## 4. Linha × linha — AMPLIADO

O contato unilateral com detecção contínua (coordenada de material) já impedia
atravessar. Faltava **atrito no contato**: a 0.4 só empurrava na normal, então as
linhas deslizavam uma sobre a outra sem resistência. Agora cada contato aplica
atrito de Coulomb posicional (estático/cinético, μ do par de linhas) a partir da
correção normal do subpasso: linhas pressionadas "pegam" e escorregam com
resistência, o que muda o relo e a distribuição do desgaste.

---

## 5. Linha × obstáculos — REESCRITO

### O que a 0.4 fazia
`wrap_rope` inseria um **nó preso** sempre que qualquer segmento encostava num
obstáculo. Encostar = enroscar. `collide_rope` ainda multiplicava a velocidade por
0,12 na copa (a linha "grudava").

### Por que está errado
Encostar não prende linha de verdade. Uma linha esticada sobre um galho, telhado
ou fio **desliza** com atrito; ela só fica presa quando dá volta (ângulo de
abraçamento grande, atrito de cabrestante e^(μθ) segura), quando cruza por cima de
um galho e trava numa forquilha, ou quando a tensão aperta contra uma superfície
áspera até o atrito estático vencer.

### Como funciona agora
* **Nó de contato deslizante** (não preso): o trecho que cruza um obstáculo ganha um
  nó que fica na superfície (restrição unilateral por subpasso) e escorrega com
  atrito de Coulomb nas duas direções: *ao longo* do obstáculo (barrida no fio, no
  beiral) e *através* do contato (linha correndo por cima, razão de tensões
  limitada por e^(μθ)).
* **Enrosco** só quando: (a) ângulo de abraçamento θ passa do limite do tipo;
  (b) a linha cruzou por cima e caiu dos dois lados (enganchou); (c) o atrito
  estático segurou com tensão alta por um tempo (apertou). Soltar: θ volta a ser
  pequeno, um tranco quebra o galho, ou a linha desliza para fora da ponta.
* **Detecção contínua** contra obstáculos finos (fio de 1 cm, galho): mesmo teste de
  lado usado entre linhas, para a linha não atravessar entre quadros.
* **Comportamento separado por tipo** (nada de colisão genérica):
  * **Linha × Árvore** — folhagem é volume poroso (só arrasto, a linha atravessa
    devagar); quem segura são **galhos e tronco** (cápsulas). Casca áspera μ≈0,6,
    forquilhas prendem quando a linha cai dentro; galho fino quebra com tranco.
  * **Linha × Poste** — cápsula de concreto μ≈0,4: a linha desliza em volta; só
    prende ao dar volta (θ > 150°) ou na cruzeta.
  * **Linha × Fio** — cápsula fina e lisa μ≈0,15: a linha escorrega ao longo do fio
    (barrida) e fica pendurada se cair por cima com os dois lados para baixo.
  * **Linha × Telhado/Muro** — caixa com quinas: a linha passa por cima do beiral e
    da cumeeira deslizando (barrida) com atrito da telha μ≈0,55; não prende sozinha.
* A **pipa** também não gruda mais ao encostar: colide e quica/desliza; só fica presa
  na copa se entrar fundo na folhagem sem vento, ou no fio/galho se ele passar entre
  o cabresto e a vela (o cabresto engancha).

---

## 6. Árvores — REESCRITAS

Antes: cilindro + bolos de cartões. Agora geradas por ramificação: tronco com
afunilamento, curvatura e base alargada (caiado de branco, como nas calçadas),
3–5 galhos primários na forquilha, galhos secundários, e copa volumosa feita de
aglomerados de folhas nas pontas dos galhos (com variação de tom e escurecimento
no interior da copa). Espécies urbanas brasileiras: mangueira, sibipiruna/oiti,
ipê (florido), coqueiro, bananeira. Tamanhos P/M/G (5–7, 8–11, 12–15 m). Os galhos
viram cápsulas de colisão: é neles que a linha enrosca.

---

## 7. Escala 1:1

| Elemento | 0.4 | 0.5 |
|---|---|---|
| Personagem | 1,64 m | **1,70 m** |
| Poste | 9 m | **10,5 m** (fios em 10 / 8,5 / 6,5 m) |
| Casa térrea | 2,8 m + telhado | 2,8 m pé-direito + laje, telhado ≤ 4 m |
| Árvore urbana | 4–14 m | **5–15 m** (P/M/G) |
| Pipa | 66 cm | **50 / 65 / 80 cm** |

---

## 8. Som

Novo som de **impacto da pipa** (papel + bambu batendo no chão/telha/árvore),
sintetizado, posicional 3D com atenuação por distância e intensidade pela
velocidade do impacto.
