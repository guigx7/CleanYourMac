# Arquivos relacionados de um app (`ResourceKind`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Baseline de 2026-10-21 15:21
(UTC−3): `docs/re/parity/apps-baseline-2026-10-21.json` e
`re-notes/ax/apps-baseline-20261021-1521/app-*.txt`. Comparação com o disco feita
só com leitura (`ls`, `du`, `mdls`, `defaults read`, `plutil -p`, `codesign -d`,
`pkgutil`, `osascript` para listar itens de início).

## Visão geral

### Como o CleanMyMac procura
Para cada app, uma lista fixa de buscadores roda em sequência, e cada um devolve
recursos com um **tipo interno** (máscara de bits) [E1]. A tela agrupa os tipos
nos grupos que o usuário vê. O CleanMyMac também roda os mesmos buscadores para
cada app encontrado **dentro** do bundle (`Contents/Library` e `Contents/MacOS`,
ex.: os helpers do Setapp em `Contents/Library/LaunchServices`) e junta tudo na
linha do app principal [E2]. Fora isso, uma parte vem da base cifrada
(`info.cmmkb`, buscador "arquivos extras da base"), que não deciframos [E3].

Casamento de nomes usado pela maioria dos buscadores, sempre só nos **filhos
diretos** da pasta (sem recursão, sem seguir links) [E4]:
- o nome do filho é comparado **em minúsculas**; num **arquivo**, a extensão sai
  antes (`com.openai.codex.plist` → `com.openai.codex`); numa **pasta**, o nome
  fica inteiro;
- **por bundle ID**: casa quando o nome do filho **contém** o bundle ID em
  qualquer posição (substring);
- **por nome do app** (`CFBundleName`, ou o nome do arquivo sem `.app`): o nome do
  filho é quebrado em palavras por espaço, e cada palavra do nome do app tem de
  aparecer entre elas;
- **trava de versão**, aplicada antes das duas: se o nome do filho **começa** com
  o termo procurado e o resto contém **algum dígito**, o filho é rejeitado.
  Exemplos desta máquina: `com.anthropic.claudefordesktop.ShipIt.C60F8F5A-…`
  (ByHost), `com.google.Chrome.7kmmTi` e `MacICNS_2026-10-21-…` ficam fora
  desse casamento; `com.google.Chrome.EwEVXI` entra [E4][E5];
- tudo passa por fim no filtro "ignorado ou de sistema" da base cifrada [E3].

### Como nós procuramos (regra forte)
Nossa regra é um **subconjunto** da do CleanMyMac (design): mesmas pastas, mas
casamento mais estrito. Definições usadas abaixo:
- **`id(x)`**: o nome do filho (sem extensão, se for arquivo), comparado sem
  diferenciar maiúsculas, é **igual** ao bundle ID do app, ou começa com o bundle
  ID seguido de `.` **e o resto não tem dígito** (`com.foo.App.helper`,
  `com.foo.App.ShipIt`). Nunca casa por substring no meio
  (`2BBY89MBSN.dev.warp` não é de `dev.warp`), nem por prefixo sem ponto
  (`com.apple.dt.xcodebuild` não é de `com.apple.dt.Xcode`).
- **`nome(x)`**: o nome do filho (sem extensão, se for arquivo) é **igual**, sem
  diferenciar maiúsculas, ao nome de casamento do app (`CFBundleName`, ou o nome
  do arquivo sem `.app`) e tem pelo menos 3 caracteres. Não casa por palavras
  soltas (`Claude - ask.workflow`, `claude-cli-nodejs` não são do Claude).
- **Travas comuns**: nunca seguimos symlinks (o filho que é link não entra);
  nunca entra item `com.apple.*` de um app que não seja `com.apple.*`; nunca
  entra item que casa com dois apps instalados (empate → fica fora); nunca
  entra nada fora das raízes listadas aqui; nunca entra item de outro usuário.

`$C` = `getconf DARWIN_USER_CACHE_DIR` (`/var/folders/…/C`) e `$T` =
`getconf DARWIN_USER_TEMP_DIR` (`/var/folders/…/T`).

## Tipos, pastas e critério

A tabela resume. Os detalhes vêm depois.

