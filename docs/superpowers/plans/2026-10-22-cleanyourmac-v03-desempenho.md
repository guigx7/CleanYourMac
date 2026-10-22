# CleanYourMac v0.3 — Módulo Desempenho: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Módulo Desempenho, com Tarefas de Manutenção executadas de verdade, Itens de Início e Itens em Segundo Plano com as ações Desativar, Reativar e Remover, e Capturas do Time Machine. A análise deve bater com a do CleanMyMac 5.7.2 nesta máquina.

**Architecture:** Mesma divisão das versões anteriores: RE clean room → specs em `docs/re/specs/performance/` → Core (`Core/Sources/CleanYourMacCore/Performance/`) → ajudante (operações tipadas novas) → app (`App/Performance/`) → paridade → teste real → release. As tarefas usam ferramentas do macOS por meio de `CommandRunner` e `PrivilegedRunner`, sem shell livre. Os itens de início e em segundo plano reaproveitam `LoginItemsSource`, as travas do ajudante da v0.2 e o guia de permissões.

**Tech Stack:** Swift 6.4, SwiftUI, macOS 14+, Swift Testing, XcodeGen, `Strings.tsv` → `gen-strings.py`, Python 3 para a paridade.

**Spec:** `docs/superpowers/specs/2026-10-22-cleanyourmac-v03-desempenho-design.md` (e as das versões anteriores, para o que ele herda)

## Global Constraints

- macOS 14+, Swift 6 strict concurrency, sem dependências externas. **Sem APIs privadas.** Ferramentas do macOS (`launchctl`, `tmutil`, `mdutil`, `dscacheutil`, `sfltool dumpbtm` só para ler) são permitidas.
- No CleanMyMac roda-se **só a análise**. O `dump-ax` recusa executar, liberar, diminuir, reindexar, acelerar, reparar, desativar, remover etc.
- **Tarefas de verdade são permitidas neste Mac** (decisão do usuário), com aviso antes das pesadas (Reindexar o Spotlight, Liberar Espaço Purgável). Desativar, Reativar e Remover só em itens de teste criados por nós (`io.github.guigx7.cymtest.*`), até o teste real com o usuário.
- Tudo respeita `CYM_DRY_RUN`: o Debug simula por padrão. O teste real usa o Release em `/Applications`.
- **Remover vai para o Lixo.** Nunca mexe em `com.apple.*` nem no app dono do item.
- Paridade: tarefas aplicáveis e recomendadas, itens de início e itens em segundo plano iguais aos do CleanMyMac. Divergências ficam em `perf-known-divergences.json` com motivo.
- pt-BR e en; cada task termina com commit e `git push origin main`.
- Testes: `swift test --package-path Core` e `scripts/test-app.sh` (nunca rodar suítes em paralelo com o app de Debug aberto).

## Review Focus

1. **Tarefa que estoura o tempo ou é cancelada no meio** (Reindexar o Spotlight demora): o status fica "tempo esgotado" ou "cancelada", não sobra processo pendurado e as outras tarefas seguem. Teste `timeoutAndCancelPerTask` na Task 6.
2. **Item que mudou entre a análise e a ação** (plist trocado, Label diferente, desligado pelos Ajustes, virou symlink): revalidar e recusar sem tocar em outro item. Testes `actionRevalidatesItem` na Task 9 e `launchdDisableRefusesSymlinkAndApple` na Task 7.
3. **Senha de administrador cancelada:** as tarefas que precisam de root falham com "cancelada" e as demais rodam. Teste `adminCancelledOnlyFailsRootTasks` na Task 6.
4. **App dono recria o item** (GoogleUpdater, Setapp): depois de remover ou desativar, a nova análise mostra o estado real, e a confirmação já tinha avisado. Teste `ownerInstalledWarns` na Task 9.
5. **Item moderno (`SMAppService`)**, que não pode ser alterado por outro app: os botões abrem os Ajustes com o guia, nunca falham em silêncio. Teste `modernItemsOpenSettings` na Task 15.

---

## Estrutura de arquivos

