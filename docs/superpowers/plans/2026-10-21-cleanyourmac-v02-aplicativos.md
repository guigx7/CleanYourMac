# CleanYourMac v0.2 — Módulo Aplicativos: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Módulo Aplicativos (Desinstalador com Redefinir, Atualizador etapa 1, Sobras) com análise igual à do CleanMyMac 5.7.2 nesta máquina, dentro das regras de segurança do design.

**Architecture:** Mesma divisão da v1. Primeiro a RE clean room produz specs em `docs/re/specs/apps/`, e o código é escrito a partir delas. O `Core` ganha a pasta `Apps/`, com o catálogo de apps, os arquivos relacionados, as sobras, os instaladores e as fontes de atualização. A remoção reaproveita `CleanEngine`, `PathPolicy` e o helper, com três grupos novos em `GroupID` e três operações privilegiadas novas. O app ganha `App/Applications/`, com uma máquina de estados própria e telas que reaproveitam `Theme`, `GlassCard`, `ModuleArtwork` e os padrões de `ReviewView`.

**Tech Stack:** Swift 6.4, SwiftUI, macOS 14+, Swift Testing, XcodeGen, String Catalog gerado por `scripts/gen-strings.py`, REA + Ghidra para a RE, Python 3 para a paridade.

**Spec:** `docs/superpowers/specs/2026-10-21-cleanyourmac-v02-aplicativos-design.md` (e, para o que ele herda, `docs/superpowers/specs/2026-10-20-cleanyourmac-v1-limpeza-design.md`)

## Global Constraints

- macOS 14+, Swift 6 strict concurrency, sem dependências externas. Bundle id `io.github.guigx7.CleanYourMac`; helper `io.github.guigx7.CleanYourMac.helper`.
- **Testes só simulação.** No CleanMyMac roda-se só a análise. Nunca se clica em Desinstalar, Remover, Atualizar ou Redefinir, e o `re-notes/dump-ax` recusa esses cliques. Nossa remoção só roda contra árvores falsas e **apps de teste criados por nós** em pasta temporária, ou em `dryRun`. Debug continua com `CYM_DRY_RUN` ligado por padrão.
- O teste real controlado (Task 24) usa só apps de teste instalados de propósito e só acontece com o usuário presente.
- Notas brutas de RE ficam em `re-notes/`, que está no `.gitignore`. Ao repo vão só as specs, escritas com nossas palavras. **Não decifrar `Resources/info.cmmkb`.**
- Caminhos e regras podem coincidir com o CleanMyMac, desde que cada regra cite evidência na spec. Textos, ícones e arte são nossos. Nada do servidor da MacPaw nem de APIs privadas da Apple.
- **Destino:** Desinstalar, Redefinir e Sobras movem para o **Lixo**. Instaladores são **apagados na hora**.
- **Helper:** ganha só `trash`, `launchdBootout` e `forgetPackage`. Valem as travas atuais: revalidação como root, nunca `com.apple.*`, nunca recibos da Apple, nunca através de links.
- **Segurança antes de paridade.** Os arquivos relacionados de cada app são um subconjunto dos do CleanMyMac. Tolerância de 1% ou 1 MB para arquivos que mudam. Listas de apps, sobras, instaladores e contagens de filtros têm paridade exata.
- **Atualizador, etapa 1:** só mostra e abre. Nunca baixa nem instala. Fontes: `SUFeedURL`, `itunes.apple.com/lookup?bundleId=`, `formulae.brew.sh/api/cask.json` (comparado localmente) e atualizações do macOS. Rede só durante a análise do módulo.
- Sem filtro Suspeitos. O próprio CleanYourMac aparece na lista, mas não pode ser desinstalado. Apps da Apple protegidos só podem ser redefinidos.
- pt-BR e en em `App/Resources/Strings.tsv`, gerado com `python3 -I scripts/gen-strings.py`.
- Cada task termina com commit (Conventional Commits, em pt-BR) e `git push origin main`. Commits intermediários onde indicado.
- Comandos de teste: Core com `swift test --package-path Core`; app com `scripts/test-app.sh`.

## Review Focus

1. **Nome de app parecido com o de outro app** (ex.: "Code" × "Visual Studio Code", "Zoom" × "ZoomIt"): os arquivos relacionados e as sobras não podem pegar arquivos do outro app. Teste `sharedPrefixNameNotRelated` na Task 6 e `installedSiblingIsNotLeftover` na Task 8.
2. **App aberto no momento de desinstalar ou redefinir:** nada é movido enquanto ele roda. O usuário fecha o app (ou confirma forçar), ou o item falha com "in use". Testes `runningAppBlocksRemoval` na Task 12 e `quitPromptBeforeUninstall` na Task 19.
3. **Feed de atualização malformado, lento ou fora do ar,** ou versões que não dá para comparar (`1.2b3`, `2026.10.14.08.27.stable_02`, build sem versão curta): o item é pulado, a checagem termina com tempo-limite e o resto do módulo funciona. Testes `malformedAppcastIgnored`, `timeoutDoesNotBlock` e `incomparableVersionsSkipped` nas Tasks 9 e 10.
4. **Itens em outro volume ou de outro dono** (app num disco externo, app de root em `/Applications`): mover para o Lixo usa o Lixo certo, e o que exige root vai para o helper sem pedir senha duas vezes. Testes `trashOnExternalVolumeUsesVolumeTrash` e `rootOwnedAppGoesToHelperTrash` na Task 12.
5. **App ou arquivo relacionado acessado por symlink** (ex.: `~/Applications/X.app -> /Volumes/...`, contêiner com link): a análise não soma o destino e a remoção só move o link. Teste `symlinkedRelatedFileNotFollowed` na Task 6.

---

## Estrutura de arquivos

```
Core/Sources/CleanYourMacCore/
├── Model/GroupID.swift, CategoryID.swift, RemovalAction.swift        # grupos .appUninstall/.appLeftovers/.appInstallers
├── Apps/
│   ├── AppRecord.swift            # metadados de um app instalado
│   ├── AppCatalog.swift           # inventário com loja, fornecedor, uso, proteção, 32 bits, plug-ins
│   ├── UsageDates.swift           # última abertura (Spotlight) — protocolo + implementação
│   ├── RelatedFiles.swift         # arquivos de um app por ResourceKind
│   ├── UninstallerScanner.swift   # AppRecord → JunkItem (desinstalar e redefinir)
│   ├── LeftoversScanner.swift
│   ├── InstallersScanner.swift
│   ├── RunningApps.swift          # quais apps estão abertos; fechar
│   ├── AppsReport.swift           # resultado agregado do módulo + AppsScan (orquestra)
│   └── Updates/
│       ├── Version.swift          # comparação de versões
│       ├── HTTPFetcher.swift      # protocolo + URLSession com tempo-limite
│       ├── AppcastParser.swift
│       ├── UpdateSources.swift    # Sparkle, App Store, Homebrew, macOS
│       └── UpdateChecker.swift
├── Cleaning/CleanEngine.swift, PrivilegedRunner.swift                 # novos cases
├── Helper/HelperExecutor.swift, HelperProtocol.swift                  # novas operações, versão 2
└── Registry.swift                                                     # appsScanners()
Core/Sources/cym/main.swift                                            # subcomando `apps`
Core/Tests/CleanYourMacCoreTests/Apps/*.swift + Fixtures/AppFixture.swift
App/Applications/
├── AppsFlowModel.swift            # Intro → Análise → Resultados ⇄ Gerenciador → Ação → Concluído
├── AppsModuleView.swift, AppsIntroView.swift, AppsScanningView.swift, AppsResultsView.swift, AppsTiles.swift
├── AppsManagerView.swift          # barra lateral com 3 seções + rodapé
├── UninstallerView.swift, UninstallerFilters.swift, AppDetailView.swift
├── UpdaterView.swift, LeftoversView.swift
└── AppsActionView.swift           # fechar apps, progresso, concluído, registro
AppTests/AppsFlowModelTests.swift, UninstallerFiltersTests.swift
docs/re/specs/apps/*.md, docs/re/parity/apps-baseline-2026-10-21.json, apps-report-*.md
scripts/re/collect-apps-baseline.sh, scripts/parity/apps_ax_to_baseline.py, scripts/parity/compare_apps.py
scripts/make-test-app.sh            # apps de teste assinados ad-hoc para os testes de remoção
```

