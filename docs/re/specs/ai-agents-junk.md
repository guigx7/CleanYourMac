# Detritos de IA (`aiAgentsJunk`)

Categoria **Acúmulos de IA**. É o grupo que o CleanMyMac chama internamente de
`aiJunkFiles` (E1).

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26 (Darwin 25.6.0), análise de 20/10/2026.

## Fonte das regras
A lista de ferramentas **não** vem da base cifrada `info.cmmkb`. Ela está fixa no
código do framework `AIToolScanning`, num catálogo estático com 7 ferramentas.
Cada ferramenta tem: identificador, nome exibido, uma lista de "identidades"
(bundle id, nome de pasta de cache, nome de pasta em Application Support) e uma
lista de locais fixos, cada um com o seu *kind* (E2, E3, E4). Abaixo, tudo isso
foi decodificado e conferido no disco deste Mac (E15). Não há regra derivada de
palpite na lista de ferramentas. A única parte que passa pela base cifrada é a
exclusão cruzada com os grupos de caches e registros do usuário (ver
"Exclusão").

## Conceitos

### Kinds (filhos de cada ferramenta), nesta ordem fixa (E5)
| # | `kind` (rawValue) | Nome exibido (nosso texto) |
|---|---|---|
| 0 | `caches` | Caches |
| 1 | `logs` | Registros |
| 2 | `temporary` | Arquivos temporários |
| 3 | `staleVersions` | Versões defasadas |

### Tipos de local (`target`) (E6, E7)
- **`whole`**: o próprio caminho (pasta ou arquivo) vira **um** item, se existir.
- **`glob(padrão)`**: busca recursiva dentro da pasta, com até **4 níveis** de
  profundidade. Cada **arquivo** (não pasta) cujo nome casa com o padrão
  (`fnmatch`, sem flags) vira um item. As subpastas são percorridas e não viram
  item.
- **`versions`**: cada filho direto da pasta vira um candidato a versão
  defasada (ver a seção "Versões defasadas").

Caminho sem `/` inicial é relativo a `~` (a pasta real do usuário, fora do
sandbox). Caminho com `/` inicial é absoluto (E7).

### Identidades (E3, E8, E9, E10)
| Tipo | Significado | Locais derivados | Kind |
|---|---|---|---|
| `bundleID` | bundle id de um app | ver a tabela "Locais derivados de bundle id" | caches e logs |
| `cacheFolder` | nome exato de uma pasta de cache | `~/Library/Caches/<nome>` e `<DARWIN_USER_CACHE_DIR>/<nome>` | caches |
| `appSupportName` | nome da pasta em Application Support (app Electron/Chromium) | `~/Library/Application Support/<nome>/<sub>`, para cada `<sub>` em: `Cache`, `Code Cache`, `GPUCache`, `DawnCache`, `DawnWebGPUCache`, `GraphiteDawnCache`, `Service Worker/CacheStorage` | caches |

**Locais derivados de bundle id** (`<bid>`), com casamento por **família**. Um
filho direto da raiz pertence à família quando o nome é igual a `<bid>`,
começa com `<bid>.` ou começa com `<bid>-`. Exemplo: em
`com.anthropic.claudefordesktop`, entram também `com.anthropic.claudefordesktop.helper`
e `com.anthropic.claudefordesktop.ShipIt` (E9, E15):
- caches: `~/Library/Caches/<família>`, `<DARWIN_USER_CACHE_DIR>/<família>`,
  `/Library/Caches/<família>` e `~/Library/Containers/<bid>/Data/Library/Caches`;
- registros: `~/Library/Logs/<família>` e `/Library/Logs/<família>`.

`<DARWIN_USER_CACHE_DIR>` vem de `confstr(_CS_DARWIN_USER_CACHE_DIR)` (neste Mac:
`/var/folders/z_/…/C/`). Todo caminho que começa com `/private/var/` é
normalizado para `/var/` antes de comparar (E11). Cada filho que casa vira **um**
item: a pasta ou o arquivo inteiro.