| `ResourceKind` | Grupo na tela | Tipo interno do CleanMyMac | Pastas do CleanMyMac | Nossa regra |
|---|---|---|---|---|
| `binaries` | Binários | 4 | o bundle e cópias da mesma linha | o bundle e as cópias com o mesmo bundle ID |
| `supportingFiles` | Arquivos de Suporte | 0x20 (suporte), 2 (caches e temporários) | `~/Library/Application Support`, `/Library/Application Support`, `~/Library/Caches`, `$C`, `$T` | `id` ou `nome` nas mesmas pastas |
| `preferences` | Preferências | 1 | `~/Library/Preferences`, `/Library/Preferences` | `id` (arquivo `.plist`) ou `nome` (pasta) |
| `container` | Contêiner | 0x20000 | `~/Library/Containers/<bundle ID>` do app; às vezes contêineres de extensões e um grupo | só `~/Library/Containers/<bundle ID>` exato |
| `userData` | Dados de Usuário | 0x10 | filhos de `~/Library` e `/Library`; `Data/Library/<Nome>` do contêiner | `id` ou `nome` em `~/Library` e `/Library`, fora das pastas padrão do macOS |
| `logs` | Registros | 8 (registros), 0x40 (relatórios de falha) | `~/Library/Logs`, `/Library/Logs`, relatórios de falha | `id` ou `nome`; relatórios com prefixo `<Nome>_` |
| `loginItems` | Itens de Início | 0x100, 0x8000, 0x200 | itens de início da sessão, helpers de login, plists do launchd | item de sessão do próprio app; plists com vínculo exato |
| `dockIcon` | Ícone do Dock | 0x1000 | `persistent-apps` do Dock | não listado na v0.2 |
| `plugins` | Plug-ins | 0x80 | pastas de plug-ins e `PDF Services` | plug-in cuja cópia está dentro do app |
| `help` | Ajuda | 0x2000 | ajuda instalada fora do app | `/Library/Documentation/Applications/<Nome>` exato |
| `installers` | Instaladores | 0x40000 | `.dmg` em `~/Downloads` | `~/Downloads/<Nome>.dmg` exato |
| `other` | Outros | vários (base) | itens da base cifrada (`.vscode`, `Chrome Apps.localized`) | recibos de pacote (ver abaixo) |
| `applications` | Aplicativos | 4 (apps internos) | apps internos de jogos do Steam/Battle.net | igual, só para linhas do Steam/Battle.net |
| `crashes` | Relatórios de Falha | — | o grupo existe, mas os relatórios de falha aparecem em Registros | não usado na v0.2 |

A coluna "Grupo na tela" usa os rótulos do CleanMyMac só para identificar o
que foi observado. Os rótulos da nossa UI vêm de `App/Resources/Strings.tsv`.

Ordem dos grupos na tela: alfabética pelo nome do grupo; dentro do grupo, os
itens vêm em ordem alfabética sem diferenciar maiúsculas
(`com.setapp.defaults.plist` antes de `com.setapp.DesktopClient.plist`) [E6].
O nome do item é o último componente do caminho.

### `binaries`
- CleanMyMac: o bundle do app (removível, salvo se protegido; ver
  `inventory.md`) e as outras cópias da mesma linha (GlucoTracker: 4) [E6][E7].
- **Regra nossa:** o bundle principal **marcado**; as cópias com o mesmo bundle
  ID que o inventário achou, **desmarcadas** (podem ser builds de
  desenvolvimento). Bundle protegido → item presente, mas não selecionável.

### `supportingFiles`
- CleanMyMac [E8][E9]:
  - suporte: em `~/Library/Application Support` e `/Library/Application Support`,
    um pedido por bundle ID e outro por nome; mais uma pasta fixa da pasta do
    usuário que não identificamos;
  - caches: `~/Library/Caches` e `$C`, por bundle ID e por nome;
  - temporários: `$T`, por bundle ID e por nome.
  Não olha `/Library/Caches`, `~/Library/HTTPStorages`, `~/Library/WebKit`,
  `~/Library/Application Scripts` nem `~/Library/Group Containers` (nenhum item
  desses aparece na baseline, apesar de existirem para quase todos os apps).
- **Regra nossa:** `id` ou `nome` nessas cinco pastas. Exemplos que batem:
  `~/Library/Application Support/Claude` (`nome`), `~/Library/Caches/com.anthropic.claudefordesktop.ShipIt`
  (`id` com sufixo), `$C/com.openai.codex.helper`, `$T/com.google.Chrome.EwEVXI`,
  `/Library/Application Support/GarageBand` (`nome`, exige o helper para remover).
- Marcado: sim, salvo os que exigem admin sem o helper aprovado.

### `preferences`
- CleanMyMac [E10]: varre a lista de preferências do sistema (domínios de
  usuário e local). Por bundle ID, quebra o nome do arquivo e o bundle ID em
  partes por ponto e exige que **todas** as partes do bundle ID estejam no nome,
  em qualquer ordem (`com.logi.optionsplus.driverhost` é do
  `com.logi.optionsplus`). Por nome, quebra por espaço (a pasta
  `~/Library/Preferences/TeamSpeak` é do TeamSpeak). Usa a trava de versão.
- `ByHost`: nenhum `ByHost` aparece na baseline (Claude, Discord e VS Code têm
  um cada, todos com dígitos depois do bundle ID e, no caso do Discord, outro
  ID). Não dá para saber se a pasta é lida.
- **Regra nossa:** `~/Library/Preferences` e `/Library/Preferences`: arquivo
  `*.plist` com `id`, ou pasta com `nome`. **Não** lemos `ByHost`. A ordem
  diferente das partes **não** casa.
- Marcado: sim. Remoção: `removePreference` (ver `removal.md`), só depois de
  fechar o app.