## Interfaces centrais (referência para todas as tasks)

As Tasks 4 a 13 definem estas interfaces, e as tasks seguintes as consomem sem mudar as assinaturas. Uma task pode acrescentar um campo se a spec justificar, e registra isso no ledger.

```swift
// GroupID: novos cases .appUninstall, .appLeftovers, .appInstallers; category == .applications
// CategoryID: novo case .applications; `static let cleanupCases: [CategoryID]` = os 4 da Limpeza

public enum AppStore: String, Codable, Sendable { case appStore, setapp, steam, battleNet, other }
public enum AppVendor: String, Codable, Sendable { case apple, google, jetBrains, macPaw, microsoft, adobe, other }
public enum AppKind: String, Codable, Sendable { case application, audioPlugin }

public struct AppRecord: Identifiable, Hashable, Sendable {
    public let id: String                 // bundleID + "|" + caminho
    public let url: URL
    public let bundleID: String
    public let name: String               // nome exibido (com ".app" como no CleanMyMac, se a spec mandar)
    public let version: String?           // CFBundleShortVersionString
    public let build: String?             // CFBundleVersion
    public let teamID: String?
    public let store: AppStore
    public let vendor: AppVendor
    public let kind: AppKind
    public let lastOpened: Date?
    public let lastUpdated: Date?
    public let isProtected: Bool          // app da Apple protegido: só redefinir
    public let isSelf: Bool               // o próprio CleanYourMac
    public let is32Bit: Bool
    public let bundleSize: Int64
    public let feedURL: URL?              // SUFeedURL
}

public enum ResourceKind: String, CaseIterable, Codable, Sendable {
    case binaries, preferences, supportingFiles, container, caches, logs, crashes,
         loginItems, plugins, dockIcon, help, userData, installers, other
}
public struct RelatedFile: Hashable, Sendable {
    public let url: URL
    public let kind: ResourceKind
    public let size: Int64
    public let isSelected: Bool           // marcado por padrão (regra da spec)
    public let removal: RemovalAction
}

public protocol UsageDates: Sendable { func lastOpened(_ app: URL) -> Date? }
public protocol RunningApps: Sendable {
    func running(bundleIDs: Set<String>) -> [RunningApp]
    func quit(_ app: RunningApp, force: Bool) async -> Bool
}
public struct RunningApp: Hashable, Sendable { public let bundleID: String; public let name: String; public let pid: pid_t }

public struct AppCatalog: Sendable {
    public init(folders: [String] = AppCatalog.defaultFolders, usage: any UsageDates = SpotlightUsageDates())
    public func apps(_ context: ScanContext) -> [AppRecord]
}
public struct RelatedFilesFinder: Sendable {
    public init()
    public func files(for app: AppRecord, installed: [AppRecord], context: ScanContext) -> [RelatedFile]
}
public struct UninstallerScanner: ScopedScanner {   // group = .appUninstall
    public init(catalog: AppCatalog, finder: RelatedFilesFinder = RelatedFilesFinder())
    /// Um JunkItem por app: removal = .moveToTrash(app) (nil se protegido ou próprio app),
    /// filhos = um JunkItem por ResourceKind com os RelatedFile como folhas. id = "appUninstall:<AppRecord.id>".
    public static func resetItem(from appItem: JunkItem) -> JunkItem   // mesmo app sem a folha do bundle
}
public struct LeftoversScanner: ScopedScanner { public init(catalog: AppCatalog) }   // group = .appLeftovers
public struct InstallersScanner: ScopedScanner { public init() }                     // group = .appInstallers

public enum UpdateSourceKind: String, Codable, Sendable { case sparkle, appStore, homebrew, macOS }
public enum UpdateAction: Hashable, Sendable {
    case openAppStore(URL), openSoftwareUpdate, openApp(URL), copyCommand(String, vendor: URL?)
}
public struct AppUpdate: Identifiable, Hashable, Sendable {
    public let id: String                 // bundleID ou "macOS:<produto>"
    public let appID: String?             // AppRecord.id
    public let name: String
    public let source: UpdateSourceKind
    public let installedVersion: String
    public let availableVersion: String
    public let releaseDate: Date?
    public let size: Int64?
    public let notes: String?             // texto puro (HTML removido)
    public let action: UpdateAction
    public let downloadURL: URL?          // para a etapa 2 (não usado na v0.2)
    public let expectedTeamID: String?    // idem
}
public protocol HTTPFetcher: Sendable { func get(_ url: URL, timeout: Duration) async throws -> Data }
public protocol UpdateSource: Sendable {
    var kind: UpdateSourceKind { get }
    func updates(for apps: [AppRecord], fetcher: any HTTPFetcher) async -> [AppUpdate]
}
public struct UpdateChecker: Sendable {
    public init(sources: [any UpdateSource], fetcher: any HTTPFetcher = URLSessionFetcher())
    public func check(_ apps: [AppRecord]) async -> UpdateCheckResult  // updates + offline: Bool
}

public struct AppsReport: Sendable {
    public let apps: [AppRecord]
    public let uninstaller: [JunkItem]    // um por app
    public let leftovers: [JunkItem]
    public let installers: [JunkItem]
    public let updates: UpdateCheckResult
}
public final class AppsScan: Sendable {
    public init(catalog: AppCatalog, uninstaller: UninstallerScanner, leftovers: LeftoversScanner,
                installers: InstallersScanner, updates: UpdateChecker)
    public func run(_ context: ScanContext) -> AsyncThrowingStream<AppsScanEvent, Error>
}
public enum AppsScanEvent: Sendable { case progress(phase: AppsScanPhase, path: String), finished(AppsReport) }
public enum AppsScanPhase: String, Sendable { case apps, related, leftovers, installers, updates }

// Remoção
// RemovalAction: + .unloadAndTrash(plist: URL, domain: LaunchdDomain), + .forgetReceipt(String)
// PrivilegedCommand: + .trash(URL, uid: uid_t), + .launchdBootout(plist: URL, domain: String), + .forgetPackage(String)
// HelperConstants.version = 2
```