## Locais varridos (catálogo completo, nesta ordem)

Ordem do catálogo (E2): Claude Code, Claude, Codex, Gemini / Antigravity,
Cursor, OpenCode, Chrome DevTools MCP.

### 1. Claude Code — id `claude_code`
Identidade: `cacheFolder` `claude-cli-nodejs` (E3).
| Caminho | Target | Kind |
|---|---|---|
| `~/.claude/debug` | whole | logs |
| `~/.claude/cache` | whole | caches |
| `~/.claude/telemetry` | whole | caches |
| `~/.claude/stats-cache.json` | whole | caches |
| `~/.claude/mcp-needs-auth-cache.json` | whole | caches |
| `~/.claude/plugins/install-counts-cache.json` | whole | caches |
| `~/.claude/shell-snapshots` | whole | temporary |
| `~/.local/share/claude/versions` | versions (link ativo: `~/.local/bin/claude`) | staleVersions |
| `~/Library/Caches/claude-cli-nodejs`, `<DARWIN_USER_CACHE_DIR>/claude-cli-nodejs` | (identidade) | caches |
| `/private/tmp/claude-<uid>` | temporário (ver abaixo) | temporary |

### 2. Claude — id `claude_desktop`
Identidades: `bundleID` `com.anthropic.claudefordesktop`, `appSupportName` `Claude`.
| Caminho | Target | Kind |
|---|---|---|
| `~/Library/Logs/Claude` | whole | logs |
| família `com.anthropic.claudefordesktop` nas raízes de bundle id | (identidade) | caches / logs |
| `~/Library/Application Support/Claude/{7 subpastas Chromium}` | (identidade) | caches |

### 3. Codex — id `codex`
Identidades: `bundleID` `com.openai.codex`, `bundleID` `com.openai.sky.CUAService`,
`cacheFolder` `Codex`, `appSupportName` `Codex`.
| Caminho | Target | Kind |
|---|---|---|
| `~/.codex/tmp` | whole | caches (sic: no catálogo é `caches`, não `temporary`) |
| `~/.codex/cache/codex_apps_tools` | whole | caches |
| `~/.codex/cache/codex_apps_server_info` | whole | caches |
| famílias dos 2 bundle ids | (identidade) | caches / logs |
| `~/Library/Caches/Codex`, `<DARWIN_USER_CACHE_DIR>/Codex` | (identidade) | caches |
| `~/Library/Application Support/Codex/{7 subpastas}` | (identidade) | caches |
| `/private/tmp/codex-browser-use` | temporário | temporary |

### 4. Gemini / Antigravity — id `gemini_antigravity`
Identidades: `bundleID` `com.google.antigravity`, `appSupportName` `Antigravity`,
`appSupportName` `Antigravity IDE`.
| Caminho | Target | Kind |
|---|---|---|
| `~/.gemini/antigravity-browser-profile/Default/Cache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/Default/Code Cache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/Default/GPUCache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/Default/DawnGraphiteCache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/Default/DawnWebGPUCache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/Default/Service Worker/CacheStorage` | whole | caches |
| `~/.gemini/antigravity-browser-profile/GraphiteDawnCache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/component_crx_cache` | whole | caches |
| `~/.gemini/antigravity-browser-profile/extensions_crx_cache` | whole | caches |
| `~/.gemini/tmp` | whole | caches |
| identidades acima | (identidade) | caches / logs |

### 5. Cursor — id `cursor`
Identidades: `bundleID` `com.todesktop.230313mzl4w4u92`, `appSupportName` `Cursor`.
| Caminho | Target | Kind |
|---|---|---|
| `~/.local/share/cursor-agent` | glob `*.log` (até 4 níveis) | logs |
| identidades acima | (identidade) | caches / logs |

### 6. OpenCode — id `opencode`
Sem identidades.
| Caminho | Target | Kind |
|---|---|---|
| `~/.local/share/opencode/log` | whole | logs |
| `~/.cache/opencode` | whole | caches |
| `/private/tmp/opencode` | temporário | temporary |

