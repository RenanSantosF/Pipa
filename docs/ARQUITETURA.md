# Pipa — Nostalgia Online · Arquitetura Técnica

> Documento vivo. Etapa atual: **1 — Demonstração jogável offline**.
> Alvo: Godot 4.7 · GDScript · Android (paisagem) · Renderer Mobile.

---

## 1. Princípios

1. **Sistemas pequenos e desacoplados.** Cada sistema é uma cena/script com responsabilidade única. Comunicação por sinais e por um "contrato" de dados (intenções do jogador, estado da pipa), nunca por caminhos de nó fixos entre módulos distintos.
2. **Simulação separada da apresentação.** A física da pipa e do vento roda em `_physics_process` com passo fixo; a parte visual (malha, linha, mãos, câmera) apenas lê o estado. Isso é o que permitirá, na etapa de rede, simular só a pipa local e *interpolar* as pipas remotas usando a mesma parte visual.
3. **Vento determinístico.** O vento é uma função de `(seed, tempo, posição)`. No multiplayer, o servidor envia apenas `seed` + relógio, e todos os clientes calculam o mesmo vento sem tráfego contínuo.
4. **Física própria e barata para a pipa.** Não usar `RigidBody3D` + `Joint` para pipa/linha: juntas de corda ficam instáveis com massas leves e forças aerodinâmicas grandes. Um integrador próprio, com poucas operações vetoriais por tick, é mais estável e previsível em celular.
5. **Conteúdo construível pelo celular.** Na etapa 1 o cenário é montado com malhas primitivas (`BoxMesh`, `CylinderMesh`, `PlaneMesh`) a partir de dados/script. Modelos `.glb` entram depois, substituindo as primitivas sem mudar a lógica.
6. **Somente APIs estáveis do Godot 4.x.** Nada experimental; tudo que for usado existe desde o 4.2/4.3 e segue válido no 4.7.

---

## 2. Visão geral dos módulos (Etapa 1)

```
                 ┌──────────────── Autoloads ────────────────┐
                 │ GameConfig   EventBus   Wind (WindField)   │
                 └──────▲───────────▲────────────▲───────────┘
                        │           │            │ sample(pos, t)
 TouchControls ──► InputRouter ──► PlayerIntent  │
 (joystick, área     (também lê     (move, look, │
  de olhar, botões)   teclado/mouse  pull, release, reel)
                       no PC)          │         │
                                       ▼         │
                ┌──────────── Player ───────────┐│
                │ FPController (CharacterBody3D)││
                │  └ Head (pitch) └ Camera3D    ││
                │     └ Viewmodel (mãos/carretel)│
                │         └ HandAnchor ─────────┼┼──► KiteLine (restrição + carretel)
                └───────────────────────────────┘│         │ tensão / comprimento
                                                 ▼         ▼
                                        KiteBody (simulação aerodinâmica)
                                          ├ KiteVisual (malha + rabiola)
                                          └ estado ► LineRenderer (corda Verlet visual)
                 HUD: indicador de vento, comprimento de linha, tensão, debug FPS
                 World: StreetBuilder (rua, casas, muros, postes, árvores), Sky/Luz
```

### Dependências (quem conhece quem)

| Módulo | Depende de | Não pode depender de |
|---|---|---|
| `WindField` | `GameConfig` | qualquer cena |
| `InputRouter` | `TouchControls` (sinais), `Input` | Player, Kite |
| `FPController` | `PlayerIntent` | Kite (só expõe `HandAnchor`) |
| `KiteLine` | `HandAnchor` (Node3D), `KiteBody` | UI |
| `KiteBody` | `WindField`, `KiteProfile` (Resource) | Player, UI |
| `LineRenderer` | posições de mão/pipa + estado da linha | física |
| `HUD` | `EventBus`, `WindField` | lógica de jogo |

---

## 3. Estrutura de pastas