---

## Fase A — Ferramentas e engenharia reversa

**Procedimento de RE (vale para as Tasks 2 e 3):** é o mesmo da v1.
- Fontes, nesta ordem: observação da análise (AX e `fs_usage`); textos e símbolos em `re-notes/static/<Framework>`; REA e Ghidra nas funções que decidem as regras.
- Frameworks-alvo: `ApplicationsModule`, `ApplicationsModuleDomain`, `ApplicationsService`, `UninstallerScanning`, `UpdaterScanning`, `AppInfoNetworkService`, `SparkleUpdaterService`, `MASUpdaterService`, `ApplicationsTerminator`, `UnusedDiskImagesScanning`, `PrivilegedRoutines`.
- Cada spec segue `docs/re/specs/_TEMPLATE.md` e cita as evidências como E1, E2… Pseudocódigo nunca entra no repo.
- Um subagente por spec, trabalhando só a partir da evidência.

### Task 1: Baseline do CleanMyMac e app de teste

**Files:**
- Create: `scripts/re/collect-apps-baseline.sh`, `scripts/parity/apps_ax_to_baseline.py`, `scripts/parity/test_apps_ax_to_baseline.py`, `scripts/make-test-app.sh`, `docs/re/parity/apps-baseline-2026-10-21.json`

- [ ] **Step 1:** Escrever `collect-apps-baseline.sh`.
  - Pré-condição: o CleanMyMac está no Gerenciador de Aplicativos depois de uma análise.
  - Despeja cada seção (Desinstalador, Atualizador, Sobras) e cada filtro do Desinstalador.
  - Para cada app, clica em "Mostre os itens incluídos" e despeja a tela.
  - Para cada grupo das Sobras, despeja a tela.
  - Saída: `re-notes/ax/apps-baseline-<data>/`.
  - Usa só `--press` em elementos de navegação. A lista de palavras proibidas do `dump-ax` já cobre desinstalar, remover, atualizar, instalar e redefinir.
- [ ] **Step 2:** Escrever `test_apps_ax_to_baseline.py` usando os dumps já salvos em `re-notes/ax/apps-manager2-*.txt` como fixture, recortados num arquivo de teste em `scripts/parity/fixtures/`, só com nomes e tamanhos. Asserções:
  - 26 apps;
  - `Bruno.app` com `lastOpened` `2026-08-20` e `size` 525000000;
  - contagens dos filtros: `unused` 1, `appStore` 3, `setapp` 1, `other` 22, `apple` 2, `google` 1, `macPaw` 2, `microsoft` 1, `vendorsOther` 20, `audioPlugins` 1.

  Rodar `python3 -I -m pytest scripts/parity/test_apps_ax_to_baseline.py`. Esperado: FAIL, porque o módulo ainda não existe.
- [ ] **Step 3:** Implementar `apps_ax_to_baseline.py <pasta> <saída.json>`. Formato:
  - `{"apps": [{name, lastOpened, size, related: {kind: [{name, size}]}}], "filters": {...}, "updates": [{name, source, installed, available}], "leftovers": {"leftoverFiles": [...], "installers": [...]}}`.
  - Reaproveitar `to_bytes` de `ax_to_baseline.py`.

  Rodar o teste. Esperado: PASS.
- [ ] **Step 4:** Rodar a coleta: análise do CleanMyMac, depois `collect-apps-baseline.sh`, depois o conversor para `docs/re/parity/apps-baseline-2026-10-21.json`. O JSON só tem nomes de apps e tamanhos desta máquina, sem dado do CleanMyMac.
- [ ] **Step 5:** Escrever `scripts/make-test-app.sh <pasta> <nome> <bundleID> [--feed URL] [--version V] [--agent]`.
  - Cria um `.app` mínimo: executável `clang`, `Info.plist` com `SUFeedURL` opcional e assinatura `codesign -s -`.
  - Com `--agent`, também gera um plist do launchd que aponta para ele.
  - Usado pelos testes de remoção e pela Task 24.
- [ ] **Step 6:** Commit `chore(re): baseline do módulo Aplicativos e gerador de app de teste` e push.

### Task 2: Specs — inventário, filtros, arquivos relacionados e redefinir

**Files:**
- Create: `docs/re/specs/apps/inventory.md`, `docs/re/specs/apps/related-files.md`, `docs/re/specs/apps/reset.md`

- [ ] **Step 1:** `inventory.md` precisa responder:
  - quais pastas entram na lista (só `/Applications`? `~/Applications`, Setapp, Steam, `/System/Applications`?);
  - o que fica fora (apps dentro de outros apps, helpers, apps da Apple não removíveis);
  - nome exibido;
  - de onde vem a "última abertura" (`kMDItemLastUsedDate`?) e a "última atualização";
  - como o tamanho total soma app e relacionados;
  - regra de cada loja (recibo `_MASReceipt`, caminho do Setapp, Steam, Battle.net);
  - regra de cada fornecedor (prefixo do bundle ID? Team ID?);
  - "Não usados": mais de 6 meses desde quando, e como trata apps nunca abertos;
  - 32 bits;
  - Plug-ins de Áudio: pastas e formatos;
  - o que é "protegido";
  - ordenações.
- [ ] **Step 2:** `related-files.md` precisa responder, por `ResourceKind`:
  - pastas e critério de vínculo (bundle ID exato, prefixo com ponto, grupo de app, Team ID, nome);
  - o que vem marcado;
  - o que nunca entra.

  Precisa também documentar, comparando com a baseline, onde o CleanMyMac acha mais que o critério forte, porque essas diferenças entram em "Divergências conhecidas". Incluir os itens do launchd e os recibos de pacote (`pkgutil --pkgs` e `--files`).
- [ ] **Step 3:** `reset.md` precisa responder:
  - o que redefinir remove;
  - o que fica marcado;
  - como trata apps da Apple protegidos;
  - quais tipos disparam a confirmação extra do design (Dados do Usuário, Contêiner).
- [ ] **Step 4:** Um commit por spec (`docs(re): spec de <tema> (apps)`) com push.

### Task 3: Specs — sobras, instaladores, atualizador, remoção e resultados

**Files:**
- Create: `docs/re/specs/apps/leftovers.md`, `installers.md`, `updater.md`, `removal.md`, `results-screen.md`