```
Core/Sources/CleanYourMacCore/Performance/
├── MaintenanceTask.swift        # MaintenanceTaskID, MaintenanceTask (aplicável, recomendada, admin, tempo-limite)
├── MaintenanceCatalog.swift     # regras de aplicabilidade/recomendação (spec), com fontes injetáveis
├── MaintenanceRunner.swift      # executa tarefas (CommandRunner/PrivilegedRunner), progresso, cancelamento
├── StartupItem.swift            # StartupItem, StartupItemKind, StartupItemState
├── StartupItemsScanner.swift    # lista de sessão, plists do launchd, itens modernos (leitura), estado desativado
├── StartupItemsActions.swift    # desativar / reativar / remover; registro dos desativados da lista de sessão
├── TimeMachineSnapshots.swift   # listar / apagar capturas locais
└── PerformanceReport.swift      # PerformanceScan + PerformanceReport + parityJSON
Core/Sources/CleanYourMacCore/Helper/…, Cleaning/PrivilegedRunner.swift   # operações novas (versão 3)
Core/Sources/cym/main.swift                                               # `cym performance`
App/Performance/  PerformanceFlowModel, PerformanceModuleView, Intro/Scanning/Results/Tiles, PerformanceManagerView,
                  MaintenanceView, StartupItemsView, SnapshotsView, PerformanceActionView, PerformanceDemoData
docs/re/specs/performance/*.md, docs/re/parity/perf-*.json|md
scripts/re/collect-perf-baseline.py, scripts/parity/perf_ax_to_baseline.py, compare_perf.py (+ testes)
```

## Interfaces centrais

```swift
public enum MaintenanceTaskID: String, CaseIterable, Codable, Sendable {
    case speedUpMail, flushDNS, freeUpPurgeable, reindexSpotlight, repairPermissions, freeUpRAM, periodicScripts, thinSnapshots
}
public struct MaintenanceTask: Identifiable, Hashable, Sendable {
    public let id: MaintenanceTaskID
    public let isApplicable: Bool         // aparece na lista
    public let isRecommended: Bool        // conta no cartão "N recomendadas" (regra da spec)
    public let requiresAdmin: Bool
    public let detail: Int64?             // ex.: bytes purgáveis ("Até 3,8 GB")
    public let timeout: Duration
}
public protocol MaintenanceFacts: Sendable { … }   // dados do sistema que as regras consultam (spec define os campos)
public struct MaintenanceCatalog: Sendable { public func tasks(_ context: ScanContext) -> [MaintenanceTask] }
public enum MaintenanceEvent: Sendable { case started(MaintenanceTaskID), finished(MaintenanceTaskID, Result<Void, CleanFailure>), completed(MaintenanceReport) }
public final class MaintenanceRunner: Sendable {
    public init(commands: any CommandRunner, privileged: any PrivilegedRunner, dryRun: Bool, log: CleanupLog)
    public func run(_ tasks: [MaintenanceTask]) -> AsyncStream<MaintenanceEvent>
}

public enum StartupItemKind: String, Codable, Sendable { case sessionLoginItem, userAgent, systemAgent, systemDaemon, modern }
public enum StartupItemState: String, Codable, Sendable { case enabled, disabled }
public struct StartupItem: Identifiable, Hashable, Sendable {
    public let id: String                 // kind + caminho/label
    public let kind: StartupItemKind
    public let name: String               // nome exibido (app dono ou arquivo)
    public let label: String?             // Label do launchd
    public let plist: URL?
    public let program: URL?
    public let ownerApp: URL?             // app dono, se achado (vínculo da v0.2)
    public let ownerBundleID: String?
    public let state: StartupItemState
    public let isBackground: Bool         // seção Itens em Segundo Plano × Itens de Início
}
public struct StartupItemsScanner: Sendable { public func items(_ context: ScanContext) -> [StartupItem] }
public enum StartupAction: Sendable { case disable, enable, remove }
public struct StartupItemsActions: Sendable {
    public func perform(_ action: StartupAction, on items: [StartupItem]) async -> [String: Result<Void, CleanFailure>]
}
// PrivilegedCommand: + .launchdDisable(plist: URL, owner: String), + .launchdEnable(plist: URL, owner: String),
//                    + .maintenance(MaintenanceTaskID)   (o ajudante mapeia para comandos fixos; HelperConstants.version = 3)
public struct LocalSnapshot: Identifiable, Hashable, Sendable { public let id: String /* data */; public let volume: URL }
public struct PerformanceReport: Sendable {
    public let tasks: [MaintenanceTask]
    public let loginItems: [StartupItem]
    public let backgroundItems: [StartupItem]
    public let snapshots: [LocalSnapshot]
    public func parityJSON() -> [String: Any]
}
```

