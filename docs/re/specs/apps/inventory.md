# Inventário de apps, filtros e ordenação (`appUninstall`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Análise do Desinstalador de
2026-10-21 15:21 (UTC−3). Baseline: `docs/re/parity/apps-baseline-2026-10-21.json`
(26 apps) e dumps AX em `re-notes/ax/apps-baseline-20261021-1521/`. Só leitura:
nada foi selecionado nem removido no CleanMyMac.

## Visão geral
O Desinstalador junta candidatos de três fontes, descarta por caminho, por
validade do bundle e por prefixo de bundle ID, agrupa cópias do mesmo app numa
linha e calcula para cada linha a loja, o fornecedor, a última abertura, se está
sem uso, se é de 32 bits e o tamanho total (app + arquivos relacionados) [E1–E6].
Plug-ins de áudio, jogos do Steam/Battle.net, apps do JetBrains Toolbox e apps
de iPhone/iPad vêm de carregadores próprios e entram na mesma lista [E7][E8].

## Locais varridos

### No CleanMyMac
1. **Varredura profunda de `/Applications`**: percorre a árvore e, ao achar um
   diretório `*.app`, cria o app e **não desce** dentro dele [E1].
2. **Lista de apps do LaunchServices** (API privada `_LSCopyAllApplicationURLs`):
   todos os apps registrados no sistema, em qualquer pasta [E1].
3. **Spotlight**: busca de itens do tipo `com.apple.application-bundle` em dois
   escopos, a pasta do usuário (inteira) e `/Applications` [E1].

As três listas são unidas sem repetir caminho [E1]. Por isso aparecem apps fora
de `/Applications`: nesta máquina, `~/Downloads/Hidden Bar.app`,
`~/Applications/Claude Code URL Handler.app` e três builds do GlucoTracker em
`~/Projetos/GUIGX/GlucoTracker/build/…` [E9].

### Regra nossa
1. Varredura profunda de `/Applications` e de `~/Applications`, sem descer em
   `*.app` e **sem seguir symlinks**.
2. Spotlight (`NSMetadataQuery`) com `kMDItemContentType == "com.apple.application-bundle"`
   nos escopos `NSMetadataQueryUserHomeScope` e `/Applications`.
3. **Não** usamos o LaunchServices privado (design: sem APIs privadas). Nesta
   máquina, as fontes 1 e 2 cobrem os 26 apps da baseline. Ver "Divergências".

Depois da união, cada caminho passa pelos filtros abaixo, nesta ordem.

## Exclusão

### 1. Por caminho (só "apps do usuário" entram)
O CleanMyMac aplica uma expressão regular ao caminho e descarta o app quando ela
casa [E2]. Em nossas palavras, fica de fora o app cujo caminho:
- começa com `/System` (a expressão abre exceção para caminhos com
  `Finder.app`, mas o Finder não aparece na baseline; provavelmente a base o
  ignora), `/Library`, `~/Library`, `/usr`, `/bin`, `/sbin`, `/etc`,
  `/dev`, `/tmp`, `/var`, `/private`, `/cores`, `/net`, `/Developer`,
  `/Applications/Developer Tools` ou `/Volumes` (discos externos não entram);
- começa com `/opt`, **exceto** `/opt/homebrew-cask/Caskroom`;
- está **dentro de outro app** (o caminho contém `.app/` seguido de mais
  componentes): helpers, apps de login, `XPCServices`, cópias em `Contents/` etc.;
- está dentro de uma pasta cujo nome tem ponto seguido de algo que não é número
  de versão nem `localized` (ex.: `Foo.bundle/X.app`, `Bar.framework/…/X.app`,
  `~/.Trash/X.app`). Pastas `Nome.localized` e `App 2.0` não excluem;
- contém `.pvm`, `.vmwarevm` ou `.backupdb` (máquinas virtuais e backups).

**Uma exceção fixa**: o caminho que termina em
`/Library/Application Support/Setapp/LaunchAgents/Setapp.app` é aceito, apesar de
estar em `~/Library` [E3]. Ele vira uma segunda cópia da linha "Setapp.app"
(ver "Agrupamento").

Efeitos nesta máquina [E9]:
- fora: `Safari.app` (symlink para `/System/Cryptexes/…`), os helpers de
  `/Library/Application Support/Logitech.localized/…` e de
  `/Library/Application Support/org.pqrs/…`, os apps dentro de
  `~/Library/Application Support` (Discord, Claude, Warp, GoogleUpdater, Setapp
  exceto o agente), as duas builds do CleanYourMac em
  `~/Library/Developer/Xcode/DerivedData`, os modelos do Script Editor em
  `/Library/Application Support`;
