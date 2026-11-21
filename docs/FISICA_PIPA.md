# Física da pipa (Etapa 1)

Implementação: `src/kite/kite_body.gd`, `src/line/kite_line.gd`, parâmetros em `src/kite/profiles/pipa_classica.tres`.
O modelo foi prototipado e ajustado em Python antes da implementação, e é verificado
a cada push pelo teste automático (`src/main/autotest.gd`).

## Translação (4 subpassos por tick de 1/60 s)

- Vento relativo: `v_rel = vento(p, t) − v`, `q = ½·ρ·|v_rel|²`
- Ângulo de ataque: `sin α = −dir(v_rel) · n` (n = normal da face voltada ao jogador)
- Força normal de placa plana: `F = −n · q · A · Cn(α)`
  - `Cn = lerp(4·sinα·cosα, 1,25·sinα, smoothstep(15°, 30°, α))` → perda de sustentação suave
- Arrasto parasita + rabiola na direção de `v_rel`
- Gravidade, metade do peso da linha, arrasto do vento na linha (∝ comprimento)

## Linha (restrição unilateral)

- Frouxa: nenhuma força. Esticada: projeta a posição e remove a velocidade radial
  acima da taxa de variação do comprimento efetivo (soltar / puxada).
- Tensão = impulso removido / dt (filtrada). Acima de `break_tension` a linha arrebenta.
- Puxada: encurta o comprimento efetivo em até 0,9 m a 4 m/s → aumenta o vento relativo.

## Orientação

- Base alinhada à linha com o ângulo do cabresto (20°): `s = s0·cos b − d·sin b`, `n = −d·cos b − s0·sin b`.
- Rumo ψ (giro em torno da linha): `ψ'' = −k_rabiola·q·sin ψ − c·ψ' + turbulência`.
- Como a força normal inclina com o nariz, a pipa anda para onde aponta.
- Linha frouxa: a base tende ao vento relativo ("paraquedas") e gira mais.

## Resultados do protótipo (linha 30 m)

| Vento (10 m) | Elevação de equilíbrio | Tensão | Comportamento |
|---|---|---|---|
| 3 m/s | — | — | não se sustenta, cai |
| 6 m/s | ~61° | 2–4 N | estável, oscila ±20° no rumo |
| 10 m/s | ~62° | 6–12 N | estável, puxa forte |