---

## Fase A — Reconhecimento e specs

### Task 1: Baseline do CleanMyMac

**Files:** Create `scripts/re/collect-perf-baseline.py`, `scripts/parity/perf_ax_to_baseline.py`, `scripts/parity/test_perf_ax_to_baseline.py`, `docs/re/parity/perf-baseline-2026-10-22.json`

- [ ] **Step 1:** Escrever o teste do conversor com os dumps já salvos (`re-notes/ax/perf-manager-*.txt`, recortados em `scripts/parity/fixtures/perf-ax/`). Asserções:
  - `tasks == ["Acelerar o Mail", "Esvaziar Cache do DNS", "Liberar Espaço Purgável", "Reindexar o Spotlight", "Reparar Permissões do Disco"]`;
  - `purgeable == 3_800_000_000`;
  - `loginItems == ["GlucoTracker.app", "Hidden Bar.app", "Vorssaint.app", "Warp.app"]`;
  - `backgroundItems` com 9 entradas, incluindo `"com.bjango.istatmenus.installer.plist"` e `"Logi Options+.app"` duas vezes;
  - `tiles == {"loginItems": 4, "maintenance": 5, "backgroundItems": 9}`.

  Rodar `python3 -I scripts/parity/test_perf_ax_to_baseline.py`. Esperado: FAIL.
- [ ] **Step 2:** Implementar o conversor. Implementar o coletor, que reaproveita as funções de `collect-apps-baseline.py`: `open -a`, análise, Resultados, "Ver Todas as Tarefas" e as três seções.
- [ ] **Step 3:** Rodar o teste. Esperado: PASS. Coletar e gerar a baseline.
- [ ] **Step 4:** Commit `chore(re): baseline do módulo Desempenho` e push.

### Task 2: Specs — Tarefas de Manutenção e Capturas do Time Machine

**Files:** Create `docs/re/specs/performance/maintenance-tasks.md`, `docs/re/specs/performance/time-machine.md`

- [ ] **Step 1:** Para **cada uma das 8 tarefas**, a spec responde:
  - o que o CleanMyMac executa (comandos, se roda como root, tempo-limite);
  - quando ela é **aplicável** (por que Liberar RAM, Scripts Periódicos e Capturas não apareceram aqui);
  - quando é **recomendada** (as 5 daqui);
  - de onde vem o "Até 3,8 GB";
  - as falhas previstas (sem pasta do Mail, sem permissão, cancelada, tempo esgotado);
  - a **nossa** forma segura e equivalente, sem API privada. Se o método dele for arriscado (ex.: encher o disco), a spec propõe uma alternativa ou a exclusão, com motivo.

  Fontes: textos e símbolos, Ghidra e REA (`gdecomp2.sh PerformanceModule|PerformanceScanning|PerformanceService|HealthMonitoringCore|PrivilegedRoutines`) e o disco desta máquina, só leitura.
- [ ] **Step 2:** `time-machine.md`: como lista e apaga as capturas locais (`tmutil listlocalsnapshots` e `deletelocalsnapshots`), se precisa de root, e quando o cartão aparece.
- [ ] **Step 3:** Um commit por spec (`docs(re): spec de <tema> (desempenho)`) com push.

### Task 3: Specs — Itens de Início, Itens em Segundo Plano e Resultados

**Files:** Create `docs/re/specs/performance/login-items.md`, `background-items.md`, `results-screen.md`

- [ ] **Step 1:** `login-items.md`:
  - de onde vêm os 4 itens (lista de sessão? Gerenciamento de Itens em Segundo Plano?);
  - nome exibido;
  - o que "Remover" faz no CleanMyMac;
  - a **nossa** forma de Desativar, Reativar e Remover, com o registro dos desativados;
  - itens modernos (`SMAppService`): como identificar e quando abrir os Ajustes.
- [ ] **Step 2:** `background-items.md`:
  - por que estes 9 itens e não outros (pastas, exclusões, `com.apple.*`, `AssociatedBundleIdentifiers`, auxiliares do Setapp);
  - nome exibido (app dono × plist);
  - o que "Remover" leva no CleanMyMac;
  - a **nossa** forma (`launchctl disable` + `bootout` / `enable` + `bootstrap`; remover = `bootout` + plist e auxiliar para o Lixo);
  - o estado desativado (`launchctl print-disabled`);
  - o aviso quando o app dono está instalado.
