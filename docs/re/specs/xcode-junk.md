# Detritos do Xcode (`xcodeJunk`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Xcode 27.1 (27A9275), análise de
20/10/2026. **O grupo não apareceu na baseline deste Mac** (ver "Baseline observada"
e "Divergências conhecidas"); a spec vem quase toda da análise estática.

## Visão geral
`xcodeJunk` é **um único grupo** da categoria Detritos do Sistema, composto por
várias subtarefas. Cada subtarefa produz **um subgrupo** (nó intermediário com nome
próprio) cujos filhos são os itens removíveis (E1, E2). O grupo faz parte da lista
de grupos de Detritos do Sistema **em qualquer ambiente** (com ou sem sandbox),
ao contrário de Usuários Apagados/Backups/etc., que só entram fora da sandbox (E3).

Raiz de apoio: `X = ~/Library/Developer/Xcode` (E4).

| # | Subtarefa (identificador) | Raiz | Subgrupo exibido (nome interno) | Nível do item | Recomendado |
|---|---|---|---|---|---|
| 1 | DerivedData (`CMSystemJunkScanIdentifierXcodeDerivedData`) | `X/DerivedData` | "Xcode Derived Data" | cada filho direto | sim, exceto `ModuleCache.noindex` e `SymbolCache.noindex` |
| 2 | Archives (`…XcodeArchives`) | `X/Archives` | "Archives" | cada `*.xcarchive` dentro de cada subpasta de data | não |
| 3 | iOS DeviceSupport (`…XcodeiOSDeviceSupport`) | `X/iOS DeviceSupport` | "iOS Device Support" | cada filho direto | não |
| 4 | tvOS DeviceSupport | `X/tvOS DeviceSupport` | "tvOS Device Support" | cada filho direto | não |
| 5 | watchOS DeviceSupport | `X/watchOS DeviceSupport` | "watchOS Device Support" | cada filho direto | não |
| 6 | macOS DeviceSupport (`…XcodeMacOSDeviceSupport`) | `X/macOS DeviceSupport` | "macOS Device Support" | cada filho direto | não |
| 7 | DeviceLogs (`…XcodeDeviceLogs`) | `X/iOS Device Logs` | "Registros de Dispositivos iOS" | a raiz inteira (1 item) | **sim** |
| 8 | CoreSimulatorCaches (`…XcodeCoreSimulatorCaches`) | `~/Library/Developer/CoreSimulator/Caches` | "Caches do Xcode" | a raiz inteira (1 item) | não |
| 9 | ModuleCaches (`…XcodeModuleCaches`) | 3 pastas fixas (abaixo) | "Module Caches" | cada pasta fixa que existir | não |
| 10 | DocumentationCache (`…DocumentationCache`) | `X/DocumentationCache` | "Xcode Documentation Cache" | cada filho direto | não |
| 11 | Simulators (`…XcodeSimulators`) | `~/Library/Developer/CoreSimulator` + `simctl` | um subgrupo por runtime | cada dispositivo simulado | sim se o simulador estiver **indisponível** |
| 12 | DownloadedRuntimes (`…XcodeDownloadedRuntimes`) | `/Library/Developer/CoreSimulator` + `simctl runtime` | "Xcode Simulator Runtimes" | cada runtime | não |

Fontes: E1, E5–E16.

## Locais varridos
- `~/Library/Developer/Xcode/DerivedData` (E5, E4)
- `~/Library/Developer/Xcode/Archives` (E6, E4)
- `~/Library/Developer/Xcode/iOS DeviceSupport`, `…/tvOS DeviceSupport`,
  `…/watchOS DeviceSupport`, `…/macOS DeviceSupport` (E7, E4)
