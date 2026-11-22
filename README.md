# Pipa — Nostalgia Online

Jogo de pipa em primeira pessoa num bairro brasileiro, para Android (Godot 4.7 / GDScript).

- Arquitetura e plano: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
- Física da pipa: [`docs/FISICA_PIPA.md`](docs/FISICA_PIPA.md)
- **Etapa atual: 1.5 — física completa de pipa, linha, rabiola e combate (offline, com adversário)**

## Como baixar o APK pelo celular

Cada push gera um APK automaticamente (GitHub Actions):

1. No GitHub, abra **Releases** → **apk-latest** → baixe `pipa-debug.apk`.
2. No Android, permita instalar de "fontes desconhecidas" para o navegador/app de arquivos.
3. Instale e jogue (o jogo abre na horizontal).

Também ficam disponíveis: o *artifact* `pipa-debug-apk` na execução do workflow e a branch `apk-builds`.

## Controles (gestos — sem botões de ação)

| Gesto | Onde | O que faz |
|---|---|---|
| Arrastar **para baixo** | metade direita | **braçada**: a distância do arrasto é o tamanho do puxão e a velocidade do dedo é a força. Ao tirar o dedo, a mão volta e a linha puxada fica **no chão** |
| Arrastar **para cima** | metade direita | **abrir a mão / dar linha**: quanto mais alto, mais solta. A linha corre com a força da pipa |
| Fazer **círculos** | metade direita | **enrolar na lata**: enrola primeiro a linha do chão, depois a que voa |
| Arrastar | faixa de cima | olhar em volta. A câmera **volta para a pipa sozinha, como uma mola** |
| Joystick flutuante | metade esquerda | andar |
| **NOVA** / **LINHA** | canto superior direito | nova pipa / trocar o tipo de linha (pura, rapinha, cerol, cerol fino, chilena) |

PC (testes): WASD anda · botão direito prende o mouse · Espaço = braçada · E = dar linha · Q = enrolar · R = nova pipa · T = trocar linha · F1 debug · F2 qualidade.

## Como é a física (resumo)

- A pipa é um **corpo rígido** com aerodinâmica de placa plana: **embica** (mergulha para onde o bico aponta com a linha esticada), **desbica** (dando linha, a rabiola endireita a pipa), anda para onde aponta e sobe com braçadas.
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