- [ ] **Step 3:** `results-screen.md`: cartões, condições, ordem, botões, estados concluído e "não há tarefas", e o cabeçalho.
- [ ] **Step 4:** Um commit por spec, com push.

---

## Fase B — Core

### Task 4: Modelos do módulo

**Files:** Create `Core/Sources/CleanYourMacCore/Performance/MaintenanceTask.swift`, `StartupItem.swift`; Test `Core/Tests/CleanYourMacCoreTests/Performance/PerformanceModelTests.swift`

- [ ] **Step 1:** Escrever os testes:
  - `taskIDsMatchSpec`: os 8 casos, em ordem;
  - `startupItemIDIsStable`: `id` = `"<kind>:<plist ou label ou caminho>"`;
  - `backgroundVsLogin`: `.sessionLoginItem` e `.modern` de app de início são login; agentes e daemons são background, como a spec decidir.

  Rodar. Esperado: FAIL.
- [ ] **Step 2:** Implementar conforme as Interfaces centrais. Rodar. Esperado: PASS.
- [ ] **Step 3:** Commit `feat(core): modelos do módulo Desempenho` e push.

### Task 5: Catálogo de tarefas (aplicável e recomendada)

**Files:** Create `Performance/MaintenanceCatalog.swift`; Test `Performance/MaintenanceCatalogTests.swift`

**Interfaces:** `MaintenanceFacts` reúne os dados do sistema que as regras da spec usam (ex.: datas da última execução guardadas por nós, presença do Mail, espaço purgável, arquitetura e versão do macOS, capturas locais). Há uma implementação de produção e uma falsa para os testes.

- [ ] **Step 1:** Escrever os testes:
  - `applicableTasksOnThisMachineShape`: com os fatos desta máquina segundo a spec, o resultado é exatamente as 5 tarefas da baseline;
  - um teste por regra de aplicabilidade e de recomendação da spec, como `freeUpRAMHiddenWhen…` e `mailNeedsMailFolder`;
  - `purgeableDetailFromFacts`: com 3.800.000.000 bytes, `detail == 3_800_000_000`.
- [ ] **Step 2:** Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS.
- [ ] **Step 3:** Commit `feat(core): tarefas de manutenção aplicáveis e recomendadas` e push.

### Task 6: Execução das tarefas

**Files:** Create `Performance/MaintenanceRunner.swift`; Test `Performance/MaintenanceRunnerTests.swift`

**Interfaces:** cada tarefa vira uma lista fixa de passos (`CommandRunner` sem root ou `PrivilegedCommand.maintenance(id)` com root), definida pela spec. O registro de cada execução vai para `~/Library/Logs/CleanYourMac/`. A data da última execução fica em `UserDefaults`, para as regras de recomendação.

- [ ] **Step 1:** Escrever os testes, com `CommandRunner` e `PrivilegedRunner` falsos:
  - `runsEachTaskWithSpecCommands`: os argumentos exatos de cada tarefa sem root, conforme a spec;
  - `rootTasksGoToPrivilegedBatch`: as tarefas com root vão num único lote, e só ele pede senha;
  - `adminCancelledOnlyFailsRootTasks`;
  - `timeoutAndCancelPerTask`: um comando falso lento passa do tempo-limite e vira `"timed out"`; cancelar no meio deixa as restantes como `"cancelled"`; não sobra processo filho;
  - `dryRunRunsNothing`;
  - `recordsLastRunDate`.
- [ ] **Step 2:** Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS.
- [ ] **Step 3:** Commit `feat(core): execução das tarefas de manutenção` e push.

### Task 7: Ajudante — desativar, reativar e tarefas como root

**Files:** Modify `Cleaning/PrivilegedRunner.swift`, `Helper/HelperExecutor.swift`, `Helper/HelperProtocol.swift` (`version = 3`); Test `HelperPerformanceTests.swift`, `PrivilegedScriptTests.swift`

