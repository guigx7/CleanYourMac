# Tarefas de manutenção (`maintenanceTasks`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83, Darwin 25.6), Apple Silicon (arm64),
2026-10-22. **Só análise estática e leitura do disco**: nenhuma tarefa foi executada, nada
foi clicado no CleanMyMac, nenhum `sudo`.

Legenda: **[E*n*]** = evidência (lista no fim); **(inferência)** = conclusão nossa, ainda
não confirmada no binário nem por observação.

## Visão geral

### Onde mora cada parte no CleanMyMac
- **Quais tarefas existem e em que ordem interna**: `PerformanceScanning.PerformanceTaskIdentifier`
  (10 casos: 8 tarefas + itens de início + agentes do launchd) [E1].
- **Quando cada tarefa é aplicável**: uma única função pura,
  `PerformanceMaintenanceTaskAvailability.isScanTaskAvailable(for:flow:isSandbox:isAppleSilicon:systemVersion:isAPFS:)`
  [E2]. As fábricas de tarefas de análise (`MaintenanceScanTaskFactory.make…Task`) só montam o
  modelo da tarefa e não têm condição própria, com uma exceção: a das capturas do Time Machine
  (ver `time-machine.md`) [E3].
- **Como cada tarefa roda**: `PerformanceService.*TaskRunner` [E4]. Quatro delas pedem ao
  **ajudante privilegiado** (`com.macpaw.CleanMyMac-setapp.Agent`, que roda como root) uma
  operação tipada: `FlushDNSCacheRequest`, `ReindexSpotlightRequest`,
  `RepairDiskPermissionsRequest(userId:)`, `PeriodicScriptRequest(script:)` [E5]. As outras
  quatro rodam no próprio processo do app, como o usuário.

### Fluxos
O `flow` tem três valores: `main` (o módulo Desempenho), `smartCare` (a Limpeza Inteligente) e
`toolbox` (os atalhos "Tarefas de manutenção" / "Capturas do Time Machine" da busca) [E2]. Esta
spec trata do `main`. No `smartCare` só entram Esvaziar Cache do DNS, Liberar Espaço Purgável e
(no macOS < 14) Executar Scripts Periódicos; Acelerar o Mail, Reparar Permissões, Reindexar o
Spotlight, Diminuir Capturas e Liberar RAM ficam fora [E2].

### Regra de aplicabilidade (fluxo `main`, decodificada de [E2])
Seja `semSandbox` = o app não está em sandbox (o CleanMyMac do Setapp não está; o CleanYourMac
também não).

| Tarefa | Aplicável quando |
|---|---|
| speedUpMail | `semSandbox` |
| flushDNS | `semSandbox` |
| freeUpPurgeable | `semSandbox` |
| reindexSpotlight | `semSandbox` |
| repairPermissions | `semSandbox` |
| freeUpRAM | **não** é Apple Silicon (sandbox não importa) |
| periodicScripts | `semSandbox` **e** versão do macOS **< 14.0** |
| thinSnapshots | `semSandbox` **e** o volume de inicialização é APFS **e** (fábrica) existe ao menos uma captura local do Time Machine |

A versão é comparada como número `maior × 100 + menor` (14.0 → 1400; 26.6 → 2606), e a regra
das tarefas periódicas é "versão atual menor que 1400" [E6].

### Por que só 5 apareceram nesta máquina
- **Liberar RAM**: o Mac é Apple Silicon (`uname -m` = `arm64`), e a regra exclui Apple Silicon
  em qualquer fluxo [E2][E7].
- **Executar Scripts Periódicos**: macOS 26.6 ≥ 14.0, então a tarefa é cortada pela versão
  [E2][E6]. Além disso, o `/usr/sbin/periodic` e o `/etc/periodic` nem existem nesta máquina
  [E7]. O corte do CleanMyMac é por versão e não pela presença da ferramenta.
