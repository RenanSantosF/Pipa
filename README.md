# Pipa — Nostalgia Online

Jogo de pipa em primeira pessoa num bairro brasileiro, para Android (Godot 4.7 / GDScript).

- Arquitetura e plano: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
- Física da pipa: [`docs/FISICA_PIPA.md`](docs/FISICA_PIPA.md)
- **Etapa atual: 1 — demonstração offline jogável**

## Como baixar o APK pelo celular

Cada push gera um APK automaticamente (GitHub Actions):

1. No GitHub, abra **Releases** → **apk-latest** → baixe `pipa-debug.apk`.
2. No Android, permita instalar de "fontes desconhecidas" para o navegador/app de arquivos.
3. Instale e jogue (o jogo abre na horizontal).

Também ficam disponíveis: o *artifact* `pipa-debug-apk` na execução do workflow e a branch `apk-builds`.

## Controles

| Ação | Celular | PC (testes) |
|---|---|---|
| Andar | joystick (metade esquerda da tela) | WASD / setas |
| Olhar | arrastar no resto da tela | botão direito do mouse prende o cursor |
| Puxar linha | **PUXAR** (toques repetidos = "dar puxadas") | Espaço / botão esquerdo |
| Dar linha | **SOLTAR** | E |
| Recolher | **RECOLHER** | Q |
| Nova pipa | **NOVA** | R |
| Qualidade gráfica | **GFX** | F2 |
| Debug | — | F1 |

## Dicas de pipa (é física de verdade)

- A pipa anda **para onde o nariz aponta**. Dê uma puxada quando ela apontar para cima e ela sobe.
- Com vento fraco perto do chão ela cai; acima dos telhados o vento é mais forte.
- **Soltar** só corre linha de verdade quando a pipa está puxando (tensão).
- Puxar demais com vento forte **arrebenta a linha** (veja a barra de tensão).

## Estrutura

```
src/autoload   GameConfig, EventBus, Wind (vento determinístico)
src/input      PlayerIntent, InputRouter, controles touch
src/player     controlador 1ª pessoa, balanço de cabeça, mãos/lata
src/kite       física da pipa, perfil (.tres), visual, rabiola
src/line       restrição/carretel da linha e linha visual
src/world      bairro gerado por seed, shader de árvores, ambiente
src/ui         HUD, indicador de vento, overlay de debug
src/main       cena principal e teste automático do CI
```
