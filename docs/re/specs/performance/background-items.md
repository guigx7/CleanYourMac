# Itens em Segundo Plano (`launchAgents`)

Seção "Itens em Segundo Plano" do módulo Desempenho: agentes e daemons do
launchd (arquivos `.plist`) de terceiros. Os textos aqui são paráfrases; os
textos finais da UI são nossos. Cada afirmação está marcada como **EVIDÊNCIA**
(com a fonte entre colchetes) ou **INFERÊNCIA**.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Análise de 2026-10-22:
árvore de Acessibilidade `re-notes/ax/perf-baseline-20261022-0228/`, baseline
`docs/re/parity/perf-baseline-2026-10-22.json`, análise estática de
`PerformanceScanning`, `PerformanceService` (só `nm`/`otool`/`strings`),
`PerformanceModule` e `SharedObjcUtils`, e leitura do disco desta máquina (só
leitura, sem sudo).

## 1. Locais varridos
- **EVIDÊNCIA** — `LaunchAgentScanLocationsProvider.scanLocations()` monta a lista
  com três métodos de `CMPaths` [E1][E2]:

  | Ordem | Método | Pasta |
  |---|---|---|
  | 1 | `launchAgentsPath` | `~/Library/LaunchAgents` |
  | 2 | `systemLaunchAgentsPath` | `/Library/LaunchAgents` |
  | 3 | `launchDaemonsPath` | `/Library/LaunchDaemons` |

- **EVIDÊNCIA** — as pastas 2 e 3 só entram se o app **não** estiver em sandbox
  (`NSProcessInfo.isSandbox`); a versão do Setapp não é sandbox, então as três
  entram [E1].
- **EVIDÊNCIA** — não entram: `~/Library/LaunchDaemons`,
  `~/Library/PrivilegedHelperTools`, `/Library/PrivilegedHelperTools`,
  `/System/Library/LaunchAgents|LaunchDaemons` (esses caminhos existem em
  `CMPaths`, mas esta tarefa não os chama) nem os plists embutidos em apps
  (`<App>.app/Contents/Library/LaunchAgents|LaunchDaemons`, usados por
  `SMAppService`) [E1][E2].
- **EVIDÊNCIA** — cada pasta é percorrida com um enumerador de diretório com a
  opção "não descer em subpastas" (valor 1); arquivos ocultos **não** são
  pulados. Só entram arquivos cuja extensão é exatamente `plist` (comparação
  com `isEqual:`, sensível a maiúsculas) [E3].

## 2. Inclusão e exclusão
Para cada `.plist` encontrado [E4]:
1. Pergunta à base de regras (`LaunchAgentsKnowledgeBase.shouldIgnoreLaunchAgentPlistUrl`)
   se deve ignorar o arquivo. Base cifrada (`info.cmmkb`): conteúdo
   desconhecido [E5].
2. Se não é ignorado, procura o **app dono** (seção 3), lê o plist como
   dicionário (`dictionaryWithContentsOfFile:error:`; se falhar, segue sem
   dicionário) e cria o item. **Não há outro filtro.**

Consequências diretas do código (**EVIDÊNCIA** pela ausência no fluxo [E4]):
- não exclui itens já desativados no launchd (`launchctl print-disabled`) nem
  plists com `Disabled = true`;
- não exclui por `com.apple.*` nem por dono (só a base de regras pode fazer
  isso);
- não usa `AssociatedBundleIdentifiers`, `Label`, `BundleProgram` nem o BTM.

### 2.1 Conferência nesta máquina (só leitura)
Há **10** plists nas três pastas; o CleanMyMac mostra **9** [E6][E7]:

| Pasta | Plist | Executável (`Program` / `ProgramArguments[0]`) | Item no CleanMyMac |
|---|---|---|---|
| `~/Library/LaunchAgents` | `com.google.GoogleUpdater.wake.plist` | `~/Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app/Contents/MacOS/GoogleUpdater` | **GoogleUpdater.app** |
| `~/Library/LaunchAgents` | `com.setapp.DesktopClient.SetappAgent.plist` | `~/Library/Application Support/Setapp/LaunchAgents/Setapp.app/Contents/MacOS/SetappAgent` | **Setapp.app** |
| `~/Library/LaunchAgents` | `com.setapp.DesktopClient.SetappAssistant.plist` | `…/SetappAssistant.app/Contents/MacOS/SetappAssistant` | **SetappAssistant.app** |
| `~/Library/LaunchAgents` | `com.setapp.DesktopClient.SetappLauncher.plist` | `…/SetappLauncher.app/Contents/MacOS/SetappLauncher` | **SetappLauncher.app** |
| `~/Library/LaunchAgents` | `com.setapp.DesktopClient.SetappUpdater.plist` | `…/SetappUpdater.app/Contents/MacOS/SetappUpdater` | **SetappUpdater.app** |
| `/Library/LaunchAgents` | `com.logi.optionsplus.plist` (Label `com.logi.cp-dev-mgr`) | `/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app/Contents/MacOS/logioptionsplus_agent` | **Logi Options+.app** (1ª) |
| `/Library/LaunchAgents` | `com.logitech.LogiRightSight.Agent.plist` | `/Library/Application Support/Logitech.localized/LogiRightSightForWebcams/LogiRightSight.app/Contents/MacOS/LogiRightSight` | **LogiRightSight.app** |
| `/Library/LaunchDaemons` | `com.bjango.istatmenus.installer.plist` | `/Library/PrivilegedHelperTools/com.bjango.istatmenus.installer` | **com.bjango.istatmenus.installer.plist** |
| `/Library/LaunchDaemons` | `com.logi.optionsplus.updater.plist` | `…/logioptionsplus_agent.app/Contents/Frameworks/logioptionsplus_updater.app/Contents/MacOS/logioptionsplus_updater` | **Logi Options+.app** (2ª) |
| `/Library/LaunchDaemons` | `com.macpaw.CleanMyMac-setapp.Agent.plist` | `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac-setapp.Agent` | **excluído** |

- **Por que o Logi Options+ aparece duas vezes**: são dois plists diferentes
  (um agente e um daemon). O app dono dos dois é o mesmo
  `logioptionsplus_agent.app`: no daemon, o caminho passa primeiro por
  `logioptionsplus_agent.app` e só depois por `logioptionsplus_updater.app`, e o
  corte é feito no **primeiro** `.app` (seção 3). O nome exibido desse pacote é
  "Logi Options+" (o `InfoPlist.strings` localizado troca o nome
  `logioptionsplus_agent`) [E6][E8].
- **Por que o do iStat Menus aparece como plist**: o executável fica em
  `/Library/PrivilegedHelperTools/`, fora de qualquer `.app`, então não há app
  dono e o nome cai para o nome do plist [E6][E9].
- **Por que o do próprio CleanMyMac não aparece**: **INFERÊNCIA** — só a base de
  regras pode excluí-lo (passo 2.1); ela deve listar o ajudante da MacPaw. O
  executável dele está em `PrivilegedHelperTools`, então, sem a base, ele
  apareceria como `com.macpaw.CleanMyMac-setapp.Agent.plist`.
- **Itens modernos fora da lista**: o `sfltool dumpbtm` mostra agentes e daemons
  `SMAppService` (tipo `agent (0x8)` / `daemon (0x10)`, sem a marca "legacy") do
  Karabiner-Elements e o ajudante do CleanYourMac. Os plists deles ficam dentro
  dos apps (`…/Contents/Library/LaunchAgents|LaunchDaemons`) e por isso não são
  varridos [E10]. Os 9 itens mostrados aparecem no BTM como `legacy agent
  (0x10008)` / `legacy daemon (0x10010)` [E10].

## 3. App dono e nome exibido
- **EVIDÊNCIA** — `CMLaunchdManager startupApplicationPathFor:accurate:` [E9]:
  1. percorre `ProgramArguments` (se for array), elemento por elemento; no
     primeiro que contenha `.app`, corta a string logo depois do **primeiro**
     `.app` e usa isso como caminho do app;
  2. se nenhum elemento servir, tenta o mesmo com `Program`;
  3. devolve também um sinal "exato": verdadeiro quando o executável encontrado
     é o executável principal do pacote (`NSBundle.executablePath`) ou quando não
     sobrou executável para comparar; falso caso contrário.
