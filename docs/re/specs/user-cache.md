# Arquivos de Cache do Usuário (`userCache`)

Regras transversais (tamanho, formatação, `.DS_Store`, KB, SIP, remoção) estão
em `common.md`. Aqui fica só o que é próprio deste grupo.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), análise de 2026-10-20 14:57.

## Composição do grupo na UI
O grupo "Arquivos de Cache do Usuário" é o resultado da tarefa composta
`UserCachesCompound`. [E1, E2] Ela reúne três tipos de subtarefa num único
contexto de agrupamento:

| Subtarefa | Tipo | Cai em `userCache`? |
|---|---|---|
| `UserCache` (`~/Library/Caches`) | simples | sim |
| `DarwinUserCache` (`$DARWIN_USER_CACHE_DIR`) | simples | sim |
| `SandboxContainersCache` (`~/Library/Containers/*/Data/Library/Caches`) | simples | **sim** |
| `ElectronAppsCache` | personalizada | sim |
| `HardcodedPathCache` (Telegram, WeChat, Adobe, Fotos…) | personalizada | sim |
| `DropboxCache` | agrupada sob `com.getdropbox.dropbox` | sim |
| `SpotifyCache` | agrupada sob `com.spotify.client` | sim |
| `AppStoreDownloadsCache` | agrupada sob `com.apple.appstore` | sim |
| `GradleCache` | agrupada sob `Gradle` | sim |

Não fazem parte deste grupo: `SystemCache` e `CoreSymbolicationdCache` (vão
para `systemCache`); `DocumentationCache` e os caches de módulos do Xcode/LLVM
(vão para os detritos do Xcode, fora desta spec). [E1, E3]

## Locais varridos
Os caminhos abaixo são fixos no código. [E4, E5]

1. `~/Library/Caches`: cada filho direto é um candidato.
2. `$DARWIN_USER_CACHE_DIR`, obtido com `confstr(_CS_DARWIN_USER_CACHE_DIR)`
   (ex.: `/var/folders/z_/…/C/`): cada filho direto é um candidato.
3. `~/Library/Containers/<container>/Data/Library/Caches`, para cada
   `<container>` em `~/Library/Containers`: cada filho direto desse `Caches` é
   um candidato.
4. Apps Electron: para cada app do usuário que contenha
   `Contents/Frameworks/Electron Framework.framework`, o candidato é
   `~/Library/Application Support/<nome do app>/Cache`. Para apps em sandbox, o
   caminho é `<container do app>/Library/Application Support/<nome do app>/Cache`.
   Só entra se existir. [E6]
5. Caminhos fixos, um grupo para cada (o item é a pasta/arquivo inteiro). [E7]

| Identificador do grupo | Caminho(s) | autoselected |
|---|---|---|
| `ru.keepcoder.Telegram` | `~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/<n>/account-*/postbox/media` (nível 2 cujo nome começa com `account-`) | não |
| `org.telegram.desktop` | `~/Library/Containers/org.telegram.desktop/Data/Library/Application Support/Telegram Desktop/tdata/user_data/{cache,media_cache}` | não |
| `com.tdesktop.Telegram` | `~/Library/Application Support/Telegram Desktop/tdata/user_data/{cache,media_cache}` | não |
| `com.tencent.xinWeChat` | `~/Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat/2.0b4.0.9/<cada subpasta>/Message/MessageTemp` | não |
| `com.tencent.tenvideo` | `~/Library/Containers/com.tencent.tenvideo/Data/Library/Application Support/Download/video` | não |
| `com.tencent.QQMusicMac` | `~/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iMusic` | não |
| `com.youku.mac` | `~/Library/Containers/com.youku.mac/Data/Documents/YTCORE_PLAYER_CACHE` | não |
| `Adobe Premier Pro Media Cache` | `~/Library/Application Support/Adobe/Common/Media Cache Files` | não |
| `System Migration Cache` | `/Library/SystemMigration/History/<primeira entrada que começa com Migration->/QuarantineRoot/private/var/db/dyld` | não |
| `com.apple.Photos` | cada filho de `~/Library/Containers/com.apple.Photos/Data/Library/Application Support/Photos Desktop/0`, **menos o acessado mais recentemente** | sim |

