# Itens de Início (`launchServicesLoginItems`)

Seção "Itens de Início" do módulo Desempenho: apps que abrem sozinhos quando o
usuário inicia a sessão. Os textos aqui são paráfrases; os textos finais da UI são
nossos. Marcamos cada afirmação como **EVIDÊNCIA** (com a fonte entre colchetes)
ou **INFERÊNCIA**.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Análise de 2026-10-22:
árvore de Acessibilidade `re-notes/ax/perf-baseline-20261022-0228/`, baseline
`docs/re/parity/perf-baseline-2026-10-22.json`, análise estática de
`PerformanceScanning`, `PerformanceService`, `PerformanceModule`,
`CleanMyMacLoginItems` e `SharedObjcUtils` (símbolos, strings, Ghidra e
`otool`), e leitura do disco desta máquina (só leitura, sem sudo).

## 1. De onde vêm os itens

### 1.1 Fonte usada pelo CleanMyMac
- **EVIDÊNCIA** — a tarefa de análise se chama `LaunchServicesLoginItemsScanTask`
  (identificador `launchServicesLoginItems`) e pede ao `CMLoginItemsManager` a
  lista `validLoginItemsList` [E1][E2].
- **EVIDÊNCIA** — `validLoginItemsList` = `fullLoginItemsList` filtrada por
  "o caminho existe no disco" [E3].
- **EVIDÊNCIA** — `fullLoginItemsList` lê a **lista de sessão antiga**
  (`LSSharedFileListCreate` com `kLSSharedFileListSessionLoginItems` +
  snapshot). Para cada entrada guarda o **caminho** da URL resolvida (sem montar
  volumes e sem interação); se a URL não resolve, guarda o **nome exibido** da
  entrada no lugar do caminho [E3].
- **EVIDÊNCIA** — não há leitura do banco do Gerenciamento de Itens em Segundo
  Plano (BTM), de `SMAppService` nem de `Contents/Library/LoginItems` nessa
  tarefa. O framework `CleanMyMacLoginItems` só declara um tipo de estado
  (`enabled` / `disabled(canBeEnabledByUser)`) usado para os **itens do próprio
  CleanMyMac** (Menu e Health Monitor), não para listar itens de terceiros [E4].

### 1.2 O que entra
Para cada caminho válido [E2]:
1. Pede o app daquele caminho ao índice de apps (`applicationByPath:`). Se não é
   um app conhecido, **descarta**.
2. Pergunta à base de regras (`LoginItemsKnowledgeBase.shouldIgnoreApplication`)
   se deve ignorar o app. A base consulta duas vezes (pelo caminho e pelo
   identificador do pacote). A base é cifrada (`info.cmmkb`); a lista não é
   conhecida [E5].
3. Se não é ignorado, vira item com: URL do app, **nome = `displayNameAtPath:`
   do app** e o `Info.plist` do app [E2][E6].

### 1.3 Conferência nesta máquina (só leitura)
`osascript -e 'tell application "System Events" to get the name of every login item'`
devolve **5** entradas; o CleanMyMac mostra **4** [E7][E8]:

| Entrada da lista de sessão | Caminho (System Events) | No CleanMyMac? | Por quê |
|---|---|---|---|
| Hidden Bar | `~/Downloads/Hidden Bar.app` | sim | caminho existe e é app |
| Warp | `/Applications/Warp.app` | sim | idem |
| Amphetamine | `missing value` | **não** | o app não está instalado; a URL não resolve, a lista guarda só o nome, e o filtro "existe no disco" o descarta (ele seria um item do grupo "Itens de Início Defeituosos" da Limpeza, ver `../broken-login-items.md`) |
| Vorssaint | `/Applications/Vorssaint.app` | sim | caminho existe e é app |
| GlucoTracker | `/Applications/GlucoTracker.app` | sim | idem |

- **EVIDÊNCIA** — nenhum dos 4 apps tem `Contents/Library/LoginItems` (`ls`
  devolve "No such file or directory") [E9].