- [ ] **Step 1:** Escrever os testes:
  - `launchdDisableAndEnableUseLabelDomain`:
    - `/Library/LaunchDaemons/x.plist` gera `launchctl disable system/<Label>` + `bootout`;
    - o enable gera `enable` + `bootstrap system <plist>`;
    - agentes usam `gui/<uid>`;
  - `launchdDisableRefusesSymlinkAndApple`: recusa plist que é link, `com.apple.*` e plist sem vínculo com o owner (mesmo `launchdLinked` da v0.2);
  - `maintenanceCommandsAreFixed`: `.maintenance(.flushDNS)` executa só os comandos da spec (sem parâmetros vindos do cliente), e um id desconhecido é recusado;
  - `appleScriptRunnerSupportsNewCommands`: o script equivalente, com aspas.
- [ ] **Step 2:** Rodar. Esperado: FAIL. Implementar. Rodar o Core inteiro. Esperado: PASS.
- [ ] **Step 3:** Commit `feat(helper): desativar/reativar launchd e tarefas de manutenção` e push.

### Task 8: Lista de itens de início e em segundo plano

**Files:** Create `Performance/StartupItemsScanner.swift`; Test `Performance/StartupItemsScannerTests.swift`

- [ ] **Step 1:** Escrever os testes, com fixture e fontes falsas:
  - `sessionItemsFromLoginItemsSource`;
  - `launchdPlistsFromSpecFolders`: as 3 pastas, sem `com.apple.*`, sem link, com as regras de exclusão da spec;
  - `ownerAppResolved`: pelo bundle ID, por `AssociatedBundleIdentifiers` ou pelo `Program` dentro do `.app`, e o nome exibido segue a spec;
  - `disabledStateFromLaunchctl`: com a saída falsa de `launchctl print-disabled`, o estado fica `.disabled`;
  - `disabledSessionItemsFromRecord`: os itens do nosso registro aparecem como desativados;
  - `modernItemsReadOnly`: se a spec usar `sfltool dumpbtm`, a saída falsa vira `.modern`.
- [ ] **Step 2:** Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS.
- [ ] **Step 3:** Commit `feat(core): itens de início e em segundo plano` e push.

### Task 9: Desativar, Reativar e Remover

**Files:** Create `Performance/StartupItemsActions.swift`; Test `Performance/StartupItemsActionsTests.swift`

- [ ] **Step 1:** Escrever os testes:
  - `disableUserAgentReversible`: disable + bootout no domínio `gui/<uid>`, e enable + bootstrap volta ao estado anterior;
  - `systemItemsGoToHelper`: com `PrivilegedRunner` falso, um único lote;
  - `removeTrashesPlistAndHelperTool`: o plist e `/Library/PrivilegedHelperTools/<label>` vão para o Lixo; o app dono nunca;
  - `sessionDisableKeepsRecordAndEnableRestores`: grava em `disabled-login-items.json` (dentro do fixture) e recoloca na lista;
  - `actionRevalidatesItem`: um plist trocado depois da análise (Label diferente ou link) é recusado;
  - `ownerInstalledWarns`: `warnings(for:)` devolve `.ownerMayRecreate(appURL)` quando o app dono existe;
  - `dryRunTouchesNothing`.
- [ ] **Step 2:** Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS.
- [ ] **Step 3:** Commit `feat(core): desativar, reativar e remover itens de início` e push.

### Task 10: Capturas do Time Machine

**Files:** Create `Performance/TimeMachineSnapshots.swift`; Test `Performance/TimeMachineSnapshotsTests.swift`

- [ ] **Step 1:** Testes com `CommandRunner` falso: `parsesListLocalSnapshots` (saída real de exemplo da spec), `deletesSelectedByDate` (comando da spec, com root se a spec mandar) e `noSnapshotsMeansNoTile`. Rodar. Esperado: FAIL.
- [ ] **Step 2:** Implementar. Rodar. Esperado: PASS. Commit `feat(core): capturas locais do Time Machine` e push.

### Task 11: Análise do módulo e `cym performance`

**Files:** Create `Performance/PerformanceReport.swift`; Modify `Registry.swift`, `cym/main.swift`; Test `Performance/PerformanceScanTests.swift`

- [ ] **Step 1:** Escrever os testes:
  - `reportHasAllSections`;
  - `cancelStopsQuickly`;
  - `cliJsonMatchesBaselineShape`: as chaves do JSON são as de `perf-baseline-2026-10-22.json`.