- `~/Library/Developer/Xcode/iOS Device Logs` (E8, E4)
- `~/Library/Developer/CoreSimulator/Caches` (E9, E4)
- Module caches (E10, E4):
  - `$DARWIN_USER_CACHE_DIR/org.llvm.clang/ModuleCache` — nome exibido `org.llvm.clang`
  - `$DARWIN_USER_CACHE_DIR/org.llvm.clang.<usuário>/ModuleCache` — nome exibido
    `org.llvm.clang.<usuário>` (`<usuário>` = nome curto da conta, `NSUserName`)
  - `~/Library/Developer/Xcode/DerivedData/ModuleCache` — nome exibido `com.apple.dt.xcode`
  - `$DARWIN_USER_CACHE_DIR` = `confstr(_CS_DARWIN_USER_CACHE_DIR)`, ex.
    `/var/folders/xx/…/C/` (equivale a `getconf DARWIN_USER_CACHE_DIR`).
- `~/Library/Developer/Xcode/DocumentationCache` (E11, E4)
- `~/Library/Developer/CoreSimulator/Devices/<UDID>` via `simctl` (E12)
- `/Library/Developer/CoreSimulator` + lista de runtimes via `simctl` (E14)

Todas as listagens de pasta são **não recursivas e ignoram ocultos** (filhos diretos,
sem arquivos com ponto) (E5, E7, E11).

## Inclusão
Regra geral de cada subtarefa: se a raiz não existe, ou a raiz está na lista de
ignorados da base, o resultado da subtarefa é vazio. Cada filho também passa pela
lista de ignorados (E5–E11).

1. **DerivedData** — cada filho direto de `DerivedData` vira item, **exceto** o
   filho chamado exatamente `ModuleCache` (ele é tratado pela subtarefa 9). Nome do
   item: o nome da pasta cortado no **último `-`** (ex.:
   `CleanYourMac-cudzrqllbzfuohercalisjtdtpyr` → `CleanYourMac`); se não houver `-`,
   o nome inteiro (ex.: `SDKExplicitPrecompiledModules`, `ModuleCache.noindex`) (E5).
   > O separador exato foi lido como uma string de 1 caractere ainda não confirmada;
   > `-` é o único que faz sentido com o formato `<Projeto>-<hash>` do Xcode.
2. **Archives** — para cada subpasta direta de `Archives` (o Xcode cria uma por data,
   ex. `2026-10-20`), lista os filhos diretos e aceita os que têm extensão
   `xcarchive` **e** contêm `Info.plist`. Nome do item, montado a partir do
   `Info.plist` do arquivo: `Name`, depois ` <CFBundleShortVersionString>`,
   depois ` (<CFBundleVersion>)` (ambos de `ApplicationProperties`), depois
   ` - <CreationDate>` formatada com data média e hora curta do locale. Campos
   ausentes são omitidos. Ex.: `MeuApp 1.2 (34) - 20 de out. de 2026 14:00` (E6).
3. **DeviceSupport (4 plataformas)** — cada filho direto da raiz vira item; nome = nome
   da pasta (ex. `17.2 (21C62)` ou `iPhone15,2 17.2 (21C62)`) (E7).
4. **Device Logs** — a pasta `iOS Device Logs` inteira é **um item** (E8).
5. **CoreSimulator Caches** — a pasta `Caches` inteira é **um item** (E9).
6. **Module Caches** — cada uma das três pastas fixas que **existir** vira item. Se
   nenhuma existir, a subtarefa é vazia (E10).
7. **Documentation Cache** — cada filho direto vira item, com nome
   `iOS <nome da pasta>` (E11).
8. **Simulators** — ver "Simuladores" abaixo (E12, E13).
9. **Runtimes baixados** — ver "Runtimes" abaixo (E14).

### Simuladores (subtarefa 11)
Pré-condições, todas obrigatórias (senão vazio) (E12, E13):
1. `~/Library/Developer/CoreSimulator` existe e não é ignorado.
2. **"Ferramentas atualizadas"** (`isUpToDate`): obtém o build do macOS
   (`ProductBuildVersion` de `/System/Library/CoreServices/SystemVersion.plist`) e o
   build do Xcode ativo (roda `/usr/bin/xcode-select -p`, pega o pai da pasta
   `Developer` e lê `ProductBuildVersion` de `version.plist`). Para cada nome
   conhecido `CoreSim` e `MobileDevice`, monta
   `$TMPDIR/com.apple.dt.Xcode.InstallCheckCache_<a>_<b>_<c>` com os três valores
   (nome, build do macOS, build do Xcode). Se **algum** desses arquivos não existir,
   considera "não atualizado" e **não lista simuladores**. Se qualquer build não puder
   ser lido, também "não atualizado".
