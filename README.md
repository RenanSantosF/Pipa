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
| **Toque** na metade esquerda / direita | **desbico** para aquele lado (o bico gira e ela mergulha um pouco); funciona até perto do chão. Vá tocando para ir **desbicando e descendo** a pipa |
| **Dois toques rápidos** | **joga a pipa** para aquele lado (desbico até o bico apontar + puxão: ela dispara para lá) |
| **Arrastar para o lado** e segurar | desbico contínuo: o bico vai girando enquanto o dedo está fora do centro (mais longe = mais rápido); voltar ao centro ou soltar = retoma |
| **Arrastar e segurar para baixo** | **puxa a linha sem parar** (mão sobre mão): a pipa sobe; quanto mais desce o dedo, mais rápido |
| **Esfregar** para cima e para baixo | cada descida rápida é um puxão a mais: puxa ainda mais rápido |
| Arrastar **para cima** | abrir a mão / **dar linha** |
| **Círculos** | enrolar na lata |
| Segundo dedo | **toque** = puxão (desbica com um polegar e puxa com o outro) · **arrastar** = olhar em volta |
| Faixa estreita no topo | olhar em volta (a câmera volta para a pipa como mola) |
| Joystick (canto inferior esquerdo) | andar |
| Ícones no canto | nova pipa · trocar linha · som · **tamanho P/M/G** · **envergadura** · **rabiola curta/média/grande** |

**Linha enroscada**: dê **trancos fortes** (segure para baixo / esfregue) para desenroscar do galho, tronco ou poste, ou **dê linha** para ela ficar frouxa e cair fora. A pipa presa num fio/galho solta com tranco.

A pipa **começa na mão**: segure arrastado para baixo (puxões — perto do chão eles saem de lado, em zigue-zague) e, com ela subindo, arraste para cima para dar linha.
**Rabiola**: curta = pipa arisca (desbica fácil, mais difícil de segurar); grande = estável e mais lenta.
**Envergadura** (quanto a travessa é arqueada) muda tudo: muita envergadura = pipa estável, desbico **fino e curto**; pouca = desbico **longo**, pipa arisca.

**Encostar não é enroscar**: a linha que encosta em fio, telhado, poste ou galho **desliza** com atrito (barrida). Ela só **enrosca** quando dá volta, cai por cima de um galho ou aperta forte contra a casca. Solta quando endireita, ou com tranco até o galho quebrar. No fio ela nunca trava: fica pendurada e escorrega ao longo dele. A pipa só prende se o fio/galho entrar no cabresto (ou se cair fundo na copa).

PC (testes): segurar clique esquerdo/← = desbico esquerda · segurar clique direito/→ = desbico direita · F = puxão (segurar = em série) · Espaço = dupla · Tab = olhar com o mouse · E = dar linha · G = braçada lenta · Q = enrolar · R = nova pipa · T = trocar linha · Y = tamanho · U = envergadura · J = rabiola.

Detalhes do desbico e do puxão: `docs/DESBICO_PUXAO.md`. O que mudou na 0.7 (pipa da foto, gestos, linha fina, desempenho): `docs/V07.md`; na 0.8 (toque = desbico, jogar, puxar segurando, rabiola, desenroscar, mais leve): `docs/V08.md`.

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