### `container`
- CleanMyMac [E11]: o contêiner do próprio bundle ID
  (`~/Library/Containers/<bundle ID>`, item do tipo contêiner, mostrado como um
  nó com filhos; os filhos são as entradas de `Data/Library/Preferences`,
  `Data/Library/Caches`, `Data/Library/Application Support` etc., com os mesmos
  nomes de grupo; por isso os dumps AX parecem "achatados"). Também entram:
  - contêineres das extensões de alguns apps: GarageBand (as extensões
    QuickLook e Thumbnail) e o `FinderSyncExt` do agente do Setapp. **Não**
    entram as extensões do GlucoTracker (`.Widget`), do WhatsApp (`.Intents`,
    `.ServiceExtension`) nem o `QEMUHelper` do UTM. O que separa os dois casos
    nesta máquina: as extensões que entram **não** têm o entitlement
    `com.apple.security.application-groups`, e as que ficam de fora têm. A
    regra real não foi achada (pode ser da base cifrada);
  - o grupo `~/Library/Group Containers/2BBY89MBSN.dev.warp` do Warp (como
    contêiner). Os grupos do ChatGPT, GlucoTracker, UTM e WhatsApp (38,5 GB em
    `group.net.whatsapp.WhatsApp.shared`) **não** entram. Provável base cifrada.
- **Regra nossa:** só `~/Library/Containers/<bundle ID>` com o bundle ID exato
  do app, como **um item** (a pasta inteira, sem filhos), se for uma pasta real
  (não link). **Nunca** contêineres de extensões, de helpers ou de grupos
  (`Group Containers`): podem ser compartilhados com outros apps do mesmo time.
- Marcado: **sim ao desinstalar**, **não ao redefinir** (ver `reset.md`).

### `userData`
- CleanMyMac [E12]: filhos diretos de `~/Library` e `/Library` casados por
  bundle ID ou nome (`~/Library/Setapp`, pasta vazia), e `Data/Library/<Nome>`
  dentro do contêiner. Itens vindos da base também caem aqui:
  `~/Library/Developer/Xcode` (767 MB) e `~/Library/Developer/CoreSimulator` do
  Xcode, `~/Library/Google/Google Chrome Brand.plist` do Chrome.
- **Regra nossa:** filhos diretos de `~/Library` e `/Library` com `id` ou `nome`,
  **exceto** os nomes da lista fixa de pastas padrão do macOS
  (`Application Support`, `Caches`, `Containers`, `Mail`, `Messages`, `Safari`,
  `Developer`, `Fonts`, `Logs`, `Preferences`… a lista completa fica no código e
  vem de uma instalação limpa) e qualquer nome `com.apple.*` de app que não é da
  Apple. Nunca descemos um nível (nada de `~/Library/Google/...`).
- Marcado: **sim ao desinstalar**, **não ao redefinir**.

### `logs`
- CleanMyMac [E13][E14]:
  - registros: `~/Library/Logs` e `/Library/Logs`, por bundle ID e por nome
    (`~/Library/Logs/com.openai.codex`, `~/Library/Logs/Claude`,
    `~/Library/Logs/warp.log`; `warp.log.old.0` não entra, porque vira
    `warp.log.old` sem a extensão e não casa);
  - relatórios de falha: em `Logs/DiagnosticReports` de `~/Library` e
    `/Library`, os arquivos cujo nome começa com o nome do app e cuja extensão é
    `.crash`, `.diag`, `.hang` ou `.spin`; em
    `~/Library/Application Support/CrashReporter`, os `.plist` com o nome do app
    no início; também `Logs/CrashReporter/<nome>.crash.log` e
    `Logs/HangReporter/<nome>/`. Os `.ips` (formato atual) **não** entram:
    `CleanYourMac-2026-10-20-170728.ips` ficou fora. O prefixo é o nome de
    casamento (`CFBundleName`), não o executável: os
    `Google Chrome_….diag` de `/Library/Logs/DiagnosticReports` não entram para o
    Chrome, cujo `CFBundleName` é `Chrome`.
  - Os dois tipos aparecem juntos no grupo Registros.
- **Regra nossa:** registros com `id` ou `nome` nas duas pastas de logs;
  relatórios de falha em `~/Library/Logs/DiagnosticReports`,
  `/Library/Logs/DiagnosticReports` e `~/Library/Application Support/CrashReporter`
  cujo nome começa com `<CFBundleName>_` e termina em `.crash`, `.diag`, `.hang`,
  `.spin` (nos dois primeiros) ou `.plist` (no último). Tudo em `logs`.
- Marcado: sim.

### `loginItems`
O CleanMyMac põe três fontes no mesmo grupo [E15][E16]:
1. **Item de início da sessão** (lista de login do usuário): se o caminho do app
   está na lista, o item é o próprio app, com tamanho 0. Nesta máquina:
   GlucoTracker, Hidden Bar, Vorssaint e Warp (`osascript` → System Events
   lista os quatro, e são exatamente os quatro da baseline).