3. `simctl` existe em
   `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl`
   (o app chama esse binário direto, **não** via `xcrun`). Se não existir, a subtarefa
   termina com erro.

Execução: `simctl list devices --json` (argumentos lidos: `list`, `devices`,
`--json`). Saída vazia → resultado vazio; JSON inválido ou sem dicionário `devices`
→ erro/vazio (E12).

Para cada chave de `devices`:
- Se a chave começa com `com.apple.CoreSimulator.SimRuntime.` é um runtime: o
  subgrupo tem o nome da chave e a "versão" é a chave sem esse prefixo (ex.
  `iOS-17-2`). Senão, a entrada cai no subgrupo especial **"não usados"**
  (`isUnused = true`), compartilhado por todas as chaves que não são runtime.
- Se a base mandar ignorar esse runtime (por nome do subgrupo), a chave é pulada.
- Para cada dispositivo do array: exige `udid`, `name` e `state` (strings). URL =
  `~/Library/Developer/CoreSimulator/Devices/<udid>`; tamanho = tamanho dessa pasta;
  disponível = booleano `isAvailable` ou, se ausente, `availability == "(available)"`.
  O item só entra se a pasta existir e não for ignorada.
- Estado: `Booted` → inicializado, `Creating` → em criação, outro → desligado.
- `availabilityError` (texto) é guardado como erro do item.
- **Recomendado = não disponível** (simulador órfão de runtime removido).

### Runtimes (subtarefa 12) (E14)
1. `/Library/Developer/CoreSimulator` existe e não é ignorado.
2. O buscador de runtimes precisa estar disponível (verifica as ferramentas de
   desenvolvedor, usando `/bin/sh` e `/usr/bin/xcode-select -p`).
3. Roda `simctl runtime list` em modo JSON (strings lidas: `runtime`, `list`,
   `--json`), com tempo limite e encerramento do processo no tempo limite; saída que não
   seja UTF-8 ou JSON válido → lista vazia.
4. De cada runtime lê `identifier` (UUID), `deletable` e `runtimeBundlePath`.
   Para cada caminho: se não for ignorado e existir, vira item com nome = último
   componente do caminho (ex. `iOS 17.2.simruntime`), tamanho do bundle e o
   `identifier` guardado para a remoção.
5. Subgrupo vazio → resultado vazio.

## Exclusão
- `DerivedData/ModuleCache` (vai para Module Caches) (E5).
- Entradas ocultas (nome com `.`) de todas as listagens (E5, E7, E11).
- Em Archives: entradas sem extensão `xcarchive` ou sem `Info.plist` (E6).
- Lista de ignorados da base de conhecimento, por caminho (todas as subtarefas) e por
  nome de runtime (simuladores). A base é cifrada; **regra nossa equivalente**: lista
  de ignorados do usuário (vazia por padrão) (E15).
- Simuladores cujo diretório de dados não existe (E13).
- Runtimes: provavelmente só os `deletable == true` (ver Divergências) (E14).

## Recomendado
- DerivedData: todos os filhos **menos** `ModuleCache.noindex` e `SymbolCache.noindex`;
  o subgrupo vem marcado (E5).
- iOS Device Logs: marcado (E8).
- Simuladores: marcados os **indisponíveis** (E13).
- Todo o resto (Archives, DeviceSupport, CoreSimulator Caches, Module Caches,
  Documentation Cache, Runtimes): **não** marcado (E6–E11, E14).