6. Dropbox: as pastas `placeholder_cache` e `prefetch_cache` do cache interno de
   cada conta do Dropbox configurada. Entra só o que tiver tamanho > 0. [E8]
7. Spotify: a pasta de armazenamento lida em
   `~/Library/Application Support/Spotify/prefs` (`storage.location=` ou
   `storage.last-location=`). O padrão é
   `~/Library/Application Support/Spotify/PersistentCache/Storage`. [E8]
8. App Store: os caminhos listados na chave `purgeables` de
   `$DARWIN_USER_CACHE_DIR/com.apple.appstore/manifest.plist`. Cada caminho que
   existir vira um item. [E9]
9. Gradle: `~/.gradle/caches`, cada filho direto. [E5]

## Inclusão
- **Nível do item:** nas raízes 1, 2, 3 e 9, cada **filho direto** vira um
  candidato. Nos casos 4 a 8, o item é o caminho indicado. [E4]
- O candidato inteiro (pasta ou arquivo) é medido, e é a unidade de remoção.
- Um candidato entra mesmo com tamanho 0 quando o helper privilegiado está
  autorizado. Sem o helper, um candidato de tamanho 0 é descartado. [E10] Na
  baseline (com helper) aparecem dezenas de itens "0 KB".
  **Regra nossa:** incluir candidatos de tamanho 0 (`includeEmpty: true`) para
  bater com a baseline.
- Nos casos agrupados (Dropbox, Spotify, App Store, Gradle), só entram itens com
  tamanho > 0. [E11]
- Não há idade mínima nem tamanho mínimo. [E4]

## Exclusão
- Filho chamado `.DS_Store` (ver `common.md`). [E4]
- Itens e grupos ignorados pela KB (por caminho, por nome ou por id de grupo).
  [E4, E12] Como não lemos a KB, a lista abaixo é a **nossa regra
  equivalente**, derivada do que existia no disco e não apareceu na baseline (os
  tamanhos são do `du -sk` na hora da análise):

  `~/Library/Caches/`:
  - `ms-playwright` (1,3 GB), `GeoServices` (64 MB), `GameKit`, `CloudKit`,
    `FamilyCircle`, `com.apple.HomeKit`, `com.apple.homed`,
    `com.apple.containermanagerd`
  - `com.apple.dt.xcodebuild`, `org.swift.swiftpm`: detritos de
    desenvolvimento, que ficam com o Xcode
  - os caminhos das ferramentas de IA (lista global em `common.md`)

  `$DARWIN_USER_CACHE_DIR/`:
  - `clang` (358 MB): é o cache de módulos do LLVM, que fica com o Xcode
  - `com.apple.FontRegistry`, `com.apple.dock`, `com.apple.dock.iconcache`,
    `com.apple.systempreferences`, `com.apple.Wallpaper-Settings.extension`,
    `com.apple.ContactsUI.MonogramPosterExtension`, `com.apple.Family`,
    `com.apple.WorkflowKit.BackgroundShortcutRunner*`, `com.apple.siriactionsd*`,
    `com.apple.WebKit.*.Sandbox`
- Arquivos restritos pelo sistema (SIP) nos caminhos fixos. [E7]
- **Symlinks** como filho direto: **regra nossa**, pulados (ver `common.md` 1.2).

## Recomendado
- O padrão é **sim** (`autoselected`) em todo item de `UserCache`,
  `DarwinUserCache`, `SandboxContainersCache`, Electron, Dropbox, App Store e
  Fotos. [E10, E6, E8, E9, E7]
- **Não** recomendados: Gradle, Spotify e os caminhos fixos de Telegram,
  WeChat, Tencent Video, QQ Music, Youku, Adobe e Migração do Sistema. [E5, E8, E7]
- A baseline mostrou tudo desmarcado: ver `common.md` §4.

## Agrupamento e nome exibido
- Todos os candidatos vão para um contexto que os **agrupa por identificador**.
  Cada identificador vira **um item de primeiro nível** na lista. [E12]
- O identificador do candidato é:
  - nas raízes 1 e 2: o **nome do próprio filho** (ex.: `Google`, `Homebrew`,
    `com.apple.helpd`, `com.apple.wallpaper.agent`) [E13];
  - na raiz 3 (containers): o **nome da pasta do container**, isto é, o
    componente logo depois de `~/Library/Containers/` (ex.:
    `~/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches/MediaCache`
    → `net.whatsapp.WhatsApp`) [E13];
  - nos casos 4 a 9: o identificador fixo da tabela, ou o bundle id do app
    (Electron).