- dentro: `/Applications/Utilities/LogiPluginService.app` (a varredura de
  `/Applications` é profunda) e as builds do GlucoTracker em `~/Projetos/…`.

### 2. Bundle inválido
O app precisa ser um bundle válido (validador próprio do CleanMyMac) [E4].
Observado: `/Applications/Karabiner-Elements.app` é uma casca sem `Info.plist`
(só `Contents/` vazio) e **não aparece** [E9].
**Regra nossa:** válido = diretório real (não symlink) com
`Contents/Info.plist` legível, `CFBundleIdentifier` não vazio e o executável de
`CFBundleExecutable` presente em `Contents/MacOS`.

### 3. Prefixos de bundle ID ignorados
Ficam fora os apps cujo bundle ID **começa** com um destes valores [E5]:
`com.parallels.winapp`, `com.parallels.ApplicationGroupBridge`,
`com.vmware.proxyApp`, `com.codeweavers.CrossOverHelper` (atalhos de apps de
Windows em VMs/CrossOver), `com.google.Chrome.app.` (atalhos de PWAs do Chrome)
e `com.setapp.teaser` (atalhos de apps do Setapp ainda não instalados).
Observado: os quatro atalhos de `~/Applications/Chrome Apps.localized/`
(GitHub, GlobalWorks, Supabase Studio, Vercel; `com.google.Chrome.app.<id>`)
não viram linha [E9]. **Regra nossa:** a mesma lista (são identificadores
técnicos).

### 4. Apps de sistema (`/System/Applications`)
O CleanMyMac separa "apps de sistema" (caminho começando com
`/System/Applications`) dos "apps do usuário" e só os mostra se a preferência
de ignorar apps de sistema estiver desligada (`IsSystemApplicationsIgnored`;
não está gravada nesta máquina, logo vale o padrão) [E6]. Observado: nenhum
app de `/System/Applications` aparece entre os 26 [E9].
**Regra nossa (v0.2):** apps de sistema **não** entram na lista. Sem
preferência para mostrá-los. Ver `reset.md` sobre redefinir apps da Apple.

### 5. Ignorados pelo usuário
O CleanMyMac tem uma lista de bundle IDs ignorados [E6]. Fora da v0.2 (design).

### O que **não** é excluído
- **O próprio CleanMyMac aparece** na lista (`CleanMyMac.app`, 484 MB). Ao abrir
  os itens incluídos dele, a lista fica vazia (a baseline não tem nenhum tipo
  para ele) [E9]. Ele tem um fluxo de autodesinstalação à parte (ver
  `removal.md`).
- **O CleanYourMac aparece** e mostra os arquivos normalmente [E9].
- Apps da App Store protegidos pela Apple e apps de sistema protegidos (quando
  mostrados) **aparecem**, com o bundle não removível (ver "Protegido").

**Regra nossa:** o CleanYourMac aparece com os arquivos dele, mas não pode ser
desinstalado nem redefinido por ele mesmo (`isSelf`); o checkbox da linha fica
desabilitado. O CleanMyMac é, para nós, um app de terceiros comum.

## Agrupamento e nome exibido

### Agrupamento
Várias cópias viram **uma linha** com vários itens "Binários" [E9]:
- GlucoTracker: 4 binários (`/Applications` e as três builds de `~/Projetos`),
  todos com o mesmo nome de arquivo e o mesmo bundle ID `com.guigx.GlucoTracker`;
- Setapp: 2 binários, `/Applications/Setapp.app` (`com.setapp.DesktopClient`)
  e o agente `~/Library/Application Support/Setapp/LaunchAgents/Setapp.app`
  (`com.setapp.DesktopClient.SetappAgent`). Os dois têm o mesmo nome de arquivo,
  mas bundle IDs diferentes. Logo, a chave do grupo é o **nome do arquivo**, ou há
  um caso especial para o Setapp (o código marca como "app principal do Setapp"
  todo bundle ID que contém `com.setapp.DesktopClient`) [E3]. *A confirmar*.
- CleanYourMac: as duas builds de `DerivedData` estão em `~/Library` e já caíram
  no filtro de caminho, então a linha tem um só binário.