## Agrupamento e nome exibido
- Grupo: título "Detritos do Xcode"; ícone do grupo: o ícone próprio do CleanMyMac
  (nós: ícone do Xcode `com.apple.dt.Xcode`, ou um ícone genérico de ferramenta) (E2, E16).
- Subgrupos na ordem da tabela acima (ordem da fábrica de tarefas; a ordem na UI não
  foi observada). Nomes: o CleanMyMac traduz ao menos "Caches do Xcode" (CoreSimulator
  Caches) e "Registros de Dispositivos iOS" (Device Logs); os demais nomes internos
  estão em inglês. **Nós**: traduzir todos (Dados Derivados, Arquivos do Xcode,
  Suporte a Dispositivos iOS/tvOS/watchOS/macOS, Registros de Dispositivos iOS, Caches
  do Xcode, Caches de Módulos, Cache de Documentação, Simuladores, Runtimes de
  Simulador) (E2, E16).
- Ícones de itens (assets do CleanMyMac, nós fazemos os nossos): dados derivados,
  simulador e simulador não usado têm ícones próprios; demais usam ícone de pasta (E16).
- Simuladores: um subgrupo por runtime (nome do runtime legível, ex. `iOS 17.2` a
  partir de `iOS-17-2`) + um subgrupo "Não usados"; filhos = dispositivos (nome do
  `name` do simctl) (E12, E13).

## Cálculo de tamanho
Tamanho alocado recursivo da pasta/bundle (mesmo medidor dos caches) (E5–E14).
Simulador: tamanho de `Devices/<udid>`. Runtime: tamanho do `runtimeBundlePath`.

## Remoção
- Itens de arquivo (DerivedData, Archives, DeviceSupport, Device Logs, Caches,
  Module Caches, Documentation): removidos pelo removedor genérico de arquivos, como
  os caches do usuário (ver a spec de caches; **nós: apagar definitivamente**).
- Simulador: `simctl delete <udid>`, com encerramento no tempo limite; erro de
  execução → falha do item (E17). Existe uma variante de depuração que só registra
  `[SIMULATE]` sem apagar (E18).
- Runtime: `simctl runtime delete <identifier>` (E17).
- Antes de limpar, o grupo declara dependência dos apps **Xcode**
  (`com.apple.dt.Xcode`) e **Simulator** (`com.apple.iphonesimulator`): se estiverem
  abertos, pedir para fechá-los (E19).
- Não precisa de admin: tudo fica na pasta do usuário; runtimes em
  `/Library/Developer/CoreSimulator` são apagados pelo próprio `simctl` (E14, E17).

## Alertas e selos
- Pedido para fechar Xcode/Simulator antes de limpar (E19).
- Cartão na tela de Resultados: "<tamanho> de Detritos do Xcode Encontrados" e, após
  limpar, "<tamanho> de Dados Derivados do Xcode Removidos" (paráfrase; E2).
- Nenhum selo por item.

## Condição para o grupo aparecer
Evidência estática: o grupo está sempre na lista de grupos da categoria (E3); não há
flag de configuração nem versão mínima do Xcode. Observação: na baseline, os grupos
vazios de Detritos do Sistema aparecem com "0 KB", mas o Xcode **não aparece**.
Leitura do disco: a última análise terminou às 14:00 (horário local; chave
`Statistics.Module.JunkCleanup.LastScanCompleteDate` = 17:00 UTC) e **todas** as
entradas de `DerivedData` com conteúdo foram criadas às 14:40. Na hora da análise
havia só `GlucoTracker-…` (0 KB), `CoreSimulator/Caches` vazio, nenhum
Archives/DeviceSupport/Device Logs/DocumentationCache/module cache do clang, e
nenhum arquivo `InstallCheckCache` em `$TMPDIR` (portanto sem simuladores) (E20).
**Conclusão (inferida):** o grupo Xcode só aparece quando o total é maior que zero
(regra diferente dos outros grupos do sistema, que aparecem com 0 KB). **Nossa
regra: esconder o grupo `xcodeJunk` quando o tamanho total for 0.**