- [ ] **Step 1:** `leftovers.md`: onde procura, como decide que o dono não existe mais, exclusões (apps da Apple, apps em volumes desmontados, arquivos compartilhados) e agrupamento. Checar contra os 49,2 KB da baseline.
- [ ] **Step 2:** `installers.md`: pastas, extensões (dmg, pkg, mpkg, zip de app?), regra de "não usado" (DMG montado? app já instalado? idade?) e o que fica marcado. Checar contra o DMG do Warp, de 187 MB.
- [ ] **Step 3:** `updater.md`: o comportamento observado do CleanMyMac e o **nosso** desenho a partir das fontes públicas do design.
  - Como lê o appcast: Sparkle 1 e 2, `sparkle:minimumSystemVersion`, canais, itens delta, `sparkle:version` × `shortVersionString`.
  - Regra de comparação de versões.
  - Como casa o cask com o app: artefato `app` mais o caminho no Caskroom; `auto_updates` fica fora.
  - Busca da App Store: campos `version`, `currentVersionReleaseDate`, `releaseNotes`, `fileSizeBytes` e `trackViewUrl`.
  - Atualizações do macOS: como listar sem root nem demora excessiva.
  - O que cada botão abre.
  - Checar contra o GarageBand 10.4.13 → 10.4.14.
- [ ] **Step 4:** `removal.md`: como o CleanMyMac remove (Lixo ou definitivo, o que pede admin, como descarrega o launchd, se esquece recibos, como fecha apps abertos), mais as **nossas** regras:
  - Lixo para Desinstalar, Redefinir e Sobras;
  - Instaladores apagados na hora;
  - as 3 operações do helper e suas travas.
- [ ] **Step 5:** `results-screen.md`: quais cartões aparecem, com que condição, em que ordem e com quais botões (vistos e encontrados no binário), e o estado sem nenhum app.
- [ ] **Step 6:** Um commit por spec (`docs(re): spec de <tema> (apps)`) com push.

---

## Fase B — Core

### Task 4: Grupos, categoria e AppRecord

**Files:**
- Modify: `Core/Sources/CleanYourMacCore/Model/GroupID.swift`, `Model/CategoryID.swift`, `App/Cleanup/IntroView.swift:19`, `App/Cleanup/ReviewView.swift:114`, `App/Cleanup/CleanupFlowModel.swift:150`, `App/Cleanup/ReviewLogic.swift`
- Create: `Core/Sources/CleanYourMacCore/Apps/AppRecord.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/AppModelTests.swift`

**Interfaces:** Produces `GroupID.appUninstall/.appLeftovers/.appInstallers`, `CategoryID.applications`, `CategoryID.cleanupCases`, `AppRecord`, `AppStore`, `AppVendor`, `AppKind`, `ResourceKind`, `RelatedFile`.

- [ ] **Step 1:** Escrever os testes:
  - `appGroupsBelongToApplications`: os 3 grupos têm `category == .applications`, e `requiresAdmin`/`requiresAdminToScan` são `false`;
  - `cleanupCasesExcludeApplications`: `CategoryID.cleanupCases == [.systemJunk, .aiClutter, .mailAttachments, .trashBins]`;
  - `resourceKindOrder`: `ResourceKind.allCases` segue a ordem de `related-files.md`.
- [ ] **Step 2:** Rodar `swift test --package-path Core --filter AppModelTests`. Esperado: FAIL, de compilação.
- [ ] **Step 3:** Implementar. No app, trocar os três `CategoryID.allCases` da Limpeza por `CategoryID.cleanupCases`, e em `ReviewLogic` ignorar grupos de `.applications`.
- [ ] **Step 4:** Rodar o Core inteiro e depois `scripts/test-app.sh`. Esperado: PASS (225 + novos no Core, 52 no app).
- [ ] **Step 5:** Commit `feat(core): grupos e modelos do módulo Aplicativos` e push.

### Task 5: AppCatalog (inventário, lojas, fornecedores, uso)

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/AppCatalog.swift`, `Apps/UsageDates.swift`, `Core/Tests/CleanYourMacCoreTests/Fixtures/AppFixture.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/AppCatalogTests.swift`

**Interfaces:**
- Consumes: `ScanContext.resolve`, `FileSizer`, `MachOFile`.
- Produces:
  - `AppCatalog`, `UsageDates`, `SpotlightUsageDates`;
  - `AppFixture.makeApp(in: URL, name: String, bundleID: String, version: String? = nil, teamID: String? = nil, masReceipt: Bool = false, feed: URL? = nil, archs: [String] = ["arm64"]) throws -> URL` para os testes.

- [ ] **Step 1:** Escrever os testes. Cada um monta a fixture com `FixtureTree` mais `AppFixture` e usa um `UsageDates` falso:
  - `listsAppsFromSpecFolders`;
  - `skipsNestedApps`;
  - `storeFromReceiptAndPath`: `_MASReceipt` dá `appStore`, `Applications/Setapp/X.app` dá `setapp`, e há os casos de Steam e Battle.net da spec;
  - `vendorRules`: um caso por fornecedor, com os valores da spec;
  - `unusedAfterSixMonths`: `now - lastOpened` > limite da spec dá não usado, e o caso "nunca aberto" segue a spec;
  - `protectedAppleApps`;
  - `marksSelf`: bundle ID `io.github.guigx7.CleanYourMac` dá `isSelf`;
  - `detects32Bit`: um Mach-O só `i386` montado à mão no cabeçalho;
  - `audioPluginsListed`: `.component`, `.vst` e `.vst3` nas pastas da spec dão `kind == .audioPlugin`;
  - `symlinkedAppNotFollowed`.
- [ ] **Step 2:** Rodar `--filter AppCatalogTests`. Esperado: FAIL.
- [ ] **Step 3:** Implementar. `SpotlightUsageDates` usa `MDItemCreateWithURL` + `kMDItemLastUsedDate`, ou o que a spec indicar. `FolderAppInventory` continua existindo para a Limpeza.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): catálogo de apps` e push.

### Task 6: RelatedFilesFinder

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/RelatedFiles.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/RelatedFilesTests.swift`

**Interfaces:** Consumes `AppRecord`. Produces `RelatedFilesFinder.files(for:installed:context:) -> [RelatedFile]`, sempre com `removal = .moveToTrash(url)`, exceto launchd, que usa `.unloadAndTrash`, e recibos, que usam `.forgetReceipt`. Os dois cases nascem na Task 12; até lá esses tipos ficam fora, e esta task deixa um teste `pending` marcado com `.disabled("Task 12")`.

- [ ] **Step 1:** Escrever os testes. App `com.example.Foo` e fixture com um arquivo por pasta de `related-files.md`:
  - `findsEachKind`: um arquivo por `ResourceKind`, no kind certo, com o tamanho alocado;
  - `defaultSelection`: segue a spec;
  - `sharedPrefixNameNotRelated`:
    - instalados "Code" (`com.example.code`) e "Visual Studio Code" (`com.microsoft.VSCode`);
    - `~/Library/Application Support/Code` pertence ao app que a spec disser, mas nunca aos dois ao mesmo tempo;
    - `~/Library/Caches/com.example.codeHelper`, sem ponto depois do ID, não pertence a `com.example.code`;
  - `groupContainerByTeam`: `~/Library/Group Containers/<TEAM>.foo` só entra com o Team ID igual;
  - `neverAppleOrOtherApps`: nada de `com.apple.*` nem de outro bundle instalado;
  - `symlinkedRelatedFileNotFollowed`: o tamanho é o do link, e o destino não é somado.
- [ ] **Step 2:** Rodar `--filter RelatedFilesTests`. Esperado: FAIL.
- [ ] **Step 3:** Implementar, com as regras como dados (tabela de pastas por kind) no próprio arquivo, citando a spec.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): arquivos relacionados a um app` e push.

