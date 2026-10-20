# Arquivos de Registro do Usuário (`userLogs`)

Regras transversais em `common.md`.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), análise de 2026-10-20 14:57.

## Composição do grupo na UI
O grupo é a tarefa composta `UserLogsCompound`, que junta as listas de **três**
subtarefas, sem agrupamento entre elas: [E1, E2]

| Subtarefa | Raiz | Cai em `userLogs`? |
|---|---|---|
| `UserLogs` | `~/Library/Logs` | sim |
| `SandboxLogs` | `~/Library/Containers/*/Data/Library/Logs` | sim |
| `QuarantineLogs` | banco de quarentena do LaunchServices | sim |

`LocalLogs`, `AppleLogs`, `PrivateLogs`/`SystemLogs` e `DiagnosticLogs` são de
`systemLogs`.

## Locais varridos
1. `~/Library/Logs`: cada filho direto é um candidato. [E3]
2. Para cada pasta em `~/Library/Containers`, cada filho direto de
   `<container>/Data/Library/Logs` é um candidato. [E4]
3. Os dois arquivos `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2`
   e `~/Library/Preferences/com.apple.LaunchServices.QuarantineEvents`, cada um
   como candidato. [E5]

## Inclusão
Cada candidato passa por um **filtro** e depois vira item, conforme o tipo:
- **Arquivo:** o item é o arquivo, com o tamanho alocado dele. [E6]
- **Pasta:** a pasta é percorrida **recursivamente** (todas as profundidades).
  Cada **arquivo** encontrado (subpastas não contam como entradas) passa pelo
  mesmo filtro e, se passar, vira filho do item. O tamanho do item é a soma dos
  filhos. Pasta sem nenhum filho aprovado **não vira item**. [E6, E7]

Filtro das raízes 1 e 2: o candidato (ou o arquivo dentro da pasta) é
**excluído** se qualquer condição abaixo valer: [E8, E9]
- o nome é `.DS_Store`;
- o **tamanho alocado é ≤ 10 240 bytes**. Para uma pasta no nível de
  candidato, vale o tamanho da pasta inteira. Por isso uma pasta com só
  arquivos pequenos some, e uma pasta grande perde os arquivos pequenos;
- a KB o ignora (por caminho ou por nome).

Filtro da raiz 3 (quarentena): o candidato é excluído se o arquivo **não
existir** ou tiver **tamanho 0**, ou se a KB o ignorar. [E10]

**Não há idade mínima**: registros de hoje entram. Também não há filtro por
extensão. [E8, E9, E10]

## Exclusão
- O filtro acima.
- **Regra nossa equivalente à KB**, derivada da observação: os registros das
  ferramentas de IA (`~/Library/Logs/Claude` e `~/Library/Logs/com.openai.codex`,
  conforme a lista global de `common.md`) não aparecem. [E11] Nesta máquina,
  todas as outras ausências se explicam pelo limite de 10 240 bytes; não foi
  preciso nenhuma outra exclusão. [E11]

## Recomendado
**Sim** para todos os itens e filhos (os modelos de registro são criados com
`autoselected`). [E6] A baseline mostrou tudo desmarcado (`common.md` §4).

## Agrupamento e nome exibido
- **Sem agrupamento:** cada candidato aprovado é um item de primeiro nível. Dois
  itens podem ter o mesmo nome (ex.: um `Setapp` de `~/Library/Logs` e outro
  vindo de um container); eles ficam separados. [E1, E6]
- **Nome cru:** o último componente do caminho **sem a última extensão**. Por
  exemplo: `warp.log` → `warp`; `warp.log.old.0` → `warp.log.old`; a pasta
  `Zed` → `Zed`; `com.apple.LaunchServices.QuarantineEventsV2` →
  `com.apple.LaunchServices`. [E12, E13]
- **Nome exibido:** se o nome cru for o bundle id de um app instalado, aparece o
  nome de exibição do app (`FileManager.displayName(atPath:)` do app, sem
  `.app`). Senão, aparece o nome cru. [E12] (Nenhum caso desses ocorreu na
  baseline.)