2. **Helper de login** (`Contents/Library/LoginItems/<helper>.app`): se o bundle
   ID do helper está nos jobs do launchd do usuário, o item é o helper, com
   tamanho 0. Nenhum nesta máquina.
3. **Plists do launchd** em `LaunchAgents` e `LaunchDaemons` de `~/Library` e
   `/Library`: o nome do arquivo (sem `.plist`) igual ao bundle ID; o nome igual
   a uma chave de `SMPrivilegedExecutables` do app; ou o plist com
   `AssociatedBundleIdentifiers` contendo o bundle ID. Com os apps internos
   (item "Visão geral"), o Setapp ganha `com.setapp.DesktopClient.SetappAgent.plist`
   e `com.setapp.DesktopClient.SetappUpdater.plist`, mas **não** os plists do
   `SetappLauncher` e do `SetappAssistant`, que têm o mesmo formato. A diferença
   não foi explicada (talvez a base).
   - Não entram os plists da Logi em `/Library` (`com.logi.optionsplus.plist` e
     `com.logi.optionsplus.updater.plist`): o `Label` e o
     `AssociatedBundleIdentifiers` deles são `com.logi.cp-dev-mgr`, e o nome do
     arquivo não é igual ao bundle ID. O `com.google.GoogleUpdater.wake.plist`
     também não entra no Chrome (associado a `com.google.GoogleUpdater`).
   - O CleanMyMac não usa o caminho do `Program` para casar.
- **Regra nossa:**
  1. item de sessão: o caminho do app está na lista de itens de início da
     sessão (lida pelo System Events; sem a permissão de Automação, a fonte fica
     vazia e o resto segue). `RelatedFile.size = 0`; remoção =
     `removeSessionLoginItem` (não apaga arquivo);
  2. plist do launchd em `~/Library/LaunchAgents`, `/Library/LaunchAgents` e
     `/Library/LaunchDaemons` quando: (a) o nome sem `.plist` **e** o `Label` são
     iguais ao bundle ID do app; ou (b) `AssociatedBundleIdentifiers` contém o
     bundle ID do app; ou (c) o nome e o `Label` são iguais a uma chave de
     `SMPrivilegedExecutables` do `Info.plist` do app (nesse caso, o helper
     `/Library/PrivilegedHelperTools/<chave>` entra junto, no mesmo item).
     Nunca `Label` ou nome `com.apple.*`; nunca plist que é link. Remoção =
     `unloadAndTrash` (domínio `user` ou `system`, ver `removal.md`). **Não**
     usamos os bundle IDs dos apps internos (subconjunto);
  3. helper de login (`Contents/Library/LoginItems`) e `SMAppService`: fora da
     v0.2. Ao mover o app para o Lixo, o macOS desliga o helper sozinho.
- Marcado: sim.

### `dockIcon`
- CleanMyMac [E17]: entrada de `persistent-apps` em `com.apple.dock` cujo URL é
  o do app (Chrome, Warp e Zed, todos conferidos com `defaults read
  com.apple.dock persistent-apps`). Tamanho 0. Remove editando a preferência do
  Dock e reiniciando o Dock.
- **Regra nossa:** **não** listamos na v0.2, porque não editamos o Dock
  (`removal.md`). O tipo fica reservado.

### `plugins`
- CleanMyMac [E18]: pastas de plug-ins da biblioteca (Internet Plug-Ins,
  QuickLook, Spotlight, PreferencePanes, Services, Screen Savers, Mail etc.) e
  `PDF Services` (por nome). O critério dos plug-ins não foi lido por completo.
  A pasta `~/Library/Services` tem três `Claude - *.workflow`, e nenhum entrou
  para o Claude, então não é por palavra do nome.
- **Regra nossa:** para cada pacote dentro do app em
  `Contents/Library/{QuickLook,Spotlight,PreferencePanes,Internet Plug-Ins,Services,Screen Savers}`,
  entra o pacote **de mesmo nome** na pasta homônima de `~/Library` ou
  `/Library`, desde que o `CFBundleIdentifier` dele seja igual ao do pacote de
  dentro do app. `PDF Services`: só `~/Library/PDF Services/<Nome>` exato. Nenhum
  nesta máquina.
- Marcado: sim.

### `help`
- CleanMyMac [E19]: `~/Library/Preferences/SDMHelpData/Other/…` e
  `/Library/Documentation/Applications/…` por nome e bundle ID, com extensão
  `help`. Nenhum nesta máquina.
- **Regra nossa:** `/Library/Documentation/Applications/<Nome>` e
  `~/Library/Preferences/SDMHelpData/Other/<bundle ID>.help` exatos.

### `installers`
- CleanMyMac [E20]: arquivos `.dmg` em `~/Downloads` casados por nome do app,
  com a trava de versão (`Warp-1.2.dmg` não casa; o
  `v0.2026.10.14.08.27.stable_02.Warp.dmg` desta máquina também não, e de fato
  não aparece no Warp, só na seção de instaladores).