**Regra nossa:** a chave do grupo é o **bundle ID** (comparação exata, sem
diferenciar maiúsculas). A cópia principal é, nesta ordem: a de `/Applications`;
depois a de `~/Applications`; depois a de última abertura mais recente. As
outras cópias entram como itens "Binários" extras, **desmarcados** (ver
`related-files.md`). O agente do Setapp não entra (bundle ID diferente e está em
`~/Library`). Isso é uma divergência documentada.

### Nome exibido
- A linha mostra o **nome de exibição do arquivo**, com a extensão:
  `Logi Options+.app` para `/Applications/logioptionsplus.app`, `Bruno.app`,
  `Google Chrome.app` [E9]. É o nome que o Finder mostra
  (`FileManager.displayName(atPath:)`, que usa o nome localizado do bundle e
  respeita a opção de mostrar extensões). Nesta máquina coincide com
  `kMDItemDisplayName` [E9][E10].
- Internamente, para casar arquivos relacionados, o CleanMyMac usa outro nome:
  `CFBundleName` do `Info.plist` ou, sem ele, o nome do arquivo sem `.app` [E10].
  Ex.: `Code` (VS Code), `Chrome` (Google Chrome), `logioptionsplus` (Logi).

**Regra nossa:** `AppRecord.name` = nome de exibição do Finder, sempre com
`.app` no fim (paridade com a baseline). Se o sistema esconder a extensão, nós a
acrescentamos. Um segundo campo (nome de casamento) guarda `CFBundleName` (ou o
nome do arquivo sem `.app`) para `related-files.md`.

## Última abertura
- Fonte: Spotlight, `kMDItemLastUsedDate` do bundle (equivale ao último valor de
  `kMDItemUsedDates`) [E11]. Conferido nos 25 apps com dado: a data da linha é a
  `kMDItemLastUsedDate` da cópia principal, convertida para o fuso local [E12].
- **Nunca aberto** (sem `kMDItemLastUsedDate`): vale a data de modificação do
  conteúdo (`kMDItemContentModificationDate`, igual ao `mtime` do bundle).
  Observado em Bruno (20 ago, `mtime` do bundle), Claude Code URL Handler,
  GarageBand (5 mar), LogiPluginService (15 out) e Xcode (16 out) [E12]. Não é
  `kMDItemDateAdded` nem o `atime` (Bruno: adicionado em 8 set, `atime` 26 ago).
- Sem nenhuma das duas, o CleanMyMac usa **agora**, e o app nunca cai em "Não
  Usados" [E11].
- Com várias cópias (GlucoTracker, Setapp), a data mostrada é a da cópia de
  `/Applications` (20 out), que aqui também é a mais recente (as builds são de
  13 e 14 out). Não dá para saber, por esta máquina, qual das duas regras vale
  [E12].

**Regra nossa:** `lastOpened` = `kMDItemLastUsedDate` da cópia principal; sem
ele, `kMDItemContentModificationDate`; sem ele, o `contentModificationDate` do
próprio bundle (`URLResourceValues`); sem nenhum, `nil`. Com `nil`, o app não
entra em "Não Usados" e vai para o fim da ordenação por data. O texto da coluna é
a data no formato médio do idioma ("5 de mar. de 2026" em pt-BR).

## Última atualização
- No Desinstalador **não existe** ordenação por "Última Atualização". O menu de
  ordenação dele tem só Tamanho, Nome e Última Abertura, mais Crescente e
  Decrescente [E13]. A opção "Última Atualização" está no menu do
  **Atualizador**, junto com Última Abertura, Tamanho e Nome [E13]. A data dela
  é a da atualização disponível (ver `updater.md`).
- **Regra nossa:** `AppRecord.lastUpdated` = `kMDItemContentModificationDate` do
  bundle (sem ele, `contentModificationDate` de `Contents/Info.plist`). Serve
  para o Atualizador mostrar há quanto tempo o app instalado não muda e como
  desempate. Não aparece no Desinstalador.

## Cálculo de tamanho
- **Tamanho da linha = soma de todos os itens da linha**, inclusive todas as
  cópias em "Binários". GlucoTracker: 1,2 + 14,2 + 17,5 + 20,3 + 22,1 + 13,8 =
  89,1 MB [E9]. Setapp: 759 MB, com o agente contado duas vezes (como binário e
  dentro de `Application Support/Setapp`). O CleanMyMac **não** deduplica itens
  aninhados [E9][E14].
