# CleanYourMac v1 — Módulo Limpeza: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App macOS nativo e open source com o módulo Limpeza (Detritos do Sistema, Acúmulos de IA, Anexos do Mail, Lixos) com comportamento de análise igual ao CleanMyMac 5.7.2.

**Architecture:** Duas fases. Primeiro a engenharia reversa (clean room) produz uma especificação por grupo em `docs/re/specs/`. Depois o código é escrito a partir dessas especificações. O código fica em um pacote Swift `Core` (modelos, scanners, motor de análise, motor de limpeza, política de caminhos e um CLI `cym` para paridade) e em um app SwiftUI (`App/`) gerado com XcodeGen, que consome o `Core`.

**Tech Stack:** Swift 6.x, SwiftUI, macOS 14+, Swift Testing (`import Testing`), XcodeGen, String Catalog (`.xcstrings`), REA (`rea-agents`, MCP) + Ghidra + JDK para a RE, Python 3 (só para os scripts de paridade).

**Spec:** `docs/superpowers/specs/2026-10-20-cleanyourmac-v1-limpeza-design.md`

## Global Constraints

- macOS 14+ como deployment target. Swift 6 com strict concurrency. Sem dependências externas no `Core` nem no app.
- App fora do sandbox, Hardened Runtime ligado, assinatura de desenvolvimento local. Bundle id: `io.github.guigx7.CleanYourMac`.
- Interface em **pt-BR e en**, com todos os textos no String Catalog. Nenhum texto descritivo, ícone, imagem ou animação copiado do CleanMyMac. Nomes funcionais de categorias podem coincidir.
- **Durante o desenvolvimento nada é limpo de verdade nesta máquina.** A remoção só roda contra árvores falsas em diretório temporário, contra cópias de apps ou em `dryRun`. Do CleanMyMac roda-se apenas a **análise**, nunca o botão Limpar.
- Notas brutas de RE (saídas do REA/Ghidra, pseudocódigo, logs do `fs_usage`) ficam em `re-notes/`, que está no `.gitignore`. Ao repo vão só as especificações escritas com nossas palavras.
- Os caminhos e as regras são fatos técnicos: podem coincidir com o CleanMyMac, desde que cada regra cite evidência na spec do grupo.
- O motor de limpeza recusa qualquer caminho fora das raízes permitidas do grupo (ver Task 9).
- Senha de administrador: no máximo uma vez por análise (só se houver grupos com `requiresAdmin`) e uma vez por limpeza. Sem helper permanente.
- Versão de referência: CleanMyMac 5.7.2 (Setapp) em `/Applications/Setapp/CleanMyMac.app`.
- Licença: MIT (decisão do construtor).
- **Commits pequenos e frequentes**: cada task termina com commit + `git push origin main`. Tasks longas fazem commits intermediários onde indicado. As mensagens seguem Conventional Commits (`feat:`, `docs:`, `test:`, `chore:`).

## Review Focus

1. **Symlink que aponta para fora da raiz** (ex.: `~/Library/Caches/x -> /Users/guigx/Documents`): a análise não deve segui-lo nem somar o destino, e a limpeza apaga só o link. Testes nas Tasks 9 e 10.
2. **Arquivo que some ou não pode ser lido durante a análise** (permissão negada, apagado no meio): o item ou subárvore é pulado, sem erro fatal e sem travar a análise. Testes nas Tasks 8 e 10.
3. **Usuário cancela o pedido de senha de admin**: os itens que precisavam de admin aparecem como falha com o motivo "cancelado"; os demais são limpos normalmente. Teste na Task 12.
4. **Caminhos com espaço, aspas, `$`, acentos ou emoji** no script privilegiado: não pode haver injeção nem caminho errado. Teste na Task 12.
5. **Cancelar a análise no meio** (botão Parar): o stream termina rápido, sem resultados parciais exibidos como finais. Testes nas Tasks 11 e 22.

---

## Estrutura de arquivos

```
CleanYourMac/
├── README.md, LICENSE, .gitignore
├── project.yml                         # XcodeGen
├── Core/
│   ├── Package.swift                   # libs: CleanYourMacCore; exec: cym
│   ├── Sources/CleanYourMacCore/
│   │   ├── Model/        CategoryID.swift, GroupID.swift, JunkItem.swift, RemovalAction.swift
│   │   ├── FileSystem/   FileSizer.swift, PathPolicy.swift, ScanContext.swift
│   │   ├── Scanning/     GroupScanner.swift, ScanEngine.swift, ScanReport.swift
│   │   ├── Rules/        PathRule.swift, RuleBasedScanner.swift, Resources/rules/<group>.json
│   │   ├── Scanners/     um arquivo por scanner especializado
│   │   ├── Cleaning/     CleanEngine.swift, PrivilegedRunner.swift, CleanupLog.swift
│   │   └── Registry.swift                # todos os scanners de produção
│   ├── Sources/cym/main.swift
│   └── Tests/CleanYourMacCoreTests/      # um arquivo por unidade + Fixtures/FixtureTree.swift
├── App/
│   ├── CleanYourMacApp.swift, Info.plist, CleanYourMac.entitlements
│   ├── Resources/Localizable.xcstrings, Assets.xcassets
│   ├── Design/       Theme.swift, GlassCard.swift, ModuleArtwork.swift, AnimatedNumber.swift
│   ├── Navigation/   RootView.swift, SidebarView.swift, AppModule.swift
│   ├── Cleanup/      CleanupFlowModel.swift, SelectionModel.swift, IntroView.swift,
│   │                 ScanningView.swift, ResultsView.swift, ReviewView.swift,
│   │                 CleaningView.swift, DoneView.swift, ResultCards.swift
│   └── Permissions/  PermissionsService.swift, PermissionsView.swift
├── AppTests/         CleanupFlowModelTests.swift, SelectionModelTests.swift
├── scripts/re/       capture-scan.sh, extract-strings.sh
├── scripts/parity/   compare.py, baseline-template.json
└── docs/re/          README.md, specs/_TEMPLATE.md, specs/<grupo>.md, parity/
```

## Interfaces centrais (referência para todas as tasks)

Definidas nas Tasks 8–12; as tasks seguintes as consomem sem mudar as assinaturas.