### 7. Chrome DevTools MCP — id `chrome_devtools_mcp`
Sem identidades. Todos com target whole e kind caches, sob
`~/.cache/chrome-devtools-mcp/chrome-profile/`:
`Default/Cache`, `Default/Code Cache`, `Default/GPUCache`, `Default/DawnCache`,
`Default/GrShaderCache`, `Default/GraphiteDawnCache`,
`Default/Service Worker/CacheStorage`, `GraphiteDawnCache`, `component_crx_cache`,
`extensions_crx_cache`.

### Pastas temporárias em `/private/tmp` (E12, E13)
Lista-se `/private/tmp` (só o primeiro nível). Um item só entra se o nome for
**exatamente** um destes:
| Nome | Ferramenta |
|---|---|
| `claude-<uid>` (ex.: `claude-501`, com o uid numérico do usuário) | Claude Code |
| `opencode` | OpenCode |
| `codex-browser-use` | Codex |

Além disso, a entrada **não pode ser um link simbólico** e tem que pertencer ao
usuário atual (dono = `getuid()`). Ela vira um item `temporary` (pasta inteira).
Outras entradas parecidas (ex.: `claude-mcp-browser-bridge-<user>`,
`codex-daemon-501`) **não** entram.

## Inclusão
- Um item é **a pasta ou o arquivo inteiro** do local (nunca o conteúdo
  avulso), exceto no `glob`, em que cada arquivo casado vira um item, e no
  `versions`, em que cada filho elegível vira um item (E6, E7).
- Local que não existe é ignorado em silêncio.
- Os achados de uma ferramenta são agrupados por kind. Uma ferramenta com zero
  itens não aparece. Um kind sem itens não aparece (E14).
- Os achados de `/private/tmp` são somados aos da mesma ferramenta, pelo id
  (E13).
- Não há idade mínima em nenhum local.

### Versões defasadas (definição exata) (E16, E17)
Só se aplica ao Claude Code (`~/.local/share/claude/versions`, com o link
ativo `~/.local/bin/claude`):
1. Listam-se os filhos diretos de `versions`, **ignorando nomes que começam com
   `.`**. Cada filho é um candidato (arquivo binário ou pasta), na ordem
   alfabética do nome (ordem só de exibição; não há "manter as N mais novas").
2. Resolve-se o link `~/.local/bin/claude` até o destino final
   (`resolvingSymlinksInPath` + `standardizedFileURL`). Se o link não existir ou
   não resolver, **nenhuma** versão é defasada (lista vazia).
3. Se o destino resolvido **não estiver** entre os candidatos, **nenhuma**
   versão é defasada (proteção: não sabemos qual está em uso).
4. São defasados todos os candidatos **diferentes** do destino ativo, com uma
   exceção: um **arquivo** (não pasta) com contagem de hard links > 1 é pulado.
5. Ou seja, mantém-se exatamente **1** versão, a ativa. Não importa se as outras
   são mais novas ou mais velhas.
6. A mesma checagem (`allowsRemoval`) é refeita no momento de montar a árvore e
   **antes de apagar**. Se a versão passou a ser a ativa, ela não é removida
   (E17).

Neste Mac, `~/.local/bin/claude` → `versions/2.1.304`. Por isso `2.1.302` e `2.1.303`
são defasadas e `2.1.304` fica (E15).

## Exclusão
- Tudo o que não está no catálogo. A regra é uma **lista fechada de caminhos**,
  não uma heurística por pasta de ferramenta.
- Em `/private/tmp`: links simbólicos e entradas de outro dono (E12).
- Em `versions`: nomes ocultos, a versão ativa, arquivos com hard link > 1.
- **Exclusão cruzada.** O JunkCleanupModule envolve as bases de "Caches do
  Usuário" e de "Registros do Usuário" com um filtro que ignora qualquer
  caminho que pertença a uma ferramenta deste catálogo (busca por
  caminho/identidade). Assim, `~/Library/Caches/claude-cli-nodejs`,
  `~/Library/Caches/com.openai.codex`, `~/Library/Logs/Claude` etc. aparecem
  **só** aqui, nunca duplicados em `userCaches`/`userLogs` (E18). A regra de
  "pertence a uma ferramenta" é: o caminho (normalizado) é igual a um local do
  catálogo ou fica dentro dele, ou é um filho direto de uma raiz de cache/log
  cujo nome casa com a família de um bundle id ou com o nome exato de um
  `cacheFolder`.