- **Tamanho de um bundle:** o CleanMyMac usa o `kMDItemPhysicalSize` do
  Spotlight quando existe, o que pode estar velho. Prova: as builds do
  GlucoTracker aparecem com 20,3 MB e 22,1 MB (valor do Spotlight), enquanto o
  `du` dá 34,5 MB e 32,5 MB hoje; o agente do Setapp, com 127 MB (Spotlight), contra
  74 MB no `du` [E14]. Sem valor no Spotlight (ChatGPT, Chrome, VS Code), soma a
  árvore: ChatGPT 1 416 400 KiB → "1,5 GB" [E14].
- Arquivos e pastas relacionados: espaço alocado, como em `common.md` §1.
- Unidades decimais e formatação: `common.md` §2.
- A linha do próprio CleanMyMac mostra 484 MB, mais que o `du` do bundle
  (439 MB). Hipótese: soma os arquivos dele sem listá-los. *A confirmar*.

**Regra nossa:** cada item é medido com `FileSizer.allocatedSize(of:)`, sem
Spotlight e sem seguir links (`common.md` §1). O tamanho da linha é a soma dos
itens **sem contar duas vezes** um item que esteja dentro de outro (por
caminho). Divergência intencional: o número é o que a remoção libera de fato. A
tolerância de paridade (1 % ou 1 MB) não cobre os valores velhos do Spotlight
nas builds do GlucoTracker e no agente do Setapp; isso fica registrado como
diferença esperada.

## Lojas (filtro "Lojas")
Regra do CleanMyMac [E15]:
- **Setapp**: o bundle ID **termina com** `-setapp`. Tem prioridade sobre a App
  Store.
- **App Store**: existe `Contents/_MASReceipt/receipt` no bundle.
- **Steam** e **Battle.net**: só para os jogos que os carregadores próprios
  acham (Steam: bibliotecas de `libraryfolders.vdf` e manifestos de
  `steamapps`; Battle.net: pasta de instalação lida de `Battle.net.config`,
  `Client/Install/DefaultInstallPath`) [E8].
- **Outro**: todo o resto.

Nesta máquina (baseline: appStore 3, setapp 1, outro 22) [E9][E16]:

| Filtro | Apps | Por quê |
|---|---|---|
| App Store (3) | GarageBand, WhatsApp, Xcode | têm `_MASReceipt/receipt` |
| Setapp (1) | CleanMyMac | `com.macpaw.CleanMyMac-setapp` |
| Outro (22) | Bruno, ChatGPT, Claude Code URL Handler, Claude, CleanYourMac, Discord, GlucoTracker, Google Chrome, Hidden Bar, Logi Options+, LogiPluginService, MacICNS, Obsidian, Perssua, Setapp, Spotifast, TeamSpeak, UTM, Visual Studio Code, Vorssaint, Warp, Zed | nenhum dos dois |
| Steam / Battle.net (0) | — | sem jogos instalados; o CleanMyMac esconde lojas com 0 |

O próprio `Setapp.app` (`com.setapp.DesktopClient`) cai em **Outro**: a regra é
o sufixo do bundle ID, não a pasta.

**Regra nossa:** igual para Setapp e App Store (são fatos técnicos fortes). Para
Steam: app dentro de `<biblioteca>/steamapps/common/` de uma das bibliotecas
listadas em `~/Library/Application Support/Steam/steamapps/libraryfolders.vdf`.
Para Battle.net: app dentro da pasta de instalação do `Battle.net.config`. Os
dois só entram se o arquivo de configuração existir e for legível. Filtros com
contagem 0 ficam escondidos, como no CleanMyMac.

## Fornecedores (filtro "Fornecedores")
Regra do CleanMyMac: **prefixo do bundle ID**, numa tabela fixa [E17]. Não usa
o Team ID: o Setapp (`MEHY5QF425`) e o CleanMyMac (`S8EX82NJP6`) têm Team IDs
diferentes e caem os dois em MacPaw; GarageBand (`F3LWYJ7GM7`) e Xcode
(`59GAB85EFG`) também diferem e caem os dois em Apple [E16].

| Fornecedor | Prefixos (comparação literal do início) |
|---|---|
| Apple | `com.apple`, `developer.apple.` |
| Google | `com.google.` |
| MacPaw | `com.macpaw`, `com.setapp`, `cx.c3.xee3`, `cx.c3.theunarchiver`, `cx.c3.thearchivebrowser` |
| JetBrains | `com.jetbrains`, `org.jetbrains`, `com.kotlinconf.iosapp` (e os apps do JetBrains Toolbox [E8]) |
| Microsoft | `com.microsoft.`, `com.skype.`, `com.followanalytics.adventureworks.msdc365` |
| Adobe | `com.adobe`, `adobe.` |
| Outros | o resto |