- **Tipo** (usado pela tela e pela remoção): `CrashReporter`, `HangReporter` e
  `DiagnosticReports` são relatórios de diagnóstico; os dois arquivos de
  quarentena são "registro de downloads"; o resto é registro comum. [E12]
- Ícone: documento genérico para arquivo e pasta genérica para pasta (escolha
  nossa).
- **Filhos:** para pastas, os arquivos aprovados. A baseline **não mostra o
  botão de expandir** nas células deste grupo (só a dica inteligente). [E13]
  **Regra nossa:** guardar os filhos no modelo (eles definem o que é apagado),
  mas mostrar o item como folha.

## Cálculo de tamanho
Alocado (`common.md`). Para pastas, é a soma dos arquivos aprovados, e não o
tamanho da pasta inteira. Exemplo observado: `DiagnosticReports` tinha 128 KB no
disco, mas só os dois arquivos acima de 10 240 bytes (20 480 + 24 576) somaram,
dando "45,1 KB". [E11, E13]

## Remoção
- Apagar definitivamente **cada arquivo aprovado**. Num item de pasta, os
  arquivos pequenos excluídos pelo filtro e a própria pasta **ficam** (escolha
  nossa: o modelo só contém os arquivos aprovados). [E6, common.md E16]
- Os arquivos de quarentena são apagados como arquivos; o LaunchServices os
  recria. Não encontramos indício de limpeza por SQL (só há uma consulta
  `SELECT`).
- Admin: não. Se a remoção falhar com `EACCES`/`EPERM`, o item vai para o lote
  privilegiado.

## Alertas e selos
Nenhum.

## requiresAdmin
- Análise: **não**. Ler os containers de outros apps exige Acesso Total ao
  Disco; sem ele, essas pastas medem 0 e caem no filtro.
- Limpeza: **não**.

## Evidências
- **E1** — pseudocódigo de `CMUserLogsScanTask userLogsWithKnowledgeBase:`:
  tarefas `userLogsScanTask`, `sandboxLogsScanTask` e `quarantineLogsScanTask`,
  com o identificador `CMSystemJunkScanIdentifierUserLogsCompound`.
- **E2** — strings do JunkCleanupModule: `systemJunkUserLogsGroupTitle` e
  `SystemJunkScanIdentifierUserLogsCompound`.
- **E3** — pseudocódigo de `CMUserLogsProvider scanningPathsWithError:` e de
  `CMPaths userLogs` (`~/Library/Logs`, SharedObjcUtils).
- **E4** — pseudocódigo de `CMSandboxLogsProvider scanningPathsWithError:` e do
  bloco associado (acrescenta `Data/Library/Logs` e lista os filhos).
- **E5** — pseudocódigo de `CMQuarantineLogsProvider scanningPathsWithError:` e
  `CMQuarantine downloadsLogsURLs`, e as strings com os dois caminhos de
  `QuarantineEvents`.
- **E6** — pseudocódigo de `CMLogsScanTask scan`, do bloco de mapeamento,
  `_entityAtURL:`, `_logModelAtURL:` e `_filterWithURL:` (modelos com
  autoselected = sim; descarta pasta sem filhos).
- **E7** — pseudocódigo de `CMLogsScanTask _entityAtURL:`: percorre a pasta com
  um enumerador recursivo e só adiciona o que não é diretório.
- **E8** — pseudocódigo de `CMLogsScanTask userLogsScanTaskWithKnowledgeBase:` e
  `sandboxLogsScanTaskWithKnowledgeBase:`: OU de (.DS_Store, NÃO(tamanho >
  0x2800), ignorado pela KB, acesso).
- **E9** — pseudocódigo de `CMFileSizePredicate shouldIgnoreObject:` (verdadeiro
  quando o tamanho alocado passa do limite), `CMCompoundPredicate shouldIgnoreObject:`
  (NÃO/E/OU) e `CMFileAccessPredicate _isFileCanBeHandled:` (sempre aceita).
