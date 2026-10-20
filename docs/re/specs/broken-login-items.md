# Itens de Início Defeituosos (`brokenLoginItems`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2. Análise de 2026-10-20 (baseline
`baseline-20261020-1457`).

## Visão geral
O grupo junta **duas sub-análises** num único resultado (identificador composto
`BrokenStartupItems`) [E1]:

1. **Itens de início da sessão** (`BrokenLoginItems`): entradas da lista de Itens
   de Início do usuário cujo alvo não existe mais [E2][E3].
2. **Agentes/daemons do launchd** (`BrokenLaunchdAgents`): arquivos `.plist` de
   configuração do launchd cujo executável não existe mais [E4][E5].

Cada item resultante tem um **tipo**: `0 = loginItem` e `1 = launchdAgent` [E3][E5].
A lista é plana, sem subgrupos.

## Locais varridos

### Sub-análise 1: itens de início
- A lista de itens de início da **sessão do usuário atual**, lida pela API
  `LSSharedFileList` com a lista `kLSSharedFileListSessionLoginItems`, com um
  snapshot da lista [E6]. Para cada entrada, são lidos [E7]:
  - a URL resolvida do alvo (só quando é uma URL de arquivo);
  - o nome exibido da entrada;
  - as chaves do `Info.plist` do bundle-alvo, quando o alvo existe.
- Não é varrido o banco de BTM (`/private/var/db/com.apple.backgroundtaskmanagement`)
  nem os itens de `SMAppService` [E6].

### Sub-análise 2: plists do launchd
As raízes vêm de `NSSearchPathForDirectoriesInDomains(Library, user+local)`, ou seja,
`~/Library` e `/Library` [E8]. Em cada uma, três pastas [E9]:

| Pasta |
|---|
| `~/Library/LaunchAgents` |
| `~/Library/LaunchDaemons` |
| `~/Library/PrivilegedHelperTools` |
| `/Library/LaunchAgents` |
| `/Library/LaunchDaemons` |
| `/Library/PrivilegedHelperTools` |

- Só os **filhos diretos** (sem recursão) cuja extensão é exatamente `plist` [E9].
- `/System/Library/...` **não** entra nessa varredura [E8][E9].
- O conjunto não tem duplicatas (é um conjunto de caminhos) [E9].

## Inclusão

### Item de início (tipo 0)
Para cada entrada da lista [E3]:
1. Se a entrada **tem URL** e o arquivo **existe** no disco → não está quebrada, e é ignorada.
2. Se tem URL, o arquivo não existe e a base de regras manda ignorar a URL → ignora.
3. Se **não tem URL** (o alvo não resolve) e tem nome, e a base manda ignorar esse
   nome → ignora.
4. Nos outros casos, vira item:
   - tamanho = tamanho do alvo (na prática é 0, porque o alvo não existe; sem URL, é 0);
   - nome exibido = nome da entrada; na falta dele, o nome de exibição do caminho
     (`displayName`); na falta deste, o último componente do caminho sem a extensão;
   - recomendado = **sim**.

> Conclusão: uma entrada cuja URL não resolve é considerada **quebrada**
> (a menos que a base a ignore).

### Agente do launchd (tipo 1)
Para cada `.plist` encontrado [E5]:
1. Se o arquivo **não é legível** pelo processo → ignora.
2. Se a base de regras manda ignorar a URL → ignora.
3. Lê o plist como dicionário e aplica o critério de "quebrado" (abaixo).
4. Se está quebrado, vira item:
   - URL = o próprio `.plist`;
   - tamanho = tamanho do `.plist`;
   - nome exibido = **nome do arquivo com extensão** (ex.: `com.foo.agent.plist`);
   - recomendado = **sim**;
   - a configuração (o dicionário) é guardada no item.

#### Critério de "quebrado" do agente [E4]
1. Executável = valor de `Program` (string). Se não houver, usa o 1º elemento de
   `ProgramArguments` (se o array existir e não estiver vazio).
2. Se existir `WorkingDirectory` e o executável **não começar com `/`**, o
   executável vira `WorkingDirectory/<executável>`.
