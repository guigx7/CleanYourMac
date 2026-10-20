# Arquivos de Registro do Sistema (`systemLogs`)

Regras transversais em `common.md`. A forma de montar os itens (arquivo → item;
pasta → item com os arquivos aprovados, percorrida recursivamente; pasta sem
filhos aprovados é descartada) e o nome exibido são os mesmos de
`user-logs.md`. Aqui fica só o que muda.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), análise de 2026-10-20 14:57.

## Composição do grupo na UI
O grupo é a tarefa composta `SystemLogsCompound`, que junta as listas das
subtarefas abaixo, sem agrupamento: [E1, E2]

| Subtarefa (identificador interno) | Raiz | Cai em `systemLogs`? |
|---|---|---|
| `LocalLogs` (criada como "system logs") | `/Library/Logs` | sim |
| `AppleLogs` | `/var/log/asl/` | sim |
| `PrivateLogs` (usa o identificador `DiagnosticLogs`) | `/private/var/log` | sim |
| `DiagnosticLogs` | `/private/var/db/diagnostics` | **não**: só entra numa variante "potencialmente insegura" que a fábrica de tarefas não usa |

## Locais varridos
1. `/Library/Logs`: cada filho direto é um candidato. [E3, E4]
2. `/var/log/asl/` (= `/private/var/log/asl`): a **própria pasta** é um
   candidato único. [E3, E5]
3. `/private/var/log`, com duas fontes de candidatos somadas: [E3, E6]
   - **nomes fixos**, sempre tentados como `/private/var/log/<nome>`:
     `DiagnosticMessages`, `cups`, `daily.out`, `weekly.out`, `monthly.out`,
     `system.log`, `install.log`, `wifi.log`, `sck_hfs.log`, `fsck_hfs.log` e
     `fsck_apfs.log`. O `sck_hfs.log` está assim no binário (provável erro de
     digitação); mantemos.
   - **filhos diretos de `/private/var/log`** cujo nome casa com uma das
     expressões regulares `system.log.\d.gz` ou `wifi.log.\d.bz2`, sem
     diferenciar maiúsculas de minúsculas. **Regra nossa:** casar o nome
     inteiro (`^system\.log\.\d\.gz$`, `^wifi\.log\.\d\.bz2$`).
   Nenhum outro arquivo de `/private/var/log` é considerado (ex.:
   `keybagd.log.0`, `shutdown_monitor.log`, `powermanagement/`, `karabiner/` e
   `fsck_apfs_error.log` ficam de fora).

## Inclusão
Filtros por raiz (o candidato, ou cada arquivo dentro de uma pasta, é
**excluído** se a condição valer): [E4, E5, E6, E7]

| Raiz | Excluir quando |
|---|---|
| 1 `/Library/Logs` | nome `.DS_Store`, **ou** tamanho alocado ≤ 10 240 bytes, **ou** a KB ignora |
| 2 `/var/log/asl/` | a KB ignora (sem limite de tamanho e sem filtro de `.DS_Store`) |
| 3 `/private/var/log` | o caminho não existe, **ou** tamanho alocado ≤ 10 240 bytes, **ou** a KB ignora |

- Sem idade mínima e sem filtro de extensão (a extensão só entra nos nomes e
  padrões da raiz 3). [E4, E6]
- O tamanho de cada candidato é medido pelo helper privilegiado quando ele está
  autorizado; senão, direto no disco. [E8]

## Exclusão
- Os filtros acima.
- **Regra nossa equivalente à KB:** nenhuma exclusão extra. Nesta máquina, tudo
  o que não apareceu se explica pelo limite de tamanho ou por não estar na lista
  da raiz 3: `LKDC-setup.log` (308 B), `MCXTools.log` (0 B), `Logi` e
  `iStat Menus 7` (8 KB cada), as pastas vazias `WindowServer`, `Xsan` e
  `hidfw-crashlogs`, `system.log.N.gz` (~1 KB cada), `wifi.log.0.bz2` (4 KB),
  `fsck_hfs.log` (8 KB alocados) e `cups` (pequeno). [E9]

## Recomendado
**Sim** para todos (os modelos de registro são criados com `autoselected`). A
baseline mostrou tudo desmarcado (`common.md` §4). [E10]

## Agrupamento e nome exibido
- Sem agrupamento: cada candidato aprovado é um item de primeiro nível. [E1]
- Nome: último componente sem a última extensão (`wifi.log` → `wifi`,
  `install.log` → `install`, `system.log` → `system`, `fsck_apfs.log` →
  `fsck_apfs`; `/var/log/asl/` → `asl`; pastas mantêm o nome). Para itens da
  raiz 3, o nome passa pela mesma busca por bundle id descrita em
  `user-logs.md`; os da raiz 2 usam sempre o nome cru. [E10, E11]
- Tipos internos: `DiagnosticReports` = relatórios de diagnóstico; `asl` =
  registros da Apple; itens sob `/private/var/log` = registros privados; o resto
  = comum. [E10]
- Ícone: documento/pasta genéricos (escolha nossa).
- Filhos: guardados no modelo, mas a célula não mostra o botão de expandir. [E11]

## Cálculo de tamanho
Alocado (`common.md`); pasta = soma dos arquivos aprovados. Com admin, a regra
nossa mede pelo lote privilegiado o que não for legível (como em
`system-cache.md`).

## Remoção
- Apagar definitivamente cada arquivo aprovado. Pastas e arquivos pequenos
  ficam. Para `asl`, todos os arquivos da pasta são aprovados, então a pasta
  fica vazia. [E12, common.md E16]
- Precisa de **admin** (os arquivos são de `root`): tudo vai para o lote
  privilegiado único (Task 12).