- **EVIDÊNCIA** — os 4 se registram com a API moderna
  `SMAppService.mainApp` (o binário do Hidden Bar, do Vorssaint e do Warp
  referencia `SMAppService`; o código do GlucoTracker chama
  `SMAppService.mainApp.register()`). No `sfltool dumpbtm` (UID 501) cada um
  aparece como registro do tipo **app (0x2)**, disposição `enabled, allowed`,
  sem "Parent Identifier"; o Amphetamine aparece do mesmo jeito, apontando para
  `/Applications/Amphetamine.app/`, que não existe [E9][E10].
- **INFERÊNCIA** — no macOS 13+, um registro `SMAppService.mainApp` é exposto
  pela lista de sessão antiga (é o que o System Events e o
  `LSSharedFileList` enxergam). Por isso o CleanMyMac vê esses apps mesmo lendo
  só a lista antiga. Conclusão: **"lista de sessão" e "BTM tipo app" são a mesma
  coisa vista por dois lados**; os 4 itens desta máquina são, ao mesmo tempo,
  entradas da lista de sessão e registros `mainApp` do BTM.

### 1.4 Itens modernos que o CleanMyMac NÃO mostra
- **EVIDÊNCIA** — no `sfltool dumpbtm` (UID 501) há registros do tipo
  **login item (0x4)**, ou seja, auxiliares embutidos em
  `<App>.app/Contents/Library/LoginItems/` e registrados via
  `SMAppService.loginItem(identifier:)` / `SMLoginItemSetEnabled`:
  "CleanMyMac Menu" e "CleanMyMac Health Monitor" (do próprio CleanMyMac) e
  "PasswordsMenuBarExtra" (da Apple) [E10]. Nenhum deles aparece na lista do
  CleanMyMac [E8].
- **INFERÊNCIA** — eles não aparecem porque não estão na lista de sessão (a única
  fonte lida). Não há, nesta máquina, nenhum item moderno do tipo 0x4 **de
  terceiros**.
- **EVIDÊNCIA** — `launchctl print-disabled gui/501` lista rótulos de auxiliares
  antigos e atuais (ex.: `com.spotify.client.startuphelper`,
  `com.bjango.istatmenus-setapp.status`), o que mostra que essa tabela guarda
  registros de itens que nem existem mais; ela **não** serve como lista de itens
  de início [E11].

## 2. Exclusão
- Entradas cuja URL não resolve ou cujo caminho não existe (passo 1.1) [E3].
- Caminhos que não são apps conhecidos pelo índice de apps (passo 1.2.1) [E2].
- Apps marcados pela base de regras (cifrada) [E5].
- Itens fora da lista de sessão (auxiliares `LoginItems` modernos, agentes do
  launchd, extensões) [E1][E10].

## 3. Recomendado
- **EVIDÊNCIA** — nenhum item vem marcado: as 4 caixas aparecem desmarcadas e o
  seletor do cabeçalho da seção mostra "Nenhum" [E8].