Nesta máquina (baseline: apple 2, google 1, macPaw 2, microsoft 1, outros 20)
[E9][E16]:

| Filtro | Apps | Bundle ID |
|---|---|---|
| Apple (2) | GarageBand, Xcode | `com.apple.garageband10`, `com.apple.dt.Xcode` |
| Google (1) | Google Chrome | `com.google.Chrome` |
| MacPaw (2) | CleanMyMac, Setapp | `com.macpaw.CleanMyMac-setapp`, `com.setapp.DesktopClient` |
| Microsoft (1) | Visual Studio Code | `com.microsoft.VSCode` |
| Outros (20) | Bruno, ChatGPT, Claude Code URL Handler, Claude, CleanYourMac, Discord, GlucoTracker, Hidden Bar, Logi Options+, LogiPluginService, MacICNS, Obsidian, Perssua, Spotifast, TeamSpeak, UTM, Vorssaint, Warp, WhatsApp, Zed | — |
| JetBrains / Adobe (0) | — | escondidos |

**Regra nossa:** a mesma tabela, com uma correção de segurança que não muda
nenhuma contagem aqui: os prefixos sem ponto final (`com.apple`, `com.macpaw`,
`com.setapp`, `com.jetbrains`, `org.jetbrains`, `com.adobe`) casam só com o
valor exato ou seguido de `.` ou `-` (assim, `com.applesauce.x` não vira Apple).
O fornecedor da linha é o da cópia principal.

## Não Usados
- Regra do CleanMyMac: a última abertura (com o fallback acima) é **anterior a
  "agora menos 6 meses de calendário"** [E18]. Antes disso, há uma checagem de
  um atributo do app que, quando verdadeiro, impede que ele conte como não usado.
  O atributo exato não foi identificado; a hipótese mais provável é "app de
  sistema". *A confirmar*.
- Nesta máquina (análise em 21 out 2026, limite em 21 abr 2026): só o
  **GarageBand** (5 mar 2026). O próximo mais antigo é o Bruno (20 ago) [E9][E12].
- Apps nunca abertos não são tratados à parte: valem pela data de modificação
  (Bruno, LogiPluginService e Xcode, todos recentes, não entram).

**Regra nossa:** `isUnused = lastOpened != nil && lastOpened < Calendar.current.date(byAdding: .month, value: -6, to: inícioDaAnálise)`.
Apps protegidos e o próprio CleanYourMac nunca contam.

## 32 bits
- Regra do CleanMyMac: lê as arquiteturas do executável principal. Se houver a
  de 64 bits (x86_64), não é 32 bits. Se não houver e houver i386, é [E19].
- Nesta máquina: 0 (o filtro nem aparece; o cartão de resultados também não).
- **Regra nossa:** lemos o cabeçalho Mach-O (fino ou universal) de
  `Contents/MacOS/<CFBundleExecutable>`. É 32 bits quando tem fatia i386 ou ppc
  e **nenhuma** de 64 bits (x86_64, arm64, arm64e). Executável ilegível ou que
  não é Mach-O (script) → não é 32 bits.

## Plug-ins de Áudio
- Regra do CleanMyMac [E7]: um carregador próprio lista os filhos de cada
  subpasta de `~/Library/Audio/Plug-Ins` e `/Library/Audio/Plug-Ins`, mais a
  pasta `/Library/Application Support/Avid/Audio/Plug-Ins` (AAX). Formatos
  conhecidos: VST3, Component (Audio Unit), Driver (HAL), CLAP, LADSPA, RTAS,
  cada um com a sua extensão de pacote; as pastas `Presets` e `Audio/Presets`
  entram como recursos do plug-in.
- O texto do filtro fala em plug-ins "de terceiros", mas nada no código filtra
  a Apple.
- **O 1 desta máquina** é `/Library/Audio/Plug-Ins/HAL/ParrotAudioPlugin.driver`
  (`com.apple.audio.ParrotAudioPlugin`, dono root, instalado pelo macOS pelo
  pacote `com.apple.files.data-template`). É o **único** pacote em todas as
  pastas de plug-ins de áudio desta máquina (as demais subpastas, como `VST`,
  `Components`, `MAS` e `Digidesign`, estão vazias) [E20]. O clique no filtro pelo
  `dump-ax` não trocou a lista (o item da barra lateral não respondeu), então a
  linha em si não foi vista. *A confirmar visualmente*.
