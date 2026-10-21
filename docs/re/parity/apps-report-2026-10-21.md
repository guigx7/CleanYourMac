# Paridade do módulo Aplicativos — 2026-10-21

CleanMyMac 5.7.2 (Setapp) × CleanYourMac v0.2, nesta máquina (macOS 26.6.2, Apple Silicon), com as duas análises
feitas em sequência.

- Baseline do CleanMyMac: [`apps-baseline-2026-10-21-final.json`](apps-baseline-2026-10-21-final.json), coletada pela
  árvore de Acessibilidade (`scripts/re/collect-apps-baseline.py` → `scripts/parity/apps_ax_to_baseline.py`). Só a
  análise rodou no CleanMyMac.
- Nossa análise: [`cym-apps-2026-10-21.json`](cym-apps-2026-10-21.json), exportada pelo app instalado em
  `/Applications`, que tem Acesso Total ao Disco (`open --env CYM_APPS_PARITY=<json> /Applications/CleanYourMac.app`).
- Comparação: `python3 -I scripts/parity/compare_apps.py <baseline> <cym> apps-known-divergences.json`.

**Resultado: 0 falhas.**

## O que bate exatamente

| Parte | Resultado |
|---|---|
| Lista de apps | os mesmos 26 apps |
| Filtros | Todos 26, Não Usados 1 (GarageBand), App Store 3, Setapp 1, Outra 22, Apple 2, Google 1, MacPaw 2, Microsoft 1, Outros 20, Plug-ins de Áudio 1 |
| Atualizações de apps | só o GarageBand, 10.4.13 → 10.4.14 (App Store, 732 MB, 22/04/2026) |
| Sobras | as mesmas 7 (2 extensões da Canva, 4 do CleanShot, 1 do Supercharge) |
| Instaladores | o DMG do Warp (185 MB) |
| Arquivos relacionados | em todos os apps, os nossos são um subconjunto dos do CleanMyMac, com os mesmos tamanhos dentro da tolerância |

## Divergências conhecidas (notas)

Todas estão descritas nas specs (`docs/re/specs/apps/`):

- **Atualizações do macOS** (Safari, macOS 26.7.1 e 27.0.1): nós as listamos e abrimos os Ajustes; o CleanMyMac não
  mostrou o cartão do sistema nesta máquina (`updater.md`, `results-screen.md`).
- **Itens que só o CleanMyMac acha** (vínculo frouxo ou base cifrada): `~/Library/Application Support/Google/Chrome`,
  `Chrome Apps.localized`, `Google Chrome Brand.plist`, `com.google.Keystone.Agent.plist` (Chrome); `~/.vscode` (VS Code);
  `~/Library/Developer/Xcode`, `CoreSimulator`, `com.apple.dt.xcodebuild`, `embeddedBinaryValidationUtility.plist`
  (Xcode); contêineres de extensões do GarageBand e o grupo `2BBY89MBSN.dev.warp` (Warp). A regra forte
  (`related-files.md`) não os inclui: segurança antes de paridade. Por isso as linhas do Chrome (1,5 GB × 6,1 GB), do
  VS Code (2,2 GB × 4,1 GB) e do Xcode (4,2 GB × 5,0 GB) são menores.
- **Ícone no Dock** (Chrome, Warp, Zed): não listado na v0.2 (não editamos o Dock).
- **Tamanho do bundle**: o CleanMyMac usa o `kMDItemPhysicalSize` do Spotlight, que pode estar velho (GlucoTracker
  e as builds dele, LogiPluginService); nós medimos o disco (`inventory.md`).
- **Nomes de 2 sobras**: o CleanMyMac mostra "Thumbnail Extension"/"QuickLook Extension"; nós mostramos o nome do
  pacote que os metadados do contêiner guardam ("ThumbnailShareExtension (Global)"…). O nome de exibição dele vem de um
  pacote que já não existe. Mapeado em [`apps-known-divergences.json`](apps-known-divergences.json).
- **Sobras de 0 KB**: o CleanMyMac mostra 0 KB para contêineres vazios; nós mostramos o bloco alocado (4 KB). O total
  fica em 69,6 KB contra 49,2 KB, dentro da tolerância.
- **Arquivos voláteis**: `~/Library/Logs/warp.log` é reescrito pelo Warp aberto (0 KB numa análise e 4,2 MB na outra).
- **O próprio CleanYourMac**: muda durante o teste (builds novos, cache do catálogo do Homebrew), então só gera notas.

## Correções feitas por causa desta comparação

- Relatórios de falha casam o prefixo `<CFBundleName>_` com maiúsculas exatas: `chrome_crashpad_handler_…` não é do
  Chrome.
- Os metadados reais dos contêineres usam `SandboxProfileDataValidationInfo/Parameters/application_bundle`.
- Contêiner sem caminho do app é sobra só se nenhum app instalado for "pai" do bundle ID, nem do mesmo fornecedor, e
  se o bundle ID não for de um pacote de dentro de um app instalado (ex.: `com.utmapp.QEMUHelper`, dentro do UTM).
- Para contar como instalado, um app registrado no LaunchServices precisa existir no disco.