- **EVIDÊNCIA** — o modelo do item guarda: URL do plist, o app dono (URL + o sinal
  acima, que o modelo chama de `isHelper`) e o dicionário do plist [E11].
- **EVIDÊNCIA** — nome exibido = `displayNameAtPath:` do **app dono** quando ele
  existe; senão, `displayNameAtPath:` do **plist** [E11]. Nesta máquina os nomes
  saem com extensão porque o Finder mostra extensões
  (`AppleShowAllExtensions = 1`).
- O app dono **não** é procurado pelo `AssociatedBundleIdentifiers` nem pelo
  `Label` [E4][E9].

## 4. Recomendado
- **EVIDÊNCIA** — nenhum item vem marcado; o seletor da seção mostra "Nenhum"
  [E7].

## 5. Agrupamento e apresentação
- Lista plana, um item por plist, ordem por **Nome** [E7].
- Cabeçalho da seção: título "Itens em Segundo Plano" e uma frase sobre
  processos e apps que rodam em segundo plano [E7][E12].
- Linha: caixa de seleção, nome e o botão de "dica inteligente" (fora do
  escopo) [E7].
- Rodapé: contagem de selecionados e o botão **Remover** (único) [E7][E12].
- Ícone do cartão nos Resultados: imagem própria "launch agents category"
  (a nossa arte é própria) [E13].
- Sem tamanho por item [E7].

## 6. Remoção no CleanMyMac
- **EVIDÊNCIA** — `BackgroundItemsRemover.remove(value:)` [E14]:
  1. chama `CMLaunchdManager removeAgentAtPath:` com o caminho do plist;
  2. se falhar e o app **não** estiver em sandbox, manda ao ajudante
     privilegiado um pedido `RemoveLaunchAgentRequest(url:)` com a URL do plist
     e espera o resultado;
  3. se estiver em sandbox, ou sem ajudante, devolve erro.
- **EVIDÊNCIA** — `removeAgentAtPath:` (sem root) [E15]:
  1. roda `/bin/launchctl unload <caminho-do-plist>`;
  2. se o comando não devolver saída: pega o **nome do arquivo** do plist sem
     `.plist` e, se existir `/Library/PrivilegedHelperTools/<esse nome>`, apaga
     esse arquivo; depois apaga o plist (`removeItemAtPath:`, sem Lixo);
  3. se o `unload` devolver saída (erro), não apaga nada e devolve falha.
- **INFERÊNCIA** — para os plists de `/Library` (donos `root`), o passo 2 não
  consegue apagar sem root e o caminho real é o do ajudante (passo 2 de
  `remove`). O que o ajudante faz como root não foi visto aqui (fica com a
  análise do `PrivilegedOperationsPerformerService`).
- O app dono **nunca** é removido. Não há aviso de que o app pode recriar o
  item; na falha, o texto pede para encerrar os apps relacionados e tentar de
  novo [E12].
- Também existe `disableAgentAtPath:` (`launchctl unload -w`) no
  `CMLaunchdManager`, mas a tela não oferece "Desativar" [E15][E7].

## 7. A NOSSA forma (CleanYourMac)

### 7.1 Análise (paridade)
- Pastas: `~/Library/LaunchAgents`, `/Library/LaunchAgents`,
  `/Library/LaunchDaemons`; filhos diretos; extensão exatamente `plist`;
  arquivos ocultos incluídos.
- App dono: regra da seção 3 (primeiro `.app` em `ProgramArguments`, depois
  `Program`). Nome = nome exibido do app dono; sem dono, nome do plist.
- Exclusões nossas (no lugar da base cifrada): `Label` ou nome do arquivo
  começando com `com.apple.`; o próprio CleanYourMac
  (`io.github.guigx7.CleanYourMac*`); e os ajudantes da MacPaw
  (`com.macpaw.*`) para bater com a observação desta máquina.
- Não usar `AssociatedBundleIdentifiers` para achar o dono (paridade). Pode ser
  usado só como informação extra na confirmação.