```swift
public enum CategoryID: String, CaseIterable, Codable, Sendable { case systemJunk, aiClutter, mailAttachments, trashBins }

public enum GroupID: String, CaseIterable, Codable, Sendable {
    case userCache, systemCache, userLogs, systemLogs, universalBinaries, languageFiles,
         brokenLoginItems, brokenPreferences, documentVersions, deletedUsers, iosBackups, xcodeJunk, // systemJunk
         aiAgentsJunk, localModels,                                                                  // aiClutter
         mailAttachments,                                                                            // mailAttachments
         trash, mailTrash                                                                            // trashBins
    public var category: CategoryID { get }
    public var requiresAdmin: Bool { get }          // limpeza precisa de root (spec do grupo)
    public var requiresAdminToScan: Bool { get }    // análise precisa de root (spec do grupo)
}

public struct JunkItem: Identifiable, Hashable, Sendable {
    public let id: String                  // "<group>:<caminho ou chave estável>"
    public let group: GroupID
    public let name: String                // nome exibido
    public let detail: String?             // ex.: "Caches", "Registros" (kinds de IA), versão do modelo
    public let url: URL?
    public let size: Int64                 // bytes alocados
    public let isRecommended: Bool
    public let badge: ItemBadge?           // .latest (backups iOS)
    public let icon: IconSource            // .file(URL) | .app(URL) | .symbol(String)
    public let removal: RemovalAction?     // nil quando o item só agrupa filhos
    public let children: [JunkItem]
}

public enum RemovalAction: Hashable, Sendable {
    case delete(URL)                                   // apagar definitivamente
    case moveToTrash(URL)
    case deleteContents(of: URL)                       // esvaziar pasta, mantendo a pasta
    case thinBinary(executable: URL, keepArch: String, bundle: URL)
    case removeLocalizations(bundle: URL, lprojs: [URL])
    case removeLoginItem(URL)                          // plist do LaunchAgent/LoginItem quebrado
    case deleteDocumentVersions(volume: URL, fileID: String)
}
// Uma task de scanner pode adicionar um case novo, desde que a spec do grupo justifique,
// e deve implementar o case no CleanEngine (Task 12) na mesma task.

public struct ScanContext: Sendable {
    public var root: URL                   // "/" em produção; diretório temporário nos testes
    public var home: URL                   // root + Users/<user>
    public var userName: String
    public var preferredLanguages: [String]
    public var now: Date
    public func resolve(_ template: String) -> URL   // expande "~", "$ROOT"
}

public protocol GroupScanner: Sendable {
    var group: GroupID { get }
    func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem]
}
public struct ScanProgress: Sendable { public let group: GroupID; public let currentPath: String; public let bytesFound: Int64 }

public enum ScanEvent: Sendable { case progress(ScanProgress), groupFinished(GroupResult), finished(ScanReport) }
public struct GroupResult: Sendable { public let group: GroupID; public let items: [JunkItem]; public var totalSize: Int64 { get } }
public struct ScanReport: Sendable {
    public let groups: [GroupID: GroupResult]
    public var totalSize: Int64 { get }
    public func totalSize(of category: CategoryID) -> Int64
    public func recommendedItems() -> [JunkItem]
}
public final class ScanEngine: Sendable {
    public init(scanners: [any GroupScanner])
    public func scan(_ groups: Set<GroupID>, context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error>
}

public struct PathPolicy: Sendable {
    public init(allowedRoots: [URL])
    public func validate(_ url: URL) throws(PathPolicyError) -> URL   // retorna o caminho padronizado
}
public enum PathPolicyError: Error, Equatable { case outsideAllowedRoots(String), isAllowedRootItself(String), symlinkEscape(String) }

public enum CleanEvent: Sendable { case started(JunkItem), finished(JunkItem, Result<Int64, CleanFailure>), completed(CleanReport) }
public struct CleanFailure: Error, Hashable, Sendable { public let reason: String }
public struct CleanReport: Codable, Sendable { public let freedBytes: Int64; public let removed: [String]; public let failed: [String: String] }
public final class CleanEngine: Sendable {
    public init(policies: [GroupID: PathPolicy], privileged: any PrivilegedRunner, dryRun: Bool, log: CleanupLog)
    public func clean(_ items: [JunkItem]) -> AsyncStream<CleanEvent>
}
public protocol PrivilegedRunner: Sendable { func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] }
public enum PrivilegedError: Error { case userCancelled, failed(String) }
```

---

## Fase A — Fundação e ferramentas

### Task 1: Esqueleto do repositório

**Files:**
- Create: `README.md`, `LICENSE` (MIT, "guigx7"), `Core/Package.swift`, `Core/Sources/CleanYourMacCore/CleanYourMacCore.swift`, `Core/Sources/cym/main.swift`, `Core/Tests/CleanYourMacCoreTests/SmokeTests.swift`, `project.yml`, `App/CleanYourMacApp.swift`, `App/Info.plist`, `App/CleanYourMac.entitlements`, `AppTests/SmokeTests.swift`
- Modify: `.gitignore` (adicionar `*.xcodeproj/`, porque o projeto é gerado pelo XcodeGen)

**Interfaces:**
- Produces: pacote `Core` com o produto library `CleanYourMacCore` (platforms `.macOS(.v14)`, swift-tools 6.0) e o executável `cym`; target de app `CleanYourMac` e target de testes `CleanYourMacTests` no `project.yml`, dependendo do pacote local `Core`.

- [ ] **Step 1:** `brew install xcodegen`. Verificação: `xcodegen --version` imprime a versão.
- [ ] **Step 2:** Escrever o teste `SmokeTests.coreVersion`: `#expect(CleanYourMacCore.version == "0.1.0")`.
- [ ] **Step 3:** Rodar `swift test --package-path Core`. Esperado: FAIL (símbolo inexistente).
- [ ] **Step 4:** Criar `public enum CleanYourMacCore { public static let version = "0.1.0" }`, mais o `Package.swift` e o `cym` imprimindo a versão.
- [ ] **Step 5:** Rodar `swift test --package-path Core`. Esperado: PASS.
- [ ] **Step 6:** No `project.yml`: app macOS 14, bundle id `io.github.guigx7.CleanYourMac`, `ENABLE_HARDENED_RUNTIME = YES`, entitlements sem sandbox (`com.apple.security.app-sandbox` ausente), `developmentLanguage: en`, `knownRegions: [en, pt-BR]`, e o target de testes `CleanYourMacTests` (`AppTests/`). O `CleanYourMacApp` mostra uma janela com "CleanYourMac".
- [ ] **Step 7:** Rodar `xcodegen generate && xcodebuild -scheme CleanYourMac -destination 'platform=macOS' build test`. Esperado: `** TEST SUCCEEDED **`.
- [ ] **Step 8:** No README, colocar uma descrição curta, o aviso de projeto de estudo independente sem vínculo com a MacPaw e como compilar.
- [ ] **Step 9:** Commit `chore: esqueleto do Core, CLI e app` e push.