### Task 7: UninstallerScanner e item de redefinir

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/UninstallerScanner.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/UninstallerScannerTests.swift`

**Interfaces:** Consumes `AppCatalog`, `RelatedFilesFinder`. Produces `UninstallerScanner` (com `removalScope` = pastas dos apps mais as pastas de `related-files.md`) e `UninstallerScanner.resetItem(from:)`.

- [ ] **Step 1:** Escrever os testes:
  - `oneItemPerApp`: o filho 0 é o bundle (`ResourceKind.binaries` ou o que a spec definir), seguido de um filho por kind não vazio, e `totalSize` é igual a bundle + relacionados;
  - `protectedAppHasNoBundleRemoval`: um app protegido não tem a folha do bundle;
  - `selfCannotBeUninstalled`: o próprio app também não tem a folha do bundle, mas pode ser redefinido;
  - `resetDropsBundleLeaf`: `resetItem` mantém só os relacionados e tem `id` `appReset:<AppRecord.id>`;
  - `resetNeedsExtraConfirmation`: `UninstallerScanner.needsResetConfirmation(_ item: JunkItem) -> Bool` é verdadeiro se houver folhas selecionadas de `userData` ou `container`;
  - `policyAcceptsOnlyScopedPaths`: `PathPolicy` do scope recusa `~/Documents/x`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar. O `ResourceKind` de cada filho fica em `JunkItem.detail` (`rawValue`), e a UI traduz.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): desinstalador e redefinir` e push.

### Task 8: Sobras e Instaladores

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/LeftoversScanner.swift`, `Apps/InstallersScanner.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/LeftoversTests.swift`, `InstallersTests.swift`

**Interfaces:** Produces `LeftoversScanner` (folhas `.moveToTrash`) e `InstallersScanner` (folhas `.delete`), ambos `ScopedScanner`.

- [ ] **Step 1:** Escrever os testes:
  - `leftoverOfRemovedApp`: `~/Library/Preferences/com.gone.App.plist` sem app instalado vira item, agrupado como a spec manda;
  - `installedSiblingIsNotLeftover`: `com.example.code.helper` com `com.example.code` instalado fica fora;
  - `appleAndSharedExcluded`: segue as exclusões da spec;
  - `unmountedVolumeAppNotLeftover`: segue a regra da spec;
  - `installerFound`: `~/Downloads/Foo.dmg` com o critério de "não usado" da spec;
  - `installerExclusions`: segue a spec, por exemplo DMG montado;
  - `installersDeleteImmediately`: a remoção é `.delete`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): sobras e instaladores` e push.

### Task 9: Versões e appcast

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/Updates/Version.swift`, `Updates/AppcastParser.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/VersionTests.swift`, `AppcastParserTests.swift`

**Interfaces:**
- `Version.compare(_ a: String, _ b: String) -> ComparisonResult?`. Devolve `nil` quando a comparação não for confiável.
- `AppcastParser.parse(_ data: Data) throws -> [AppcastItem]`.
- `AppcastItem`: `version`, `shortVersion`, `minimumSystemVersion`, `date`, `notes`, `notesURL`, `downloadURL`, `length`, `channel`, `isDelta`.
- `AppcastParser.best(_ items: [AppcastItem], systemVersion: OperatingSystemVersion) -> AppcastItem?`.

- [ ] **Step 1:** Escrever os testes:
  - `numericOrder`: `"10.4.14" > "10.4.13"`, `"1.10" > "1.9"`, `"2.0" == "2.0.0"`;
  - `incomparableVersionsSkipped`: `compare("1.2b3", "1.2")` e o par com `"2026.10.14.08.27.stable_02"` seguem a regra de `updater.md`, e o que a spec chamar de não confiável retorna `nil`;
  - `parsesSparkle2Appcast`: fixture XML escrita por nós, com 3 itens, um delta, um de canal beta e um com `minimumSystemVersion` 99.0;
  - `bestSkipsDeltaBetaAndTooNew`;
  - `malformedAppcastIgnored`: XML truncado faz o parser lançar erro, e `best` de `[]` é `nil`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar o parser com `XMLParser`. As novidades são convertidas de HTML para texto puro.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): versões e appcast` e push.

### Task 10: Fontes de atualização e UpdateChecker

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/Updates/HTTPFetcher.swift`, `Updates/UpdateSources.swift`, `Updates/UpdateChecker.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/UpdateSourcesTests.swift`

**Interfaces:**
- Produces: `HTTPFetcher`, `URLSessionFetcher` (sem cookies, com `User-Agent` `CleanYourMac/<versão>`), `SparkleSource`, `AppStoreSource`, `HomebrewSource(caskroom: String = "/opt/homebrew/Caskroom")`, `MacOSUpdateSource`, `UpdateChecker`, `UpdateCheckResult { updates: [AppUpdate]; offline: Bool }`.
- Tempo-limite padrão de 10 s por requisição e 60 s para a checagem toda.
- Fetcher falso nos testes: `[URL: Result<Data, Error>]` e atraso opcional.

- [ ] **Step 1:** Escrever os testes. As respostas são fixtures JSON e XML escritas por nós:
  - `sparkleUpdateFound`: app 1.0 com `SUFeedURL` e appcast com 1.2 dá `AppUpdate` com `source == .sparkle` e `action == .openApp(app.url)`;
  - `appStoreLookup`:
    - para um app com recibo, a URL pedida é `https://itunes.apple.com/lookup?bundleId=<id>` e mais nada;
    - a resposta com a versão 10.4.14 dá a ação `.openAppStore(trackViewUrl)`;
  - `homebrewOnlyForCaskroomApps`: o catálogo tem os casks `foo` e `bar`, e só `foo` está no Caskroom falso. Só `foo` gera item, e a ação é `.copyCommand("brew upgrade --cask foo", vendor:)`;
  - `homebrewSkipsAutoUpdates`;
  - `homebrewCatalogNotSentApps`: nenhuma URL pedida contém bundle IDs;
  - `macOSUpdateOpensSettings`: `CommandRunner` falso com a saída de `softwareupdate --list` dá `.openSoftwareUpdate`;
  - `offlineFlag`: todas as requisições falham, e o resultado é `offline == true` com `updates == []`;
  - `timeoutDoesNotBlock`: uma fonte com atraso maior que o limite deixa a checagem terminar dentro de limite + 1 s, com as outras fontes presentes;
  - `oneUpdatePerApp`: quando duas fontes concordam, entra a de prioridade maior, na ordem de `updater.md`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar. Cada fonte é independente e roda em paralelo num `TaskGroup` com tempo-limite.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): fontes públicas de atualização` e push.

### Task 11: Helper — trash, launchdBootout e forgetPackage

**Files:**
- Modify: `Core/Sources/CleanYourMacCore/Cleaning/PrivilegedRunner.swift`, `Helper/HelperExecutor.swift`, `Helper/HelperProtocol.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/HelperExecutorTests.swift`, `PrivilegedScriptTests.swift`

**Interfaces:**
- Produces `PrivilegedCommand.trash(URL, uid: uid_t)`, `.launchdBootout(plist: URL, domain: String)` e `.forgetPackage(String)`, com `HelperConstants.version = 2`.
- `HelperExecutor` ganha `commands: any CommandRunner` (injetável) e `trashRoot: (uid_t) -> URL?`. Em produção, `trashRoot` devolve a home do uid + `.Trash`, e nos testes devolve uma pasta da fixture.

- [ ] **Step 1:** Escrever os testes:
  - `trashMovesIntoUserTrashWithUniqueName`: dois itens com o mesmo nome levam ao segundo com sufixo, e o dono passa a ser o uid pedido;
  - `trashRefusesOutsidePrefixesAndVital`;
  - `bootoutOnlyLaunchdFolders`:
    - aceito: plist em `/Library/LaunchDaemons` ou `/Library/LaunchAgents`, com nome que não começa com `com.apple.` e domínio `system` ou `gui/<uid>`;
    - recusado: qualquer outro, inclusive por symlink;
    - o `CommandRunner` falso recebe `["bootout", "system", <plist>]`;
  - `forgetPackageRefusesApple`: `com.apple.pkg.X` é recusado; `com.example.pkg` gera `pkgutil --forget com.example.pkg`; um id com `/`, espaço ou `;` é recusado (o id precisa casar com `^[A-Za-z0-9._-]+$`);
  - `appleScriptRunnerSupportsNewCommands`: o script gerado tem `mv` para o Lixo, `launchctl bootout` e `pkgutil --forget`, com os argumentos entre aspas, e os casos com aspas e `$` da v1 continuam passando.
- [ ] **Step 2:** Rodar `--filter HelperExecutorTests` e `--filter PrivilegedScriptTests`. Esperado: FAIL.
- [ ] **Step 3:** Implementar no `HelperExecutor` e no `AppleScriptPrivilegedRunner`. O helper responde `refused` para versões de cliente diferentes de 2. O app, ao ver um helper com versão 1, pede para reinstalar o ajudante (Task 21).
- [ ] **Step 4:** Rodar o Core inteiro. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(helper): mover para o Lixo, descarregar launchd e esquecer recibo` e push.