- **Regra nossa:** `~/Downloads/<Nome>.dmg` com o nome exato. Desmarcado (o
  instalador é tratado em `installers.md`).

### `other` e recibos de pacote
- CleanMyMac: o grupo "Outros" só mostrou itens da base cifrada (`~/.vscode` do VS
  Code, `~/Applications/Chrome Apps.localized` do Chrome) [E3].
- Recibos [E21]: o CleanMyMac procura pacotes pelo bundle ID e pelo nome
  (`findPackagesByBundleID:`), e para cada um junta o recibo e os arquivos que ele
  instalou, classificados pelo caminho. Nenhum recibo aparece na baseline,
  embora `com.logi.installer.pluginservice.package` tenha instalado o
  `LogiPluginService.app` (o ID não começa com `com.logi.pluginservice`). Os
  recibos da Apple (`com.apple.pkg.GarageBand_AppStore`, `com.apple.pkg.Xcode`)
  também ficam fora.
- **Regra nossa:** um recibo entra em `other` quando (a) o `package-id` é igual
  ao bundle ID ou começa com o bundle ID seguido de `.`; (b) não é `com.apple.*`;
  (c) o volume é `/`; e (d) a lista de arquivos (`pkgutil --files <id>`) contém o
  caminho do bundle relativo ao `location` do recibo. O item é o registro, não os
  arquivos (só `forgetReceipt`; nada é apagado do disco por causa do recibo).
  Tamanho 0. Nenhum nesta máquina. Marcado: sim, só se o helper estiver
  aprovado.

### `applications`
- CleanMyMac: apps internos de um jogo do Steam ou do Battle.net (a linha é a
  pasta do jogo) [E22].
- **Regra nossa:** igual, só nessas linhas. Nenhum nesta máquina.

## Inclusão
Um item entra quando o caminho real está numa das raízes da tabela, casa pela
regra do tipo, não é link, passa pelas travas comuns e não está **dentro** de
outro item da mesma linha (o item de fora absorve o de dentro). Um caminho que
casaria com dois tipos fica no primeiro desta ordem: `binaries`, `container`,
`loginItems`, `preferences`, `logs`, `supportingFiles`, `userData`, `plugins`,
`help`, `installers`, `other`.

## Exclusão (nunca entra)
- `~/Library/Group Containers/*`, `~/Library/Application Scripts/*`,
  `~/Library/HTTPStorages/*`, `~/Library/WebKit/*`, `~/Library/Cookies/*` (o
  CleanMyMac tem um buscador de cookies para `<bundle ID>.binarycookies`, mas o
  arquivo não aparece na baseline), `~/Library/Saved Application State/*` (não
  existe nesta máquina), `ByHost`.
- Arquivos soltos na pasta do usuário (`~/.vscode`, `~/.claude`, `~/.perssua`,
  `~/.warp`): nunca, mesmo com o nome do app.
- Tudo de `/System`, `/usr`, `/private/var/db` (exceto o registro de recibo via
  `pkgutil`), `/Library/Apple`.
- Contêineres de extensões e de helpers; contêineres de grupo.
- Qualquer item que case com mais de um app instalado.
- Para app que não é `com.apple.*`: qualquer item `com.apple.*`.

## Recomendado (marcação)
- No CleanMyMac, a baseline mostra todos os checkboxes desmarcados, porque
  nenhum app estava selecionado. O `dump-ax` não alcança o checkbox (ele não
  tem título), então não foi possível ver o que fica marcado ao selecionar um
  app [E6]. Pelo código, ao selecionar o app entram os recursos
  "removíveis"; o bundle protegido e alguns recursos de plug-in são criados como
  não removíveis [E7][E23].
- **Regra nossa (Desinstalar)**: tudo marcado, exceto as cópias extras em
  `binaries`, `installers`, itens que exigem admin quando o helper não está
  aprovado (ficam desmarcados e com aviso) e itens protegidos (não
  selecionáveis). Para Redefinir, ver `reset.md`.

## Agrupamento e nome exibido
Grupo = `ResourceKind`, com os rótulos da coluna "Grupo na tela" escritos com
nossas palavras na UI; item = último componente do caminho (o item de sessão
mostra o nome do app). Ordem: grupos e itens em ordem alfabética, sem
diferenciar maiúsculas.

## Cálculo de tamanho
- CleanMyMac: tamanho alocado (`common.md` §1). Para bundles, o
  `kMDItemPhysicalSize` do Spotlight quando existe (ver `inventory.md`). Os tipos
  item de sessão, helper de login, Dock e recibo valem **0** [E24]. Não
  deduplica itens aninhados.
- **Regra nossa:** `FileSizer.allocatedSize(of:)` em cada item (pasta inteira,
  sem seguir links); 0 para item de sessão e recibo; plist do launchd com helper
  = soma dos dois. Item dentro de outro não é contado de novo.