## requiresAdmin
- Análise: não
- Limpeza: não

## Evidências
- **E1** — pseudocódigo de `SystemJunkScanTasksFactory` (funções `xcodeDerivedData`,
  `xcodeArchives`, `iOSDeviceSupport`, `tvOSDeviceSupport`, `watchOSDeviceSupport`,
  `macOSDeviceSupport`, `iosDeviceLogs`, `coreSimulatorCache`, `moduleCache`,
  `moduleDocumentation`, `xcodeSimulators`, `simulatorRuntimes`) e símbolos: cada uma
  retorna um subgrupo `XcodeJunkSubGroupModel` ou lista de simuladores/runtimes.
- **E2** — `re-notes/static/JunkCleanupModule/localizable-pt-BR.json`: chaves
  `system_junk_xcode_junk_group_title`, `…_description`, `system_junk_xcode_caches_title`,
  `system_junk_xcode_device_logs_title`, `tiles_xcode_junk_normal_*`,
  `tiles_xcode_junk_completed_*`.
- **E3** — pseudocódigo de `Tagged.systemJunkGroupForEnvironment(isSandbox:)` e
  `allForEnvironment(isSandbox:)` (JunkCleanupModule): `xcodeJunk` está na lista fixa,
  junto com brokenPreferences/userLogs/documentVersions/userCaches; a segunda lista
  (deletedUsers, brokenStartupItems, systemLogs, backups, applicationLanguages,
  systemCaches, universalBinaries) só entra fora da sandbox.
- **E4** — pseudocódigo de `CMPaths` (SharedObjcUtils): `xcodeSupportURL`,
  `derivedData`, `archives`, `moduleCache`, `iOSDeviceSupport` e afins, `iOSDeviceLogs`,
  `xcodeDocumentationCache`, `coreSimulatorURL`, `coreSimulatorCachesURL`,
  `systemCoreSimulatorURL`, `llvmModuleCache`, `llvmUserModuleCache`,
  `darwinUserCaches` (usa `confstr`); strings do SharedObjcUtils.
- **E5** — pseudocódigo de `CMXcodeDerivedDataScanTask` (`scan`, `junkModelWithURL:`,
  `scanningPathsWithURL:`).
- **E6** — `CMXcodeArchivesScanTask` (`scan`, `archives`, `_modelsForArchivesAtURL:`,
  `_isValidArchiveAtURL:`, `_titleForArchiveAtURL:`, `dateFormatter`); strings
  `xcarchive`, `Info.plist`, ` (%@)`, ` - %@`.
- **E7** — `CMXcodeDeviceSupportJunkScanTask` (`scan`, `scanningPathsWithURL:`,
  construtores por plataforma).
- **E8** — `CMXcodeDeviceLogsScanTask::scan`.
- **E9** — `CMXcodeCoreSimulatorCachesTask::scan`.
- **E10** — `CMXcodeModuleCachesScanTask::scan`; strings `org.llvm.clang`,
  `org.llvm.clang.%@`, `com.apple.dt.xcode`, `Module Caches`.
- **E11** — `CMXcodeModuleDocumentationCachesScanTask` (`scan`, `junkModelWithURL:`);
  string `iOS %@`.
- **E12** — `CMXcodeSimulatorsScanTask` (`scan`, `_devicesInformationFromXcrunOutput:error:`,
  `_performScanWithDevicesInfo:`, `_scanForSimulatorsWithDevices:runtimeVersion:progress:`),
  `CMXcrunTaskFactory::simctlTaskWithArguments:error:`; strings `devices`, `--json`,
  `com.apple.CoreSimulator.SimRuntime.`.
- **E13** — `CMXcodeSimulatorModel::modelWithSimulatorInfo:…`,
  `_CMGetXcodeSimulatorModelState`, `CMXcodeSimulatorControl` (`isUpToDate`,
  `_knownInstallCacheNames`, `_buildXcodeInstallCacheURLWithName:…`,
  `_developmentToolsURL`, `_developmentToolsBuildVersion`, `_systemBuildVersion`);
  strings `CoreSim`, `MobileDevice`, `com.apple.dt.Xcode.InstallCheckCache_%@_%@_%@`.