- **Regra nossa:** mesmas pastas, subpastas por formato e extensões: `.vst`,
  `.vst3`, `.component`, `.driver`, `.clap`, `.aaxplugin`, `.dpm` (RTAS),
  `.so`/pasta LADSPA. Cada pacote vira uma linha `kind = .audioPlugin`. **Plug-ins
  com bundle ID `com.apple.*` ou instalados por recibo `com.apple.*` aparecem
  (paridade de contagem), mas são protegidos**: checkbox desabilitado, sem
  remoção. Plug-ins em `/Library` exigem o helper para remover.

## Protegido
No CleanMyMac, o bundle de um app **não é removível** quando [E21]:
- o `Info.plist` dele está protegido pelo SIP (`isRestricted`), o que vale para
  os apps de `/System/Applications` e os links do Cryptex; ou
- a base cifrada marca o bundle ID como protegido (`isAppProtectedWithBundleId:`).

O app protegido **aparece na lista** (quando não for filtrado antes); só o item
"Binários" fica não removível, com uma explicação de que dá para remover os
arquivos relacionados e assim redefinir o app [E21]. Apps da App Store que a
Apple não deixa remover falham na remoção com uma explicação própria (ver
`removal.md`). Nesta máquina, **nenhum** dos 26 é protegido: GarageBand e Xcode
(da Apple, pela App Store) não têm a flag do SIP, e o Safari, que tem, foi
excluído pelo caminho [E9][E16].

**Regra nossa:** `isProtected` = o `Info.plist` tem `SF_RESTRICTED` em
`st_flags`, ou o caminho real está em `/System`, ou o bundle ID está na nossa
lista fixa de apps que o macOS reinstala sozinho (Safari e afins; ver
`reset.md`). O app protegido só pode ser redefinido. Na v0.2 ele quase nunca
aparece, porque `/System/Applications` está fora da lista.

## Ordenação
- Opções do Desinstalador: **Nome**, **Tamanho**, **Última Abertura**, cada uma
  em ordem **Crescente** ou **Decrescente** [E13].
- Estado visto ao abrir: Nome, crescente (`Bruno`, `ChatGPT`,
  `Claude Code URL Handler`, `Claude`, `CleanMyMac`, `CleanYourMac`…). Não se
  sabe se é o padrão de fábrica ou a última escolha guardada.
- Nome: comparação localizada sem diferenciar maiúsculas, como no Finder
  (`Claude Code URL Handler.app` vem antes de `Claude.app`; `Logi Options+.app`
  antes de `LogiPluginService.app`).
- Tamanho crescente: Claude Code URL Handler (4,1 KB), Hidden Bar, MacICNS …
  Xcode (4,9 GB), Google Chrome (6,1 GB). O CleanMyMac entra na ordenação
  normalmente [E13].
- Última Abertura crescente: GarageBand, Bruno, Visual Studio Code, Obsidian…
  Usa a hora, não só o dia: no mesmo dia 20 out, UTM (03:08) < Perssua (03:09)
  < Setapp (04:59) < Logi (13:41) < Claude Code URL Handler (15:01, data de
  modificação) < Hidden Bar < Claude < GlucoTracker < CleanYourMac (22:11)
  [E12][E13].

**Regra nossa:** as mesmas três chaves e as duas direções. Padrão: Nome,
crescente. Desempate: nome. Sem `lastOpened` vai para o fim nas duas direções.
A escolha fica guardada em `UserDefaults` (por seção).

## Remoção
Fora do escopo deste documento: ver `removal.md` (destino Lixo, helper) e
`reset.md`.

## Alertas e selos
- Texto de ajuda no item protegido (nosso texto).
- CleanYourMac: linha com o checkbox desabilitado e uma dica dizendo que ele não
  se desinstala sozinho.

## requiresAdmin
- Análise: não (os metadados de contêineres e algumas pastas exigem Acesso Total
  ao Disco, não root).
- Limpeza: ver `removal.md`.

## Evidências
- **E1**: ApplicationsService, `CMSystemApplicationsProvider`
  (`_findAllApplications_NonSandboxed`, `_createApplicationsArrayInPathDeep:`,
  `_spotlightAppsURLs`), decompilados: varredura profunda que pula
  descendentes ao achar `.app`, chamada a `_LSCopyAllApplicationURLs` e consulta
  `CMMetadataSearchQueryFactory` com os escopos `NSMetadataQueryUserHomeScope` e
  `/Applications` para `com.apple.application-bundle`; junção por caminho.