- **E10** — pseudocódigo de `CMLogsScanTask quarantineLogsScanTaskWithKnowledgeBase:`:
  NÃO(existe E tamanho > 0), OU KB, OU acesso.
- **E11** — leitura do disco (`ls -la`/`du -sk ~/Library/Logs` e `stat` dos
  arquivos) comparada com a baseline: `TeamSpeak` (arquivos ≤ 8 KB),
  `Homebrew`, `fsck_hfs.log` (1146 B), `DiscRecording.log` e as pastas
  `com.bjango.*` ficam de fora pelo limite; `CrashReporter` entra com 12 288 B;
  `Claude` (1,7 MB) e `com.openai.codex` (3,8 MB) ficam fora sem explicação pelo
  tamanho.
- **E12** — pseudocódigo de `CMMLogItem initWithURL:workspace:fileManager:paths:`
  (remove a extensão real e pega o último componente), `name`, `displayName`,
  `_fetchDisplayNameForAppWithBundleID:` e `_fetchType`.
- **E13** — observação da baseline (`Arquivos de Registro do Usuário.txt`):
  nomes `warp.log.old`, `warp` e `com.apple.LaunchServices` (= 20 480 bytes, o
  tamanho de `QuarantineEventsV2`); células sem o botão de expandir.

## Divergências conhecidas
- A remoção apaga só os arquivos aprovados. Não está provado que o CleanMyMac
  não apague a pasta inteira quando todos os filhos são selecionados.
- O nome de exibição a partir de bundle id não foi observado.
- A lista de ignorados da KB foi reduzida às ferramentas de IA.

## Checklist de testes
- `userLogs_smallFileExcluded`: `~/Library/Logs/a.log` com 1146 B (4096
  alocados) → nenhum item.
- `userLogs_thresholdIsStrict`: um arquivo com exatamente 10 240 bytes alocados
  → nenhum item; com 12 288 → item.
- `userLogs_fileItemNameStripsExtension`: `~/Library/Logs/warp.log` com 50 KB →
  item "warp"; `warp.log.old.0` → "warp.log.old".
- `userLogs_folderKeepsOnlyBigFiles`: `~/Library/Logs/DiagnosticReports/` com
  `a` (20 480), `b` (24 576) e 10 arquivos de 4096 → 1 item
  "DiagnosticReports" com 45 056 bytes e 2 filhos.
- `userLogs_folderRecursive`: `~/Library/Logs/X/sub/deep.log` (50 KB) → item X
  com o filho `deep.log`.
- `userLogs_folderOfSmallFilesDropped`: `~/Library/Logs/TeamSpeak/` com 8
  arquivos de 8192 → nenhum item.
- `userLogs_dsStoreSkipped`: `~/Library/Logs/X/.DS_Store` grande (20 KB) mais
  `X/a.log` (20 KB) → item X com só `a.log`.
- `userLogs_noAgeFilter`: um arquivo de 50 KB modificado agora → item.
- `userLogs_sandboxLogs`: `~/Library/Containers/com.foo/Data/Library/Logs/foo.log`
  (50 KB) → item "foo".
- `userLogs_quarantineIncludedIfNonEmpty`:
  `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` (20 480 B)
  → item "com.apple.LaunchServices"; com 0 B → nenhum item.
- `userLogs_excludesAITools`: `~/Library/Logs/Claude/main.log` (1 MB) → nenhum
  item.
- `userLogs_allRecommended`: todos os itens e filhos com `isRecommended = true`.
- `userLogs_removalKeepsSmallFiles`: limpar o item X (com `big.log` de 50 KB e
  `small.log` de 1 KB) apaga `big.log` e mantém `small.log` e a pasta X.

## Baseline observada
Total: **16,1 MB**, 8 itens, todos desmarcados:
warp.log.old 11,4 MB · Setapp 3,6 MB · Zed 963 KB · warp 49,2 KB ·
DiagnosticReports 45,1 KB · Perssua 36,9 KB · com.apple.LaunchServices 20,5 KB ·
CrashReporter 12,3 KB.