### Task 12: CleanEngine — Lixo, launchd, recibos e apps abertos

**Files:**
- Modify: `Core/Sources/CleanYourMacCore/Model/RemovalAction.swift`, `Cleaning/CleanEngine.swift`, `Apps/RelatedFiles.swift` (remover o `.disabled`)
- Create: `Core/Sources/CleanYourMacCore/Apps/RunningApps.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/AppsRemovalTests.swift`

**Interfaces:**
- Produces:
  - `RemovalAction.unloadAndTrash(plist: URL, domain: LaunchdDomain)`, com `LaunchdDomain` = `.system | .user`;
  - `RemovalAction.forgetReceipt(String)`;
  - `RunningApps`, `RunningApp`, `WorkspaceRunningApps` (AppKit `NSRunningApplication`);
  - o `CleanEngine.init` ganha `runningApps: any RunningApps = WorkspaceRunningApps()` e `bundleIDOf: @Sendable (JunkItem) -> String?`. O padrão lê o `AppRecord.id` do prefixo do `id`.
- Regras:
  - `.moveToTrash` sem permissão vai para o lote como `.trash(url, uid: getuid())`;
  - `.unloadAndTrash` roda `launchctl bootout` (no domínio `user`, sem root) e depois manda para o Lixo, e no domínio `system` vira `[.launchdBootout, .trash]`;
  - `.forgetReceipt` sempre usa o lote privilegiado.

- [ ] **Step 1:** Escrever os testes, com fixtures e apps de teste:
  - `uninstallMovesAppAndFilesToTrash`: o app de teste de `AppFixture` e os relacionados vão para `FileManager.trashItem`, e na fixture usa-se `ScanContext.home/.Trash` por injeção. Os originais somem e as cópias ficam no Lixo;
  - `runningAppBlocksRemoval`: com um `RunningApps` falso dizendo que o app está aberto, todas as folhas do item falham com `"in use"` e nada sai do lugar;
  - `trashOnExternalVolumeUsesVolumeTrash`: monta um DMG temporário (`hdiutil create -size 20m` + `attach -nobrowse`), cria um app de teste nele, desinstala e confere `/Volumes/<x>/.Trashes/<uid>`. No fim, desmonta;
  - `rootOwnedAppGoesToHelperTrash`: o `removeUnprivileged` falso lança `EACCES`, e o `PrivilegedRunner` falso recebe `.trash(url, uid:)` uma única vez no lote;
  - `launchdUserAgentUnloadedThenTrashed`: o `CommandRunner` falso recebe `bootout gui/<uid> <plist>` antes do Lixo;
  - `receiptForgottenViaBatch`;
  - `dryRunTouchesNothing`;
  - `installersDeletedNotTrashed`.
- [ ] **Step 2:** Rodar `--filter AppsRemovalTests`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar o Core inteiro. Esperado: PASS, com todos os testes da v1 verdes.
- [ ] **Step 5:** Commit `feat(core): remoção de apps (Lixo, launchd, recibos, apps abertos)` e push.