- **Diminuir Capturas do Time Machine**: `tmutil listlocalsnapshots /` não lista nenhuma
  captura (o Time Machine não tem destino configurado; a única captura APFS do volume é a
  `com.apple.os.update-…` do sistema selado, que não começa com `com.apple.TimeMachine`)
  [E7][E8]. Detalhes em `time-machine.md`.

### Recomendada
- **Não achamos regra de intervalo.** Não há data de última execução gravada nas preferências
  (`com.macpaw.CleanMyMac-setapp`, `.HealthMonitor`, `.Menu`) nem texto ou símbolo de "última
  execução" no módulo [E9]. Também não há limite de tamanho do `Envelope Index` em
  nenhum dos frameworks de desempenho.
- O cartão de Resultados disse "5 Tarefas de Manutenção Recomendadas", exatamente o número de
  tarefas aplicáveis. O módulo usa uma estratégia simples de autosseleção
  (`PerformanceModuleConfig.autoSelectableStrategy: SimpleAutoSelectableStrategy`) [E10].
  **(inferência)**: no fluxo `main`, **toda tarefa aplicável é recomendada** (vem marcada); o
  título da rotina ("manutenção semanal", `tile_weekly_maintenance_cocktail_*`) é só texto,
  sem agenda por trás.
- Os três ícones do cartão (Mail, DNS, purgável) são as três primeiras tarefas da lista.
  **(inferência)**: a lista sai em ordem alfabética do título localizado (Acelerar, Esvaziar,
  Liberar, Reindexar, Reparar), e o cartão mostra os primeiros ícones.
- **Dúvida em aberto**: se o Liberar Espaço Purgável some quando a estimativa é 0. A fábrica
  sempre cria o modelo [E11]; o filtro, se existir, estaria no PerformanceModule (não
  decompilado nesta etapa).

## As 8 tarefas

### 1. Acelerar o Mail (`speedUpMail`)
**O que o CleanMyMac faz** [E12][E13]:
1. Verifica se existe a pasta `~/Library/Mail`. Se não existe, falha com "sem pasta do Mail"
   (`noMailFolder`).
2. Num executor com progresso, roda um **`VACUUM;`** no banco `Envelope Index` do Mail
   (`~/Library/Mail/<V mais recente>/MailData/Envelope Index`), aberto com FMDB **no próprio
   processo do app, como o usuário**. A pasta `V*` é a "última versão usada" que o provedor
   de contas do Mail informa. Se o executor não pode ser criado ou o VACUUM falha, a tarefa
   falha ("Mail Vacuum process failed").
3. Depois roda `/usr/bin/mdimport` com **um argumento** (o caminho da pasta do Mail;
   **inferência** a partir do tamanho do array, ainda não confirmada) para o Spotlight
   reimportar as mensagens.
- **Root**: não. **Acesso Total ao Disco**: sim (sem ele, o `~/Library/Mail` não pode ser
  lido; a UI tem um balão "Conceder Acesso" só para esta tarefa) [E14].
- **Mail aberto**: não achamos verificação nem encerramento do Mail no executor
  (**inferência**: o CleanMyMac roda o VACUUM mesmo com o Mail aberto).
- **Tempo-limite**: nenhum explícito encontrado.
- **Aplicável**: `semSandbox` (a pasta do Mail só é checada ao executar).

**Nossa forma** (decisão do construtor na execução, ver ledger da v0.3):
- O design da v0.3 proíbe escrever no `Envelope Index` por fora, então **não fazemos VACUUM**.
  A tarefa roda só `/usr/bin/mdimport ~/Library/Mail` (como o usuário), que pede ao Spotlight
  para reimportar as mensagens: é o que melhora a busca do Mail, e a descrição promete só isso.
- Aplicável se `~/Library/Mail` existe (o CleanMyMac mostra sempre; quem não usa o Mail não vê
  uma tarefa que falharia).
- Exige Acesso Total ao Disco (guia de permissões existente). Pode rodar com o Mail aberto.
- Root: **não**. Tempo-limite: 10 min.