## Remoção
Ver `removal.md` (Lixo, helper, ordem dos passos). Por tipo: arquivos e pastas →
`moveToTrash`; preferências → `removePreference`; launchd → `unloadAndTrash`;
item de sessão → `removeSessionLoginItem`; recibo → `forgetReceipt`.

## Alertas e selos
- Item que exige admin sem helper: desmarcado, com aviso.
- Item protegido (bundle do app protegido, plug-in da Apple): sem checkbox.

## requiresAdmin
- Análise: não. Sem Acesso Total ao Disco, `~/Library/Containers` e partes de
  `~/Library` ficam ilegíveis; esses itens não aparecem (a análise avisa).
- Remoção: só para itens fora da pasta do usuário (`/Library/...`, recibos).

## Comparação por app (baseline × nossa regra)
Simulação da nossa regra nesta máquina em 2026-10-21 (script de leitura, fora do
repositório) contra a baseline. "Itens" não conta os binários. Os tamanhos
mudaram um pouco entre a análise do CleanMyMac (15:21) e a simulação (~16:30),
nos caches e registros de apps abertos. **Nenhum item da nossa regra ficou fora
da lista do CleanMyMac** (subconjunto conferido item a item, por tipo e nome).

| App | Itens CMM | Itens nossos | Total CMM | Total nosso | Só no CleanMyMac (divergência) |
|---|---|---|---|---|---|
| Bruno | 0 | 0 | 0 | 0 | — |
| ChatGPT | 6 | 6 | 9,2 MB | 9,2 MB | — |
| Claude Code URL Handler | 0 | 0 | 0 | 0 | — |
| Claude | 7 | 7 | 529 MB | 529 MB | — |
| CleanMyMac | 0 | (sem par) | — | — | linha sem detalhe no CleanMyMac |
| CleanYourMac | 4 | 4 | 1,1 MB | 1,5 MB | — (cache `$C` cresceu) |
| Discord | 2 | 2 | 1,2 GB | 1,2 GB | — |
| GarageBand | 4 | 2 | 952 MB | 952 MB | 2 contêineres de extensão (QuickLook, Thumbnail; 4,1 KB cada) |
| GlucoTracker | 3 | 3 | 15 MB | 16 MB | — (contêiner mudou) |
| Google Chrome | 18 | 12 | 4,5 GB | 24,3 MB | `~/Library/Application Support/Google/Chrome` (2,8 GB) e `~/Library/Caches/Google/Chrome` (1,7 GB), `Google Chrome Brand.plist`, `Chrome Apps.localized`, `com.google.Keystone.Agent.plist` (base cifrada) e o ícone do Dock |
| Hidden Bar | 3 | 3 | 143 KB | 205 KB | — |
| Logi Options+ | 5 | 5 | 17,8 MB | 17,8 MB | — |
| LogiPluginService | 0 | 0 | 0 | 0 | — |
| MacICNS | 5 | 5 | 774 KB | 774 KB | — |
| Obsidian | 2 | 2 | 13,1 MB | 13,1 MB | — |
| Perssua | 5 | 5 | 8 MB | 8,1 MB | — |
| Setapp | 17 | 13 | 317 MB | 319 MB | contêiner `com.setapp.DesktopClient.SetappAgent.FinderSyncExt`, plists `…SetappAgent.plist` e `…SetappUpdater.plist` de `~/Library/LaunchAgents`, `com.setapp.defaults.plist` |
| Spotifast | 0 | 0 | 0 | 0 | — |
| TeamSpeak | 2 | 2 | 393 KB | 393 KB | — |
| UTM | 2 | 2 | 965 MB | 965 MB | — |
| Visual Studio Code | 3 | 2 | 3,2 GB | 1,3 GB | `~/.vscode` (1,9 GB, base cifrada) |
| Vorssaint | 6 | 6 | 14,8 MB | 14,9 MB | — |
| Warp | 8 | 6 | 661 MB | 660 MB | grupo `2BBY89MBSN.dev.warp` (5,3 MB) e o ícone do Dock |
| WhatsApp | 3 | 3 | 114 MB | 117 MB | — |
| Xcode | 8 | 4 | 768 MB | 1,2 MB | `~/Library/Caches/com.apple.dt.xcodebuild` (outro bundle ID, casado por substring), `~/Library/Developer/Xcode` (767 MB) e `~/Library/Developer/CoreSimulator` (base), `embeddedBinaryValidationUtility.plist` (base) |
| Zed | 6 | 5 | 1,2 GB | 1,2 GB | o ícone do Dock |

Binários: iguais em todas as linhas, menos GlucoTracker (as três builds entram
desmarcadas, com o tamanho do `du`) e Setapp (sem o agente de `~/Library`).