- Estado de cada item (nosso, extra): ver 7.3.

### 7.2 Domínio e rótulo
- **Rótulo** = chave `Label` do plist (não o nome do arquivo!). Exemplo desta
  máquina: `com.logi.optionsplus.plist` tem `Label = com.logi.cp-dev-mgr`, e é
  esse rótulo que aparece no `print-disabled` [E6][E16]. Sem `Label`, o item é
  mostrado mas Desativar/Reativar ficam indisponíveis.
- **Domínio**: plist em `LaunchAgents` (do usuário ou de `/Library`) →
  `gui/<uid>` (o uid do usuário da sessão), **sem root**. Plist em
  `/Library/LaunchDaemons` → `system`, **pelo ajudante** (root).
- Nunca agir sobre rótulo `com.apple.*` (trava também no ajudante, com
  revalidação como root, como na v0.2).

### 7.3 Ler o estado desativado (só leitura)
- Comandos: `launchctl print-disabled gui/<uid>` e
  `launchctl print-disabled system`. Os dois rodam **sem root** [E16].
- Formato observado (macOS 26.6.2):
  - uma linha `disabled services = {`, uma linha por serviço e uma `}`;
  - cada linha de serviço: dois TABs, o rótulo entre aspas, ` => ` e a palavra
    `enabled` ou `disabled`. Ex.: `"com.logi.cp-dev-mgr" => enabled`;
  - a saída do domínio `system` começa com uma linha vazia;
  - nesta máquina: 21 serviços em `gui/501` e 11 em `system`.
- Interpretação: é a **tabela de substituições** do domínio. Um rótulo só aparece
  se alguém já o ligou/desligou (`enable`/`disable`, Ajustes, BTM). `disabled` =
  não será carregado; `enabled` = liberado. Rótulo ausente = vale a chave
  `Disabled` do plist (padrão: falso). A tabela guarda também rótulos de itens
  que nem existem mais (ex.: `com.spotify.client.startuphelper`).
- Parser: regex por linha `^\s*"(.+)"\s*=>\s*(\w+)\s*$`; aceitar
  `disabled`/`true` como desativado e `enabled`/`false` como ativo
  (**INFERÊNCIA**: versões antigas do `launchctl` usavam `true`/`false`).
- Estado do item = substituição do domínio dele, senão `Disabled` do plist.

### 7.4 Desativar
- `gui/<uid>`: `launchctl disable gui/<uid>/<Label>` e depois
  `launchctl bootout gui/<uid>/<Label>` (ignorar o erro "não carregado").
- `system`: as mesmas duas operações (`disable system/<Label>`,
  `bootout system/<Label>`) via operação tipada nova do ajudante.
- O plist fica no lugar. O item continua na lista, com o estado "Desativado" e a
  ação Reativar.

