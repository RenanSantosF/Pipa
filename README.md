# Pipa — Nostalgia Online

Jogo de pipa em primeira pessoa num bairro brasileiro, para Android (Godot 4.7 / GDScript).

- Arquitetura e plano: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
- Física da pipa: [`docs/FISICA_PIPA.md`](docs/FISICA_PIPA.md)
- **Etapa atual: 1.5 — física completa de pipa, linha, rabiola e combate (offline, com adversário)**

## Como baixar o APK pelo celular

> O app agora se chama `br.pipa.nostalgia` e usa sempre a mesma chave (`android/debug.keystore`): instala ao lado de qualquer versão antiga e cada atualização instala por cima da anterior.

Cada push gera um APK automaticamente (GitHub Actions):

1. No GitHub, abra **Releases** → **apk-latest** → baixe `pipa-debug.apk`.
2. No Android, permita instalar de "fontes desconhecidas" para o navegador/app de arquivos.
3. Instale e jogue (o jogo abre na horizontal).

Também ficam disponíveis: o *artifact* `pipa-debug-apk` na execução do workflow e a branch `apk-builds`.

## Controles (só gestos — sem botões)

Quase a tela inteira é da pipa; um dedo controla tudo:

| Gesto | O que faz |
|---|---|
| **Arrastar para o lado** (esquerda/direita) | **desbico** para aquele lado: enquanto o dedo está fora do centro a mão dá linha e o **bico vai girando** para o lado — quanto mais longe o dedo, mais rápido gira. Voltar ao centro ou soltar = retoma a linha e ela se firma |
| **Toque rápido** | **puxão**: a pipa dispara para onde o bico aponta; toques seguidos = puxões seguidos (mão sobre mão) |
| Desbica e toca | a jogada básica: desbica até o bico apontar para onde você quer e toca |
| **Arranque para baixo** | puxão forte; continuar descendo = braçada (a linha puxada vai para o chão) |
| Arrastar **para cima** | abrir a mão / **dar linha** |
| **Círculos** | enrolar na lata |
| Faixa estreita no topo, ou **dois dedos** | olhar em volta (a câmera volta para a pipa como mola) |
| Canto inferior esquerdo | andar (joystick) |
| Ícones no canto | nova pipa · trocar linha · som · **tamanho P/M/G** · **envergadura** |

A pipa **começa na mão**: vá dando toques (puxões — perto do chão eles saem de lado, em zigue-zague) e, com ela subindo, arraste para cima para dar linha.
**Envergadura** (quanto a travessa é arqueada) muda tudo: muita envergadura = pipa estável, desbico **fino e curto**; pouca = desbico **longo**, pipa arisca.

**Encostar não é enroscar**: a linha que encosta em fio, telhado, poste ou galho **desliza** com atrito (barrida). Ela só **enrosca** quando dá volta, cai por cima de um galho ou aperta forte contra a casca. Solta quando endireita, ou com tranco até o galho quebrar. No fio ela nunca trava: fica pendurada e escorrega ao longo dele. A pipa só prende se o fio/galho entrar no cabresto (ou se cair fundo na copa).

PC (testes): segurar clique esquerdo/← = desbico esquerda · segurar clique direito/→ = desbico direita · F = puxão · Espaço = dupla · Tab = olhar com o mouse · E = dar linha · G = braçada lenta · Q = enrolar · R = nova pipa · T = trocar linha · Y = tamanho · U = envergadura.

Detalhes do desbico e do puxão: `docs/DESBICO_PUXAO.md`. O que mudou na 0.7 (pipa da foto, gestos, linha fina, desempenho): `docs/V07.md`.

## Como é a física (resumo)

- A pipa é a **pipa brasileira** de duas varetas: vareta passando acima do papel (cabeça), travessa envergada na borda de cima, papel em pentágono e linhas da cabeça às pontas da travessa. É um **corpo rígido** com aerodinâmica de asa de baixo alongamento (sustentação e arrasto explícitos, estol tardio); cada meia-vela tem o diedro da envergadura. No **desbico** a mão dá linha, a vareta descarregada relaxa torta e o vento gira o bico; a tensão que sobra leva a pipa para onde o bico aponta.
- A **linha** é simulada nó a nó: faz **barriga** com o vento, estica, afrouxa, ondula com a braçada.
- **Combate**: quando as linhas cruzam, o cerol desgasta a outra linha. Quem **dá linha** ou **puxa rápido** espalha o próprio desgaste; quem fica parado é cortado. Chilena > cerol fino > cerol > rapinha >> pura. Uma linha que chega na outra pipa **laça no cabresto**.
- Sons em 3D: papel da pipa, linha "cantando" (tom sobe com a tensão), chiado do cerol relando, estalo do corte, catraca da lata.

Detalhes: [`docs/FISICA_PIPA.md`](docs/FISICA_PIPA.md).

> Cerol e linha chilena são proibidos e perigosos na vida real. No jogo eles existem apenas como mecânica.

## Estrutura

```
src/autoload   GameConfig, EventBus, Wind (vento determinístico)
src/physics    XPBD: Rope (linha), KiteRigidBody (pipa), TailChain (rabiola),
               KiteRig (pipa completa + lata), LineCombat (cruzamento/corte),
               KitePhysicsWorld (simula tudo junto), tipos de linha (.tres)
src/input      PlayerIntent, InputRouter, GestureControls (gestos)
src/player     controlador 1ª pessoa + câmera mola
src/character  skin teen_01 (Rua 10) + IK dos braços
src/bot        adversário que empina e tenta cortar
src/audio      sons sintetizados e posicionais
src/kite       perfis e visual da pipa e da rabiola
src/line       desenho da linha
src/world      bairro gerado por seed, shader de árvores, ambiente
src/ui         HUD, indicador de vento, overlay de debug
src/main       cena principal e teste automático do CI
```