3. Padroniza o caminho e expande `~`.
4. Se **não sobrou caminho nenhum** (sem `Program`, sem `ProgramArguments`, ou
   plist que não pôde ser lido como dicionário) → **quebrado**.
5. Se o caminho estiver numa área **sem permissão de leitura** (em algum nível
   acima):
   - sem autorização de admin no momento → **não quebrado** (é conservador);
   - com autorização → a existência é verificada pelo executor privilegiado.
6. Caso contrário, verifica a existência normalmente.
7. Se o executável **existe** → não quebrado.
8. Se não existe, mas o **nome do arquivo** do executável é igual a uma das chaves
   `SMPrivilegedExecutables` do `Info.plist` de algum app instalado (conhecido pelo
   índice de apps) → **não quebrado** (o app pode reinstalar o helper) [E10].
9. Senão → **quebrado**.

## Exclusão
- Entradas e plists marcados pela base de regras (`shouldIgnoreURL` /
  `isIgnoreItem` no contexto deste grupo) [E11]. A base é cifrada, então a nossa
  lista equivalente começa vazia (ver Divergências).
- Plists ilegíveis (sub-análise 2, passo 1).
- Executáveis em áreas protegidas quando não há autorização (passo 5).
- Helpers declarados em `SMPrivilegedExecutables` de apps instalados (passo 8).

## Recomendado
Todos os itens vêm **marcados** (`isAutoselected = true`), dos dois tipos [E3][E5].

## Agrupamento e nome exibido
- Lista plana, um item por entrada/plist.
- Nome: ver Inclusão. Não há filhos ao expandir.
- Ícone: o código de análise não define um ícone por item. Proposta: para o tipo 0,
  o ícone genérico de app; para o tipo 1, o ícone de documento `.plist` (o ícone do
  arquivo dado pelo `NSWorkspace`).
- Ícone do grupo na lista de grupos: imagem própria do grupo (`system junk broken
  login items` na árvore AX) [E12]. A nossa arte é própria.

## Cálculo de tamanho
- Tipo 0: tamanho do alvo (alocado, via o serviço de tamanho de arquivos), que em
  geral é 0 porque o alvo não existe.
- Tipo 1: tamanho do arquivo `.plist` [E5].
- O total do grupo costuma ser de poucos KB, ou 0 KB quando há só itens do tipo 0.

## Remoção
O removedor decide pelo tipo [E13]:

**Tipo 0 (item de início):** remove a entrada da lista de Itens de Início pelo
caminho (o caminho da URL; sem URL, o nome) [E13][E14]:
- se a entrada estiver na lista de itens **desativados pelo próprio app**, ela é
  retirada dessa lista e a lista é regravada;
- senão, a entrada é apagada da lista da sessão (`LSSharedFileList`);
- não apaga nenhum arquivo do disco.

**Tipo 1 (agente launchd):** [E13][E15]
1. Roda `/bin/launchctl unload <caminho-do-plist>`.
2. Se o comando não retornar saída (sucesso): se existir
   `/Library/PrivilegedHelperTools/<label>` (label = nome do plist sem a extensão),
   esse helper é apagado. Depois, o `.plist` é apagado com `removeItem`
   (definitivo, sem Lixo).
3. Se o `unload` falhar (por exemplo, plist em `/Library`, que é do root), a remoção
   passa para o **executor privilegiado** (admin). Sem executor disponível → erro.