```
Pipa/
├── project.godot                 # Android paisagem, renderer Mobile, 60 ticks físicos
├── icon.svg
├── export_presets.cfg            # preset Android (debug), sem chaves/segredos
├── .gitignore / .gitattributes
├── README.md                     # como abrir, testar e exportar
├── docs/
│   ├── ARQUITETURA.md            # este documento
│   ├── FISICA_PIPA.md            # equações e parâmetros da pipa (etapa 1)
│   └── REDE.md                   # protocolo (etapa 3, apenas esboço agora)
├── .github/workflows/
│   └── android-debug.yml         # CI: importa projeto e gera APK debug como artifact
│
├── src/                          # código + cenas, organizado por FUNCIONALIDADE
│   ├── main/
│   │   ├── main.tscn             # cena inicial: World + Player + Kite + HUD
│   │   └── main.gd               # liga os sistemas (injeção de dependências)
│   ├── autoload/
│   │   ├── game_config.gd        # qualidade gráfica, sensibilidade, constantes
│   │   ├── event_bus.gd          # sinais globais (line_snapped, kite_crashed...)
│   │   └── wind_field.gd         # vento determinístico (seed + tempo + altura)
│   ├── input/
│   │   ├── player_intent.gd      # class_name PlayerIntent (dados puros)
│   │   ├── input_router.gd       # junta toque/teclado ► PlayerIntent
│   │   ├── touch_controls.tscn
│   │   ├── virtual_joystick.gd
│   │   ├── look_pad.gd           # área de arrastar para câmera (multitoque)
│   │   └── touch_button.gd       # botão com estado "segurando"
│   ├── player/
│   │   ├── player.tscn
│   │   ├── fp_controller.gd      # CharacterBody3D: andar, olhar, gravidade
│   │   ├── head_motion.gd        # balanço da cabeça, inclinação suave
│   │   └── viewmodel/
│   │       ├── viewmodel.tscn    # braços, mãos, lata/carretel (primitivas)
│   │       └── viewmodel_animator.gd  # puxar, soltar, recolher (procedural)
│   ├── kite/
│   │   ├── kite.tscn
│   │   ├── kite_body.gd          # integrador: forças, torques, estado
│   │   ├── kite_profile.gd       # class_name KiteProfile (Resource)
│   │   ├── kite_visual.gd        # malha da pipa + tremulação
│   │   ├── kite_tail.gd          # rabiola (cadeia Verlet curta + arrasto)
│   │   └── profiles/
│   │       └── pipa_classica.tres
│   ├── line/
│   │   ├── kite_line.gd          # restrição unilateral + carretel (comprimento)
│   │   └── line_renderer.gd      # corda visual Verlet ► ImmediateMesh (fita)
│   ├── world/
│   │   ├── world.tscn            # Sol, WorldEnvironment, chão, StreetBuilder
│   │   ├── street_builder.gd     # monta rua/calçadas/casas/muros/postes por seed
│   │   ├── house_builder.gd      # casa simples parametrizada (cores, telhado)
│   │   ├── tree_sway.gdshader    # balanço de árvores no vértice (vento)
│   │   └── environment/
│   │       └── tarde.tres        # Environment: céu procedural, névoa leve
│   ├── ui/
│   │   ├── hud.tscn
│   │   ├── wind_indicator.gd     # seta discreta + intensidade
│   │   └── debug_overlay.gd      # FPS, tensão, ângulo de ataque (desligável)
│   └── util/
│       └── math_util.gd          # damping independente de framerate, etc.
│
├── assets/                       # conteúdo importado (vazio na etapa 1)
│   ├── models/  textures/  audio/  materials/  fonts/
│
└── server/                       # ETAPA 3 — servidor Railway (não criado ainda)
```

**Por que por funcionalidade (`src/kite/`, `src/line/`...) e não por tipo (`scripts/`, `scenes/`)?** Ao editar pelo celular/GitHub, tudo de um sistema fica em uma pasta só; menos navegação e menos chance de quebrar referências.

---

## 4. Física da pipa (núcleo do projeto)

### 4.1 Estado

`KiteBody` é um `Node3D` com estado próprio:

- posição `p`, velocidade `v` (m/s)
- orientação `q` (Basis/Quaternion), velocidade angular `ω` (rad/s)
- massa `m` (~0,06–0,12 kg), inércia diagonal simplificada

### 4.2 Forças por tick (passo fixo 1/60 s, 2 subpassos)

1. **Vento aparente:** `v_rel = vento(p, t) − v`.
2. **Ângulo de ataque `α`:** ângulo entre `v_rel` e o plano da pipa (normal = eixo Z local).
3. **Placa plana (modelo empírico estável):**
   - `Cl(α) ≈ Cl_max · sin(2α)` (com perda de sustentação suavizada acima de ~40–45°)
   - `Cd(α) ≈ Cd0 + Cd90 · sin²(α)`
   - `L = ½ ρ |v_rel|² A Cl` (perpendicular a `v_rel`, no plano de simetria da pipa)
   - `D = ½ ρ |v_rel|² A Cd` (na direção de `v_rel`)
4. **Gravidade:** `m·g` no centro de massa.
5. **Centro de pressão ≠ ponto do cabresto:** a força aerodinâmica é aplicada no centro de pressão (que se move com `α`) e a linha puxa no ponto do cabresto. Esse desalinhamento gera o **torque de arfagem** que faz a pipa achar sozinha um ângulo de equilíbrio — é daí que vem o comportamento natural, não de "seguir o dedo".
6. **Rabiola:** arrasto concentrado atrás da pipa → torque restaurador de guinada/rolagem (estabilidade). Sem rabiola (ou rabiola curta) a pipa fica instável e "gira" — comportamento real e configurável.
7. **Amortecimento angular** pequeno (ar) para evitar oscilações numéricas.

### 4.3 Linha = restrição unilateral (só puxa, nunca empurra)

- Se `|p_cabresto − p_mão| < comprimento` → linha frouxa, sem força (pipa cai/"embica").
- Se esticada → corrige posição e remove a componente de velocidade que afasta (estilo PBD), com pequena elasticidade (linha de algodão/nylon estica ~1–3%). A **tensão** resultante é medida e exposta (HUD, vibração, animação das mãos, risco de arrebentar).
- **Puxar** = a mão recua rapidamente (≈ 0,3–0,6 m em ~0,15 s) → aumenta vento aparente → a pipa ganha sustentação e sobe (é assim na vida real).
- **Soltar (dar linha)** = o carretel libera comprimento proporcional à tensão (linha "corre"); a pipa afasta e ganha altura com vento bom, ou perde se o vento estiver fraco.
- **Recolher** = reduz comprimento a uma taxa limitada; puxa a pipa para perto e para baixo.
- Peso/arrasto da própria linha: aproximado como força extra para baixo proporcional ao comprimento (barato, dá a sensação de "linha pesada" em longas distâncias).

### 4.4 Linha visual (separada da física)

- Cadeia Verlet de **16–24 pontos** (configurável por qualidade), presa na mão e no cabresto.
- Comprimento de repouso = comprimento atual da linha; gravidade + vento lateral nos pontos → curvatura natural (catenária) quando frouxa, quase reta quando tensa.
- 2–3 iterações de restrição por frame; custo desprezível.
- Renderizada como fita voltada para a câmera via `ImmediateMesh` (1 draw call, material unshaded fino com leve transparência na distância).

### 4.5 Vento (`WindField`)

- Direção base + intensidade base (configuráveis; depois vindas do servidor).
- **Rajadas:** `FastNoiseLite` amostrado no tempo (baixa frequência) + turbulência (média frequência).
- **Gradiente de altura** (lei de potência, terreno suburbano): `v(h) = v_ref · (h / h_ref)^0.25`, com vento quase nulo perto do chão e turbulência maior na altura dos telhados → subir a pipa "acima das casas" é recompensador, como na infância.
- API: `sample(world_pos: Vector3) -> Vector3`, `get_base_direction()`, `get_gust_factor()`.