- [ ] **Step 2:** Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS. Conferir `swift run --package-path Core cym performance` nesta máquina contra a baseline.
- [ ] **Step 3:** Commit `feat(core): análise do Desempenho e cym performance` e push.

---

## Fase C — App

Mesmo visual dos outros módulos: gradiente laranja já em `Theme`, `GlassCard`, `ArtPalette` própria (disco laranja com um símbolo de velocímetro), as peças do Gerenciador de Aplicativos (`AppsItemRow`/`TriStateCheckbox` com nomes acessíveis) e o guia de permissões.

### Task 12: Fluxo e navegação

**Files:** Create `App/Performance/PerformanceFlowModel.swift`, `PerformanceModuleView.swift`; Modify `App/Navigation/AppModule.swift` (`.performance` disponível), `RootView.swift`; Test `AppTests/PerformanceFlowModelTests.swift`

- [ ] **Step 1:** Escrever os testes, com fakes:
  - `scanThenResults`, `nothingFound`, `stopReturnsToIntro`;
  - `runSelectedTasksShowsProgressAndDone`;
  - `disableAsksConfirmationWithOwnerWarning`;
  - `heavyTasksAskBeforeRunning`: Reindexar o Spotlight e Liberar Espaço Purgável pedem confirmação extra.
- [ ] **Step 2:** Rodar `scripts/test-app.sh`. Esperado: FAIL. Implementar. Rodar. Esperado: PASS. Commit `feat(app): fluxo do módulo Desempenho` e push.

### Task 13: Intro, Análise e Resultados

**Files:** Create `App/Performance/PerformanceIntroView.swift`, `PerformanceResultsView.swift`, `PerformanceTiles.swift`; Modify `App/Design/ModuleArtwork.swift`; Test `AppTests/PerformanceTilesTests.swift`

- [ ] **Step 1:** Teste `tilesFollowSpec`: cartões, ordem, botões e destino de cada Revisar (seção e foco), conforme `results-screen.md`. Rodar. Esperado: FAIL.
- [ ] **Step 2:** Implementar as telas e a arte. Rodar. Esperado: PASS. Conferir capturas em pt-BR e en. Commit `feat(app): intro, análise e resultados do Desempenho` e push.

### Task 14: Gerenciador — Tarefas de Manutenção

**Files:** Create `App/Performance/PerformanceManagerView.swift`, `MaintenanceView.swift`

- [ ] **Step 1:** Teste no modelo, `taskSelectionAndRunOnlyVisibleSection`: o escopo da ação é a seção, como na v0.2. Rodar. Esperado: FAIL.
- [ ] **Step 2:** Implementar:
  - a lista com checkbox, nome, subtítulo ("Até 3,8 GB"), descrição e data da última execução;
  - o rodapé "N selecionadas" + **Executar**;
  - o progresso por tarefa, com Parar;
  - a explicação do Acelerar o Mail sem Acesso Total ao Disco, com o botão do guia.

  Rodar. Esperado: PASS. Commit `feat(app): tarefas de manutenção` e push.

### Task 15: Gerenciador — Itens de Início e em Segundo Plano

**Files:** Create `App/Performance/StartupItemsView.swift`; Test `AppTests/PerformanceFlowModelTests.swift`

- [ ] **Step 1:** Escrever os testes:
  - `modernItemsOpenSettings`: Desativar ou Remover num item `.modern` abre Ajustes › Itens de Início com o guia, sem chamar as ações;
  - `disabledListShowsReactivate`: os itens `.disabled` aparecem num grupo "Desativados" com **Reativar**;
  - `footerOffersDisableAndRemove`.

  Rodar. Esperado: FAIL.
- [ ] **Step 2:** Implementar:
  - as duas seções com linhas (ícone do app dono, nome, tipo, estado);
  - o menu Selecionar;
  - o rodapé com **Desativar** e **Remover**, e **Reativar** no grupo de desativados;
  - as confirmações com o aviso de que o app dono pode recriar o item, com o botão "Abrir no Desinstalador" que leva ao módulo Aplicativos.

  Rodar. Esperado: PASS. Commit `feat(app): itens de início e em segundo plano` e push.

### Task 16: Capturas do Time Machine, ação e conclusão, textos