### Task 13: AppsScan, Registry e CLI

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Apps/AppsReport.swift`
- Modify: `Core/Sources/CleanYourMacCore/Registry.swift`, `Core/Sources/cym/main.swift`
- Test: `Core/Tests/CleanYourMacCoreTests/Apps/AppsScanTests.swift`

**Interfaces:**
- Produces:
  - `AppsScan`, `AppsReport`, `AppsScanEvent`, `AppsScanPhase`;
  - `Registry.appsScan(fetcher: any HTTPFetcher = URLSessionFetcher()) -> AppsScan`;
  - `Registry.appsPolicies(context:) -> [GroupID: PathPolicy]`;
  - `cym apps [--json] [--no-network]`, com saída no formato de `apps-baseline` (Task 1).
- `UpdateChecker` roda em paralelo com sobras e instaladores, e as fases são emitidas em ordem.

- [ ] **Step 1:** Escrever os testes:
  - `reportHasAllSections`;
  - `cancelStopsQuickly`: cancelar dentro de 200 ms termina o stream com `CancellationError`, sem `finished`;
  - `noNetworkStillReports`: com o fetcher falhando, `updates.offline == true` e o resto do relatório é preenchido;
  - `cliJsonMatchesBaselineShape`: as chaves de `cym apps --json` são iguais às de `apps-baseline-2026-10-21.json`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar. Esperado: PASS. Depois rodar `swift run --package-path Core cym apps --no-network | head`, que deve mostrar os 26 apps desta máquina.
- [ ] **Step 5:** Commit `feat(core): análise do módulo Aplicativos e cym apps` e push.

---

## Fase C — App

Todas as telas seguem o visual da Limpeza: gradiente próprio do módulo em `Theme.gradient(for: .applications)`, `GlassCard` e animações em Core Animation para a arte. Textos novos vão para `Strings.tsv` (pt-BR e en), escritos por nós.

### Task 14: AppsFlowModel e navegação

**Files:**
- Create: `App/Applications/AppsFlowModel.swift`, `App/Applications/AppsModuleView.swift`
- Modify: `App/Navigation/AppModule.swift` (`isAvailable` passa a valer para `.cleanup` e `.applications`), `App/Navigation/RootView.swift`, `App/Design/Theme.swift`, `project.yml` (se precisar de novas pastas)
- Test: `AppTests/AppsFlowModelTests.swift`

**Interfaces:**
- Produces `AppsFlowModel`, com:
  - `Phase`: `.intro, .scanning, .results, .manager(Section), .confirmQuit([RunningApp]), .acting, .done(CleanReport), .nothingFound`;
  - `Section`: `.uninstaller, .updater, .leftovers`;
  - `func start()`, `func stop()`, `func openManager(_ s: Section, filter: UninstallerFilter? = nil)`, `func act(on items: [JunkItem], mode: ActionMode)`, `func restart()`;
  - `ActionMode`: `.uninstall, .reset, .removeLeftovers`;
  - `let selection = SelectionModel()`, reaproveitado.
- `RootView` mostra o gerenciador de Aplicativos em tela cheia, como faz com o `ReviewView`.

- [ ] **Step 1:** Escrever os testes, com `AppsScan` falso e `Cleaning` falso:
  - `scanThenResults`;
  - `emptyReportShowsNothingFound`;
  - `stopReturnsToIntro`;
  - `actWithRunningAppAsksToQuit`;
  - `resetWithUserDataNeedsConfirmation`;
  - `doneKeepsFailures`;
  - `switchingModuleKeepsCleanupState`: a Limpeza não é zerada ao ir para Aplicativos e voltar.
- [ ] **Step 2:** Rodar `scripts/test-app.sh`. Esperado: FAIL.
- [ ] **Step 3:** Implementar. Chamar `AppsEnvironment.makeModel()` como faz `CleanupEnvironment`, com `CYM_DRY_RUN` e `CYM_DEMO` respeitados.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(app): fluxo do módulo Aplicativos` e push.

### Task 15: Intro, Análise e Resultados

**Files:**
- Create: `App/Applications/AppsIntroView.swift`, `AppsScanningView.swift`, `AppsResultsView.swift`, `AppsTiles.swift`
- Modify: `App/Design/ModuleArtwork.swift` (variante de arte do módulo: nova, própria), `App/Resources/Strings.tsv`
- Test: `AppTests/AppsTilesTests.swift`

**Interfaces:** Produces `AppsTile.Kind` (os cartões de `results-screen.md`, na ordem dela) e `AppsTile.tiles(for: AppsReport, now: Date) -> [AppsTile]`.

- [ ] **Step 1:** Escrever os testes. `tilesFollowSpec`: para cada condição de `results-screen.md`, o cartão aparece com os botões certos, e `nothingFoundHasNoTiles`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar as telas.
  - Intro: arte, título, subtítulo e as 3 categorias.
  - Análise: fase atual, caminho e contador de apps.
  - Resultados: "N apps encontrados", **Gerenciar Aplicativos** e cartões.
  - Snapshot com `CYM_SNAPSHOT` (via `scratchpad/shot.sh`) para conferir.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS. Conferir os snapshots em pt-BR e en.
- [ ] **Step 5:** Commit `feat(app): intro, análise e resultados de Aplicativos` e push.

### Task 16: Gerenciador — Desinstalador com filtros

**Files:**
- Create: `App/Applications/AppsManagerView.swift`, `UninstallerView.swift`, `UninstallerFilters.swift`, `AppsDemoData.swift`
- Test: `AppTests/UninstallerFiltersTests.swift`

**Interfaces:**
- `UninstallerFilter`: `.all, .unused, .selected, .store(AppStore), .vendor(AppVendor), .audioPlugins`.
- `UninstallerFilters.counts(apps: [AppRecord], selection: Set<String>, now: Date) -> [UninstallerFilter: Int]`.
- `UninstallerFilters.apply(_ f: UninstallerFilter, ...) -> [AppRecord]`.
- `UninstallerSort`: `.name, .size, .lastOpened, .lastUpdated`.
- Os filtros de loja e fornecedor só aparecem com contagem maior que 0, se a spec confirmar esse comportamento.

- [ ] **Step 1:** Escrever os testes:
  - `countsMatchBaselineShape`: com os 26 apps de `AppsDemoData`, criados nesta task a partir dos nomes e metadados da baseline, as contagens são `.unused` 1, `.store(.appStore)` 3, `.store(.setapp)` 1, `.store(.other)` 22, `.vendor(.apple)` 2, `.vendor(.google)` 1, `.vendor(.macPaw)` 2, `.vendor(.microsoft)` 1, `.vendor(.other)` 20 e `.audioPlugins` 1;
  - `selectedFilterFollowsSelection`;
  - `sortByLastOpenedPutsNeverOpenedPerSpec`;
  - `searchMatchesNameCaseInsensitive`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar a tela.
  - Barra lateral com Desinstalador, Atualizador e Sobras.
  - Lista de filtros com contagens.
  - Linhas: checkbox, ícone, nome, última abertura, tamanho e botão para os itens incluídos.
  - Busca, menu Ordenar e rodapé "N selecionado(s) | tamanho" com **Desinstalar**.
  - Um app protegido mostra a explicação em vez do checkbox de desinstalar, e o próprio app também.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS. Conferir o snapshot.
- [ ] **Step 5:** Commit `feat(app): desinstalador com filtros` e push.

### Task 17: Detalhe do app e Redefinir

**Files:**
- Create: `App/Applications/AppDetailView.swift`
- Modify: `App/Applications/UninstallerView.swift`
- Test: `AppTests/AppsFlowModelTests.swift` (casos novos)

- [ ] **Step 1:** Escrever os testes:
  - `detailTogglesPropagate`: marcar um kind marca as folhas, e desmarcar uma folha deixa o kind misto (reaproveita `SelectionModel`);
  - `resetUsesResetItem`: escolher "Redefinir" no menu do app chama `act(on: [resetItem], mode: .reset)`;
  - `resetConfirmationListsKinds`: a confirmação extra lista os kinds `userData` e `container`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar o painel de itens incluídos: kinds com tamanho, folhas com caminho abreviado e "Mostrar no Finder". Adicionar a ação Redefinir e a confirmação extra.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(app): itens incluídos e redefinir` e push.

### Task 18: Atualizador e Sobras

**Files:**
- Create: `App/Applications/UpdaterView.swift`, `LeftoversView.swift`
- Test: `AppTests/AppsFlowModelTests.swift` (casos novos)

**Interfaces:** Produces `AppsFlowModel.perform(_ action: UpdateAction)`, que usa `NSWorkspace.open` para URLs e Ajustes (`x-apple.systempreferences:com.apple.Software-Update-Settings.extension`) e `NSPasteboard` para `copyCommand`.

- [ ] **Step 1:** Escrever os testes, com um `URLOpener` falso:
  - `updateActionOpensRightPlace`: um caso por `UpdateAction`;
  - `offlineShowsNotice`;
  - `leftoversRemoveButtonDisabledWithoutSelection`.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar as duas telas.
  - **Atualizador:** lista com nome, versão instalada e fonte, mais o painel de detalhe (fonte, versão atual → nova, data, tamanho e novidades). O botão **Atualizar** abre o lugar certo, e não há seleção múltipla. Isso desvia do CleanMyMac porque a v0.2 não instala nada. O menu Selecionar fica para a etapa 2. Registrar a ruling.
  - **Sobras:** grupos Arquivos de Sobras e Instaladores com tamanhos, lista com checkbox e rodapé com **Remover**.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(app): atualizador e sobras` e push.