### 7.5 Reativar
- `launchctl enable <domínio>/<Label>` e depois
  `launchctl bootstrap <domínio> <caminho-do-plist>` (ignorar o erro "já
  carregado"). `system` pelo ajudante.

### 7.6 Remover (para o Lixo)
1. `launchctl bootout <domínio>/<Label>` (erro "não carregado" é aceito).
2. Mover o plist para o Lixo.
3. Executável auxiliar ligado: se `Program` (ou `ProgramArguments[0]`) aponta para
   `/Library/PrivilegedHelperTools/<arquivo>` e `<arquivo>` é igual ao `Label`
   **ou** ao nome do plist sem `.plist`, mover também para o Lixo. Nunca
   levar um `.app` nem nada fora de `PrivilegedHelperTools` (regras de vínculo
   da v0.2).
4. Plists de `/Library/...` e o auxiliar: pelo ajudante (root).
- Não mexer na tabela `disabled` ao remover (o rótulo pode ficar lá; é
  inofensivo).

### 7.7 Aviso de app dono instalado
- Se o app dono existe (seção 3) ou se algum app instalado tem um
  `CFBundleIdentifier` igual a um `AssociatedBundleIdentifiers` do plist, a
  confirmação de **Remover** avisa que esse app pode recriar o item na próxima
  vez que abrir (caso típico: Setapp, GoogleUpdater, Logi Options+) e oferece
  abrir o Desinstalador nele. Para **Desativar** o aviso não é necessário (a
  substituição `disabled` sobrevive à recriação do plist).
- Erros de remoção: frase nossa no sentido de "encerre os apps relacionados e
  tente de novo".

### 7.8 Itens modernos (`SMAppService` / BTM)
- Plists dentro de apps (`Contents/Library/LaunchAgents|LaunchDaemons`) não são
  varridos (paridade). Se no futuro forem listados, as ações abrem Ajustes ›
  Geral › Itens de Início
  (`x-apple.systempreferences:com.apple.LoginItems-Settings.extension`), com o
  guia de permissões; nunca escrever no BTM.

## 8. requiresAdmin
- Análise: não (os plists das três pastas são legíveis por todos nesta máquina).
- Desativar/Reativar/Remover: não para `gui/<uid>` (`~/Library/LaunchAgents`);
  `/Library/LaunchAgents`: desativar/reativar não, remover sim (o plist é do
  `root`); `/Library/LaunchDaemons`: sim para tudo.

## Evidências
- **E1**: `otool -tV` de `PerformanceService` em `LaunchAgentScanLocationsProvider.scanLocations()` (0xbc68): seletores `launchAgentsPath`, `processInfo` + `NSProcessInfo.isSandbox` (SharedUtils), `systemLaunchAgentsPath`, `launchDaemonsPath`; desvio que pula as duas últimas em sandbox.
- **E2**: Ghidra de `SharedObjcUtils`: `CMPaths::launchAgentsPath.c` (pasta pessoal + `Library/LaunchAgents`), `::systemLaunchAgentsPath.c` (`/Library/LaunchAgents`), `::launchDaemonsPath.c` (`/Library/LaunchDaemons`); strings de `SharedObjcUtils` com as variantes `/System/Library/...`.
- **E3**: Ghidra de `PerformanceScanning`, `FUN_00002534.c` + `otool` (0x27a8: opções = 1; `enumeratorAt:includingPropertiesForKeys:options:errorHandler:`, `nextObject`, comparação da extensão com `plist` via `isEqual:`).
- **E4**: `FUN_00002d78.c` (por plist: base de regras, `startupApplicationPathFor:accurate:`, `makeLaunchAgentExecutableModel`, `dictionaryWithContentsOfFile:error:`, `makeLaunchAgentModel`); `BackgroundItemsScanTaskFactory::_makeLaunchAgentsScanTask.c`.
- **E5**: `PerformanceScanning::LaunchAgentsKnowledgeBase::shouldIgnoreLaunchAgentPlistUrl.c`.
- **E6**: leitura do disco: `ls -la` das pastas e `plutil -p` de cada plist (2026-10-22).
- **E7**: AX `re-notes/ax/perf-baseline-20261022-0228/background-items.txt` e baseline JSON.
- **E8**: `plutil -p` do `Info.plist` e do `InfoPlist.strings` de `logioptionsplus_agent.app`; `mdls -name kMDItemDisplayName` = `Logi Options+.app`; `logioptionsplus_updater.app` = `logioptionsplus_updater.app`.
- **E9**: `CMLaunchdManager::startupApplicationPathFor:accurate:.c` e `::appPathFormObject:executablePath:.c` (SharedObjcUtils).
- **E10**: `sfltool dumpbtm` sem root (saída salva como `btm.txt` no scratchpad desta sessão): tipos `legacy agent`/`legacy daemon` para os 9 + o da MacPaw; `agent`/`daemon` do Karabiner com URL relativa ao app; daemon do CleanYourMac em `Contents/Library/LaunchDaemons`.
- **E11**: `otool` de `PerformanceService` em `LaunchAgentModelFactory.makeLaunchAgentModel(url:executable:plist:)` (dois ramos com `displayNameAtPath:`) e `makeLaunchAgentExecutableModel(applicationPath:isHelper:)`; símbolos `LaunchAgentModel.{url,name,plist,executable}`, `LaunchAgentExecutableModel.{url,isHelper}`.
- **E12**: `localizable-pt-BR.json` e `Localizable.stringsdict` do `PerformanceModule` (chaves `background_items_*`, `cleanup_complete_*_background_items_*`, `background_items_footer_selected_items_count`).
- **E13**: AX `results.txt` (imagem "launch agents category" no cartão); strings `launchAgentsCategory`, `launchAgentsCategoryBig` em `PerformanceModule`.
- **E14**: `otool` de `PerformanceService` em `BackgroundItemsRemover.remove(value:)` (0x47bc): `removeAgentAtPath:`, `isSandbox`, chamada ao ajudante + `AnyPublisher.syncResult()`; símbolos `RemoveLaunchAgentRequest.init(url:)` em `PrivilegedOperationsPerformerService`.
- **E15**: `CMLaunchdManager::removeAgentAtPath:.c`, `::removeAgentAtPath:filesRemoverBlock:.c`, `::unloadLaunchAgentWithConfigPath:filesRemoverBlock:.c`, `::removePrivilegedToolWithLabel:filesRemoverBlock:.c`, `::_unloadAgentAtPath:shouldDisable:.c`, `::disableAgentAtPath:.c`, `FUN_00007c54.c` (bloco padrão = `removeItemAtPath:error:`).
- **E16**: `launchctl print-disabled gui/501` e `launchctl print-disabled system` nesta máquina, sem root.

## Divergências conhecidas
- **Desativar/Reativar**: extensão nossa (o CleanMyMac só remove).
- **Remover vai para o Lixo** (o CleanMyMac apaga de vez) e usa `bootout` (o
  CleanMyMac usa o antigo `unload`).
- **Auxiliar ligado**: o CleanMyMac apaga `/Library/PrivilegedHelperTools/<nome
  do plist>` sem olhar o `Program`; nós exigimos que o `Program` aponte para ele
  (ou que o nome bata com o `Label`/nome do plist **e** o `Program` aponte para
  dentro de `PrivilegedHelperTools`). Mais conservador.
- **Base de regras cifrada**: no lugar dela, `com.apple.*`, o próprio
  CleanYourMac e `com.macpaw.*`. Pode haver outros itens que o CleanMyMac esconde
  e nós mostramos.
- **Plist ilegível ou sem `Program`/`ProgramArguments`**: o CleanMyMac lista
  mesmo assim (com o nome do plist); mantemos.

## Checklist de testes
1. `~/Library/LaunchAgents/x.plist` com `ProgramArguments[0] = /Applications/Foo.app/Contents/MacOS/Foo` → item "Foo.app" (nome exibido), desmarcado.
2. Executável em `/Applications/Foo.app/Contents/Frameworks/Bar.app/Contents/MacOS/Bar` → dono `Foo.app` (primeiro `.app`).
3. Executável fora de `.app` (`/usr/local/bin/x`) → nome = `x.plist`.
4. Só `Program`, sem `ProgramArguments` → dono pelo `Program`.
5. Plist em subpasta de `LaunchAgents` → ignorado; `y.PLIST` → ignorado; `.oculto.plist` → incluído.
6. `com.apple.algo.plist` em `/Library/LaunchAgents` → excluído (regra nossa).
7. Plist com `Label` diferente do nome do arquivo → Desativar usa o `Label` (`launchctl disable gui/<uid>/<Label>`).
8. Parser de `print-disabled`: linhas com `enabled`, `disabled`, `true`, `false`; linha vazia inicial; rótulos com pontos e hífens.
9. Item desativado (substituição `disabled`) → aparece com estado "Desativado" e ação Reativar.
10. Desativar em `gui/<uid>` sem root → `disable` + `bootout`; plist intacto.
11. Reativar → `enable` + `bootstrap gui/<uid> <plist>`.
12. Remover em `~/Library/LaunchAgents` → `bootout`, plist no Lixo.
13. Remover daemon com `Program = /Library/PrivilegedHelperTools/<Label>` → plist e auxiliar no Lixo, via ajudante.
14. Remover com app dono instalado → confirmação com o aviso de recriação.
15. Em `CYM_DRY_RUN`, nenhum `launchctl` de escrita é executado.