- **E2**: string da expressão regular de exclusão em ApplicationsService (lista
  de prefixos, exceção do Caskroom e do Finder, `.app/`, `.pvm`, `.vmwarevm`,
  `.backupdb` e a regra de pasta com ponto), formatada com `~/Library`; usada
  por `CMApplicationInfo isUserAppAtPath:`.
- **E3**: bloco de filtro de `CMSystemInfo _findAllApplications`
  (ApplicationsService): aceita o app quando ele é "do usuário" **ou** termina
  com `/Library/Application Support/Setapp/LaunchAgents/Setapp.app`;
  `isSetappMainApp` = bundle ID contém `com.setapp.DesktopClient`.
- **E4**: `CMApplicationInfo isValidWithPath:` → `CMBundleValidator isValidApplicationAtPath:`.
- **E5**: strings de ApplicationsService (prefixos ignorados) e o bloco de
  filtro de `_findAllApplications` que descarta por `hasPrefix:`.
- **E6**: `isSystemApp` = caminho começa com `/System/Applications`;
  `UninstallerScanResult(userApplications:systemApplications:steamApplications:…)`;
  `UninstallerKnowledgeBaseFactory.build(ignoredAppBundleIDs:isSystemApplicationsIgnored:)`;
  chave `IsSystemApplicationsIgnored` em SharedPreferences; `defaults read` sem a
  chave.
- **E7**: UninstallerScanning: `AudioPluginLoader` (diretórios do usuário, raiz
  e Avid), `AudioPluginFormat` (`directoryName`, `bundleExtension`), strings
  `VST3`, `Component`, `Driver`, `CLAP`, `LADSPA`, `RTAS`,
  `/Library/Application Support/Avid/Audio/Plug-Ins`, `Presets`, `Audio/Presets`.
- **E8**: UninstallerScanning: `CMSteamApplicationLoader` (`libraryfolders.vdf`,
  `steamapps`, `appid`, `installdir`), `CMBlizzardApplicationLoader`
  (`Battle.net.config`, `Client`, `Install`, `DefaultInstallPath`,
  `net.battle.bootstrapper`, `_retail_`), `CMJetBrainsToolboxApplicationsLoader`
  (`JetBrains`, `Toolbox`, `apps`), `MobileUninstallerApplication`.
- **E9**: observação AX da baseline (`filter-*.txt`, `app-*.txt`) comparada com o
  disco: `mdfind "kMDItemContentType == com.apple.application-bundle"`, `ls`,
  `defaults read …/Info CFBundleIdentifier`, `ls -lO` (flags) e `du -sk`.
- **E10**: `CMApplicationInfo displayName` (`displayNameAtPath:`) e `name`
  (`CFBundleName`, senão o último componente sem extensão), decompilados.
- **E11**: `CMApplicationInfo lastUsedDate` (via `lastAccessDateAtPath:`; sem
  valor, usa a data atual) e `usedDates` (`MDItemCopyAttribute(kMDItemUsedDates)`).
- **E12**: `mdls -name kMDItemLastUsedDate -name kMDItemContentModificationDate -name kMDItemDateAdded`
  dos 26 bundles × datas da baseline (todas batem; os cinco sem
  `kMDItemLastUsedDate` batem com `kMDItemContentModificationDate`).
- **E13**: observação AX de 2026-10-21 (`re-notes/ax/t2-sortmenu-*`,
  `t2-sorted-*`, `t2-upd-*`): itens do menu de ordenação do Desinstalador e do
  Atualizador, e as listas reordenadas (a ordenação foi devolvida para Nome,
  crescente).
- **E14**: `mdls -name kMDItemPhysicalSize` × `du -sk` nas cópias do GlucoTracker,
  no agente do Setapp e no CleanMyMac.
- **E15**: `CMApplicationInfo store` (Setapp tem prioridade sobre App Store),
  `isSetappApp` (sufixo `-setapp`), `isFromAppStore` (`Contents/_MASReceipt/receipt`
  acessível); chaves de filtro de Steam e Battle.net em ApplicationsModule.
- **E16**: `codesign -dv` (Team IDs) e `ls Contents/_MASReceipt` dos apps da
  lista.
- **E17**: `CMApplicationInfo vendor` → `vendorForBundleID:`; tabela de prefixos
  nas strings de ApplicationsService, na ordem Apple, Adobe, Google, MacPaw,
  JetBrains, Microsoft.
- **E18**: `UninstallerApplicationType.isUnusedForSixMonths` (ApplicationsModuleDomain,
  decompilado): soma −6 meses à data atual pelo calendário e compara com
  `lastUsedDate`, depois de uma checagem prévia de um atributo do app.