### O que NUNCA é removido (regra de segurança para o implementador)
O motor só pode apagar os caminhos listados acima. Fica proibido, mesmo que
"pareça cache", apagar qualquer outra coisa nas pastas das ferramentas, em
especial:
- **Claude Code** (`~/.claude`): `projects/` (sessões), `history.jsonl`,
  `settings.json`, `settings.local.json`, `.credentials.json`, `CLAUDE.md`,
  `agents/`, `commands/`, `skills/`, `plugins/` (exceto o arquivo
  `install-counts-cache.json`), `todos/`, `file-history/`, `session-env/`,
  `ide/`, `statsig/`, `~/.claude.json`. Em `~/.local/share/claude/versions`, a
  versão ativa e o link `~/.local/bin/claude`.
- **Claude** (`~/Library/Application Support/Claude`): tudo, exceto as 7
  subpastas Chromium listadas. Ficam `Local Storage`, `IndexedDB`, `Cookies`,
  `Session Storage`, `Preferences`, `config.json`, `claude_desktop_config.json`,
  `claude-code`, `claude-code-sessions`, `local-agent-mode-sessions`,
  `Partitions`, `blob_storage`, `DawnGraphiteCache` (sic: não está na lista
  de subpastas do app; só aparece no perfil do Antigravity), `GPUPersistentCache` etc.
- **Codex** (`~/.codex`): `auth.json`, `config.toml`, `sessions/`,
  `history.jsonl`, `log/`, `archived_sessions/`, `AGENTS.md`, `rules/`
  e o resto de `cache/` além dos 2 itens listados.
- **Gemini**: `~/.gemini/settings.json`, `oauth_creds.json`, `GEMINI.md`,
  `antigravity/`, e do perfil do navegador tudo o que não está listado
  (cookies, `Local Storage`, `IndexedDB`, `Preferences`).
- **Cursor**: no `~/.local/share/cursor-agent`, só arquivos `*.log`. Fica o
  resto (`versions`, binários, estado). `~/.cursor` não é tocado.
- **OpenCode**: `~/.local/share/opencode/opencode.db*`, `repos/`, `auth.json`.
- Nenhum link simbólico é seguido nem apagado como se fosse o destino.

## Recomendado
**Nada** vem marcado. Todos os itens e grupos começam desmarcados, e o seletor
do grupo mostra "Nenhum" (E14). O usuário marca a ferramenta inteira ou um kind.

## Agrupamento e nome exibido
Árvore de 2 níveis (E19):
1. **Ferramenta** (`AIJunkFindings`): nome exibido = nome do catálogo
   (`Claude Code`, `Claude`, `Codex`, `Gemini / Antigravity`, `Cursor`,
   `OpenCode`, `Chrome DevTools MCP`). Tamanho = soma dos kinds. Tem botão de
   dica ("smart tip") com uma frase sobre a ferramenta (escreva textos próprios).
   **Ícone**: o mapeador da UI tem acesso ao `NSWorkspace` (E19). Nossa regra:
   para a primeira identidade `bundleID` da ferramenta que resolve para um app
   instalado (`NSWorkspace.urlForApplication(withBundleIdentifier:)`), use o
   ícone do app. Para ferramentas sem app (Claude Code, OpenCode, Chrome
   DevTools MCP) ou com o app ausente, use um ícone genérico de ferramenta de
   terminal (SF Symbol `terminal`).