### 4.6 Proteções numéricas

- Limites de velocidade/ângulo; se `NaN` ou explosão → reset suave da pipa.
- Colisão da pipa com o mundo via `PhysicsDirectSpaceState3D.intersect_ray` do ponto anterior ao atual (barato, evita atravessar telhados). Fios de poste e árvores enganchando: etapa posterior.

---

## 5. Primeira pessoa e controles

- `CharacterBody3D` (cápsula) → `Head` (pitch, limitado −80°…+85° para olhar a pipa no alto) → `Camera3D` (FOV ~70).
- **Viewmodel** filho da câmera: braços/mãos/lata de linha com primitivas na etapa 1, animação **procedural** (molas/lerp) para puxar, soltar e recolher; sem `AnimationPlayer` por enquanto (troca fácil por animações reais depois).
- Balanço de cabeça ao andar + leve atraso (sway) do viewmodel ao girar.
- Opção (padrão ligado) de **assistência de mira**: ao segurar "puxar", a câmera tende suavemente a manter a pipa no quadro — ajuda no touch sem tirar o controle.

**Layout touch (paisagem):**

```
┌───────────────────────────────────────────────────────┐
│ [vento ↗ 4 m/s]                       [linha 42 m]   │
│                                                       │
│        (metade direita inteira = arrastar câmera)     │
│                                                       │
│   ( joystick )                       [RECOLHER]       │
│   (dinâmico )                  [SOLTAR]   [PUXAR]     │
└───────────────────────────────────────────────────────┘
```

- Joystick dinâmico (aparece onde o polegar toca na metade esquerda).
- Multitoque real (`InputEventScreenTouch`/`InputEventScreenDrag` por `index`), para andar, olhar e puxar ao mesmo tempo.
- No PC (testes): WASD, mouse, `Espaço` puxar, `E` soltar, `Q` recolher.

---

## 6. Gráficos e desempenho (Etapa 1)

| Item | Decisão |
|---|---|
| Renderer | **Mobile** (Vulkan). Fallback **Compatibility** documentado para aparelhos sem Vulkan adequado. |
| Luz | 1 `DirectionalLight3D` (sol de fim de tarde) com sombra de 2 cascatas, distância ~60 m; resto por luz ambiente do céu. Sem GI em tempo real. |
| Céu | `ProceduralSkyMaterial` com cores de tarde; névoa leve de profundidade. |
| Cenário | Primitivas com materiais compartilhados (poucos materiais = poucos draw calls); objetos repetidos (postes, árvores, muros) via `MultiMeshInstance3D`. |
| Árvores | Balanço no vertex shader (sem custo de CPU), lendo vento global por `global uniform`. |
| Culling | Visibility range (HLOD simples) em objetos distantes; `OccluderInstance3D` com casas como oclusores quando o cenário crescer (etapa 2). |
| Resolução | `scaling_3d` ajustável (0,7–1,0) em `GameConfig`; FPS alvo 30/60 selecionável. |
| Texturas | ETC2/ASTC (import padrão para Android, "VRAM Compressed"). |

**Orçamento alvo (intermediário):** < 150 draw calls, < 150k triângulos visíveis, física da pipa < 0,3 ms/frame.

---

## 7. Multiplayer (planejado — Etapa 3, NÃO implementado agora)

Registrado aqui para que a etapa 1 já nasça compatível.

- **Transporte:** WebSocket seguro. O Railway termina o TLS no proxy; o servidor escuta WS simples na porta `$PORT` e os clientes conectam em `wss://<app>.up.railway.app`. **Nenhuma dependência de UDP.**
- **Servidor proposto:** Node.js + TypeScript + biblioteca `ws` (leve, deploy direto no Railway, fácil adicionar Postgres/Redis para contas). Alternativa: Godot headless — mais pesado e com deploy mais complexo; decidir antes da etapa 3.
- **Cliente:** `WebSocketPeer` do Godot (API de baixo nível), protocolo próprio binário (`PackedByteArray`, valores quantizados) — sem depender da API de alto nível `MultiplayerAPI`, já que o servidor não é Godot.
- **Autoridade:**
  - Servidor: salas, identidade, chat (limite de taxa, filtro), relógio e seed do vento, validação de velocidade/posição do jogador, limites de comprimento de linha, eventos de disputa/corte (futuro).
  - Cliente: simulação da própria pipa (responsividade), enviada a 10–15 Hz.
  - Pipas e jogadores remotos: buffer de snapshots + interpolação (~100–150 ms), mesma parte visual (`KiteVisual`, `LineRenderer`).