Erro por item: uma mensagem genérica com o nome do item (parafrasear: "não foi
possível remover os itens de início de X").

## Alertas e selos
Nenhum alerta ou selo específico.

## requiresAdmin
- Análise: não (há verificação privilegiada opcional para executáveis em áreas
  protegidas; sem admin, esses casos contam como não quebrados).
- Limpeza: tipo 0, não; tipo 1, não para `~/Library/...` e **sim** para `/Library/...`.

## Regras prontas (modelo CleanYourMac)
| Regra | Valor |
|---|---|
| Raízes (tipo 1) | `~/Library/LaunchAgents`, `~/Library/LaunchDaemons`, `~/Library/PrivilegedHelperTools`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools` |
| Nível | filhos diretos, glob `*.plist` (extensão exata, minúscula) |
| Fonte (tipo 0) | `LSSharedFileList` / `kLSSharedFileListSessionLoginItems` |
| Idade mínima | nenhuma |
| Recomendado | sim |
| Remoção tipo 0 | tirar da lista de itens de início |
| Remoção tipo 1 | `launchctl unload` + apagar o helper homônimo + apagar o plist (definitivo); admin se for em `/Library` |

## Baseline observada
- Grupo "Itens de Início Defeituosos": **0 KB**, nenhum item ("nada para limpar") [E12].
- Leitura do disco, só leitura: nenhum `.plist` em `~/Library/LaunchAgents`,
  `/Library/LaunchAgents` ou `/Library/LaunchDaemons` aponta para um executável
  ausente ou deixa de ter `Program`/`ProgramArguments`.
  `~/Library/LaunchDaemons` e `~/Library/PrivilegedHelperTools` não existem [E16].
  Isso é consistente com o 0 KB.

## Evidências
- **E1**: pseudocódigo de `CMBrokenStartupItemsScanTask scanTaskWithKnowledgeBase:privilegedOperationsPerformer:`. Cria a tarefa composta com as duas subtarefas (login items + launchd agents). String `CMSystemJunkScanIdentifierBrokenStartupItems`.
- **E2**: pseudocódigo de `CMBrokenLoginItemsScanTask scan`. Pede `loginItemInfos` ao `CMLoginItemsManager` e mapeia cada uma.
- **E3**: pseudocódigo do bloco de mapeamento de `CMBrokenLoginItemsScanTask scan` (FUN_00005d1c). Regras de existência, ignorar, nome, `CMStartupItemModel` com tipo 0 e autoselecionado.
- **E4**: pseudocódigo de `CMBrokenLaunchdAgentsItemsScanTask _isLaunchdAgentBrokenWithConfiguration:`. Strings `Program`, `ProgramArguments`, `WorkingDirectory`.
- **E5**: pseudocódigo de `CMBrokenLaunchdAgentsItemsScanTask scan` e do seu bloco (FUN_00005150). Legibilidade, ignorar, tamanho, modelo do tipo 1 com nome = último componente.
- **E6**: pseudocódigo de `CMLoginItemsManager accessLoginItemsWithBlock:` e `loginItemInfos` (SharedObjcUtils). `LSSharedFileListCreate` com `kLSSharedFileListSessionLoginItems` + snapshot.
- **E7**: pseudocódigo de `CMLoginItemsManager infoFromLoginItem:`. URL resolvida (só file URL), chaves do `Info.plist`, nome exibido.
- **E8**: pseudocódigo de `CMPaths libraryPaths` (SharedObjcUtils). Domínio usuário+local da pasta Library.
- **E9**: pseudocódigo de `CMSystemInfo allLaunchFiles` (ApplicationsService). Sufixos `/LaunchAgents`, `/LaunchDaemons`, `/PrivilegedHelperTools`; filtro por extensão `plist`; conjunto.
- **E10**: pseudocódigo de `CMBrokenLaunchdAgentsItemsScanTask _isAgentInPathOwnedByAnyApp:` e `CMApplicationInfo privilegedExecutables` (chaves de `SMPrivilegedExecutables`).
- **E11**: pseudocódigo de `BrokenLoginItemsKnowledgeBase shouldIgnoreURL:` / `isIgnoreItem:` (JunkCleanupModule). Delegam para a base de regras por categoria.
- **E12**: observação da baseline, `Detritos do Sistema/Itens de Início Defeituosos.txt` e `_category.txt`.
- **E13**: pseudocódigo de `BrokenStartupItemRemover.removeItem(_:)` e das funções auxiliares (SystemJunkScanning). Despacho por tipo; tipo 1 chama `removeAgentAtPath:` com fallback no executor privilegiado; tipo 0 chama `removeLoginItemAtPath:error:`.
- **E14**: pseudocódigo de `CMLoginItemsManager removeLoginItemAtPath:error:`. Lista de desativados vs. `deleteAppPathFromLoginItems:error:`.
- **E15**: pseudocódigo de `CMLaunchdManager removeAgentAtPath:filesRemoverBlock:`, `unloadLaunchAgentWithConfigPath:filesRemoverBlock:` e `removePrivilegedToolWithLabel:filesRemoverBlock:`. Strings `/bin/launchctl`, `unload`.
- **E16**: leitura do disco (PlistBuddy, só leitura) dos plists nas pastas acima, em 2026-10-20.

## Divergências conhecidas
- **Não houve observação real** de um item quebrado. O grupo estava vazio (0 KB) e
  todas as regras vêm da análise estática. A paridade de nome e ícone na UI não foi
  conferida.
- **Base de regras cifrada** (`info.cmmkb`): as listas de "ignorar" por URL ou por
  nome deste grupo não são conhecidas. Proposta: começar com uma lista vazia,
  configurável, e ignorar sempre os plists cujo nome comece com `com.apple.`
  (proteção extra; nas pastas varridas, a Apple quase nunca instala plists que
  quebram).
- **API de Itens de Início**: `LSSharedFileList` é obsoleta. No macOS 13+ ela não
  mostra os itens de "Abrir ao iniciar sessão" registrados via BTM/`SMAppService`.
  Para paridade, usamos a mesma API (ela continua disponível, com aviso de
  deprecação). Se ela não estiver disponível, a sub-análise 1 fica desligada e a
  sub-análise 2 continua.
- **Plist sem `Program`/`ProgramArguments`** (ex.: uso só de `BundleProgram`) é
  marcado como quebrado pelo CleanMyMac. Mantemos esse comportamento para paridade,
  mas o marcamos como suspeito no teste. Avaliar uma exceção para `BundleProgram`
  quando o bundle associado existir.
- A "lista de itens desativados pelo app" é um recurso do CleanMyMac (gerenciador de
  itens de início) que não existe no CleanYourMac. Ignoramos esse ramo.
- A forma exata da remoção privilegiada no fallback (se faz também o `unload` como
  root) não é visível. Proposta: com admin, `launchctl bootout system <plist>`
  (ignorando erro) e depois apagar o plist.

## Checklist de testes
1. `~/Library/LaunchAgents/x.plist` com `Program=/nao/existe` → 1 item tipo 1, nome `x.plist`, marcado, tamanho = tamanho do plist.
2. Igual, mas `Program=/bin/ls` → nenhum item.
3. `ProgramArguments=["/nao/existe","-a"]` sem `Program` → item.
4. `ProgramArguments=["rel/tool"]` + `WorkingDirectory=/tmp/wd`, com `/tmp/wd/rel/tool` existente → nenhum item; sem o arquivo → item.
5. `ProgramArguments=["~/bin/tool"]` → `~` expandido antes de checar.
6. Plist sem `Program` e sem `ProgramArguments` → item (quebrado).
7. Plist corrompido (texto inválido) → item (quebrado).
8. Arquivo `y.txt` na pasta → ignorado (extensão diferente); `z.PLIST` → ignorado (extensão exata `plist`).
9. Plist dentro de uma subpasta de `LaunchAgents` → ignorado (sem recursão).
10. Plist sem permissão de leitura → ignorado.
11. Executável ausente cujo nome do arquivo = chave `SMPrivilegedExecutables` de um app instalado → nenhum item.
12. Executável numa pasta ilegível, sem admin → nenhum item.
13. Item de início com URL de um app apagado → item tipo 0, tamanho 0, nome = nome da entrada, marcado.
14. Item de início com app existente → nenhum item.
15. Remoção do tipo 1 em `~/Library` → `launchctl unload` chamado com o caminho do plist; plist apagado; `/Library/PrivilegedHelperTools/<label>` apagado se existir.
16. Remoção do tipo 1 em `/Library` sem admin → erro reportado com o nome do item.
17. Remoção do tipo 0 → a entrada sai da lista de itens de início e nenhum arquivo é apagado.