2. **Kind** (`AIJunkGroup`, `detail`): nome = rótulo do kind (Caches,
   Registros, Arquivos temporários, Versões defasadas), na ordem fixa
   0→3. Tamanho = soma dos itens. É um nó folha na árvore. A lista de caminhos
   incluídos fica disponível em "mostrar itens incluídos" (lista de caminhos, só
   leitura). Ícone: SF Symbol genérico por kind (ex.: `archivebox`, `doc.text`,
   `clock`, `square.stack.3d.down.right`).

Ordem das ferramentas na lista: pela ordenação ativa do Gerenciador (padrão
"Tamanho", decrescente, conforme `results-screen.md`). Na baseline:
Claude Code > Claude > Codex > OpenCode.

## Cálculo de tamanho
- Item = tamanho da pasta/arquivo pelo medidor de arquivos comum, com tamanho
  **lógico** (o framework usa o serviço `logicalSizeAtURL`) (E20). Pastas são
  somadas recursivamente, sem seguir links simbólicos e sem contar o mesmo
  inode duas vezes.
- Kind = soma dos itens. Ferramenta = soma dos kinds. Grupo = soma das
  ferramentas.
- Não há sobreposição entre itens do catálogo (os locais são disjuntos). Se a
  implementação encontrar o mesmo caminho por dois caminhos (ex.: o local fixo
  e a identidade), conte uma vez só.

## Remoção
- **Apagar definitivamente** o item inteiro (pasta ou arquivo), pelo removedor
  genérico de arquivos da Limpeza (não vai para o Lixo).
- Versões defasadas: refazer a checagem da versão ativa imediatamente antes de
  apagar cada uma (E17).
- O CleanMyMac **não** fecha nem verifica as ferramentas abertas para este
  grupo. Ver "Divergências" para a nossa proteção adicional.
- Admin: não, para tudo o que fica em `~` e em `/private/tmp` do próprio usuário.
  Itens em `/Library/Caches` ou `/Library/Logs` que não forem apagáveis pelo
  usuário são reportados como falha (não pedimos admin na v1).

## Alertas e selos
Nenhum alerta antes de limpar este grupo e nenhum selo. O selo "Novo" é da
entrada da categoria/fluxo "Acúmulos de IA", não deste grupo (E21).

## requiresAdmin
- Análise: não.
- Limpeza: não (só em casos raros em `/Library/...`, que tratamos como falha).

## Evidências
- **E1** — strings do AIToolScanning/JunkCleanupModule: identificador de
  grupo `aiJunkFiles`; textos `ai_clutter_agents_junk_group_*`.
- **E2** — pseudocódigo do inicializador estático de `AIJunkCatalog.tools`:
  monta o array com 7 ferramentas, em ordem, cada uma pela sua função de
  inicialização.
- **E3** — dados estáticos (`__DATA,__data`) dos arrays `identities` de cada
  ferramenta, decodificados com `otool -s`: pares (texto, tipo 0/1/2).
- **E4** — strings `__cstring` do AIToolScanning (via `otool -v -s __TEXT __cstring`):
  todos os caminhos e bundle ids citados.
- **E5** — pseudocódigo de `AIJunkKind.rawValue` e array estático `allCases` =
  [0,1,2,3].
- **E6** — pseudocódigo de `Target.__derived_enum_equals` (2 casos sem valor +
  1 caso com texto) e da função de varredura por local (decide entre o
  caminho inteiro, a listagem de versões e a busca por padrão com
  profundidade 4 e `fnmatch`).
- **E7** — pseudocódigo da função de resolução de caminho (prefixo `/` =
  absoluto, senão relativo à home real do `DirectoryURLProvider`).
- **E8** — pseudocódigo da função de varredura por identidade (3 ramos por tipo
  de identidade, raízes de cache, Application Support com as 7 subpastas do
  array estático, Containers + `Data/Library/Caches`).
- **E9** — pseudocódigo do casamento de família (igual, ou prefixo `<id>.`, ou
  prefixo `<id>-`).
- **E10** — pseudocódigo da varredura de registros por bundle id
  (`Library/Logs` da home e `/Library/Logs`).