## 4. Agrupamento e nome exibido
- Lista plana, um item por app, ordenada por **Nome** (seletor "Ordenar por:
  Nome") [E8].
- **EVIDÊNCIA** — nome = `displayNameAtPath:` do app. Nesta máquina o nome sai
  **com a extensão** (`Warp.app`, `Hidden Bar.app`), porque o Finder está
  configurado para mostrar extensões (`AppleShowAllExtensions = 1` no domínio
  global); não é o nome da entrada da lista ("Warp")
  [E2][E8].
- Cada linha tem a caixa de seleção, o nome e um botão de "dica inteligente"
  (recurso de IA do CleanMyMac; fora do escopo) [E8].
- Cabeçalho da seção: título "Itens de Início" e uma frase sobre gerenciar os
  apps abertos ao iniciar a sessão [E8][E12].
- Rodapé: contagem de selecionados (plural "N item/itens selecionado(s)") e o
  botão **Remover** (o único botão de ação; não há "Desativar") [E8][E12].

## 5. Cálculo de tamanho
Não se aplica: os itens não mostram tamanho [E8].

## 6. Remoção no CleanMyMac
- **EVIDÊNCIA** — o removedor (`LoginItemsRemover.remove`) chama
  `CMLoginItemsManager removeLoginItemAtPath:error:` com o caminho do app [E13].
- **EVIDÊNCIA** — `removeLoginItemAtPath:error:` [E14]:
  - se o caminho **não** está na lista de sessão e está na lista de
    "desativados pelo app" (ver 6.1), tira de lá e regrava essa lista;
  - senão, procura na lista de sessão a entrada cujo caminho (ou nome, quando
    não resolve) é igual e a apaga com `LSSharedFileListItemRemove`.
- Nenhum arquivo é apagado; o app continua instalado [E14].
- Textos de resultado: título curto de sucesso, subtítulo "N itens de início"
  (plural), e na falha uma frase pedindo para tentar de novo [E12].

### 6.1 "Desativar" existe no código, mas não nesta tela
- **EVIDÊNCIA** — `CMLoginItemsManager` tem `disableLoginItemAtPath:` e
  `enableLoginItemAtPath:` [E15]:
  - desativar: lê da lista de sessão a URL e o atributo "oculto"
    (`kLSSharedFileListLoginItemHidden`) da entrada, guarda um dicionário
    `{URL, Hidden}` na preferência `AutoLaunchedApplicationDictionary` do
    domínio `com.macpaw.CleanMyMac2.DisabledLoginItems`, apaga a entrada da
    lista e **encerra** o app se estiver aberto;
  - reativar: recoloca a entrada com o mesmo "oculto", tira da preferência e
    abre o app.
- **EVIDÊNCIA** — o domínio `com.macpaw.CleanMyMac2.DisabledLoginItems` não
  existe nesta máquina (`defaults read` diz que o domínio não existe) [E16].
- **EVIDÊNCIA** — a tela do Desempenho oferece só **Remover** [E8].

## 7. A NOSSA forma (CleanYourMac)

### 7.1 Leitura
- Mesma fonte do CleanMyMac: a lista de sessão. O Core já lê assim
  (`SystemLoginItems` em `Core/Sources/CleanYourMacCore/Cleaning/Commands.swift`:
  `LSSharedFileListCreate` + snapshot + nome exibido + URL resolvida). É API
  pública (obsoleta, mas pública), então pode continuar.
- Regras de paridade: só entradas cuja URL resolve para um caminho que existe e é
  um bundle `.app`; nome = nome exibido do app pelo `FileManager.displayName`
  (o que dá `Warp.app` nesta máquina); nenhum item marcado; ordem por nome.
- Excluir sempre o próprio CleanYourMac e qualquer app `com.apple.*` (regra do
  projeto).
- Alternativa equivalente, sem `LSSharedFileList`: `tell application "System
  Events" to get {name, path, hidden} of every login item` (exige a permissão de
  Automação para o System Events).

### 7.2 Remover
- Tirar a entrada da lista de sessão. Ordem de preferência:
  1. `LSSharedFileListItemRemove` (já existe no Core, sem pedir permissão);
  2. AppleScript `tell application "System Events" to delete login item "<nome>"`
     (pede a permissão de Automação na 1ª vez).
- Não apaga nada do disco. Se o item estava na nossa lista de desativados,
  remover = tirar desse registro (como o CleanMyMac faz).

### 7.3 Desativar e Reativar
- **Desativar** = guardar o registro e tirar da lista de sessão (7.2). O app
  não é encerrado (diferente do CleanMyMac: encerrar um app aberto sem o usuário
  pedir é perda de trabalho em potencial). Registro em
  `~/Library/Application Support/CleanYourMac/disabled-login-items.json`, um
  objeto por item:

  | Campo | Para que serve |
  |---|---|
  | `name` | nome da entrada na lista (para `delete`/conferência) |
  | `path` | caminho absoluto do `.app` (para recolocar) |
  | `bundleIdentifier` | achar o app se ele mudar de lugar |
  | `hidden` | atributo "abrir oculto" da entrada original |
  | `disabledAt` | data (ISO 8601) |
  | `wasModern` | `true` se, no momento, o `sfltool dumpbtm` (só leitura, opcional) mostrava o app como registro `mainApp` (tipo app 0x2 sem pai); serve só para o aviso de 7.4 |

  Gravar o arquivo **antes** de tirar da lista; se tirar falhar, desfazer o
  registro.
- **Reativar** = `tell application "System Events" to make new login item at
  end with properties {path:"<path>", hidden:<hidden>}`; se o caminho não
  existir, tentar achar o app pelo `bundleIdentifier`; se não achar, avisar e
  manter o registro. Depois de recolocar, apagar o registro.
- A lista "Desativados" mostrada na UI vem só desse arquivo; um item desligado
  por fora (Ajustes) simplesmente não aparece na lista de sessão.

### 7.4 Itens modernos (`SMAppService` / BTM)
- **Como identificar** (só leitura):
  - auxiliar embutido: existe `<App>.app/Contents/Library/LoginItems/*.app`, ou o
    `sfltool dumpbtm` mostra um registro **login item (0x4)** com "Parent
    Identifier" do app; ou
  - app principal registrado por `SMAppService.mainApp`: registro **app (0x2)**
    com disposição `enabled` e sem pai.
- **Regra de ação**:
  - item que está na lista de sessão (inclui os `mainApp` desta máquina):
    Remover/Desativar pela lista (7.2/7.3), como o CleanMyMac;
  - item que **não** está na lista de sessão (auxiliar `LoginItems`, tipo 0x4):
    não há API pública para outro app desligá-lo. Desativar/Remover **abre
    Ajustes › Geral › Itens de Início** com
    `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` e mostra
    o guia de permissões (padrão da v0.2) com o nome do item a desligar. Nunca
    escrever no BTM.
- **INFERÊNCIA (a confirmar no teste real)** — para um app `mainApp`, tirar a
  entrada da lista pode deixar o app achando que ainda está registrado (ou o
  app pode se registrar de novo ao abrir). A confirmação de Desativar/Remover de
  um item com `wasModern = true` avisa que o próprio app pode recolocá-lo e
  sugere desligar também a opção "abrir ao iniciar sessão" dentro do app.
- Nesta máquina não há item moderno de terceiros fora da lista de sessão: os 3
  registros 0x4 são do CleanMyMac e da Apple (excluídos por regra).

## 8. Alertas e selos
- Sem selos por item. Sem alerta antes de Remover no CleanMyMac (não
  verificado por clique; inferência a partir do fluxo comum de remoção).
- No CleanYourMac: confirmação de Remover/Desativar com a lista dos itens e o
  aviso de 7.4 quando couber.

## 9. requiresAdmin
- Análise: não.
- Remover/Desativar/Reativar: não (lista do usuário). Permissão de Automação
  (System Events) só se usarmos AppleScript.

## Evidências
- **E1**: símbolos/strings de `PerformanceScanning`: `LaunchServicesLoginItemsScanTask`, `LoginItemsScanTaskFactory.makeLaunchServicesLoginItemsScanTask()`, `CMLoginItemsManagerType`, `validLoginItemsList`, `launchServicesLoginItems` (`re-notes/static/PerformanceScanning/`).
- **E2**: Ghidra de `PerformanceScanning` (`re-notes/decomp/PerformanceScanning/FUN_00003980.c` e `FUN_00003b20.c`): percorre `validLoginItemsList`, chama `applicationByPath:`, a base de regras, `displayNameAtPath:`, `applicationInfoPlist` e `url`, e monta o modelo. Os stubs ObjC estão em `FUN_00006f00.c`, `FUN_00006f80.c`, `FUN_00007100.c`, `FUN_00007120.c`.
- **E3**: Ghidra de `SharedObjcUtils`: `CMLoginItemsManager::fullLoginItemsList.c` e `::validLoginItemsList.c`.
- **E4**: símbolos e strings de `CleanMyMacLoginItems` (`LoginItemSystemSettingsStatus`, `canBeEnabledByUser`, `enabled`, `disabled`, `CleanMyMacLoginItemsManagerType`); o binário não tem outra lógica.
- **E5**: `PerformanceScanning::LoginItemsKnowledgeBase::_shouldIgnoreApplication.c` (duas consultas à base).
- **E6**: símbolos de `PerformanceService`: `LaunchServicesLoginItemModelFactory.make(name:url:plist:)`, `LaunchServicesLoginItemModel.{name,url,plist}`.
- **E7**: `osascript` (System Events) nesta máquina, só leitura: nomes `Hidden Bar, Warp, Amphetamine, Vorssaint, GlucoTracker`; caminhos com `missing value` para o Amphetamine; `hidden` = `false` para todos.
- **E8**: AX `re-notes/ax/perf-baseline-20261022-0228/login-items.txt` e baseline JSON (4 itens, caixas desmarcadas, "Selecionar: Nenhum", "Ordenar por: Nome", botão Remover).
- **E9**: `ls <App>.app/Contents/Library/LoginItems` (inexistente nos 4); `nm -u`/`strings` dos binários de Hidden Bar, Vorssaint e Warp (`SMAppService`, `mainAppService`); `GlucoTracker/Application/Services/LaunchAtLoginController.swift` usa `SMAppService.mainApp`.
- **E10**: `sfltool dumpbtm` sem root (saída salva no scratchpad desta sessão como `btm.txt`): registros UID 501 do tipo app (0x2) para Amphetamine, GlucoTracker, Hidden Bar, Vorssaint e Warp; registros login item (0x4) para CleanMyMac Menu, CleanMyMac Health Monitor e PasswordsMenuBarExtra.
- **E11**: `launchctl print-disabled gui/501` (só leitura).
- **E12**: `re-notes/static/PerformanceModule/localizable-pt-BR.json` e `PerformanceModule.framework/.../pt-BR.lproj/Localizable.stringsdict` (chaves `login_items_*`, `cleanup_complete_*_login_items_*`, `login_items_footer_selected_items_count `).
- **E13**: `otool` de `PerformanceService` em `LoginItemsRemover.remove(value:)`: chamada a `removeLoginItemAtPath:error:` com o caminho do modelo.
- **E14**: `CMLoginItemsManager::removeLoginItemAtPath:error:.c`, `::loginItemIsDisabled:.c`, `::deleteAppPathFromLoginItems:error:.c` (SharedObjcUtils).
- **E15**: `CMLoginItemsManager::disableLoginItemAtPath:.c`, `::enableLoginItemAtPath:.c`, `::disabledLoginItemsList.c`, `::writeDisabledLoginItemsList:.c`.
- **E16**: `defaults read com.macpaw.CleanMyMac2.DisabledLoginItems` nesta máquina: domínio inexistente.

## Divergências conhecidas
- **Desativar/Reativar**: o CleanMyMac 5 só oferece Remover nesta tela. Nós
  oferecemos também Desativar (reversível), por decisão do usuário. Ao desativar
  não encerramos o app.
- **Registro de desativados**: o CleanMyMac usa uma preferência
  (`com.macpaw.CleanMyMac2.DisabledLoginItems`); nós usamos um JSON nosso em
  `~/Library/Application Support/CleanYourMac/`.
- **Base de regras cifrada**: a lista de apps ignorados não é conhecida; a nossa
  começa com o próprio CleanYourMac e `com.apple.*`.
- **Itens 0x4 de terceiros**: o CleanMyMac não os lista. Se quisermos mostrá-los
  (com a ação "abrir Ajustes"), isso é uma extensão nossa, fora da paridade;
  na v0.3 seguimos o CleanMyMac e não listamos.

## Checklist de testes
1. Lista de sessão com 1 app existente → 1 item, nome = nome exibido do app, desmarcado.
2. Entrada cuja URL não resolve (app apagado) → nenhum item (vai para "Itens de Início Defeituosos" da Limpeza).
3. Entrada que aponta para uma pasta ou documento (não `.app`) → nenhum item.
4. Entrada do próprio CleanYourMac ou de app `com.apple.*` → nenhum item.
5. Remover → a entrada some da lista de sessão; o `.app` continua no disco.
6. Desativar → registro gravado no JSON com `name`, `path`, `bundleIdentifier`, `hidden`; a entrada some da lista; o app aberto continua aberto.
7. Reativar → a entrada volta com o mesmo `hidden`; o registro some do JSON.
8. Reativar com o app movido → acha pelo `bundleIdentifier`; com o app apagado → aviso e registro mantido.
9. Remover um item que está só no JSON (desativado) → sai do JSON; nada muda na lista de sessão.
10. App `mainApp` (ex.: app de teste nosso com `SMAppService.mainApp.register()`): aparece na lista; Desativar mostra o aviso de 7.4; conferir se o app volta a se registrar ao abrir.
11. Auxiliar 0x4 de terceiros (app de teste com `Contents/Library/LoginItems`): não aparece na lista (paridade).
12. Ordem por nome, sem diferenciar maiúsculas.