## 2. Esvaziar Cache do DNS (`flushDNS`)
**O que o CleanMyMac faz** [E5][E15]: o app pede `FlushDNSCacheRequest` ao ajudante. O
ajudante, **como root**, roda `/usr/bin/dscacheutil -flushcache` e depois
`/usr/bin/killall -HUP mDNSResponder`. Se o ajudante não está autorizado ou conectado, a
tarefa falha com "você não autorizou" ("Not authorized privileged agent").
- **Tempo-limite**: nenhum encontrado no app; o executor do ajudante não foi decodificado.
- **Aplicável**: `semSandbox`.

**Nossa forma**: operação tipada no nosso ajudante (sem shell livre), as mesmas duas linhas:
`/usr/bin/dscacheutil -flushcache` e `/usr/bin/killall -HUP mDNSResponder`. Root: **sim** (o
`killall` no `mDNSResponder`, que é do sistema, exige). Tempo-limite: 30 s.

### 3. Liberar Espaço Purgável (`freeUpPurgeable`)
**De onde vem o "Até X GB"** [E11][E16]: a fábrica do modelo chama
`CSDiskSpaceGetRecoveryEstimate` com a URL `/`. É **API pública** do CoreServices
(`CarbonCore/DiskSpaceRecovery.h`, macOS 10.7+), que devolve uma estimativa rápida e
conservadora dos bytes recuperáveis. O valor vira o subtítulo "Até %@".
- Medido nesta máquina (só leitura): estimativa = **3.870.242.029 bytes (3,87 GB)**, idêntica a
  `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity` do `URLResourceValues`
  (268,98 GB − 265,11 GB) [E17]. O CleanMyMac mostrou "Até 3,8 GB" e depois "Até 3,9 GB",
  coerente com esse valor (que varia um pouco).

**O que o CleanMyMac executa** [E16]: **não enche o disco.** Usa a API pública
`CSDiskSpaceStartRecovery("/", bytesNeeded, options: 0, …)`, com
`bytesNeeded = espaço livre atual (NSURLVolumeAvailableCapacityKey) + estimativa`, ou seja,
pede ao sistema para liberar tudo o que estimou. Cancelar chama `CSDiskSpaceCancelRecovery`.
A limpeza real é feita pelo próprio macOS (processo auxiliar do sistema), que pode apagar
capturas locais do Time Machine e caches e, com `options = 0`, pode pedir confirmação ao
usuário antes de algo destrutivo.
- **Root**: não (roda no app, como o usuário).
- **Falhas**: a API devolve erro; cancelada no meio ("canceled mid-operation").
- **Tempo-limite**: nenhum explícito encontrado.
- **Aplicável**: `semSandbox`.

**Nossa forma**: a mesma API pública, que é segura:
1. Estimar com `CSDiskSpaceGetRecoveryEstimate(URL(fileURLWithPath: "/"))`.
2. Executar com `CSDiskSpaceStartRecovery` no `/`, `bytesNeeded` = livre atual + estimativa,
   `options = 0` (deixar o sistema pedir confirmação quando for apagar capturas), callback numa
   fila nossa; cancelar com `CSDiskSpaceCancelRecovery`.
3. Resultado = livre depois − livre antes (pode ser menor que a estimativa; a descrição diz
   "até").
- Aplicável quando a estimativa for **> 0** (decisão nossa; ver dúvida em aberto).
- Root: **não**. Tempo-limite sugerido: 10 min (depois disso, cancelar e relatar o parcial).
- Não usar `purge` aqui: o `purge` mexe em memória e cache de disco, não em espaço purgável.

### 4. Reindexar o Spotlight (`reindexSpotlight`)
**O que o CleanMyMac faz** [E5][E15]: pede `ReindexSpotlightRequest` ao ajudante, que roda
**como root** `/usr/bin/mdutil -E /` (apaga e recria o índice do volume de inicialização). O
app observa o estado da indexação (`CMSpotlightIndexingObserver`) para mostrar que o Spotlight
está reindexando.
- **Tempo-limite**: nenhum encontrado (o `mdutil -E` volta logo; a indexação continua em
  segundo plano).