- **E11** — pseudocódigo de `AIJunkRoots` (`confstr(0x10002)` = cache do
  Darwin, checagem de `APP_SANDBOX_CONTAINER_ID`) e da normalização
  `/private/var/` → `/var/`.
- **E12** — pseudocódigo da varredura de `/private/tmp` (conjunto de nomes da
  listagem, tabela nome→ferramenta, checagem de link simbólico pelo
  `NSFileType` e de dono por `NSFileOwnerAccountID` == `getuid()`).
- **E13** — disassembly da função que monta a tabela de temporários:
  `"claude-"` + `String(uid)`, `opencode`, `codex-browser-use`. Pseudocódigo de
  `AgentFootprintScanner.mergedFindings` (soma por id de ferramenta).
- **E14** — baseline `Acúmulos de IA/Detritos de IA.txt`: 4 ferramentas, todas
  `[checked=0]`, seletor "Nenhum".
- **E15** — leitura do disco (somente leitura): `~/.local/bin/claude` →
  `versions/2.1.304`; versões 2.1.302/303/304 (~262 MB cada); `~/Library/Caches`
  tem `claude-cli-nodejs`, `Codex`, `com.openai.codex`,
  `com.openai.sky.CUAService`, `com.anthropic.claudefordesktop(.ShipIt)`; cache
  do Darwin tem `com.anthropic.claudefordesktop.helper`, `com.openai.codex.helper`;
  `/private/tmp/claude-501` existe. As somas batem com a baseline (Claude Code
  ≈ 536 MB de versões + ~33 MB do resto; Claude ≈ 230 MB de caches Chromium +
  logs; Codex ≈ 34 MB; OpenCode ≈ 4,5 MB em `~/.cache/opencode`).
- **E16** — pseudocódigo da listagem de versões (ignora nomes com `.` inicial,
  ordena) e do filtro (resolve o link ativo; lista vazia se não resolver ou se
  o ativo não estiver entre os filhos; pula arquivos com
  `NSFileReferenceCount` > 1).
- **E17** — pseudocódigo de `StaleVersionGuard.allowsRemoval(of:toolIdentifier:)`:
  acha o local `staleVersions` da ferramenta, resolve o link e só permite se o
  caminho for diferente do ativo. Strings `staleVersionGuard` no mapeador de
  nós da UI.
- **E18** — classes `AIJunkExcludingCachesKnowledgeBase` /
  `AIJunkExcludingLogsKnowledgeBase` (JunkCleanupModule), que envolvem a
  base e ignoram itens via `AIJunkCatalogLookup.tool(matching:)`. Pseudocódigo
  de `tool(matching:)`.
- **E19** — strings do JunkCleanupModule:
  `JunkCleanupItemNode<AIJunkFindings, JunkCleanupItemNode<AIJunkGroup, Node>>`,
  `AIClutterNodeMapper` com campos `workspace` e `staleVersionGuard`; dicas por
  ferramenta e por kind.
- **E20** — strings/imports do AIToolScanning: `logicalSizeAtURL:`,
  `FileSizingServiceType`.
- **E21** — localização `custom_flow_aiClutter_badge`.

## Baseline observada
Grupo "Detritos de IA": **824 MB**, seletor "Nenhum", nada marcado.
| Ferramenta | Tamanho | Marcado |
|---|---|---|
| Claude Code | 560 MB | não |
| Claude | 222 MB | não |
| Codex | 37,7 MB | não |
| OpenCode | 4,5 MB | não |

(Os filhos por kind não foram expandidos na captura.)

## Divergências conhecidas
- **Proteção de pasta temporária em uso (nossa adição).** `/private/tmp/claude-<uid>`
  guarda dados das sessões **abertas** do Claude Code. O CleanMyMac o oferece
  sem checar nada. Nós o mostramos igual (paridade de tamanho), mas, na hora de
  limpar, se houver um processo do usuário chamado `claude` em execução,
  pulamos esse item e o reportamos como "em uso". Fazemos o mesmo com
  `/private/tmp/opencode` (processo `opencode`) e `/private/tmp/codex-browser-use`
  (processo `codex`).