- **E14** — `CMXcodeDownloadedRuntimesScanTask::scan`; `CMSimulatorRuntimesFetcher`
  (Swift, só strings de log/args: `runtime`, `list`, `identifier`, `deletable`,
  `runtimeBundlePath`, `/bin/sh`, `/usr/bin/xcode-select -p`, mensagens de timeout e
  de JSON inválido).
- **E15** — `XcodeJunkKnowledgeBase::shouldIgnoreURL:` e `::shouldIgnoreSimulatorRuntime:`
  (JunkCleanupModule): delegam a consulta à base cifrada.
- **E16** — strings do JunkCleanupModule: assets `system-junk_xcode-derived-data`,
  `system-junk_xcode-ios-simulator`, `system-junk_xcode-ios-simulator-unused`.
- **E17** — `XcodeSimulatorRemover::remove(uuid:)` (args `delete <uuid>`) e
  `XcodeSimulatorRuntimeRemover::remove(uuid:)` (args `runtime delete <uuid>`), ambos
  via `simctlTaskWithArguments:` com `setTerminateOnTimeout`.
- **E18** — strings `ConfigDependentXcodeSimulatorRemover`, `DebugXcodeSimulatorRemover`,
  `[SIMULATE]: Remove simulator`.
- **E19** — pseudocódigo de uma função do JunkCleanupModule que monta dependências de
  apps com os bundle ids `com.apple.dt.Xcode` e `com.apple.iphonesimulator`; string
  `ApplicationDependency`.
- **E20** — leitura do disco (só leitura): `stat` das entradas de
  `~/Library/Developer/Xcode/DerivedData` (criação 14:40, exceto `GlucoTracker-…`
  01:31, 0 KB); `~/Library/Developer/CoreSimulator/Caches` vazio; ausência de
  Archives/DeviceSupport/`iOS Device Logs`/DocumentationCache e de
  `org.llvm.clang*` no cache Darwin; nenhum `com.apple.dt.Xcode.InstallCheckCache*` em
  `$TMPDIR`; preferências do grupo de apps do CleanMyMac (data da última análise).
- **E21** — baseline `re-notes/ax/baseline-20261020-1457/Detritos do Sistema/_category.txt`:
  lista de grupos sem "Detritos do Xcode".

## Baseline observada
Grupo ausente. Lista de grupos da categoria na baseline (para conferência da posição):
Cache do Usuário 2,8 GB, Cache do Sistema 765 MB, Binários Universais 32 MB, Registro
do Usuário 16,1 MB, Registro do Sistema 10,1 MB, Idioma 213 KB, Itens de Início
Defeituosos 0 KB, Versões de Documentos 0 KB, Usuários Apagados 0 KB, Preferências
Defeituosas 0 KB, Backups iOS 0 KB (E21). O cartão de resultados também não mostrou
Xcode.

## Divergências conhecidas
- **Nada do grupo foi observado na UI.** Ordem dos subgrupos, nomes exibidos dos
  subgrupos sem chave de tradução, aparência dos simuladores e a regra "esconder com 0"
  são inferências. Recomendação: refazer a captura agora que `DerivedData` tem
  ~218 MB (CleanYourMac-…, SDKExplicitPrecompiledModules, ModuleCache.noindex,
  SDKStatCaches.noindex, CompilationCache.noindex) para confirmar nomes, marcações e
  posição do grupo.
- Separador do nome em DerivedData: assumimos o último `-` (não confirmado byte a byte).
- Ordem exata dos três valores no nome `InstallCheckCache_<a>_<b>_<c>` não confirmada.
  **Nossa regra:** em vez desse arquivo, considerar as ferramentas "atualizadas" quando
  `xcodebuild -checkFirstLaunchStatus` sair com 0 (verificação pública equivalente);
  se falhar, não listar simuladores.