### Task 2: Ferramental de engenharia reversa

**Files:**
- Create: `scripts/re/capture-scan.sh`, `scripts/re/extract-strings.sh`, `docs/re/README.md`, `docs/re/specs/_TEMPLATE.md`

**Interfaces:**
- Produces: `scripts/re/capture-scan.sh <rótulo>`, que grava em `re-notes/fs/<rótulo>-<timestamp>.log` os acessos do processo do CleanMyMac (e do helper/agent dele) via `sudo fs_usage -w -f filesys` filtrado pelos PIDs `com.macpaw.CleanMyMac-setapp*`. Para com Ctrl+C.
- Produces: `scripts/re/extract-strings.sh <Framework>`, que grava em `re-notes/static/<Framework>/` três arquivos: `strings.txt`, `symbols.txt` (`nm -gU` + `swift demangle`) e `localizable-<lang>.json`.
- Produces: o template de spec com estas seções obrigatórias: **Versão de referência**, **Locais varridos**, **Inclusão**, **Exclusão**, **Recomendado**, **Agrupamento e nome exibido**, **Cálculo de tamanho**, **Remoção** (definitiva/Lixo/conteúdo, precisa de admin, o que faz se o app estiver aberto), **Alertas/selos**, **requiresAdmin (análise)**, **Evidências** (cada afirmação acima referencia E1, E2…) e **Divergências conhecidas**.