- **Falhas**: ajudante não autorizado; script com erro.
- **Aplicável**: `semSandbox`.

**Nossa forma**: operação tipada no ajudante: `/usr/bin/mdutil -E /`. Antes, ler
`mdutil -s /` (sem root) e não oferecer a tarefa se a indexação estiver desligada no volume.
Avisar que é pesada (busca fica incompleta por um tempo). Root: **sim**. Tempo-limite: 60 s para
o comando; o progresso da reindexação é só informativo.

### 5. Reparar Permissões do Disco (`repairPermissions`)
**O que o CleanMyMac faz** [E5][E15][E18]: o app pega o `getuid()` do usuário e pede
`RepairDiskPermissionsRequest(userId:)` ao ajudante, que roda **como root**
`/usr/sbin/diskutil resetUserPermissions / <uid>`. O app espera num semáforo com
**tempo-limite de 1800 s (30 min)**; se passar, falha com "tempo esgotado". Pode ser
cancelada.
- **Falhas**: ajudante não autorizado; `diskutil` falha ao iniciar ou devolve erro; tempo
  esgotado.
- **Aplicável**: `semSandbox`.

**Nossa forma**: operação tipada no ajudante: `/usr/sbin/diskutil resetUserPermissions /
<uid>`, com o `uid` do usuário logado validado pelo ajudante (nunca 0, tem que ser o dono da
sessão que pediu). Root: **sim**. Tempo-limite: 30 min (paridade). Descrição honesta: refaz as
permissões e ACLs da pasta do usuário. Não é o antigo "reparar permissões" do sistema, que não
existe desde o macOS 10.11. Falha conhecida: o `diskutil` pode recusar partes da pasta
protegidas pelo TCC/SIP; tratar código ≠ 0 como falha parcial, com a saída no registro.

### 6. Liberar RAM (`freeUpRAM`)
**O que o CleanMyMac faz** [E19]: no próprio processo, como o usuário (`CMTimedRAMCleaner` /
`CMRAMCleaner`): aloca blocos de 256 MB cheios de dados aleatórios, até o total da RAM,
para forçar o sistema a comprimir e paginar a memória dos outros processos. Para quando não
consegue alocar, quando a memória comprimida "estoura" duas vezes, quando o relatório de RAM
falha, ou no cancelamento/tempo-limite (`cleanWithTimeout:`). Depois libera tudo.
- **Aplicável**: só em Mac **Intel** (não Apple Silicon) [E2].

**Avaliação**: método **arriscado** (provoca pressão de memória de propósito, pode deixar o
Mac lento durante a tarefa e empurrar dados de outros apps para o swap; o ganho é cosmético).

**Nossa forma**:
- Apple Silicon: **não aplicável** (paridade).
- Intel: **não copiamos a pressão de memória.** Usamos `/usr/sbin/purge` (libera o cache de
  disco inativo; ferramenta do macOS) pelo ajudante. Root: **sim**. Tempo-limite: 2 min.
  Descrição honesta: "libera o cache de arquivos em memória" (sem prometer acelerar).
- Se o CleanYourMac for só arm64, a tarefa existe no Core (para o modelo ficar completo), mas
  nunca é aplicável.

### 7. Executar Scripts Periódicos (`periodicScripts`)
**O que o CleanMyMac faz** [E5][E15][E20]: o modelo tem a lista de scripts (diário, semanal e
mensal, pela descrição da tarefa) e o app pede um `PeriodicScriptRequest(script:)` por script,
em sequência. O ajudante roda **como root** `/usr/sbin/periodic <script>`. Para no primeiro que
falhar.
- **Tempo-limite**: nenhum encontrado.
- **Aplicável**: `semSandbox` e macOS **< 14.0** [E2][E6].

