# Desbico e puxão (v0.6)

Revisão dedicada aos dois comandos da pipa. O voo (aerodinâmica, linha, rabiola,
cruzamento) foi **preservado**; só mudou a mão do pipeiro (`KiteHand`), um
momento aerodinâmico da vela relaxada (`KiteRigidBody`) e a entrada (gestos/botão).

Medições com a sonda `-- --controlprobe --seq=desbico|puxao|combo|spam`
(linha de 25 m, vento 6,5 m/s, pipa M, envergadura média).

## 1. O que estava errado (medido antes de mudar)

| | Antes (v0.5) |
|---|---|
| Nariz no desbico | 21° → 12° → volta: **nunca apontava para baixo** |
| Trajetória | 4 m de lado, só 0,6 m para baixo: "elevador lateral" |
| Escorregamento* | **70–108°**: a pipa andava de lado, contra a própria orientação |
| Folga | 0,05 s (3,6 N) e logo um tranco programado a 10 N: nunca perdia sustentação |
| Puxão | arrastar 230 px para baixo; encostar o dedo já disparava um desbico; a pipa só subia +0,2 m |

\* ângulo entre a velocidade da pipa no plano perpendicular à linha e a direção do nariz.

**Causas:**
1. O desbico era uma **sequência fixa de 0,55 s** (folga 0,07 s + tranco + volta) —
   uma animação de entradas, não um comando contínuo.
2. A folga era curta demais para a linha (25 m de linha com barriga absorvem 22 cm
   de mão em 0,07 s): a tensão quase não caía.
3. O lado vinha de deslocar o ponto do cabresto e torcer a vela, o que gira a
   **face** da vela (guinada) e gera **força lateral** → a pipa desliza de lado.
4. O puxão é o que faz a pipa ir para onde o bico aponta — mas o bico nunca virava,
   então o puxão não tinha para onde mandar a pipa. E a entrada (arrasto longo,
   conflito com o toque do desbico) atrasava e travava.

## 2. Desbico (como funciona agora)

**Segurar = dar linha; soltar = retomar.** Nada posiciona nem gira a pipa.

1. **Folga real**: o braço vai 35 cm à frente e a mão fica *entreaberta*: a linha
   corre quando a tensão passa de ~3 N. A tensão no cabresto cai de ~8 N para ~3 N.
2. **Perda de sustentação**: sem tensão o cabresto não segura mais o ângulo da vela;
   a velocidade do ar cai e a pipa começa a cair.
3. **O bico gira (física da pipa de combate)**: a vareta envergada, carregada, fica
   simétrica; **sem carga ela relaxa torta** (para o lado do jeito de soltar) e o
   vento na vela torta faz um momento em torno da **normal** — gira o bico, sem
   força lateral. O momento é proporcional a `q·A·h·relaxação`, e a relaxação vem
   da **tensão real** no cabresto (some com a linha esticada). Envergadura pouca =
   vareta mole → gira mais (arisca); muita → gira menos (desbico fino).
4. **Mergulho diagonal**: com o bico para o lado e para baixo, a tensão que ainda
   resta leva a pipa **pela orientação dela**, na diagonal; a gravidade faz a curva.
   A vareta relaxada também aparece no modelo (asas acompanham).
5. **Recuperação gradual**: ao soltar, a mão fecha (0,18 s) e o braço volta (0,45 s);
   a linha estica, a vareta volta a envergar, o momento some e a rabiola (pêndulo) +
   o cabresto trazem o bico de volta, com uma oscilação amortecida.

Medido (segura 1,0 s): rumo até **−111°**, nariz até **−26°** (para baixo), −4 m de
lado e −1,7 m de altura no 1º segundo; ao soltar segue por inércia ~0,7 s e sobe
(rumo −99° → −15° em ~1,4 s, passa a +15° e assenta). Toque curto (0,3 s): rumo ~30°
e volta. Escorregamento durante o mergulho ~35–50° (a pipa afunda um pouco abaixo
do bico com pouca tensão — o natural para uma placa leve) contra 70–108° antes.

## 3. Puxão (como funciona agora)

**Arranque do braço**: 0,6 m em 0,09 s (pico ~10 m/s), mão fechada.
* Tensão: **7,7 → 16 N em 0,1 s**, depois cai aos poucos (~0,6 s) — o braço
  devolve devagar (0,42 s).
* A pipa responde na hora mas com inércia: "cabeceia" (ângulo de ataque 21° → 25°
  → 18° → volta) e acelera **para onde o bico aponta** (é a sustentação que cresce
  com o vento aparente — não um aumento artificial de velocidade). Parada no centro
  da janela isso dá uma subida pequena; depois de um desbico a manda na direção do
  bico (6–8 m/s).
* **Puxões seguidos**: o braço não volta todo; no fim do curso a outra mão pega a
  linha mais à frente (**mão sobre mão**): a tensão sobe em degraus (15 → 16 → 19 N)
  e a linha é recolhida (4 puxões em 0,22 s ≈ 2 m).
* **Puxar enquanto dá linha** (arrastando para cima) = puxada "correndo linha": a
  linha escorrega no tranco e a pipa sobe ganhando linha.
* **Soltando da mão** (linha < 18 m ou pipa < 14 m acima da mão), o tranco é o de
  levantar pipa: cede um pouco, puxa de lado alternando (zigue-zague — a pipa cruza
  o vento, ganha velocidade e sobe) e a linha corre se ela já estiver alta. É o mesmo
  movimento que fazia a pipa subir da mão na v0.5, preservado.

## 4. Controles no celular

> **v0.7:** os botões saíram — agora é tudo por gestos (arrastar para o lado =
> desbico, toque = puxão). Ver `docs/V07.md`. O texto abaixo descreve a v0.6.

* **Botão PUXAR** (círculo grande no canto inferior direito): o puxão sai **no
  instante do toque** (não espera soltar). Toques seguidos = puxões seguidos;
  segurar = puxões em série (a cada 0,3 s). Anel pulsa a cada puxão.
* **Desbico**: encostar e **segurar** na metade esquerda/direita da tela = dar linha
  para aquele lado; soltar = retomar. Dois toques rápidos = desbicada dupla. Se o
  dedo começar a arrastar (olhar / gestos de linha), o desbico termina na hora.
* Teclado (testes): segurar ←/→ ou clique esquerdo/direito = desbico; F = puxão;
  Espaço = dupla; G = braçada lenta.

## 5. Arquivos

* `src/physics/kite_hand.gd` — mão do pipeiro reescrita (estados de desbico,
  retomada, puxão, tranco de soltar da mão).
* `src/physics/kite_rigid_body.gd` — relaxação da vareta (`relax`, `spin_bias`):
  momento em torno da normal e diedro relaxado/torto.
* `src/physics/kite_rig.gd` — relaxação calculada pela tensão no cabresto; `regrip`
  (mão sobre mão).
* `src/kite/kite_profile.gd` — `spin_coef` por envergadura.
* `src/input/*` — botão PUXAR, desbico segurado; `src/ui/icons.gd` — ícone.
* `src/main/control_probe.gd` — sonda de medição.