### Task 19: Ação — fechar apps, progresso, concluído e registro

**Files:**
- Create: `App/Applications/AppsActionView.swift`
- Test: `AppTests/AppsFlowModelTests.swift` (casos novos)

- [ ] **Step 1:** Escrever os testes:
  - `quitPromptBeforeUninstall`:
    - em `.confirmQuit`, "Fechar e continuar" chama `RunningApps.quit(force: false)` e depois `act`;
    - se o app não fechar em 10 s, oferece "Forçar", que só age com confirmação;
    - "Cancelar" volta ao gerenciador sem tocar em nada;
  - `progressThenDone`;
  - `partialFailureShowsLog`: falha com o motivo traduzido, reaproveitando `FailureText` da Limpeza.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar as telas de fechar apps, de progresso (item atual e total) e de concluído. O concluído diz que os itens foram para o Lixo, com botão "Abrir Lixo", e mostra o registro.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(app): desinstalar, redefinir e remover sobras` e push.

### Task 20: Localização, arte e DemoData

**Files:**
- Modify: `App/Resources/Strings.tsv`, `App/Applications/AppsDemoData.swift` (relatório completo para `CYM_DEMO`), `App/Design/ModuleArtwork.swift`

- [ ] **Step 1:** Escrever o teste `allAppsStringsLocalized` em `AppTests/SmokeTests.swift`: cada chave `apps.*` usada no código existe em pt-BR e en no `Localizable.xcstrings` gerado. Rodar. Esperado: FAIL, se faltar alguma.
- [ ] **Step 2:** Completar `Strings.tsv`, rodar `python3 -I scripts/gen-strings.py` e finalizar a arte do módulo. A CPU em repouso tem de ficar perto de 0%, como na Limpeza.
- [ ] **Step 3:** Rodar `scripts/test-app.sh`. Esperado: PASS. Snapshots em pt-BR e en com `CYM_DEMO`.
- [ ] **Step 4:** Commit `feat(app): textos e arte do módulo Aplicativos` e push.

### Task 21: Permissões e versão do helper

**Files:**
- Modify: `App/Permissions/HelperManager.swift`, `App/Permissions/PermissionsView.swift`, `App/Applications/AppsModuleView.swift`
- Test: `AppTests/PermissionsFlowTests.swift` (casos novos)

- [ ] **Step 1:** Escrever os testes:
  - `oldHelperAsksReinstall`: um ping com `version == 1` mostra "Atualizar ajudante", que faz unregister + register via `SMAppService`, e o usuário aprova em Ajustes;
  - `appManagementNeededForAppsInApplications`: desinstalar um app de `/Applications` sem a permissão Gerenciamento de Apps mostra o guia, como na Limpeza.
- [ ] **Step 2:** Rodar. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(app): permissões do módulo Aplicativos e helper v2` e push.

---

## Fase D — Paridade, teste real e release

### Task 22: Comparação de paridade

**Files:**
- Create: `scripts/parity/compare_apps.py`, `scripts/parity/test_compare_apps.py`, `docs/re/parity/apps-report-2026-10-21.md`

- [ ] **Step 1:** Escrever os testes:
  - `exactListsMustMatch`: apps, sobras, instaladores e filtros;
  - `relatedIsSubset`: ter item a mais é falha, e ter item a menos é "divergência documentada" se estiver na spec;
  - `toleranceOnePercentOrOneMB`.
- [ ] **Step 2:** Rodar `python3 -I -m pytest scripts/parity/test_compare_apps.py`. Esperado: FAIL.
- [ ] **Step 3:** Implementar `compare_apps.py <baseline.json> <cym.json>`.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS. Depois:
  - nova análise do CleanMyMac e `collect-apps-baseline.sh`;
  - logo em seguida, `cym apps --json`;
  - `compare_apps.py`.

  Corrigir as diferenças pela spec. Escrever `apps-report-2026-10-21.md` com o resultado e as divergências explicadas, como no relatório da v1.
- [ ] **Step 5:** Commit `test(parity): paridade do módulo Aplicativos` e push.

### Task 23: Revisão final (subagente opus)

- [ ] **Step 1:** Rodar `review-package` do skill de execução, de `fe8b7d5` até `HEAD`, e despachar o revisor no modelo mais capaz, com o Review Focus deste plano. Ele precisa conferir em especial:
  - as travas das 3 operações novas do helper;
  - a regra de vínculo forte.
- [ ] **Step 2:** Corrigir os Critical e Important com TDD, cada um RED → GREEN com a suíte inteira verde. Os Minor vão para o ledger.
- [ ] **Step 3:** Commit `fix: revisão final do módulo Aplicativos` e push.

### Task 24: Teste real controlado (com o usuário)

- [ ] **Step 1:** Com o build Release, criar com `scripts/make-test-app.sh`:
  - `/Applications/CYM Teste.app`, com `--agent`, preferências, cache e um DMG `~/Downloads/cym-teste.dmg`;
  - um app de teste aberto, para testar o pedido de fechar.

  **Avisar o usuário e esperar o ok antes de cada etapa.**
- [ ] **Step 2:** Rodar a análise. Desinstalar `CYM Teste.app`. Redefinir um segundo app de teste. Remover o DMG.
- [ ] **Step 3:** Conferir:
  - tudo do app de teste está no Lixo;
  - o agente está descarregado (`launchctl print` não acha o job);
  - o DMG foi apagado;
  - os registros mostram `dryRun: false`;
  - nenhum outro arquivo mudou (`fs_usage` do app durante a ação, só caminhos dos apps de teste).
- [ ] **Step 4:** Esvaziar o Lixo só se o usuário pedir.

### Task 25: Documentação e release v0.2.0

**Files:**
- Modify: `README.md` (seção Aplicativos, roadmap, permissões, Lixo), `project.yml` (`MARKETING_VERSION: 0.2.0`, `CURRENT_PROJECT_VERSION: 3`)

- [ ] **Step 1:** Atualizar o README e a versão. Rodar as duas suítes. Esperado: PASS.
- [ ] **Step 2:** Commit `docs: README da v0.2` e `chore: versão 0.2.0`, com push.
- [ ] **Step 3:** **Perguntar ao usuário** antes de publicar. Com o ok:
  - build Release, zip e SHA-256;
  - tag `v0.2.0` e `gh release create`;
  - notas da release, incluindo que o Atualizador não instala nada ainda;
  - reinstalar em `/Applications`.