- Runtimes: o código Swift do buscador não foi decompilado; o filtro por `deletable`
  e a forma exata da linha de comando (`simctl runtime list -j`) são inferidos das
  strings. **Nossa regra:** `xcrun simctl runtime list -j`, só entradas com
  `deletable == true` e `runtimeBundlePath` existente.
- `simctl list devices --json`: a ordem dos argumentos lida do array constante não foi
  confirmada; a forma acima é a documentada pela Apple.
- Lista de ignorados da base cifrada não reproduzida; usamos só a lista do usuário.
- Removedor genérico de arquivos: não investigado aqui; seguimos a mesma escolha da
  spec de caches (apagar definitivamente).
- Tradução: traduzimos todos os nomes de subgrupo (o CleanMyMac deixa vários em inglês).

## Checklist de testes
1. `~/Library/Developer/Xcode` ausente → grupo oculto (total 0).
2. `DerivedData/MeuApp-abcdefghijklmnop` (10 MB) → item "MeuApp", 10 MB, marcado.
3. `DerivedData/ModuleCache.noindex` (5 MB) → item "ModuleCache.noindex", **não** marcado;
   idem `SymbolCache.noindex`.
4. `DerivedData/ModuleCache` (pasta) → não aparece em Dados Derivados; aparece em
   Module Caches como "com.apple.dt.xcode".
5. `DerivedData/.DS_Store` → ignorado.
6. `DerivedData/SDKExplicitPrecompiledModules` → item com o nome inteiro, marcado.
7. `Archives/2026-10-20/MeuApp 20-10-26 14.00.xcarchive` com `Info.plist`
   (`Name=MeuApp`, `ApplicationProperties.CFBundleShortVersionString=1.2`,
   `CFBundleVersion=34`, `CreationDate`) → item "MeuApp 1.2 (34) - <data>", não marcado.
8. `Archives/2026-10-20/Quebrado.xcarchive` sem `Info.plist` → ignorado;
   `Archives/2026-10-20/notas.txt` → ignorado.
9. `iOS DeviceSupport/17.2 (21C62)` (3 GB) → item "17.2 (21C62)" no subgrupo iOS, não
   marcado; o mesmo para tvOS/watchOS/macOS.
10. `iOS Device Logs/` com 2 arquivos (1 MB) → um único item de 1 MB, marcado.
11. `~/Library/Developer/CoreSimulator/Caches` (200 MB) → um item "Caches do Xcode",
    não marcado.
12. `$DARWIN_USER_CACHE_DIR/org.llvm.clang/ModuleCache` existe e
    `org.llvm.clang.<usuário>/ModuleCache` não → só um item "org.llvm.clang".
13. `DocumentationCache/v257` → item "iOS v257", não marcado.
14. simctl JSON com chave `com.apple.CoreSimulator.SimRuntime.iOS-17-2` e dispositivo
    `isAvailable=false` com pasta `Devices/<udid>` existente → subgrupo iOS 17.2, item
    marcado; com `isAvailable=true` → não marcado.
15. Dispositivo sem campo `isAvailable` e `availability="(available)"` → disponível.
16. Dispositivo cuja pasta `Devices/<udid>` não existe → omitido.
17. Chave de `devices` que não começa com o prefixo de runtime → subgrupo "Não usados".
18. Ferramentas "não atualizadas" (verificação de primeiro uso falha) → nenhum
    simulador listado, sem erro.
19. simctl ausente → subtarefa de simuladores retorna erro, demais subtarefas seguem.
20. Runtime `deletable=true` com `runtimeBundlePath` existente → item com nome do
    bundle, não marcado; limpar chama `simctl runtime delete <identifier>`.
21. Limpar simulador → `simctl delete <udid>`; falha do processo → item com erro.
22. Xcode aberto ao limpar → pedir para fechar Xcode/Simulator.
23. Grupo com todos os itens de 0 bytes → grupo oculto.