- O CleanMyMac usa um caminho privilegiado próprio para os registros da Apple e
  de diagnóstico. **Regra nossa:** `rm` dos arquivos pelo lote privilegiado; o
  `syslogd` recria o que precisar.

## Alertas e selos
Nenhum.

## requiresAdmin
- Análise: **não** para usuários administradores: `/private/var/log/*` é
  legível pelo grupo `admin`, e `DiagnosticReports` pelo grupo
  `_analyticsusers`. Para um usuário padrão, parte dos itens mede 0 e cai no
  filtro.
- Limpeza: **sim**.

## Evidências
- **E1** — pseudocódigo de `CMSystemLogsScanTask systemLogsWithKnowledgeBase:privilegedOperationsPerformer:`
  e da variante `…allowPotentiallyUnsafeOperaionts:` (a de diagnóstico só entra
  com a flag ligada; a variante comum passa desligada); identificador
  `CMSystemJunkScanIdentifierSystemLogsCompound`. Pseudocódigo de
  `SystemJunkScanTasksFactory _systemLogs` (usa a variante comum).
- **E2** — strings do JunkCleanupModule: `systemJunkSystemLogsGroupTitle` e
  `SystemJunkScanIdentifierSystemLogsCompound`.
- **E3** — pseudocódigo de `CMPaths localLogs` (`/Library/Logs`), `aslLogs`
  (`/var/log/asl/`), `privateLogs` (`/private/var/log`) e `diagnosticsLogs`
  (`/private/var/db/diagnostics`) (SharedObjcUtils), e de
  `CMLocalLogsProvider`, `CMAppleLogsProvider` e `CMDiagnosticLogsProvider`
  `scanningPathsWithError:`.
- **E4** — pseudocódigo de `CMLogsScanTask systemLogsScanTaskWithKnowledgeBase:`
  (provedor local; filtro .DS_Store / tamanho 0x2800 / KB / acesso).
- **E5** — pseudocódigo de `CMLogsScanTask appleLogsScanTaskWithKnowledgeBase:`
  (filtro só com KB e acesso).
- **E6** — pseudocódigo de `CMPrivateLogsProvider scanningPathsWithError:`,
  `knownPatterns` e `_knownPaths`, e dos blocos que filtram por regex e montam
  os caminhos. O conteúdo das duas listas constantes foi lido do binário (2
  padrões e 11 nomes). A regex é criada sem diferenciar maiúsculas.
- **E7** — pseudocódigo de `CMLogsScanTask privateLogsScanTaskWithKnowledgeBase:privilegedOperationsPerformer:`:
  NÃO(alcançável E tamanho > 0x2800), OU KB, OU acesso.
- **E8** — pseudocódigo de `CMLogsScanTask _fileSizeAtURL:`.
- **E9** — leitura do disco: `ls -la /Library/Logs /private/var/log` e
  `du -sk /Library/Logs/*`, comparados com a baseline.
- **E10** — pseudocódigo de `CMLogsScanTask _logModelAtURL:` / `_entityAtURL:`
  (autoselected = sim) e de `CMMLogItem _fetchType` / `name`.
- **E11** — observação da baseline (`Arquivos de Registro do Sistema.txt`):
  nomes sem extensão e células sem o botão de expandir.
- **E12** — símbolos de `LogsRemover` (SystemJunkScanning): recebe um cliente
  privilegiado com operações de registros e trata os tipos "Apple" e
  "diagnóstico" por um caminho próprio.

## Divergências conhecidas
- A regex é ancorada no nome inteiro. A original pode casar por trecho, e não
  há diferença para os nomes reais.
- `/private/var/db/diagnostics` fica de fora, como no CleanMyMac padrão.
- Os registros da Apple são apagados por `rm` privilegiado, e não pelo serviço
  próprio do CleanMyMac.

## Checklist de testes
- `systemLogs_localLogsChildren`: `$ROOT/Library/Logs/DiagnosticReports/{a.ips (20 KB), b.diag (4 KB)}`
  → item "DiagnosticReports" com só `a.ips`.
- `systemLogs_localSmallFileExcluded`: `$ROOT/Library/Logs/LKDC-setup.log`
  (308 B) → nenhum item.
- `systemLogs_aslWholeFolderNoSizeLimit`: `$ROOT/private/var/log/asl/{x.asl (1 KB), y.asl (2 KB)}`
  → 1 item "asl" com os 2 filhos.
- `systemLogs_privateKnownName`: `$ROOT/private/var/log/wifi.log` (50 KB) →
  item "wifi".
- `systemLogs_privateUnknownNameIgnored`: `$ROOT/private/var/log/keybagd.log.0`
  (50 KB) → nenhum item.
- `systemLogs_privatePatternMatches`: `system.log.3.gz` com 20 KB → item
  "system.log.3"; com 1 KB → nenhum item.
- `systemLogs_privatePatternCaseInsensitive`: `WIFI.LOG.0.BZ2` (20 KB) → item.
- `systemLogs_privateMissingKnownNameSkipped`: sem `daily.out` → nenhum item,
  sem erro.
- `systemLogs_diagnosticsNotScanned`: `$ROOT/private/var/db/diagnostics/x`
  (1 MB) → nenhum item.
- `systemLogs_requiresAdminToClean`: 2 itens selecionados → 1 chamada ao runner
  privilegiado.
- `systemLogs_allRecommended`: todos os itens com `isRecommended = true`.

## Baseline observada
Total: **10,1 MB**, 7 itens, todos desmarcados:
DiagnosticReports 7,3 MB · wifi 2,4 MB · DiagnosticMessages 147 KB · install
135 KB · asl 86 KB · system 12,3 KB · fsck_apfs 12,3 KB.