**Nossa forma**: mesma regra de versão **e** `/usr/sbin/periodic` existente e executável. Pelo
ajudante: `/usr/sbin/periodic daily`, depois `weekly`, depois `monthly`. Root: **sim**.
Tempo-limite: 10 min por script. Nesta máquina (macOS 26), nunca aplicável.

### 8. Diminuir Capturas do Time Machine (`thinSnapshots`)
Resumo (detalhes em `time-machine.md`): `/usr/bin/tmutil thinlocalsnapshots / 1073741824 3`,
**no processo do app, sem o ajudante**; aplicável se `semSandbox`, volume de inicialização APFS
e `tmutil listlocalsnapshots /` listar ao menos uma linha `com.apple.TimeMachine…` [E3][E21].
Nossa forma: igual, como o usuário; root: **não** (com fallback pelo ajudante se o `tmutil`
recusar). Tempo-limite: 10 min.

## Falhas previstas (todas as tarefas)
Textos de erro do módulo (paráfrase) [E14]:
- **genérica**: a tarefa não rodou por motivo desconhecido;
- **cancelada**: parou porque o usuário cancelou;
- **sem pasta do Mail**: só no Acelerar o Mail;
- **sem autorização**: o usuário não autorizou a operação de administrador (ajudante);
- **tempo esgotado**: a tarefa passou do tempo-limite;
- **Acesso Total ao Disco**: o Acelerar o Mail pede antes de rodar.