- **Links simbólicos nos locais fixos.** No código vimos a checagem de link só
  em `/private/tmp`. Nós, por segurança, nunca seguimos links: se o local fixo
  for um link, ele é ignorado.
- **Ícones.** O mapeamento exato de ícone por ferramenta não foi confirmado. A
  regra "ícone do app pelo bundle id, senão genérico" é nossa.
- **`/Library/Caches` e `/Library/Logs`.** Varridos para paridade, sem pedir
  admin na limpeza.
- **Tamanho.** Usamos o tamanho lógico. Em pastas com muitos arquivos pequenos
  (caches Chromium), o valor pode diferir alguns % do "tamanho em disco".

## Checklist de testes
Fixtures montadas com `FixtureTree`, injetando home, `DARWIN_USER_CACHE_DIR`,
`/private/tmp` e uid falsos.
1. `~/.claude/cache/a.bin` (10 KB) → ferramenta "Claude Code", kind Caches, 1
   item = a pasta `~/.claude/cache`, desmarcado.
2. `~/.claude/projects/x.jsonl`, `~/.claude/settings.json`, `~/.claude/history.jsonl`
   → nenhum item (nunca entram).
3. `~/.claude/debug/log.txt` → kind Registros. `~/.claude/shell-snapshots/s.sh`
   → kind Arquivos temporários.
4. `versions/{1.0.0,1.0.1,1.0.2}` + link `~/.local/bin/claude` → `versions/1.0.1`
   → defasadas: 1.0.0 e 1.0.2. A 1.0.1 fica.
5. Mesmo cenário sem o link → nenhuma versão defasada.
6. Link apontando para `/outro/lugar/claude` (fora de `versions`) → nenhuma
   versão defasada.
7. `versions/.tmp123` → ignorado. `versions/1.0.0` com 2 hard links (e não
   ativo) → ignorado.
8. Antes de apagar, o link muda para a versão marcada → ela não é apagada.
9. `/private/tmp/claude-<uid>` do usuário → Claude Code / temporários.
   `/private/tmp/claude-999` (outro uid no nome) → não entra. Link simbólico
   `claude-<uid>` → não entra. Dono diferente → não entra.
10. `/private/tmp/codex-daemon-501` → não entra. `/private/tmp/codex-browser-use`
    → Codex / temporários.
11. `~/Library/Caches/com.anthropic.claudefordesktop.ShipIt` e
    `<darwin>/com.anthropic.claudefordesktop.helper` → ferramenta "Claude",
    Caches, 2 itens. `~/Library/Caches/com.anthropic.claudefordesktopX` → não
    entra (não é `.` nem `-`).
12. `~/Library/Application Support/Claude/Cache` e `/Local Storage` → só `Cache`
    entra. `DawnGraphiteCache` do Claude → não entra.
13. `~/Library/Caches/claude-cli-nodejs.old` → não entra (`cacheFolder` é exato).
14. `~/.local/share/cursor-agent/a/b/c/x.log` (3 níveis) → entra como arquivo.
    `…/a/b/c/d/e/y.log` (5 níveis) → não entra. `z.txt` → não entra.
15. `~/.codex/tmp` vazio → item de 0 KB no kind Caches (sic).
16. Ferramenta sem nenhum local existente → não aparece. Kind sem itens → não
    aparece.
17. `~/Library/Caches/com.openai.codex` aparece em Detritos de IA e **não**
    aparece em Caches do Usuário. O mesmo vale para `~/Library/Logs/Claude` em
    Registros do Usuário.
18. Ordem dos kinds sob uma ferramenta: Caches, Registros, Arquivos temporários,
    Versões defasadas.
19. Limpeza de um kind → apaga só os itens desse kind. Os demais e as pastas-pai
    (`~/.claude`) permanecem.
20. Com um processo `claude` ativo → `/private/tmp/claude-<uid>` pulado e
    reportado como em uso. Os outros itens marcados são apagados.