- **E19**: `CMApplicationInfo is32BitsOnly` (decompilado), sobre `archs`.
- **E20**: `find /Library/Audio/Plug-Ins ~/Library/Audio/Plug-Ins …`,
  `defaults read …/ParrotAudioPlugin.driver/Contents/Info`, `codesign -dv` e
  `pkgutil --file-info`; o clique em "Plug‑ins de Áudio" pelo `dump-ax` não mudou
  a lista (também no dump da baseline, que repete a lista de "Outros").
- **E21**: `CMResourcesFetcher fetchAllResourcesForApplication:addAppBundleToResourceList:`
  (bundle removível = não restrito e não protegido pela base) e
  `CMApplicationInfo isRestricted` (`isFileRestricted:` no `Info.plist`); chaves
  `protected_system_application_info` e
  `error_description_bundle_exclusion_app_cannot_be_removed_format`.

## Divergências conhecidas
- **Sem LaunchServices privado**: um app registrado só no LaunchServices, fora
  de `/Applications`, `~/Applications` e da pasta do usuário indexada pelo
  Spotlight, não aparece para nós (ex.: app no Caskroom antigo de `/opt`, ou em
  pasta excluída do Spotlight). Nesta máquina, nenhum.
- **Agrupamento por bundle ID**: o agente do Setapp não vira segundo binário da
  linha Setapp. As cópias extras com o mesmo bundle ID entram desmarcadas.
- **Tamanho**: sem Spotlight e sem contar duas vezes itens aninhados. Setapp e
  GlucoTracker ficam menores que na baseline.
- **Fornecedor**: prefixos sem ponto exigem fronteira (`.` ou `-`).
- **Apps de sistema**: nunca listados na v0.2 (o CleanMyMac permite mostrá-los
  por preferência).
- **Plug-ins de áudio da Apple**: listados, mas sempre protegidos.
- **CleanMyMac**: para nós é um app comum, com os arquivos relacionados dele
  listados. Na baseline, a linha dele não tem detalhe.

## Checklist de testes
1. Árvore falsa com `/Applications/A.app`, `/Applications/Sub/B.app`,
   `/Applications/A.app/Contents/Library/LoginItems/H.app` → A e B; H fica fora.
2. `X.app` symlink em `/Applications` → fora.
3. `Casca.app` sem `Info.plist` → fora.
4. Bundle ID `com.google.Chrome.app.abc` em `~/Applications/Chrome Apps.localized/` → fora.
5. App em `~/Library/Application Support/Foo/Foo.app` e em `/Volumes/Ext/Foo.app` → fora.
6. App em `~/Downloads/Foo.app` (indexado) → dentro.
7. Duas cópias com o mesmo bundle ID → uma linha; principal = a de `/Applications`;
   a outra em "Binários", desmarcada; tamanho sem dupla contagem.
8. `com.foo.bar-setapp` com `_MASReceipt` → Setapp; só `_MASReceipt` → App Store.
9. `com.apple.dt.Xcode` → Apple; `com.applesauce.x` → Outros; `com.macpaw-labs.x` → MacPaw;
   `com.microsoftx.y` → Outros.
10. `kMDItemLastUsedDate` ausente → usa a data de modificação; os dois ausentes →
    `nil`, fora de "Não Usados", fim da ordenação.
11. Última abertura há 6 meses e 1 dia → Não Usado; há 5 meses e 29 dias → não.
12. Executável só i386 → 32 bits; universal i386+x86_64 → não; script → não.
13. `/Library/Audio/Plug-Ins/HAL/X.driver` com `com.apple.*` → linha de plug-in
    protegida; `~/Library/Audio/Plug-Ins/VST3/Y.vst3` → linha removível.
14. `Info.plist` com `SF_RESTRICTED` → `isProtected`.
15. CleanYourMac → aparece, com `isSelf` e checkbox desabilitado.
16. Ordenação por Última Abertura com horas diferentes no mesmo dia → ordem pela
    hora; Nome → `Claude Code URL Handler.app` antes de `Claude.app`.

## Baseline observada (2026-10-21)
26 apps; filtros: todos 26, não usados 1 (GarageBand), suspeitos 0, selecionados
0, App Store 3, Setapp 1, Outro 22, Apple 2, Google 1, MacPaw 2, Microsoft 1,
Outros 20, Plug-ins de Áudio 1 (ParrotAudioPlugin.driver, inferido).