## Evidências
- **E1**: chamadas de `CMApplicationResource resourceWithValue:bundleIdentifier:type:…`
  em cada buscador de UninstallerScanning, com o tipo de cada um (preferências
  1, caches/temporários 2, bundle 4, registros 8, biblioteca 0x10, suporte e
  arquivos extras de app em sandbox 0x20, relatórios de falha 0x40,
  PDF/plug-ins 0x80, item de sessão 0x100, launchd 0x200, estado salvo 0x400,
  recibo 0x800, Dock 0x1000, ajuda 0x2000, helper de login 0x8000, contêiner
  0x20000, DMG em Downloads 0x40000, cookies 0x100000).
- **E2**: `CMResourcesFetcher fetchAllResourcesForApplication:addAppBundleToResourceList:`
  e `CMResourceFetcherHelper appsInsideBundleAtPath:` (`/Contents/Library` e
  `/Contents/MacOS`), decompilados.
- **E3**: `CMResourcesFromKnowledgeBaseFetcher` (`additionalFilesForApplicationName:bundleId:`,
  `resourceTypeByPath:`) e o uso de `isIgnoreOrSystemItemFileWithPath:` em todos
  os buscadores.
- **E4**: `CMDirectoryFileFinder` (`fastEnumerateFilesAtPath:onFile:` com
  `fts_open` físico e `FTS_SKIP` em cada entrada, a função de casamento por
  substring e por palavras, `isValidVersionPattern:forApplicationName:` com a
  expressão `\s*\d+`) e `CMDirectoryFileFinderRequest` (`matchByWords`,
  `lowercasedName`, `nameComponents`), decompilados.
- **E5**: `ls $T | grep com.google.Chrome` (14 pastas; as 5 da baseline são
  exatamente as que não têm dígito depois do bundle ID) e os `ByHost` de
  `~/Library/Preferences`.
- **E6**: dumps AX `app-*.txt` (grupos, ordem e checkboxes `checked=0`); a
  tentativa de clicar no nome do Hidden Bar não marca a linha
  (`re-notes/ax/t2-hb2-*`).
- **E7**: `CMApplicationResource` (`removable`, `isRemovable`) e o bundle criado
  como removível só se não for restrito nem protegido pela base.
- **E8**: `CMSupportingFilesFetcher fetchResourcesForApplication:` e
  `CMPaths applicationSupportPaths`/`libraryPaths`
  (`NSSearchPathForDirectoriesInDomains` com domínios de usuário e local).
- **E9**: `CMCachesFetcher`/`CMTempFilesFetcher directoryFinderRequestsForApplication:`
  (`userCaches`, `darwinUserCaches`, `userTempPath`).
- **E10**: `CMPreferencesFilesFetcher fetchResourcesForApplication:`
  (`allPreferencesNames`, casamento por partes com separador e por palavras).
- **E11**: `CMApplicationContainerFetcher` (`sandboxContainerPath` =
  `<Containers>/<bundle ID>/Data`; filhos das subpastas da biblioteca do
  contêiner, sem `.DS_Store`, `Library`, `Documents`, `CrashReporter` e links;
  `Library/<Nome>` como 0x10; a raiz como 0x20000); entitlements via
  `codesign -d --entitlements -` das extensões.
- **E12**: `CMLibraryPathsFetcher` (tipo 0x10) e a baseline (Setapp, Xcode,
  Chrome).
- **E13**: `CMLogsFetcher` (`userLogs`, `localLogs`, bundle ID e nome).
- **E14**: `CMCrashLogsFetcher` (strings `Logs/DiagnosticReports/`, `.crash`,
  `.diag`, `.hang`, `.spin`, `Application Support/CrashReporter/`, `.plist`,
  `Logs/CrashReporter/%@.crash.log`, `Logs/HangReporter/%@/`) e o disco.
- **E15**: `CMLoginItemsFetcher`, `CMApplicationInfo isInLoginItems`
  (`validLoginItemsList`, `SMCopyAllJobDictionaries` no domínio do usuário,
  `loginItemInfoPlistForAppURL:helperAppURL:`); `osascript -e 'tell application "System Events" to get the path of every login item'`.
- **E16**: `CMLaunchDemonsFetcher` (`LaunchDaemons`/`LaunchAgents` de
  `libraryPaths`, pedido por bundle ID, `privilegedExecutables`,
  `isPlistHasAssociatedBundleIdentifier:forBundleID:`); `plutil -p` dos plists
  desta máquina.
- **E17**: `CMDockIconFetcher`/`CMResourceFetcherHelper dockIconRecordForItemAtPath:`
  (`persistent-apps`, `_CFURLString`) e `defaults read com.apple.dock persistent-apps`.
- **E18**: `CMPluginsFetcher` (`pluginsPaths`), `CMPDFServicesFetcher`; lista de
  pastas de plug-ins nas strings de ApplicationsService; `ls ~/Library/Services`.
- **E19**: `CMApplicationHelpFetcher` (`~/Library/Preferences/SDMHelpData/Other`,
  `/Library/Documentation/Applications`, `help`).