- [ ] **Step 1:** Instalar o ferramental: `brew install --cask temurin ghidra`, depois `npm i -g rea-agents` e registrar o MCP no Claude Code conforme o README do REA (https://github.com/morluto/rea) apontando para o Ghidra. Verificação: `claude mcp list` mostra o REA como `✔ Connected`. Se o REA não conectar, registrar o motivo em `docs/re/README.md` e seguir só com Ghidra headless (`analyzeHeadless`) mais os scripts.
- [ ] **Step 2:** Escrever os dois scripts (ambos com `set -euo pipefail` e criando `re-notes/` se faltar).
- [ ] **Step 3:** Rodar `scripts/re/extract-strings.sh SystemJunkScanning`. Esperado: os três arquivos são criados e não ficam vazios. Rodar `git status` e confirmar que nada de `re-notes/` aparece.
- [ ] **Step 4:** Em `docs/re/README.md`, descrever o processo clean room (evidência → spec com nossas palavras → código só a partir da spec), as regras do que pode e do que não pode entrar no repo e como usar os scripts.
- [ ] **Step 5:** Commit `chore(re): scripts e template de especificação` e push.

---

## Fase B — Especificações de engenharia reversa

Em todas as tasks desta fase, o procedimento por grupo é o mesmo:

1. Rodar `extract-strings.sh` nos frameworks indicados.
2. Rodar `capture-scan.sh <grupo>` enquanto se executa **só a análise** do CleanMyMac (Limpeza → Analisar). Depois abrir o Gerenciador de Limpeza e anotar em `re-notes/` os itens, os tamanhos e o que vem marcado.
3. Usar o REA/Ghidra nos binários indicados para responder o que a observação não mostra: recomendado, exclusões, limites de idade e tamanho, e a forma de remoção.
4. Escrever `docs/re/specs/<grupo>.md` a partir do template, com nossas palavras e com cada regra apontando para uma evidência.
5. Registrar a baseline da análise do CleanMyMac em `docs/re/parity/baseline-2026-10-20.json` (formato definido na Task 3).

Critério de conclusão de cada spec: todas as seções do template preenchidas ou marcadas como "não se aplica" com justificativa, e nenhum pseudocódigo colado.

### Task 3: Spec — caches e registros (userCache, systemCache, userLogs, systemLogs) + formato de baseline

**Files:**
- Create: `docs/re/specs/user-cache.md`, `system-cache.md`, `user-logs.md`, `system-logs.md`, `docs/re/specs/common.md`, `scripts/parity/baseline-template.json`, `docs/re/parity/baseline-2026-10-20.json`
- Binários-alvo: `SystemJunkScanning`, `ScanningCore`, `LegacyScanningCore`, `KnowledgeBaseService`, `NodesCore`

**Interfaces:**
- Produces: `common.md`, com as regras transversais: unidade de tamanho (alocado vs. lógico, hard links), formatação exibida (decimal/binária, ex.: "4,5 GB"), e se as regras vêm do servidor (`KnowledgeBaseService`) e o que acontece offline.
- Produces: o formato da baseline: `{ "cmmVersion": "5.7.2", "capturedAt": ISO8601, "groups": { "<GroupID.rawValue>": { "totalBytes": Int, "items": [{ "name": String, "bytes": Int, "recommended": Bool }] } } }`.

- [ ] **Step 1:** Seguir o procedimento da Fase B para os 4 grupos e para `common.md`.
- [ ] **Step 2:** Commit `docs(re): spec de caches e registros` e push.

### Task 4: Spec — Binários Universais e Arquivos de Idioma

**Files:**
- Create: `docs/re/specs/universal-binaries.md`, `language-files.md`
- Binários-alvo: `SystemJunkScanning`, `CleaningCore`, `PrivilegedRoutines`, `PrivilegedOperationsPerformerService`

- [ ] **Step 1:** Seguir o procedimento da Fase B. As specs devem responder:
  - quais apps são pulados (Apple, App Store, assinados, em uso);
  - qual arquitetura é mantida;
  - quais idiomas são preservados (os idiomas preferidos do usuário? `Base.lproj`? `en`?);
  - se a assinatura é refeita e como;
  - se é preciso a permissão de Gerenciamento de Apps.
- [ ] **Step 2:** Commit `docs(re): spec de binários universais e idiomas` e push.

### Task 5: Spec — Itens de Início/Preferências Defeituosos, Versões de Documentos, Usuários Apagados, Backups iOS, Xcode

**Files:**
- Create: `docs/re/specs/broken-login-items.md`, `broken-preferences.md`, `document-versions.md`, `deleted-users.md`, `ios-backups.md`, `xcode-junk.md`
- Binários-alvo: `SystemJunkScanning`, `CleaningCore`, `PrivilegedRoutines`

- [ ] **Step 1:** Seguir o procedimento da Fase B para os 6 grupos, um commit por grupo (`docs(re): spec de <grupo>`) com push. Para grupos vazios nesta máquina, a evidência vem da análise estática, e a seção "Divergências conhecidas" registra que não houve observação real.

### Task 6: Spec — Acúmulos de IA

**Files:**
- Create: `docs/re/specs/ai-agents-junk.md`, `local-models.md`
- Binários-alvo: `AIToolScanning`, `LocalModelScanning`

- [ ] **Step 1:** Seguir o procedimento da Fase B. As specs devem cobrir:
  - a lista de ferramentas reconhecidas e, para cada uma, os caminhos por kind (caches, registros, temporários, versões defasadas);
  - como se define "versão defasada";
  - como os modelos do Ollama e do LM Studio são enumerados e dimensionados (blobs compartilhados entre modelos!);
  - o texto e o momento do alerta.
- [ ] **Step 2:** Commit `docs(re): spec de acúmulos de IA` e push.

### Task 7: Spec — Anexos do Mail, Lixos e tela de Resultados

**Files:**
- Create: `docs/re/specs/mail-attachments.md`, `trash.md`, `mail-trash.md`, `docs/re/specs/results-screen.md`
- Binários-alvo: `MailJunkScanning`, `TrashJunkScanning`, `JunkCleanupModule`, `CleaningCore`, `UnusedDiskImagesScanning`

**Interfaces:**
- Produces: `results-screen.md`, que define:
  - quais cartões aparecem, em que condição e em que ordem;
  - quais têm botão Limpar e o que esse botão limpa (só os recomendados?);
  - a seleção inicial do Gerenciador e as opções de "Selecionar";
  - a ordenação padrão;
  - o comportamento do "Recomeçar";
  - o que aparece no Registro de Limpeza;
  - se `UnusedDiskImagesScanning` aparece na Limpeza. Se não aparecer, fica registrado como fora da v1.

- [ ] **Step 1:** Seguir o procedimento da Fase B. Em "Anexos do Mail", definir a regra exata de "arquivos modificados são mantidos".
- [ ] **Step 2:** Commit `docs(re): spec de mail, lixos e tela de resultados` e push.

---

## Fase C — Core

Todos os testes do Core usam `FixtureTree` (criado na Task 8), que monta uma árvore real em `FileManager.default.temporaryDirectory/cym-<UUID>` e a apaga no `deinit`. Os testes nunca tocam em `~` de verdade.

### Task 8: Modelos, ScanContext e FileSizer

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Model/*.swift`, `FileSystem/ScanContext.swift`, `FileSystem/FileSizer.swift`, `Core/Tests/CleanYourMacCoreTests/Fixtures/FixtureTree.swift`, `FileSizerTests.swift`, `ModelTests.swift`

**Interfaces:**
- Produces: os modelos da seção "Interfaces centrais". `GroupID.category` deve bater com a taxonomia; `GroupID.requiresAdmin` fica com valor `false` em todos até as specs (Tasks 13–19) definirem.
- Produces: `FixtureTree`, com `init()`, `file(_ relPath: String, bytes: Int, modified: Date? = nil) -> URL`, `dir(_:) -> URL`, `symlink(_ relPath: String, to: URL) -> URL`, `hardlink(_:to:) -> URL`, `chmod(_:_:)` e `context(user: String = "tester", languages: [String] = ["pt-BR","en"]) -> ScanContext`.
- Produces: `public struct FileSizer: Sendable { public init(); public func allocatedSize(of url: URL) -> Int64 }`, recursivo, sem seguir symlinks e contando cada inode uma vez. Se a spec `common.md` disser outra coisa, seguir a spec e ajustar os testes.
- Produces: `public enum SizeFormatter { public static func string(_ bytes: Int64, locale: Locale) -> String }` no formato definido em `common.md`.

- [ ] **Step 1:** Escrever os testes:
  - `ModelTests.groupCategories`: cada `GroupID` está na categoria certa (ex.: `.localModels.category == .aiClutter`, `.mailTrash.category == .trashBins`).
  - `FileSizerTests.sumsTree`: 3 arquivos de 4096, 10000 e 1 bytes; o resultado é igual à soma de `totalFileAllocatedSize` de cada um.
  - `FileSizerTests.doesNotFollowSymlinks`: um link para uma pasta de 1 MB fora da árvore não muda o total.
  - `FileSizerTests.hardLinkCountedOnce`.
  - `FileSizerTests.unreadableSubtreeSkipped`: uma pasta com `chmod 000` não lança erro e entra no total como 0.
  - `SizeFormatterTests`: os valores e as strings exatas de `common.md` para `pt-BR` e `en`.
- [ ] **Step 2:** Rodar `swift test --package-path Core`. Esperado: FAIL.
- [ ] **Step 3:** Implementar o `FileSizer` com `FileManager.enumerator(at:includingPropertiesForKeys:[.totalFileAllocatedSizeKey,.isSymbolicLinkKey,.fileResourceIdentifierKey], options: [], errorHandler: { _,_ in true })` e um `Set` de identificadores de arquivo.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): modelos, contexto e cálculo de tamanho` e push.

### Task 9: PathPolicy

**Files:**
- Create: `Core/Sources/CleanYourMacCore/FileSystem/PathPolicy.swift`, `Core/Tests/CleanYourMacCoreTests/PathPolicyTests.swift`

**Interfaces:**
- Consumes: `FixtureTree`.
- Produces: o `PathPolicy` da seção de interfaces.

- [ ] **Step 1:** Escrever os testes:
  - `acceptsChild`: raiz `R`, `R/a/b` → ok.
  - `rejectsOutside`: `/etc/hosts` → `.outsideAllowedRoots`.
  - `rejectsDotDot`: `R/../x` → `.outsideAllowedRoots`.
  - `rejectsRootItself`: `R` → `.isAllowedRootItself`.
  - `rejectsSymlinkedParentEscape`: `R/link -> /tmp/outside`, validar `R/link/file` → `.symlinkEscape`.
  - `acceptsSymlinkLeaf`: `R/link` (o próprio link) → ok, porque apagar o link não apaga o destino.
  - `prefixTrick`: raiz `R/Caches`, caminho `R/CachesEvil/x` → `.outsideAllowedRoots`.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar: padronizar com `standardizedFileURL`, resolver symlinks **só do diretório pai** e comparar por componentes de caminho, não por prefixo de string.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): política de caminhos permitidos` e push.

### Task 10: Regras como dados + RuleBasedScanner

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Rules/PathRule.swift`, `Rules/RuleBasedScanner.swift`, `Core/Tests/CleanYourMacCoreTests/RuleBasedScannerTests.swift`
- Modify: `Core/Package.swift` (adicionar `resources: [.copy("Rules/Resources/rules")]`)

**Interfaces:**
- Consumes: `FileSizer`, `ScanContext`, `JunkItem`.
- Produces:

```swift
public struct PathRule: Codable, Sendable {
    public var roots: [String]             // templates: "~/Library/Caches", "$ROOT/Library/Logs"
    public var itemLevel: ItemLevel        // .root | .children  (cada filho direto vira um item)
    public var include: [String]?          // globs fnmatch sobre o nome; nil = tudo
    public var exclude: [String]           // globs sobre o caminho relativo à raiz
    public var minAgeDays: Int?
    public var recommended: Bool
    public var removal: RemovalKind        // .delete | .moveToTrash | .deleteContents
    public var detail: String?
}
public struct GroupRules: Codable, Sendable { public var group: GroupID; public var rules: [PathRule] }
public struct RuleBasedScanner: GroupScanner {
    public init(rules: GroupRules)
    public static func bundled(_ group: GroupID) throws -> RuleBasedScanner  // carrega rules/<group>.json do Bundle.module
}
```
- O nome exibido do item é o nome do arquivo ou pasta. Para pastas com bundle id (`com.foo.bar`), quando houver um app instalado com esse id, o nome é o do app e o ícone é `.app(URL)`.

- [ ] **Step 1:** Escrever os testes, com regras construídas no próprio teste:
  - `childrenBecomeItems`: `~/Library/Caches/{A,B}` → 2 itens com os tamanhos certos.
  - `excludeWins`: com `exclude: ["com.apple.Safari*"]`, essa pasta não aparece.
  - `minAge`: um arquivo modificado há 1 dia não entra com `minAgeDays: 7`.
  - `missingRootIsEmpty`: raiz inexistente → `[]`, sem erro.
  - `symlinkChildNotFollowed`: um filho que é symlink para uma pasta grande fora da árvore aparece com o tamanho do link, ou é pulado se a spec mandar.
  - `vanishingFileTolerated`: um arquivo removido entre a enumeração e o cálculo de tamanho não derruba a análise.
  - `reportsProgress`: o callback recebe pelo menos um `currentPath` por raiz.
  - `bundledLoads`: para cada JSON em `rules/`, `RuleBasedScanner.bundled` decodifica sem erro. O teste passa com a pasta vazia e ganha força nas tasks seguintes.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar. O glob usa `fnmatch` com `FNM_PATHNAME` desligado.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): scanner baseado em regras` e push.

### Task 11: ScanEngine e ScanReport

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Scanning/{GroupScanner,ScanEngine,ScanReport}.swift`, `Core/Tests/CleanYourMacCoreTests/ScanEngineTests.swift`

**Interfaces:**
- Consumes: `GroupScanner`, `JunkItem`.
- Produces: `ScanEngine`, `ScanEvent`, `GroupResult` e `ScanReport` da seção de interfaces. Os grupos rodam em paralelo (`TaskGroup`, até 4 ao mesmo tempo). Os eventos de progresso são limitados a no máximo 1 a cada 50 ms por grupo. O erro de um scanner vira um `GroupResult` vazio e não interrompe os outros. `totalSize` não conta duas vezes o mesmo `id`.

- [ ] **Step 1:** Escrever os testes, com scanners falsos:
  - `emitsFinishedWithAllGroups`;
  - `totalsByCategory`;
  - `failingScannerDoesNotAbort`;
  - `cancellationStopsQuickly`: um scanner que dorme 10 s; cancelar a task consumidora termina em menos de 1 s, e nenhum `.finished` é emitido;
  - `recommendedItems`: só retorna os itens com `isRecommended`, incluindo filhos.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): motor de análise` e push.

### Task 12: CleanEngine, PrivilegedRunner e CleanupLog

**Files:**
- Create: `Core/Sources/CleanYourMacCore/Cleaning/{CleanEngine,PrivilegedRunner,CleanupLog}.swift`, `Core/Tests/CleanYourMacCoreTests/{CleanEngineTests,PrivilegedScriptTests}.swift`

**Interfaces:**
- Consumes: `PathPolicy`, `JunkItem`, `RemovalAction`.
- Produces:
  - `CleanEngine`, `CleanEvent`, `CleanReport`, `PrivilegedRunner` e `PrivilegedError` da seção de interfaces.
  - `public enum PrivilegedCommand: Hashable, Sendable { case remove(URL), removeContents(URL), lipoThin(URL, keepArch: String), codesignAdhoc(URL) }`, a ser estendido pelas Tasks 14–15 conforme a spec.
  - `public struct AppleScriptPrivilegedRunner: PrivilegedRunner`, que monta **um** script shell e executa via `NSAppleScript` com `do shell script "<script>" with administrator privileges`. O erro -128 vira `.userCancelled`. Cada comando emite `echo "CYM:<índice>:<status>"`, e o runner devolve um resultado por comando a partir dessas linhas.
  - `static func makeScript(_ commands: [PrivilegedCommand]) -> String`, testável.
  - `public struct CleanupLog { public init(directory: URL); func write(_ report: CleanReport) throws -> URL }`, que grava em `~/Library/Logs/CleanYourMac/cleanup-<ISO8601>.json`.
- Regras: cada item tem seu caminho validado pela `PathPolicy` do grupo antes de qualquer ação. Os itens de grupos `requiresAdmin`, ou cuja remoção sem privilégio falhar com `EACCES`/`EPERM`, vão para um único lote privilegiado no fim. Com `dryRun = true`, nada é tocado e cada item termina como `.success(size)`, com o log marcado `"dryRun": true`.

- [ ] **Step 1:** Escrever os testes, com `FakePrivilegedRunner`:
  - `deletesOnlySelected`: numa fixture com 3 itens, limpar 2 deixa o terceiro intacto.
  - `deleteContentsKeepsFolder`.
  - `refusesOutsidePolicy`: um item fabricado com `.delete(/etc/hosts)` → `.failure`, e o arquivo continua existindo.
  - `dryRunTouchesNothing`: os hashes da árvore antes e depois são iguais.
  - `adminBatchedOnce`: dois itens de `systemCache` geram exatamente 1 chamada ao runner.
  - `adminCancelled`: o fake lança `.userCancelled` → os itens de admin falham com `reason == "cancelled"`, e os demais são removidos.
  - `logWritten`.
  - `PrivilegedScriptTests.quotesHostilePaths`: para os caminhos `"/tmp/a b"`, `"/tmp/it's"`, `"/tmp/$(rm -rf ~)"`, `"/tmp/ação 🧹"`, o script contém cada caminho como literal entre aspas simples, com `'` escapado como `'\''`. O teste roda o script com `/bin/sh -n` (só sintaxe) e depois com `rm` trocado por `echo`, e verifica que a saída lista os caminhos exatos.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): motor de limpeza com dry-run, lote privilegiado e registro` e push.

---

## Fase D — Scanners por grupo (a partir das specs)

Padrão de cada task: os valores (caminhos, exclusões, recomendado, `requiresAdmin`, forma de remoção) vêm **exclusivamente** da spec do grupo. Cada task também:

- atualiza `GroupID.requiresAdmin` e `GroupID.requiresAdminToScan` para os seus grupos;
- registra os scanners em `Registry.swift` (`public enum Registry { public static func productionScanners() -> [any GroupScanner]; public static func policies(context: ScanContext) -> [GroupID: PathPolicy] }`);
- cria um teste de fixture por regra relevante da spec, com o nome `<grupo>_<regra>`, por exemplo `userCache_excludesSafari`.

Ao final de cada task: rodar `swift run --package-path Core cym scan --groups <grupos> --json` (o CLI fica pronto na Task 20; antes disso, verificar só pelos testes) e anotar as diferenças em relação à baseline na seção "Divergências conhecidas" da spec.

### Task 13: Caches e registros (userCache, systemCache, userLogs, systemLogs)

**Files:** Create `Core/Sources/CleanYourMacCore/Rules/Resources/rules/{userCache,systemCache,userLogs,systemLogs}.json`, `Core/Sources/CleanYourMacCore/Registry.swift`, `Core/Tests/CleanYourMacCoreTests/CacheLogRulesTests.swift`

- [ ] **Step 1:** Escrever testes de fixture para cada inclusão, exclusão e regra de recomendado das 4 specs.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Escrever os 4 JSONs e o `Registry`.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): regras de caches e registros` e push.

### Task 14: Binários Universais

**Files:** Create `Core/Sources/CleanYourMacCore/Scanners/UniversalBinariesScanner.swift`, `Core/Tests/CleanYourMacCoreTests/UniversalBinariesTests.swift`
**Interfaces:** Produces `UniversalBinariesScanner: GroupScanner`. O tamanho do item é o que se economiza (fatias que seriam removidas, lidas do cabeçalho fat com `MachO`/`lipo -detailed_info`). A remoção é `.thinBinary`; o `CleanEngine` executa `lipo -thin` e, se a spec mandar, `codesign` (via `PrivilegedCommand`).

- [ ] **Step 1:** Escrever os testes:
  - `detectsFatBinary`: compilar na fixture um executável fat com `clang -arch arm64 -arch x86_64` e conferir o tamanho economizado esperado;
  - `skips<categoria>` para cada regra de exclusão da spec;
  - `thinnedCopyStillValid`: copiar um app real não Apple e com binário universal de `/Applications` para a fixture (`ditto`), rodar a limpeza sobre a **cópia** e verificar `codesign --verify --deep` (ou o resultado que a spec define) e que `open -W -a` da cópia não retorna erro de lançamento.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar o scanner e os cases de remoção.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): binários universais` e push.

### Task 15: Arquivos de Idioma

**Files:** Create `Core/Sources/CleanYourMacCore/Scanners/LanguageFilesScanner.swift`, `Core/Tests/CleanYourMacCoreTests/LanguageFilesTests.swift`

- [ ] **Step 1:** Escrever os testes:
  - `keepsPreferredLanguages`: com `["pt-BR","en"]`, os `pt-BR.lproj`, `pt.lproj`, `en.lproj` e `Base.lproj` ficam, conforme a spec;
  - `skips<categoria>` da spec;
  - `strippedCopyStillValid`: mesma técnica de cópia de app da Task 14.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): arquivos de idioma` e push.

### Task 16: Itens de Início e Preferências Defeituosos

**Files:** Create `Scanners/BrokenLoginItemsScanner.swift`, `Scanners/BrokenPreferencesScanner.swift` e os testes correspondentes.

- [ ] **Step 1:** Escrever os testes:
  - `loginItemWithMissingProgram`: um LaunchAgent plist cujo `Program`/`ProgramArguments[0]` não existe → item;
  - `validLoginItemIgnored`;
  - `corruptPlist`: bytes inválidos em `~/Library/Preferences/x.plist` → item;
  - `validPlistIgnored`;
  - mais as regras extras da spec.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): itens de início e preferências defeituosos` e push.

### Task 17: Versões de Documentos, Usuários Apagados, Backups iOS, Xcode

**Files:** Create `Scanners/DocumentVersionsScanner.swift`, `Scanners/DeletedUsersScanner.swift`, `Scanners/IOSBackupsScanner.swift`, `rules/xcodeJunk.json` (ou `Scanners/XcodeJunkScanner.swift`, se a spec exigir lógica), e os testes.

- [ ] **Step 1:** Escrever os testes:
  - `iosBackups_latestBadgePerDevice`: 2 backups do mesmo `Info.plist` "Target Identifier" → o mais novo recebe `.latest` e não vem recomendado (ou o que a spec disser);
  - `deletedUsers_folderWithoutAccount`: uma pasta em `$ROOT/Users/` sem usuário correspondente → item. Os usuários existentes são injetados por um protocolo `UserDirectory`, para que o teste não dependa do `dscl`;
  - `documentVersions_*` conforme a spec (a fixture simula `.DocumentRevisions-V100`);
  - `xcode_*` para cada regra.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar, com um commit por scanner (`feat(core): <grupo>`) e push.
- [ ] **Step 4:** Rodar todos os testes. Esperado: PASS.

### Task 18: Acúmulos de IA (aiAgentsJunk, localModels)

**Files:** Create `rules/aiAgentsJunk.json` (uma regra por ferramenta e kind, com `detail` = kind), `Scanners/LocalModelsScanner.swift`, e os testes.

- [ ] **Step 1:** Escrever os testes:
  - `aiAgents_groupedByTool`: os itens filhos ficam agrupados por ferramenta (item pai com `removal == nil`);
  - `aiAgents_<ferramenta>_<kind>` para cada linha da spec;
  - `localModels_ollamaSharedBlobs`: dois manifestos compartilhando 1 blob → o tamanho de cada modelo e o total seguem a regra da spec, sem contar o blob duas vezes no total;
  - `localModels_lmStudio`;
  - `localModels_removalKeepsSharedBlob`: remover um modelo não apaga um blob usado por outro.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): acúmulos de IA` e push.

### Task 19: Anexos do Mail, Lixo, Lixos do Mail

**Files:** Create `Scanners/MailAttachmentsScanner.swift`, `rules/trash.json` ou `Scanners/TrashScanner.swift` (lixos de volumes via `FileManager.mountedVolumeURLs` → `.Trashes/<uid>`), `rules/mailTrash.json`, e os testes.

- [ ] **Step 1:** Escrever os testes:
  - `mail_keepsModifiedAttachments`, com a regra exata da spec;
  - `trash_userAndVolumes`: os volumes são injetados por um protocolo `VolumeProvider`;
  - `mailTrash_*`.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): mail e lixos` e push.

### Task 20: CLI `cym` e comparação de paridade

**Files:** Modify `Core/Sources/cym/main.swift`. Create `scripts/parity/compare.py`, `scripts/parity/test_compare.py`.

**Interfaces:**
- Produces:
  - `cym scan [--groups a,b] --json` imprime JSON no formato da baseline (Task 3), com `"tool": "cym"`.
  - `cym clean --dry-run [--groups …] [--recommended]` imprime o que seria removido. **Não existe modo não-dry no CLI.**
  - `python3 -I scripts/parity/compare.py <baseline.json> <cym.json>` imprime uma tabela por grupo (bytes CMM, bytes cym, diferença % e itens que só existem de um lado) e sai com código 1 se algum grupo passar da tolerância: `max(2%, 5 MB)`.

- [ ] **Step 1:** Escrever `test_compare.py` com dois casos: idênticos → exit 0; um grupo com 10% de diferença → exit 1, com o grupo listado.
- [ ] **Step 2:** Rodar `python3 -I -m unittest scripts/parity/test_compare.py`. Esperado: FAIL.
- [ ] **Step 3:** Implementar o `compare.py` e o `cym` (parsing de argumentos à mão, sem dependências).
- [ ] **Step 4:** Rodar o unittest. Esperado: PASS. Rodar `swift run --package-path Core cym scan --json > re-notes/cym.json` e depois `compare.py` contra a baseline. Esperado: a tabela é impressa (paridade completa só na Task 28).
- [ ] **Step 5:** Commit `feat(cli): cym scan/clean --dry-run e comparação de paridade` e push.

---

## Fase E — App

Quando precisar de texto descritivo, ele é escrito em pt-BR e en no `Localizable.xcstrings`, com chaves no formato `cleanup.<tela>.<elemento>`. Nenhum texto é copiado do CleanMyMac.

### Task 21: Design base, navegação e localização

**Files:** Create `App/Design/{Theme,GlassCard,ModuleArtwork,AnimatedNumber}.swift`, `App/Navigation/{RootView,SidebarView,AppModule}.swift`, `App/Resources/Localizable.xcstrings`, `App/Resources/Assets.xcassets` (AppIcon próprio, simples). Modify `App/CleanYourMacApp.swift`.

**Interfaces:**
- Produces:
  - `enum AppModule: CaseIterable { case cleanup, performance, applications, spaceLens; var isAvailable: Bool }`, em que só `cleanup` vem habilitado e os outros mostram o selo "Em breve"/"Soon".
  - `struct Theme { static func gradient(for: AppModule) -> LinearGradient }`, com verde para cleanup, laranja, azul e roxo.
  - `ModuleArtwork(module:, isAnimating: Bool)`, uma forma desenhada em SwiftUI (disco de vidro com material e brilho) que pulsa e gira suavemente quando `isAnimating`.
  - `AnimatedNumber(bytes: Int64)`, um contador que interpola o valor com `contentTransition(.numericText())`.
- Janela com `.windowStyle(.hiddenTitleBar)`, sidebar translúcida e conteúdo com o gradiente do módulo.

- [ ] **Step 1:** Implementar. Verificação: `xcodebuild … build`, depois abrir o app e conferir a sidebar com os 4 módulos e o fundo verde; testar em `-AppleLanguages "(en)"` e `"(pt-BR)"` que os nomes mudam.
- [ ] **Step 2:** Commit `feat(app): design base, sidebar e localização` e push.

### Task 22: CleanupFlowModel (máquina de estados)

**Files:** Create `App/Cleanup/CleanupFlowModel.swift`, `AppTests/CleanupFlowModelTests.swift`

**Interfaces:**
- Consumes: `ScanEngine`, `CleanEngine`, `ScanReport`, `Registry`.
- Produces:

```swift
@MainActor @Observable final class CleanupFlowModel {
    enum Phase: Equatable { case intro, scanning, results, review, cleaning, done(CleanReport), nothingFound }
    private(set) var phase: Phase
    private(set) var currentPath: String
    private(set) var currentGroup: GroupID?
    private(set) var bytesFound: Int64
    private(set) var report: ScanReport?
    let selection: SelectionModel
    init(scanEngine: ScanEngine, cleanEngineFactory: @escaping (Bool) -> CleanEngine, context: ScanContext)
    func startScan(); func stopScan(); func restart()
    func openReview(category: CategoryID? = nil)
    func clean(items: [JunkItem]); func cleanRecommended(in category: CategoryID)
}
```

- [ ] **Step 1:** Escrever os testes, com scanners falsos e `dryRun`:
  - `scanGoesToResults`;
  - `emptyScanGoesToNothingFound`;
  - `stopScanReturnsToIntro`: sem `report`; cobre o item 5 do Review Focus;
  - `bytesFoundIncreasesMonotonically`;
  - `cleanGoesToDoneWithReport`;
  - `restartClearsState`.
- [ ] **Step 2:** Rodar `xcodebuild … test`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(app): modelo do fluxo de limpeza` e push.

### Task 23: Telas Intro e Análise

**Files:** Create `App/Cleanup/{IntroView,ScanningView}.swift`

- [ ] **Step 1:** Implementar a **Intro** (layout dos prints: arte à esquerda, título, subtítulo e lista das 4 categorias à direita, botão circular "Analisar" embaixo com brilho) e a **Análise** (arte com `isAnimating`, nome do grupo atual, caminho atual em fonte monoespaçada truncado no meio, `AnimatedNumber` do total e botão "Parar"). As transições usam `.transition(.opacity.combined(with: .scale))`.
- [ ] **Step 2:** Verificação manual: rodar o app com um ambiente de debug `CYM_FIXTURE_ROOT` (aponta o `ScanContext.root` para uma fixture) e conferir a animação, o caminho mudando e o total subindo. Rodar também contra o disco real (a análise é só leitura).
- [ ] **Step 3:** Commit `feat(app): telas de intro e análise` e push.

### Task 24: Tela de Resultados

**Files:** Create `App/Cleanup/{ResultsView,ResultCards}.swift`

- [ ] **Step 1:** Implementar conforme `docs/re/specs/results-screen.md`:
  - título "O Mac tem X de detritos." (texto nosso, mesmo sentido);
  - botão "Revisar Todos os Detritos";
  - cartões `GlassCard` com quais aparecem, a ordem e os botões definidos na spec, e com ícones dos apps de IA encontrados (via `NSWorkspace.icon(forFile:)`);
  - "Recomeçar" na barra.
  - Animação: os cartões entram em cascata (delay de 0,05 s cada).
- [ ] **Step 2:** Verificação manual no app.
- [ ] **Step 3:** Commit `feat(app): tela de resultados` e push.

### Task 25: Gerenciador de Limpeza (revisão)

**Files:** Create `App/Cleanup/{SelectionModel,ReviewView}.swift`, `AppTests/SelectionModelTests.swift`

**Interfaces:**
- Produces:

```swift
@MainActor @Observable final class SelectionModel {
    enum State { case off, mixed, on }
    func state(of item: JunkItem) -> State
    func toggle(_ item: JunkItem)                 // pai liga/desliga todos os filhos
    func select(_ preset: Preset, in group: GroupID)   // Preset: .none, .recommended, .all
    func applyInitialSelection(_ report: ScanReport)    // conforme results-screen.md
    var selectedItems: [JunkItem] { get }         // folhas com removal != nil
    var selectedBytes: Int64 { get }
}
```

- [ ] **Step 1:** Escrever os testes:
  - `parentToggleSelectsChildren`;
  - `oneChildMakesParentMixed`;
  - `presetRecommended`;
  - `selectedBytesSumsLeavesOnly`: sem somar pai e filho;
  - `initialSelectionMatchesSpec`.
- [ ] **Step 2:** Rodar os testes. Esperado: FAIL.
- [ ] **Step 3:** Implementar o `SelectionModel` e a `ReviewView`:
  - tela clara, `NavigationSplitView` com 3 colunas (categorias / grupos com ícone e tamanho / itens);
  - itens com checkbox tri-state, ícone, nome, selo "recomendado" (✦), tamanho e chevron que expande os filhos;
  - "Selecionar" (Nenhum/Recomendados/Todos), busca (`.searchable`) e "Ordenar por" (Tamanho/Nome);
  - rodapé "N itens selecionados | X" com o botão "Limpar" desabilitado quando não há seleção;
  - alertas de confirmação para backup iOS `.latest` e para modelos locais.
- [ ] **Step 4:** Rodar os testes. Esperado: PASS. Verificação manual no app.
- [ ] **Step 5:** Commit `feat(app): gerenciador de limpeza` e push.

### Task 26: Telas de Limpeza, Concluído e Registro

**Files:** Create `App/Cleanup/{CleaningView,DoneView}.swift`

- [ ] **Step 1:** Implementar:
  - **Limpeza**: arte animada, item atual, barra de progresso por bytes e contador de bytes liberados;
  - **Concluído**: total removido com `AnimatedNumber` e botão "Recomeçar";
  - **Falha parcial**: mensagem própria e botão "Registro de Limpeza", que abre uma sheet com a lista de falhas e o motivo, e um botão para mostrar o arquivo de log no Finder.
- [ ] **Step 2:** Verificação manual com `CYM_FIXTURE_ROOT` (limpeza real **só na fixture**) e com o modo `CYM_DRY_RUN=1` contra o disco real. Esse modo é o **padrão em builds Debug**; o Release limpa de verdade.
- [ ] **Step 3:** Commit `feat(app): telas de limpeza e conclusão` e push.

### Task 27: Permissões e administrador

**Files:** Create `App/Permissions/{PermissionsService,PermissionsView}.swift`

**Interfaces:**
- Produces: `struct PermissionsService { func hasFullDiskAccess() -> Bool; func hasAppManagement() -> Bool; func openSettings(for: Permission) }`.
  - Acesso Total ao Disco: tentar abrir para leitura `~/Library/Safari/Bookmarks.plist`, ou, se não existir, `~/Library/Application Support/com.apple.TCC/TCC.db`.
  - Gerenciamento de Apps: tentativa de escrita num arquivo temporário dentro de um bundle de app de terceiro, que é desfeita em seguida. Usar o método que a spec da Task 4 indicar, se houver um melhor.
  - Os links abrem `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` e `?Privacy_AppBundles`.

- [ ] **Step 0:** Análise privilegiada: embutir o executável `cym` no bundle do app (`project.yml`: dependência do produto `cym` copiada para `Contents/Helpers/`). Criar `PrivilegedScanService`, que, quando algum grupo pedido tem `requiresAdminToScan`, executa `cym scan --groups <esses> --json` uma única vez via `AppleScriptPrivilegedRunner` (adicionar `case runScan(executable: URL, groups: [GroupID])` ao `PrivilegedCommand`, cuja saída é o JSON) e junta o resultado no `ScanReport`. Cancelar a senha deixa esses grupos vazios, com um aviso na tela de Resultados. Teste em `CleanupFlowModelTests.adminScanCancelledShowsNotice`, com um runner falso.
- [ ] **Step 1:** Implementar:
  - tela de onboarding mostrada antes da Intro quando falta o Acesso Total ao Disco, com o passo a passo e a verificação automática ao voltar o foco para o app;
  - pedido de Gerenciamento de Apps só quando a seleção inclui Binários Universais ou Idiomas;
  - aviso antes do pedido de senha ("Alguns itens precisam de permissão de administrador").
- [ ] **Step 2:** Verificação manual: revogar e conceder o Acesso Total ao Disco nos Ajustes e ver a tela reagir. Cancelar o pedido de senha numa limpeza de fixture que inclua um grupo `requiresAdmin` e ver as falhas "cancelado" no registro.
- [ ] **Step 3:** Commit `feat(app): permissões e fluxo de administrador` e push.

---

## Fase F — Fechamento

### Task 28: Paridade final, documentação e revisão

**Files:** Create `docs/re/parity/report-<data>.md`. Modify `README.md` e as specs (seção "Divergências conhecidas").

- [ ] **Step 1:** Recapturar a baseline (só a análise do CleanMyMac) e rodar o `cym scan --json` logo em seguida. Rodar `compare.py`. Esperado: exit 0. Se sair 1, corrigir as regras ou documentar a divergência com justificativa e evidência.
- [ ] **Step 2:** Comparar os itens recomendados entre os dois lados (a tabela do `compare.py` inclui a coluna `recommended`).
- [ ] **Step 3:** Rodar `swift test --package-path Core` e `xcodebuild … test`. Esperado: tudo PASS, sem warnings novos de concorrência.
- [ ] **Step 4:** No README: funcionalidades, screenshots, permissões necessárias, aviso de "use por sua conta e risco" e como contribuir.
- [ ] **Step 5:** Commit `docs: relatório de paridade e README da v1` e push. Criar a tag `v0.1.0` e fazer push da tag.