- Candidatos de raízes diferentes com o **mesmo identificador** se juntam no
  mesmo item. Exemplo: `$DARWIN_USER_CACHE_DIR/net.whatsapp.WhatsApp` e os
  filhos de `~/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches`
  formam um único item "WhatsApp.app" (25,1 MB). [E12, E14]
- Um candidato que passou por "busca profunda" da KB entra como os filhos dele
  direto no grupo. [E12] (Regra nossa: sem busca profunda; o candidato entra
  inteiro.)
- **Nome exibido:** se o identificador for o bundle id de um app que o
  LaunchServices conhece (`NSWorkspace.urlForApplication(withBundleIdentifier:)`),
  o nome é o **nome do arquivo do app, com `.app`**, como `WallpaperAgent.app`
  (`com.apple.wallpaper.agent`), `Phone.app` (`com.apple.mobilephone`),
  `Finder.app`, `ControlCenter.app`, `Google Chrome Helper (Aperitif).app`
  (`com.google.Chrome.helper`) e `Warp.app`. Caso contrário, o nome é o
  identificador cru (`Google`, `Homebrew`, `pnpm`, `com.apple.helpd`). [E14]
- Dois identificadores podem levar ao mesmo nome: na baseline aparecem dois
  "Setapp.app" (`com.setapp.DesktopClient` com 3,5 MB e
  `com.setapp.DesktopClient.SetappAgent` com 4,1 KB). Eles **não** se juntam,
  porque o agrupamento é pelo identificador. [E14]
- **Ícone:** o do app, quando ele é encontrado; senão, um ícone genérico de
  pasta (escolha nossa: os ícones não aparecem na árvore de acessibilidade).
- **Filhos ao expandir:** cada candidato do grupo (pastas ou arquivos com
  caminho completo). Ao expandir uma pasta, aparece o conteúdo dela. Todos os
  itens do grupo têm o botão "mostrar itens incluídos". [E15]
- Ordem padrão: por tamanho, decrescente; empates em ordem alfabética
  decrescente (observação da baseline: os itens de 0 KB vão de `Zed` a
  `AccessibilityUIServer.app`). A ordenação é da tela (`results-screen.md`).

## Cálculo de tamanho
Alocado, conforme `common.md`. O tamanho do item é a soma dos tamanhos dos seus
candidatos.

## Remoção
- Apagar definitivamente cada candidato (a pasta ou arquivo filho), não a raiz.
  [common.md E13/E16]
- Não precisa de admin, porque os caminhos pertencem ao usuário. Se o
  `removeItem` falhar com `EACCES`/`EPERM`, o item vai para o lote privilegiado
  (Task 12). `System Migration Cache` fica em `/Library` e precisa de admin.
- O CleanMyMac não fecha nem avisa sobre apps abertos ao apagar caches. Regra
  nossa: igual, sem aviso (o app recria o cache).

## Alertas e selos
Nenhum alerta ou selo observado. Cada item mostra o ícone de "dica inteligente"
(informações sobre o item); isso fica fora da v1.

## requiresAdmin
- Análise: **não**. Para medir os containers de outros apps e algumas pastas,
  como `com.apple.Safari`, o processo precisa de Acesso Total ao Disco; sem ele,
  essas pastas medem 0.
- Limpeza: **não** (com o lote privilegiado como plano B para falhas de
  permissão).

## Evidências
- **E1** — pseudocódigo de `CMUserCachesCompoundTask initWithKnowledgeBase:privilegedOperationsPerformer:`
  (função interna de montagem): tarefas simples `CMUserCachesScanTask`,
  `CMDarwinUserCachesScanTask` e `CMSandboxContainersCachesScanTask`;
  personalizadas `CMElectronAppsCacheScanTask` e `CMHardcodedPathCacheScanTask`;
  agrupadas Dropbox, Spotify, App Store e Gradle, com as chaves
  `com.getdropbox.dropbox`, `com.spotify.client`, `com.apple.appstore` e
  `Gradle` (strings do binário). O identificador composto é
  `CMSystemJunkScanIdentifierUserCachesCompound`.
