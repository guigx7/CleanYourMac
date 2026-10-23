# CleanYourMac v0.6 — Agentes de IA: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Módulo "Agentes de IA". Nas worktrees ligadas, tira `node_modules` e pastas de build ignoradas pelo git. Também
tira as sessões dos agentes com mais de 7 dias. Tudo vai para o Lixo, com o fluxo de um clique dos outros módulos.

**Architecture:** O Core ganha `Core/Sources/CleanYourMacCore/Agents/`:
- catálogo dos agentes, em Swift;
- localizador do git;
- descoberta de worktrees lendo `.git/worktrees/*/gitdir`;
- pastas recriáveis com `git check-ignore`/`ls-files`;
- sessões por agente;
- relatório, cartões, removedor e `cym agents`.

O app ganha `App/Agents/`: fluxo, Intro, Resultados, Gerenciador com 2 seções e conclusão.

**Tech Stack:** Swift 6 (strict), SwiftUI, Foundation. Git só como ferramenta externa opcional (`CommandRunner`). Sem
dependências novas.

**Spec:** `docs/superpowers/specs/2026-10-23-cleanyourmac-v06-agentes-design.md`.

## Global Constraints

- **Nunca** apagar worktree, branch, arquivo rastreado ou alteração sem commit. Das worktrees saem só as pastas recriáveis.
- Só worktrees **ligadas**, nunca o checkout principal; só dentro da pasta pessoal.
- **Pastas recriáveis:**
  - `node_modules` (sempre);
  - `.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.vite`, `.angular/cache`, `.expo`, `dist`, `build`, `out`,
    `coverage`, `.output`, `target`, `.gradle`, `DerivedData`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.venv`,
    `venv`, procuradas até 4 níveis;
  - as de build só se o git as ignora e se não contêm nada rastreado;
  - sem git utilizável, só `node_modules`.
- **"Em uso":** modificação de fora das pastas recriáveis nas últimas 24 h (86.400 s). Sessão antiga: mais de 7 dias
  (604.800 s) desde a data mais nova do conjunto.
- **Nunca tocar** `~/.claude/projects/*/memory`, `~/.claude/history.jsonl`, `~/.claude/settings*.json`, `~/.claude.json`,
  skills, plugins, nem bancos (`opencode.db`, `*.sqlite`).
- **Jobs do Claude Code:** saem como sessão só sem worktree ligada dentro, sem `backup/`, com `state.json` não ativo e
  parados há mais de 7 dias.
- **Remover = Lixo** (`FileManager.trashItem`), revalidando cada item. `CYM_DRY_RUN` é respeitado e o registro fica em
  `~/Library/Logs/CleanYourMac/agents-*.json`.
- Sem APIs privadas; textos em pt-BR e en (`App/Resources/Strings.tsv` → `python3 -I scripts/gen-strings.py`); commit e
  push por tarefa em `main`.
- Teste real só com itens `io.github.guigx7.cymtest` e com o ok do usuário; release só com o ok do usuário.

## Review Focus

1. **Agente rodando agora** na worktree (arquivo mudado há 5 min): o cartão não leva, e a remoção recusa se a data mudou.
   Testes: `recentWorktreeNotSafe` (Task 3) e `refusesWhenWorktreeChanged` (Task 6).
2. **`node_modules` é link simbólico** (pnpm/workspaces) ou alguma pasta do caminho é link: nunca seguir, nunca listar.
   Teste: `symlinkedFoldersSkipped` (Task 3).
3. **`dist`/`build` versionados** no repositório: ficam de fora. Teste: `trackedBuildFolderSkipped` (Task 3).
4. **`gitdir` relativo, caminho com espaço/acento, worktree apagada à mão** (registro sobrando): resolver ou ignorar sem
   travar. Teste: `gitdirVariants` (Task 2).
5. **Sessão ativa ou recente e a pasta `memory/`** no meio das sessões: nunca entram. Teste:
   `recentAndMemoryNeverListed` (Task 4).

---

### Task 1: Catálogo dos agentes e localizador do git

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Agents/AgentsCatalog.swift`, `Core/Sources/CleanYourMacCore/Agents/GitTool.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Agents/GitToolTests.swift`

**Interfaces:**
- Produces:
  - `AgentsCatalog`:
    - `static let agents: [AgentsCatalog.Agent]`;
    - `Agent { id: String; name: String; worktreeRoots: [String]; sessions: SessionLayout }`, com
      `SessionLayout` = `.claudeCode` | `.codex` | `.gemini`;
    - `static let rebuildable: [String]` (a lista exata das Global Constraints, `node_modules` primeiro);
    - `static let neverTouch: [String]`.
  - Raízes de worktree relativas a `~`: Claude Code `[".claude/jobs/*/tmp/*"]` e o padrão `<repo>/.claude/worktrees/*`
    (tratado na Task 2); Codex `[".codex/worktrees/*"]`; Gemini `[]`.
  - `GitTool`:
    - `static func locate(runner: any CommandRunner, fileExists: (String) -> Bool) -> GitTool?`;
    - `func ignored(_ relPaths: [String], in worktree: URL) -> Set<String>`;
    - `func hasTracked(_ relPath: String, in worktree: URL) -> Bool`.

- [ ] **Step 1: Testes que falham**, com um `RecordingRunner` (`CommandRunner` falso):
  - `locatePrefersCommandLineTools`: com `fileExists` verdadeiro para
    `/Library/Developer/CommandLineTools/usr/bin/git`, `locate` devolve esse executável.
  - `locateUsesXcodeSelect`: sem as Command Line Tools e com `xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`,
    usa `<dev>/usr/bin/git`.
  - `locateNilWithoutDeveloperTools`: sem nenhum dos dois, devolve `nil`. **Nunca** chama `/usr/bin/git`, que abre o
    instalador; conferir pelas chamadas gravadas.
  - `ignoredParsesOutput`: `check-ignore` com saída `"dist\nbuild\n"` e status 0 → `["dist", "build"]`; status 1 → `[]`.
    Os argumentos esperados são `["-C", wt, "check-ignore", "--", "dist", "build", "out"]`.
  - `hasTrackedParses`: `ls-files` com saída não vazia → `true`; com saída vazia → `false`.
- [ ] **Step 2:** `swift test --package-path Core --filter GitToolTests` → FAIL (tipo não existe).
- [ ] **Step 3:** Implementar `AgentsCatalog` e `GitTool` (o `check-ignore` em lotes de até 200 caminhos por chamada).
- [ ] **Step 4:** `swift test --package-path Core --filter GitToolTests` → PASS.
- [ ] **Step 5:** commit `feat(core): catálogo de agentes e localizador do git`.

### Task 2: Descoberta das worktrees

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Agents/WorktreeFinder.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Agents/WorktreeFinderTests.swift` (com `FixtureTree`: estrutura `.git` falsa,
  sem rodar o git)

**Interfaces:**
- Consumes: `AgentsCatalog`.
- Produces:
  - `Worktree: Hashable, Sendable { url: URL; repo: URL?; branch: String?; isOrphan: Bool }`. A branch vem de
    `.git/worktrees/<n>/HEAD` (`ref: refs/heads/x`); `nil` quando está destacada (detached).
  - `WorktreeFinder(home: URL).worktrees(isCancelled: @Sendable () -> Bool) throws -> [Worktree]`, ordenadas por caminho.

- [ ] **Step 1: Testes que falham**
  - `linkedWorktreesFromGitdir`: o repositório `Projetos/a` tem `.git/worktrees/w1/gitdir` = `<home>/Projetos/a-w1/.git`, e
    `a-w1/.git` contém `gitdir: <home>/Projetos/a/.git/worktrees/w1`. Resultado: 1 worktree, `repo` = `a`, branch lida do
    HEAD. O checkout principal **não** entra.
  - `gitdirVariants`:
    - `gitdir` relativo (`../a-w2/.git`, resolvido a partir de `.git/worktrees/w2`);
    - caminho com espaço e acento (`Projetos/São Paulo w3`);
    - registro sobrando, com a pasta da worktree apagada: ignorado;
    - `.git` da worktree apontando para outro repositório: ignorado.
  - `outsideHomeSkipped`: um `gitdir` apontando para `/private/tmp/x/.git` fica de fora.
  - `agentRootOrphan`: `<home>/.claude/jobs/j1/tmp/wt` com o arquivo `.git` apontando para um repositório que não existe
    entra como `isOrphan == true` e `repo == nil`.
  - `walkSkipsLibraryAndNodeModules`: um `.git` dentro de `node_modules/pkg` e outro em `Library/x` não viram repositório.
- [ ] **Step 2:** `--filter WorktreeFinderTests` → FAIL.
- [ ] **Step 3:** Implementar:
  - varrer `~` atrás de pastas `.git`, com `autoreleasepool` por item; sem descer em `Library` (exceto pelas raízes do
    catálogo), `node_modules`, `.Trash` e pacotes; os ocultos só pelas raízes do catálogo;
  - juntar as raízes do catálogo e `<repo>/.claude/worktrees/*` de cada repositório achado;
  - remover repetidos pelo `PathPolicy.realPath`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(core): descoberta de worktrees ligadas pelos registros do git`.

### Task 3: Pastas recriáveis de cada worktree

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Agents/RebuildableFinder.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Agents/RebuildableFinderTests.swift`. Um teste de integração usa o git de verdade
  numa pasta temporária e é pulado se `GitTool.locate` devolver `nil`.

**Interfaces:**
- Consumes: `Worktree`, `GitTool?`, `FileSizer(mode: .allocated)`.
- Produces:
  - `RebuildableItem: Hashable, Sendable { url: URL; worktree: URL; name: String; size: Int64; modified: Date? }`;
  - `WorktreeEntry: Hashable, Sendable { worktree: Worktree; items: [RebuildableItem]; lastActivity: Date?; isRecent: Bool }`;
  - `RebuildableFinder(git: GitTool?, now: Date).entry(for: Worktree) -> WorktreeEntry?` (`nil` sem nenhum item);
  - `var buildFoldersSkipped: Bool`, verdadeiro quando `git == nil`.

- [ ] **Step 1: Testes que falham**
  - `nodeModulesAtAnyDepthUpTo4`: `node_modules` em `wt/`, em `wt/apps/web/` e em `wt/a/b/c/d/e/` (nível 5 fica de fora).
    Uma `node_modules` dentro de outra não é listada à parte.
  - `buildFoldersNeedIgnore`: o git falso diz que `dist` é ignorada e `build` não → só `node_modules` e `dist` entram.
  - `trackedBuildFolderSkipped`: `dist` ignorada, mas com `hasTracked("dist") == true` → fica de fora.
  - `noGitOnlyNodeModules`: com `git: nil` e `dist` presente → só `node_modules`, e `buildFoldersSkipped == true`.
  - `symlinkedFoldersSkipped`: `node_modules` como link para outra pasta, e `apps/` como link → nada listado por esses
    caminhos.
  - `recentWorktreeNotSafe`:
    - `src/x.ts` modificado há 3 h → `isRecent == true`;
    - um arquivo dentro de `node_modules` modificado agora **não** conta;
    - tudo com mais de 24 h → `false`;
    - `lastActivity` = a data mais nova de fora das pastas recriáveis.
  - `integrationWithRealGit` (pulado sem git): `git init`, `.gitignore` com `dist/`, `build/` com um arquivo commitado →
    só `node_modules` e `dist` entram.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implementar.
  - **Atividade:** olhar as datas dos arquivos até 3 níveis, mais a do índice em `.git/worktrees/<n>/index` (sem descer em
    recriáveis nem em `.git`).
  - **Tamanho:** `FileSizer.allocatedSize`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(core): node_modules e builds ignorados das worktrees`.

### Task 4: Sessões antigas dos agentes

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Agents/SessionFinder.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Agents/SessionFinderTests.swift`

**Interfaces:**
- Consumes: `AgentsCatalog`, `WorktreeFinder` (para saber se um job tem worktree dentro).
- Produces:
  - `AgentSession: Hashable, Sendable, Identifiable { id: String; agent: String; project: String?; urls: [URL]; size: Int64;
    lastModified: Date; isOrphanRemains: Bool }`. O `id` é `"<agent>:<sessão>"`.
  - `SessionFinder(home: URL, now: Date, worktrees: Set<URL>).sessions() -> [AgentSession]`, só as com mais de 7 dias,
    ordenadas por agente e depois por `lastModified`.

- [ ] **Step 1: Testes que falham**
  - `claudeSessionIsOneItem`: `projects/-p/<id>.jsonl` (10 dias), mais `projects/-p/<id>/` e
    `file-history/<id>`, `session-env/<id>`, `todos/<id>-agent-x.json` → **um** item com 5 urls. `lastModified` é a data
    mais nova; se um desses arquivos foi tocado há 2 dias, a sessão fica de fora.
  - `claudeOrphanRemains`: `file-history/<id2>` com 9 dias e sem `.jsonl` → item com `isOrphanRemains == true`.
  - `recentAndMemoryNeverListed`:
    - sessão de 3 dias fica de fora;
    - `projects/-p/memory/` com arquivos de 30 dias nunca aparece;
    - `history.jsonl` e `settings.json` de 30 dias nunca aparecem.
  - `jobsRules`, com tudo a 20 dias:
    - job `j1` com `state.json` `{"state":"done"}` entra;
    - `j2` com `"blocked"` fica de fora;
    - `j3` com uma worktree ligada em `tmp/wt` fica de fora;
    - `j4` com `backup/` fica de fora.
  - `codexSessions`: `~/.codex/sessions/2026/09/01/rollout-x.jsonl` com 20 dias entra; o de 2 dias não. `*.sqlite` nunca
    entra.
  - `geminiChats`: `~/.gemini/tmp/<hash>/chats/c.json` com 20 dias entra.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implementar. O `id` da sessão do Claude Code é o nome do `.jsonl` sem extensão; os restos dela se ligam
  pelo prefixo do nome. Estados ativos do job: `running`, `blocked`, `waiting`, `pending`, `paused` e qualquer estado
  desconhecido. Só `done`, `completed`, `failed` e `cancelled` liberam.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(core): sessões antigas do Claude Code, Codex e Gemini`.

### Task 5: Conferência do Codex (sem código)

- [ ] **Step 1:** Ler o esquema de `~/.codex/thread_history_*.sqlite` (`sqlite3 -readonly <cópia> .schema`), numa cópia na
  pasta de rascunho, e ver se as sessões aparecem por caminho.
- [ ] **Step 2:** Com uma sessão falsa criada por nós (`~/.codex/sessions/…/io.github.guigx7.cymtest-*.jsonl`), conferir no
  Codex CLI (`codex resume`, só listar) se um arquivo que sumiu quebra a lista ou só some dela. Isso exige o ok do usuário;
  sem o ok, anotar como pendência e manter o Codex.
- [ ] **Step 3:** Anotar o resultado no design ("Decisões tomadas depois da revisão", item 4). Se o Codex quebrar, tirar
  `.codex` de `AgentsCatalog.agents`, com um teste que fixa isso. Commit `docs: conferência das sessões do Codex`.

### Task 6: Relatório, cartões, removedor e `cym agents`

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Agents/AgentsReport.swift`, `Core/Sources/CleanYourMacCore/Agents/AgentsRemoval.swift`
- Modify: `Core/Sources/cym/main.swift` (subcomando `agents [--json]`), `Core/Sources/CleanYourMacCore/Cleaning/CleanupLog.swift`
  (`write(agents:)`, prefixo `agents`)
- Test: `Core/Tests/CleanYourMacCoreTests/Agents/AgentsReportTests.swift`, `AgentsRemovalTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `AgentsReport: Sendable { worktrees: [WorktreeEntry]; sessions: [AgentSession]; buildFoldersSkipped: Bool; tiles: [AgentsTile] }`,
    com `total`, `isEmpty` e `removing(_ ids: Set<String>) -> AgentsReport`.
  - Os ids marcáveis são o caminho do `RebuildableItem` e o `AgentSession.id`.
  - `AgentsTile { kind: .worktrees | .sessions(agent: String); count: Int; size: Int64; ids: Set<String> }`:
    - o cartão de worktrees leva só as entradas com `isRecent == false`;
    - há um cartão de sessões por agente.
  - `AgentsScan(home:now:).run() -> AsyncThrowingStream<AgentsScanEvent, Error>`, com os eventos
    `.progress("worktrees"|"folders"|"sessions")` e `.finished(AgentsReport)`. Roda numa thread de 8 MB, como no `ClutterScan`.
  - `AgentsTarget { id: String; urls: [URL]; modified: Date?; root: URL; size: Int64 }`;
    `AgentsReport.targets(for: Set<String>) -> [AgentsTarget]`.
  - `AgentsRemover(trasher:, home:, dryRun:, log:).remove(_ targets: [AgentsTarget]) async -> [String: Result<Void, CleanFailure>]`.

- [ ] **Step 1: Testes que falham**
  - `tilesOnlySafe`: 2 worktrees, uma recente → o cartão de worktrees conta 1 entrada e o tamanho só dela. As sessões
    viram 1 cartão por agente.
  - `removingDropsEmpty`: tirar todos os itens de uma worktree faz a entrada sumir, e os cartões são recalculados.
  - `refusesWhenWorktreeChanged`: o alvo é um `node_modules`; depois da análise, a data dele mudou → `"item changed"` e
    nada vai para o Lixo.
  - `refusesSymlinkAndOutsideRoot`:
    - o alvo virou link → recusado;
    - um alvo cujo caminho não está dentro de `root` (`root` = worktree ou `~/.claude` etc.) → `"kept: protected"`;
    - qualquer caminho de `AgentsCatalog.neverTouch` → `"kept: protected"`.
  - `sessionRemovedAsUnit`: uma sessão com 3 urls vai inteira para o Lixo. Se uma delas mudou, nenhuma vai.
  - `dryRunAndLog`: `dryRun` não toca em nada e grava `agents-*.json`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implementar. A revalidação reaproveita a ideia do `ClutterRemover.unchanged`: `lstat`, `realPath` do pai e
  a data. O `cym agents --json` imprime as worktrees com os itens e as sessões por agente, com os tamanhos.
- [ ] **Step 4:** PASS; `swift test --package-path Core` inteiro → PASS.
- [ ] **Step 5:** Rodar `swift run --package-path Core -c release cym agents` na máquina (só leitura) e conferir à mão contra
  o levantamento do design: 9 worktrees no `organizacao10x`; `wt-sim` como worktree, e não como sessão; 72 sessões do
  Claude e 149 do Codex com mais de 7 dias.
- [ ] **Step 6:** commit `feat(core): relatório, cartões, remoção para o Lixo e cym agents`.

### Task 7: App — fluxo (`AgentsFlowModel`)

**Files:**
- Create: `App/Agents/AgentsFlowModel.swift`
- Test: `AppTests/AgentsFlowModelTests.swift`

**Interfaces:**
- Consumes: `AgentsScan`, `AgentsRemover`, `AgentsReport`.
- Produces:
  - `AgentsFlowModel` (`@MainActor @Observable`) com as mesmas fases do `ClutterFlowModel`: `intro`, `scanning`,
    `results`, `nothingFound`, `removing`, `done(Outcome)`.
  - Seções `.worktrees` e `.sessions`.
  - Métodos: `start`, `stop`, `back`, `restart`, `openManager(_:autoselect:)`, `toggle`, `setAll`, `cleanTile(_:)`
    (seleciona os ids do cartão e pede a confirmação), `requestRemoval`, `confirmRemoval`, `reviewMore`.
  - Campos: `selectedCount`, `selectedSize`, `confirmingRemoval`.
  - `AgentsEnvironment.makeModel()`, com `CYM_DRY_RUN` no Debug.

- [ ] **Step 1: Testes que falham** (scan e remover falsos, como em `AppTests/ClutterFlowModelTests.swift`):
  - `scanToResults`;
  - `emptyIsNothingFound`;
  - `tileCleanSelectsOnlySafeAndConfirms`: o cartão não marca a worktree recente;
  - `recentWorktreeSelectableByHand`;
  - `stopIgnoresQueuedResult`;
  - `removalUpdatesReportAndOutcome`, com uma falha mantida no relatório e a chave pelo caminho.
- [ ] **Step 2:** `scripts/test-app.sh` → FAIL.
- [ ] **Step 3:** Implementar, no padrão do `ClutterFlowModel`, com o índice de ids para o rodapé.
- [ ] **Step 4:** PASS (matar o Debug depois: `pkill -f "Debug/CleanYourMac.app"`).
- [ ] **Step 5:** commit `feat(app): fluxo do módulo Agentes de IA`.

### Task 8: App — telas, textos e navegação

**Files:**
- Create: `App/Agents/AgentsModuleView.swift` (Intro, Análise, Nada encontrado, Removendo, Concluído),
  `App/Agents/AgentsResultsView.swift`, `App/Agents/AgentsManagerView.swift`
- Modify:
  - `App/Navigation/AppModule.swift` (`case agents`, depois de `clutter`, símbolo `cpu`);
  - `App/Navigation/RootView.swift`;
  - `App/Design/Theme.swift`, `App/Design/ModuleArtwork.swift`, `App/Cleanup/CategoryInfo.swift` (cor própria);
  - `App/Resources/Strings.tsv` (chaves `module.agents` e `agents.*`).

**Interfaces:**
- Consumes: `AgentsFlowModel` (Task 7). Reaproveitar do Acúmulos `ClutterFileRow`, `ClutterGroupRow` e
  `ClutterSectionHeader`, renomeando para `ModuleFileRow`, `ModuleGroupRow` e `ModuleSectionHeader` em
  `App/Design/ManagerRows.swift`, se o uso duplo pedir.

- [ ] **Step 1:** Telas:
  - **Resultados:** cabeçalho com o total de espaço e cartões com o botão **Limpar**, que chama `cleanTile`, mais Revisar.
  - **Gerenciador, Worktrees:** repositório → worktree (branch, caminho, "mudou há X", selo "em uso" se recente, selo
    "repositório principal não encontrado" se órfã) → pastas.
  - **Gerenciador, Sessões:** agente → projeto → sessão (data e tamanho), mais "restos de sessões apagadas".
  - **Sessões de agentes não suportados:** OpenCode, Cursor e Copilot detectados pela pasta (`~/.local/share/opencode`,
    `~/.cursor`, `~/.copilot`) aparecem numa linha "não suportado ainda", sem caixa.
  - **Avisos:** sem git, "Só node_modules: instale as ferramentas de linha de comando do Xcode para incluir as pastas de
    build". Na confirmação, "não dá mais para retomar essas conversas" e "o espaço volta ao esvaziar o Lixo".
- [ ] **Step 2:** Textos pt/en com redação nossa; `python3 -I scripts/gen-strings.py`.
- [ ] **Step 3:** `scripts/test-app.sh` → PASS. Capturas com `scratchpad/shot.sh` (`CYM_MODULE=agents`,
  `CYM_AGENTS_AUTO=results|worktrees|sessions|done`) e conferência visual.
- [ ] **Step 4:** commit `feat(app): telas do módulo Agentes de IA`.

### Task 9: Revisão final e correções

- [ ] **Step 1:** Subagente no modelo mais capaz revisa `git diff <início>..HEAD` com foco em segurança de dados (Global
  Constraints e Review Focus), concorrência, memória e chaves de texto.
- [ ] **Step 2:** Corrigir cada achado confirmado com TDD. Rodar as duas suítes inteiras. Commit `fix(agentes): correções da
  revisão final`.

### Task 10: Teste real, README, versão e release

- [ ] **Step 1 (com o ok do usuário):** criar `~/Projetos/io.github.guigx7.cymtest-repo`, com uma worktree ligada
  (`git worktree add`) que tenha `node_modules`, `dist` ignorado e `build` versionado, e sessões falsas
  `io.github.guigx7.cymtest-*` com data de 10 dias. Limpar pelo app instalado e conferir: só `node_modules`/`dist` e as
  sessões falsas no Lixo; `build`, o código e o registro da worktree intactos (`git worktree list`).
- [ ] **Step 2:** README (seção do módulo, permissões, `cym agents`, roadmap) e `project.yml` com `MARKETING_VERSION`
  `0.6.0` e `CURRENT_PROJECT_VERSION` `7`. Commit e push.
- [ ] **Step 3:** Release `v0.6.0` só com o ok explícito do usuário.