Resultado da tela final: sucesso ("tarefas concluídas") ou falha geral ("não foi possível
executar algumas tarefas"), com registro por tarefa [E14].

Nossa política: cada tarefa roda isolada; a falha de uma não impede as outras; o registro
guarda comando, código de saída e saída de erro (sem dados pessoais do Mail).

## Tabela-resumo

| ID | Aplicável quando | Recomendada quando | Root? | Timeout sugerido | Nosso comando |
|---|---|---|---|---|---|
| speedUpMail | `~/Library/Mail` existe (CMM: sempre, fora de sandbox) | aplicável | não (precisa de Acesso Total ao Disco) | 10 min | `mdimport ~/Library/Mail` (sem VACUUM, regra do design) |
| flushDNS | sempre (fora de sandbox) | aplicável | **sim** | 30 s | `dscacheutil -flushcache` + `killall -HUP mDNSResponder` |
| freeUpPurgeable | estimativa > 0 (CMM: sempre) | aplicável | não | 10 min | `CSDiskSpaceStartRecovery("/", livre + estimativa, 0)` (API pública) |
| reindexSpotlight | sempre; nós: só se a indexação de `/` estiver ligada | aplicável | **sim** | 60 s | `mdutil -E /` |
| repairPermissions | sempre (fora de sandbox) | aplicável | **sim** | 30 min | `diskutil resetUserPermissions / <uid>` |
| freeUpRAM | Mac Intel | aplicável | **sim** (`purge`) | 2 min | `purge` (CMM: pressão de memória, não copiado) |
| periodicScripts | macOS < 14 e `/usr/sbin/periodic` existe | aplicável | **sim** | 10 min/script | `periodic daily`, `weekly`, `monthly` |
| thinSnapshots | APFS e ≥ 1 captura `com.apple.TimeMachine` em `/` | aplicável | não (fallback ajudante) | 10 min | `tmutil thinlocalsnapshots / 1073741824 3` |

"Recomendada quando = aplicável" segue a inferência da seção **Recomendada**.

## Fatos que o Core precisa consultar (`MaintenanceFacts`)
Protocolo só de leitura, com implementação real e falsa (testes):
- `osVersion: (major: Int, minor: Int)` (comparação como `major*100+minor`).
- `isAppleSilicon: Bool`.
- `isBootVolumeAPFS: Bool`.
- `isSandboxed: Bool` (sempre `false` no nosso app; existe para espelhar a regra).
- `mailLibraryExists: Bool` (`~/Library/Mail`).
- `mailEnvelopeIndexURL: URL?` (a pasta `V*` de número mais alto que tenha
  `MailData/Envelope Index`; `nil` se não houver ou sem Acesso Total ao Disco).
- `envelopeIndexSizeBytes: Int64?` (informativo, para o registro).
- `isMailRunning: Bool` (`com.apple.mail` em `NSRunningApplication`).
- `hasFullDiskAccess: Bool`.
- `purgeableEstimateBytes: Int64` (`CSDiskSpaceGetRecoveryEstimate("/")`).
- `bootVolumeAvailableBytes: Int64` (`volumeAvailableCapacityKey`).
- `isSpotlightIndexingEnabled: Bool` (`mdutil -s /`).
- `periodicToolExists: Bool` (`/usr/sbin/periodic` executável).
- `localTimeMachineSnapshots: [String]` (nomes de `tmutil listlocalsnapshots /` que começam
  com `com.apple.TimeMachine`).
- `isHelperInstalledAndAuthorized: Bool`.
- `lastRun: [MaintenanceTaskID: Date]` (registro nosso; o CleanMyMac não guarda; só informativo,
  não muda "recomendada").

## requiresAdmin
- Análise: não (tudo acima é leitura sem root).
- Execução: sim para flushDNS, reindexSpotlight, repairPermissions, periodicScripts e freeUpRAM
  (`purge`); não para speedUpMail, freeUpPurgeable e thinSnapshots.

## Evidências
- **E1**: `PerformanceTaskIdentifier.allCases` e os nomes de caso na ordem dos metadados do
  PerformanceScanning (`freeUpRAM, periodicScripts, flushDNSCache, speedUpMail,
  repairDiskPermissions, reindexSpotlight, thinLocalSnapshots, launchServicesLoginItems,
  launchAgents, freeUpPurgeableSpace`); fluxos `main, smartCare, toolbox`.
- **E2**: disassembly arm64 de `isScanTaskAvailable(for:flow:isSandbox:isAppleSilicon:systemVersion:isAPFS:)`
  (PerformanceScanning @ 0x5288; máscaras de bits por caso decodificadas) e a decompilação
  correspondente em `re-notes/decomp/PerformanceScanning/`.
- **E3**: `MaintenanceScanTaskFactory.make*Task` (decompilados; só montam o modelo) e a tarefa
  de análise das capturas (`FUN_00004f38`), que lança erro se `CMVolumeThinner("/").isThinningAvailable`
  for falso.
- **E4**: símbolos `PerformanceService.*TaskRunner` / `*TaskModelFactory` (`symbols.txt`).
- **E5**: tipos `FlushDNSCacheRequest`, `ReindexSpotlightRequest`,
  `RepairDiskPermissionsRequest(userId:)`, `PeriodicScriptRequest(script:)` e
  `PrivilegedOperationsClient.runFlushDNSCacheScript()` / `runPeriodicScript(for:)` em
  PrivilegedOperationsPerformerService; classe `MaintenanceTaskOperations` no ajudante.
- **E6**: `CMSystemVersion isLessThenSystem:` compara `_currentSystemVersion`, montado com o
  formato `%lu%02lu` (maior, menor), em SharedObjcUtils; a chamada em `isScanTaskAvailable`
  passa 0x578 = 1400.
- **E7**: comandos nesta máquina: `uname -m` → `arm64`; `sw_vers` → 26.6.2;
  `which periodic` → não encontrado; `/usr/sbin/periodic` e `/etc/periodic` inexistentes.
- **E8**: `tmutil listlocalsnapshots /` → só o cabeçalho; `tmutil destinationinfo` → nenhum
  destino; `diskutil apfs listSnapshots /` → só `com.apple.os.update-…`.
- **E9**: `defaults read` dos três domínios `com.macpaw.CleanMyMac-setapp*` (sem datas de
  tarefas); busca de `last`/`interval`/`date` nos `strings.txt`/`symbols.txt` de PerformanceModule,
  PerformanceService e PerformanceScanning.
- **E10**: `PerformanceModuleConfig.autoSelectableStrategy : ModuleCore.SimpleAutoSelectableStrategy`
  e `canBeAutoselected`/`isAutoSelected` (PerformanceModule).
- **E11**: `FreeUpPurgeableSpaceTaskModelFactory.make()` decompilado: URL `/` e
  `CSDiskSpaceGetRecoveryEstimate`; modelo sempre criado.
- **E12**: `SpeedUpMailTaskRunner.launch(value:)` decompilado (verifica `Mail` na pasta da
  biblioteca, executor `CMExecutor`, depois `CMProcess` com `mdImportToolUrl`), strings "Could
  not find mail folder", "Failed to create executor", "Mail Vacuum process failed",
  `/usr/bin/mdimport`.
- **E13**: MailboxService: `CMMailInfo vacuumWithError:` executa `VACUUM;`;
  `envelopeIndexURL` = `mailDataURL` + `Envelope Index`; `mailDataURL` = `mailLibraryURL` +
  `MailData`; `mailLibraryURL` = home + `Library/Mail/<lastUsedVersionDirectoryName>`.
- **E14**: chaves `error_description_maintenance_*`, `speed_up_mail_fda_popover_*`,
  `cleanup_complete_*_maintenance_*` (PerformanceModule, pt-BR/en).
- **E15**: disassembly arm64 do ajudante (`/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac-setapp.Agent`):
  `/usr/sbin/periodic` + argumento do pedido; `/usr/bin/dscacheutil` + `-flushcache`;
  `/usr/bin/killall` + `-HUP` + `mDNSResponder`; `/usr/bin/mdutil` + `-E` + `/`;
  `/usr/sbin/diskutil` + `resetUserPermissions` + `/` + uid; texto "Failed to launch diskutil
  resetUserPermissions".
- **E16**: PerformanceService importa `CSDiskSpaceGetRecoveryEstimate`,
  `CSDiskSpaceStartRecovery`, `CSDiskSpaceCancelRecovery`; disassembly perto de 0xc6bc:
  `bytesNeeded` = `NSURLVolumeAvailableCapacityKey` + valor pedido, `options` = 0; header
  público `CarbonCore.framework/Headers/DiskSpaceRecovery.h` do SDK.
- **E17**: programa de leitura nosso (scratchpad) nesta máquina: estimativa 3.870.242.029 B;
  disponível 265.114.533.888 B; disponível p/ uso importante 268.984.775.917 B.
- **E18**: `RepairDiskPermissionsTaskRunner` (FUN_000089e8): `getuid()`, `dispatch_semaphore`,
  espera com constante 1800.0; strings "Repair disk permissions script failed", "Waiting for
  repair disk permissions script timed out".
- **E19**: `CMRAMCleaner _cleanMemoryWithCancellationBlock:` e `CMTimedRAMCleaner cleanWithTimeout:`
  decompilados (blocos de 0x10000000 bytes, dados aleatórios, paradas por falta de memória,
  memória comprimida, relatório de RAM ou cancelamento).
- **E20**: `PeriodicScriptsTaskRunner.launch(value:)` decompilado (um pedido por script, para no
  primeiro erro); `periodic_scripts_description` cita diários, semanais e mensais.
- **E21**: `CMVolumeThinnerProcessesFactory` e `ThinLocalSnapshotsTaskRunner` (FUN_0000b0e0:
  tamanho 0x40000000, urgência 3) decompilados.

## Divergências conhecidas
- **speedUpMail** só aparece se `~/Library/Mail` existir e não faz o VACUUM do `Envelope Index`
  (só o `mdimport`), por regra do design.
- **freeUpPurgeable** some com estimativa 0 (no CleanMyMac, não confirmado).
- **reindexSpotlight** some se a indexação de `/` estiver desligada.
- **freeUpRAM** em Intel usa `purge` em vez de pressão de memória.
- **periodicScripts** também exige o `/usr/sbin/periodic` presente.
- **Tempos-limite** em todas as tarefas (o CleanMyMac só tem o de 30 min no reparo de
  permissões).