- **E2** — strings do JunkCleanupModule: o grupo da UI
  `systemJunkUserCacheGroupTitle` corresponde a
  `SystemJunkScanIdentifierUserCachesCompound`.
- **E3** — pseudocódigo de `CMSystemCachesCompoundTask initWithKnowledgeBase:…`
  e as classes `CMXcodeModuleDocumentationCachesScanTask` e
  `CMXcodeModuleCachesScanTask`.
- **E4** — pseudocódigo de `CMCacheScanTask scan`, do bloco de mapeamento
  associado e de `contentOfCachesDirectoryURL`: lista os filhos diretos e pula
  `.DS_Store` e o que a KB ignora. Se a KB pedir, faz busca profunda; senão,
  mede o filho inteiro.
- **E5** — pseudocódigo de `CMPaths userCaches`, `darwinUserCaches` (`confstr`),
  `sandboxContainer` e `gradleCaches` (SharedObjcUtils), e de
  `CMGradleCacheScanTask isResultAutoselectable` (= não).
- **E6** — pseudocódigo de `CMElectronAppsCacheScanTask _scan`,
  `_electronCacheURLForApplication:` e `_containsCacheForApplication:`: grupo
  pelo bundle id, autoselected = sim. A string do framework Electron está nas
  strings do binário.
- **E7** — pseudocódigo de `CMHardcodedPathCacheScanTask _groups`, `_telegram`,
  `_weChat`, `_adobe`, `_systemMigrationCache`, `_applePhotosDesktopCache`,
  `_groupForURLS:identifier:autoselected:` e `_groupFilesForURLS:…`, mais as
  strings com os caminhos e identificadores.
- **E8** — pseudocódigo de `CMDropboxCacheScanTask scan` (limite de tamanho 0,
  autoselected = sim) e do scanner Swift do Spotify (autoselected = não);
  strings `placeholder_cache`, `prefetch_cache`, `Spotify/prefs`,
  `PersistentCache/Storage`, `storage.location=`.
- **E9** — pseudocódigo de `CMAppStoreDownloadsManifest init` e
  `purgeablePaths`, e de `CMAppStoreDownloadsCacheScanTask scan`
  (autoselected = sim).
- **E10** — pseudocódigo do bloco de `CMCacheScanTask scan`: um candidato de
  tamanho 0 só entra com o helper autorizado; `isResultAutoselectable` = sim.
- **E11** — pseudocódigo de `CMCachesCompoundTask _scanGroupedTasksInContext:`:
  só adiciona itens com tamanho > 0.
- **E12** — pseudocódigo de `CMCachesCompoundTask scan`,
  `_scanPlainTasksInContext:`, `_addCustomItemsInContext:` e de
  `CMCachesContext addItem:`, `addItem:toGroupWithIdentifier:` e
  `_hasOnlyFileModelChildren:`.
- **E13** — pseudocódigo de `CMCachesContext _groupIdentifierFromURL:`: o último
  componente, ou o componente seguinte ao caminho dos containers.
- **E14** — observação da baseline comparada com o disco (`ls` das três raízes)
  e com a resolução de bundle id via `mdfind kMDItemCFBundleIdentifier`:
  `com.apple.wallpaper.agent` → WallpaperAgent.app, `com.apple.mobilephone` →
  Phone.app, `com.setapp.DesktopClient.SetappAgent` → Setapp.app,
  `net.whatsapp.WhatsApp` → WhatsApp.app.
- **E15** — observação da baseline: as células de userCache têm o botão
  "Mostre os itens incluídos".

## Divergências conhecidas
- Não há busca profunda guiada pela KB: um candidato sempre entra inteiro.
- A lista de exclusões é derivada da observação nesta máquina, não da KB. Em
  outra máquina, itens que a KB ignoraria vão aparecer no CleanYourMac.
- Symlinks como filho direto não viram item (o CleanMyMac com helper os
  mostraria com 0 KB).
- O cache do Dropbox depende da localização das contas, lida de
  `~/.dropbox/info.json` (conhecimento público). O CleanMyMac usa uma classe
  própria para isso, que não foi analisada.
- `GeoServices`, `ms-playwright` e o resto da lista de exclusões ficam fora por
  paridade, mesmo sendo caches de verdade.