- **Banda estimada:** ~40 bytes/snapshot × 12 Hz × N jogadores visíveis; com 16 jogadores ≈ 7–8 KB/s de download por cliente.

---

## 8. Riscos identificados

| Risco | Impacto | Mitigação |
|---|---|---|
| Instabilidade numérica da pipa (massa leve, forças altas) | Pipa "explode"/treme | Subpassos, restrição PBD em vez de mola rígida, amortecimento, clamps, reset de NaN |
| Pipa "boa demais" ou impossível de empinar | Diversão | Todos os coeficientes em `KiteProfile` (.tres) editável sem mexer em código; overlay de debug |
| Renderer Mobile em GPUs fracas/sem Vulkan | Não abre / lento | Preset de qualidade + documentação para trocar para Compatibility |
| Sombras e transparência (linha, folhas) | Queda de FPS | Sombra curta, 2 cascatas; linha unshaded; folhas com alpha scissor (não blend) |
| `ImmediateMesh` reconstruída todo frame | CPU | Só ~24 pontos × 2 vértices; aceitável. Se necessário, trocar por `ArrayMesh` com buffer reaproveitado |
| Multitoque mal tratado | Controles travam | Rastreamento por `index` em cada controle; testes no aparelho |
| Fidelidade a "Godot 4.7" | API inexistente | Só APIs estáveis 4.x; validação headless do projeto no CI |
| Desenvolvimento só pelo celular | Sem editor desktop | Godot Editor para Android (oficial) **ou** CI do GitHub gerando APK; tudo em texto (`.tscn`/`.gd`/`.tres`) editável pelo GitHub |
| Ausência de testes no aparelho por parte da IA | Bugs só vistos no celular | Checklist de teste por etapa + overlay de debug com FPS/tensão |

---

## 9. Etapa 1 — Escopo e critério de aceite

**Entregas:**
1. `project.godot` configurado (paisagem, Mobile, entradas, autoloads, 60 Hz físico).
2. Rua com calçadas, ~8 casas simples, muros, postes com fios (visuais), algumas árvores, campinho/terreno vazio.
3. Controlador em primeira pessoa com controles touch e de teclado.
4. Viewmodel: braços, mãos e carretel/lata com animação procedural.
5. Pipa com física aerodinâmica, rabiola e perfil editável.
6. Linha com restrição física + renderização dinâmica com curvatura.
7. Vento com rajadas e gradiente de altura + indicador discreto.
8. Iluminação de fim de tarde.
9. Workflow do GitHub Actions para gerar APK debug.

**Aceite:** abrir no Godot 4.7 sem erros; em aparelho intermediário rodar ≥ 30 FPS; a pipa decola com vento e puxadas, se estabiliza sozinha, oscila de forma crível, cai ao perder vento/linha frouxa e responde a soltar/recolher.

**Fora da etapa 1:** sons, pássaros/cachorros/pessoas, ciclo dia/noite completo, multiplayer, chat, contas, disputas.

---

## 10. Roteiro das próximas etapas (resumo)

2. Ambiente e atmosfera: bairro maior, modelos `.glb`, sons ambientes, pássaros, cachorros, ciclo tarde → pôr do sol, LOD/occlusion.
3. Multiplayer: servidor Railway (WSS), salas, identidade, sincronização de jogadores/pipas/vento, chat.
4. Contas e persistência, personalização de pipas.
5. Polimento, otimização por aparelho, publicação.