**Files:** Create `App/Performance/SnapshotsView.swift`, `PerformanceActionView.swift`; Modify `App/Resources/Strings.tsv`; Test `AppTests/SmokeTests.swift`

- [ ] **Step 1:** Estender `allAppsStringsLocalized` para `App/Performance` (chaves `perf.*`). Rodar. Esperado: FAIL.
- [ ] **Step 2:** Implementar:
  - as capturas, com lista, seleção e **Apagar**, e confirmação;
  - as telas de progresso e de conclusão (o que rodou, o que falhou e por quê, o registro);
  - os textos em pt-BR e en.

  Rodar. Esperado: PASS. Commit `feat(app): capturas do Time Machine, conclusão e textos do Desempenho` e push.

### Task 17: Ajudante v3 e permissões

**Files:** Modify `App/Permissions/HelperManager.swift` e as telas de Resultados; Test `AppTests/PermissionsFlowTests.swift`

- [ ] **Step 1:** Testes:
  - `helperV2AsksUpdate`: `state(for: .enabled, version: 2) == .outdated`;
  - `performanceRequirements`: as tarefas com root e os itens de sistema, sem o ajudante, exigem `.admin`.

  Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS.
- [ ] **Step 2:** Commit `feat(app): permissões do Desempenho e helper v3` e push.

---

## Fase D — Paridade, revisão, teste real e release

### Task 18: Paridade

**Files:** Create `scripts/parity/compare_perf.py`, `scripts/parity/test_compare_perf.py`, `docs/re/parity/perf-report-2026-10-22.md`, `perf-known-divergences.json`

- [ ] **Step 1:** Testes:
  - `exactTaskLists`: aplicáveis e recomendadas;
  - `exactStartupItems`: listas, com repetidos comparados como listas;
  - `knownDivergencesAreNotes`.

  Rodar. Esperado: FAIL. Implementar. Rodar. Esperado: PASS.
- [ ] **Step 2:** Rodar a análise nova do CleanMyMac e a nossa, em sequência e pelo app instalado (`open --env`), quando a análise precisar de Acesso Total ao Disco. Corrigir pela spec. Escrever o relatório. Commit `test(parity): paridade do módulo Desempenho` e push.

### Task 19: Revisão final (subagente no modelo mais capaz)

- [ ] **Step 1:** Rodar o pacote de revisão desde o commit do design e despachar o revisor com este Review Focus. Ele precisa conferir em especial:
  - as operações novas do ajudante, com atenção a comandos fixos, links e `com.apple.*`;
  - as tarefas que rodam como root.
- [ ] **Step 2:** Corrigir os Critical e Important com TDD (vermelho → verde, suíte inteira verde). Os Minor vão para o ledger. Commit e push.

### Task 20: Teste real controlado (com o usuário)

- [ ] **Step 1:** Release instalado em `/Applications`. Pedir o ok e conduzir pela Acessibilidade, como na v0.2:
  - **Tarefas:** rodar cada tarefa aplicável. Avisar antes de Reindexar o Spotlight e Liberar Espaço Purgável. Conferir o efeito de cada uma (ex.: o cache do DNS esvaziado, `mdutil -s /` indexando, o espaço livre antes e depois).
  - **Itens:**
    - criar um agente de teste `io.github.guigx7.cymtest.agent` (carregado) e um item de sessão de teste;
    - Desativar, conferindo `launchctl print-disabled` e o processo parado;
    - Reativar, conferindo que voltou;
    - Remover, conferindo que o plist foi para o Lixo e o agente foi descarregado.
  - **Botões:** testar todos os Revisar, os Ajustes com o guia, Voltar, Recomeçar e Abrir Registro.
- [ ] **Step 2:** Corrigir o que aparecer, com teste. Limpar os itens de teste. Registrar no ledger.

### Task 21: Documentação e release v0.3.0

- [ ] **Step 1:** Atualizar o README: módulo Desempenho, permissões e o roadmap. Versão `0.3.0` (build 4) em `project.yml`, `CleanYourMacCore.version` e no teste de versão. Rodar as duas suítes. Commits `docs: README da v0.3` e `chore: versão 0.3.0`, com push.
- [ ] **Step 2:** **Perguntar ao usuário** antes de publicar. Com o ok: build Release, zip, SHA-256, tag `v0.3.0`, `gh release create` com as notas, conferir o asset baixado e reinstalar em `/Applications`.