- **E20**: `CMDownloadFilesFetcher` (`downloadsURL`, extensão `dmg`).
- **E21**: `CMReceiptFetcher` (`findPackagesByBundleID:`,
  `_findReceiptResourcesForPackage:`); `pkgutil --pkgs`, `--pkg-info` e `--files`.
- **E22**: `CMResourcesFetcher fetchAllResourcesForSteamApplication:`/`…BlizzardApplication:`
  e `innerApplicationsFor…`.
- **E23**: `CMPluginResourcesFetcher` (único buscador que passa `removable`
  variável).
- **E24**: `ResourceSizeProvider.size(forType:resourceValue:)` (quatro tipos
  devolvem 0; o resto usa `byteSizeAtPath:`).

## Divergências conhecidas
- **Substring × igualdade**: o CleanMyMac aceita o bundle ID em qualquer posição
  do nome e o nome do app como palavra solta. Nós exigimos igualdade ou o prefixo
  com ponto. Efeito aqui: `com.apple.dt.xcodebuild` fica fora do Xcode. Em
  outras máquinas, isso evita casos como `com.foo.App` × `com.foo.AppHelper` e
  "Code" × "Code Helper".
- **Base cifrada**: os itens extras (Chrome, VS Code, Xcode, Setapp, grupo do
  Warp) não entram para nós. O maior efeito é no Chrome (4,5 GB a menos) e no VS
  Code (1,9 GB a menos). É aceito pelo design. Uma lista nossa de casos
  conhecidos pode vir depois, sempre com vínculo forte.
- **Apps internos**: não rodamos as regras para os helpers dentro do bundle.
  Setapp perde dois plists do launchd e os itens dos helpers que só casam pelo ID
  deles. (Os caches `…SetappAgent`, `…SetappLauncher`, `…SetappUpdater`
  continuam entrando, porque começam com `com.setapp.DesktopClient.`.)
- **Contêineres de extensão e de grupo**: nunca (GarageBand −2, Setapp −1,
  Warp −1).
- **Dock**: não listado na v0.2.
- **Preferências por partes fora de ordem**: não casam.
- **Relatórios de falha**: o mesmo critério, mas só com prefixo `<Nome>_`.
  `Logs/CrashReporter` e `HangReporter` (legados) não são lidos.
- **Recibos**: critério nosso (ID + arquivo do bundle no recibo). A paridade
  aqui é trivial (0 × 0).

## Checklist de testes
1. `com.foo.App` instalado; `~/Library/Caches/com.foo.App`,
   `~/Library/Caches/com.foo.App.helper`, `~/Library/Caches/com.foo.AppHelper`,
   `~/Library/Caches/x.com.foo.App` → só os dois primeiros.
2. `$T/com.foo.App.7kmmTi` → fora (dígito); `$T/com.foo.App.EwEVXI` → dentro.
3. App "Code" (`CFBundleName`) e `~/Library/Application Support/Code` → dentro;
   `Code Helper` e `code-oss` → fora (`sharedPrefixNameNotRelated`).
4. Dois apps com `CFBundleName` "Foo": `~/Library/Application Support/Foo` → fora
   dos dois (empate).
5. `~/Library/Preferences/com.foo.App.plist` → dentro;
   `ByHost/com.foo.App.<UUID>.plist` → fora; `app.foo.com.plist` → fora.
6. `~/Library/Containers/com.foo.App` → `container`;
   `~/Library/Containers/com.foo.App.Widget` → fora;
   `~/Library/Group Containers/TEAM.com.foo.App` → fora.
7. `~/Library/Containers/com.foo.App` como symlink → fora, e o tamanho do
   destino não é somado (`symlinkedRelatedFileNotFollowed`).
8. `~/Library/LaunchAgents/com.foo.App.plist` com `Label` `com.foo.App` →
   `loginItems`; o mesmo arquivo com `Label` `com.bar` → fora; plist com
   `AssociatedBundleIdentifiers = ["com.foo.App"]` e outro nome → dentro;
   `com.foo.App.Updater.plist` sem associação → fora.
9. `SMPrivilegedExecutables = {"com.foo.App.Helper": …}` e
   `/Library/LaunchDaemons/com.foo.App.Helper.plist` +
   `/Library/PrivilegedHelperTools/com.foo.App.Helper` → um item com os dois.
10. `~/Library/Logs/DiagnosticReports/Foo_2026-10-21-….diag` → `logs`;
    `Foo-2026-….ips` → fora; `Foobar_….diag` → fora.
11. App que não é da Apple e `~/Library/Caches/com.apple.Foo` com o nome do app →
    fora.
12. `~/Library/Mail` para um app chamado "Mail" de terceiros → fora (pasta
    padrão).
13. Item dentro de outro item da mesma linha → conta uma vez.
14. App na lista de itens de início → item `loginItems` com tamanho 0 e
    `removeSessionLoginItem`.
15. Recibo `com.foo.App.pkg` cujos arquivos incluem `Foo.app` → `other` com
    `forgetReceipt`; recibo `com.foo.installer.pkg` → fora; `com.apple.pkg.X` → fora.