## Checklist de testes
- `userCache_childrenBecomeItems`: `~/Library/Caches/{Google,Homebrew}` com
  1 MB e 2 MB → 2 itens com esses tamanhos e `isRecommended = true`.
- `userCache_dsStoreSkipped`: `~/Library/Caches/.DS_Store` → nenhum item.
- `userCache_emptyFolderIncluded`: `~/Library/Caches/Vazio/` (pasta vazia) →
  1 item com 0 bytes.
- `userCache_symlinkSkipped`: `~/Library/Caches/link -> /tmp/grande` → nenhum
  item.
- `userCache_excludesPlaywright`: `~/Library/Caches/ms-playwright/x` (5 MB) →
  nenhum item.
- `userCache_excludesAITools`: `~/Library/Caches/claude-cli-nodejs/a` → nenhum
  item.
- `userCache_darwinRoot`: `$DARWIN/com.foo.bar/x` (fixture com
  `$DARWIN_USER_CACHE_DIR` apontando para a árvore) → item `com.foo.bar`.
- `userCache_excludesClang`: `$DARWIN/clang/ModuleCache/x` → nenhum item.
- `userCache_containerGroupedByContainer`:
  `~/Library/Containers/com.foo.app/Data/Library/Caches/{A,B}` → **1** item
  `com.foo.app`, com 2 filhos (A e B), tamanho = A + B.
- `userCache_mergesSameIdentifier`: `$DARWIN/com.foo.app` (1 MB) mais o
  container `com.foo.app` com `Caches/A` (2 MB) → 1 item com 3 MB e 2 filhos.
- `userCache_displayNameFromBundleId`: identificador = bundle id de um app de
  fixture registrado (`Foo.app`) → nome "Foo.app" e ícone do app.
  Identificador sem app (`com.apple.helpd`) → nome "com.apple.helpd".
- `userCache_sameDisplayNameNotMerged`: dois ids diferentes que resolvem para
  "Setapp.app" → 2 itens.
- `userCache_gradleNotRecommended`: `~/.gradle/caches/modules-2` (1 MB) → item
  no grupo `Gradle`, `isRecommended = false`.
- `userCache_gradleZeroSkipped`: `~/.gradle/caches/vazio` (0 B) → nenhum item.
- `userCache_electronCache`: app de fixture com
  `Contents/Frameworks/Electron Framework.framework` e nome "Foo", mais
  `~/Library/Application Support/Foo/Cache` (1 MB) → item agrupado pelo bundle
  id do app, recomendado.
- `userCache_photosKeepsMostRecent`: `Photos Desktop/0/{a,b,c}` com datas de
  acesso a < b < c → filhos a e b; c fica.
- `userCache_telegramNotRecommended`: a pasta `postbox/media` de uma conta
  `account-1` existe → item `ru.keepcoder.Telegram`, não recomendado.
- `userCache_removalDeletesChildNotRoot`: limpar o item `Google` apaga
  `~/Library/Caches/Google`, e `~/Library/Caches` continua existindo.

## Baseline observada
Total do grupo: **2,8 GB**, 256 itens de primeiro nível, todos desmarcados. Os
maiores: Google 1,6 GB · Homebrew 592 MB · pnpm 352 MB · node-gyp 67,6 MB ·
com.apple.helpd 37,6 MB · WallpaperAgent.app 32,9 MB · WhatsApp.app 25,1 MB ·
Google Chrome Helper (Aperitif).app 23 MB · ffmpeg-static-nodejs 19,3 MB ·
com.apple.Safari.SafeBrowsing 19 MB · com.apple.parsecd 18,8 MB ·
Vorssaint.app 14,1 MB · com.apple.iconservicesagent 5,6 MB ·
com.onevcat.Kingfisher.ImageCache.default 4,4 MB · com.apple.photolibraryd
3,9 MB · Setapp.app 3,5 MB · Phone.app 3,2 MB · Spotlight.app 2,4 MB ·
PassKit 2,4 MB · Perssua Helper (GPU).app 2,3 MB. Há 155 itens de 0 KB (ex.:
Safari.app, Maps.app, Google Chrome.app, iCloud Drive.app). Lista completa em
`docs/re/parity/baseline-2026-10-20.json` (`groups.userCache`).
