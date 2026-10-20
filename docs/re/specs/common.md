# Regras transversais (`common`)

Regras que valem para todos os grupos da Limpeza. As specs de grupo só repetem
o que for diferente daqui.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), análise de 2026-10-20 14:57
(horário local, UTC−3).

## 1. Cálculo de tamanho

### 1.1 Unidade: tamanho alocado em disco
- O tamanho de um item é o **espaço alocado** (blocos), não o tamanho lógico.
  Arquivo de 1 byte = 4096 bytes num volume APFS comum. [E1, E2]
- Para arquivos, o CleanMyMac pergunta primeiro ao Spotlight o "tamanho físico"
  do item. Se não houver resposta, ele percorre a árvore e soma
  `st_blocks × 512` de cada entrada. Arquivos gigantes (≥ 2⁴¹ bytes) usam o
  tamanho lógico arredondado para blocos de 512. O total é arredondado para
  cima, para múltiplos de 512. [E1]
- **Regra nossa:** `FileSizer.allocatedSize(of:)` soma
  `totalFileAllocatedSizeKey` (com `fileAllocatedSizeKey` como alternativa) de
  cada entrada da árvore. Não usamos o Spotlight. O resultado é equivalente para
  arquivos e pastas comuns. [E1, E14]

### 1.2 Symlinks
- A árvore é percorrida em modo "físico": **symlinks não são seguidos**. Um
  link conta só os próprios blocos, que costumam ser 0. [E1]
- **Regra nossa:** igual. Um symlink nunca soma o tamanho do destino. Quando a
  raiz enumerada de um grupo de cache tem um filho direto que é symlink, ele
  **não vira item** (ver `user-cache.md`).

### 1.3 Hard links
- O CleanMyMac **não deduplica** hard links: cada caminho conta os blocos do
  inode de novo. [E1]
- **Regra nossa (divergência intencional):** dentro de um mesmo item, cada inode
  conta **uma vez** (por `fileResourceIdentifierKey`). Assim o tamanho mostrado
  não passa do espaço que a remoção realmente libera. Na prática a diferença é
  nula nos caches e registros observados.

### 1.4 Erros
- Subárvores ilegíveis (`EACCES`/`EPERM`) contam 0 e não interrompem a análise.
  O CleanMyMac registra o erro e segue. Arquivos que somem durante a contagem
  (`ENOENT`) também contam 0 e não geram log. [E1]
- Quando o tamanho dá 0 e o arquivo não é legível, o CleanMyMac pede o tamanho
  ao helper privilegiado, se ele estiver autorizado. Sem o helper, o tamanho fica
  0 (ver o efeito disso em `user-cache.md` e `system-cache.md`). [E3]

## 2. Formatação do tamanho exibido

- Base **decimal (SI)**: 1 KB = 1000 bytes, 1 MB = 10⁶, 1 GB = 10⁹,
  1 TB = 10¹². Prova: 4096 bytes aparecem como "4,1 KB", 12 288 como "12,3 KB"
  e 45 056 como "45,1 KB". [E4, E5]
- Unidades possíveis: KB, MB, GB, TB. **Não existe "bytes"**: a menor unidade é
  KB. [E5]
- A unidade é a maior que caiba no valor: valor ≥ 10¹² → TB; ≥ 10⁹ → GB;
  ≥ 10⁶ → MB; caso contrário, KB. [E5]
- Casas decimais: com valor na unidade **< 100**, no máximo **1** casa decimal;
  com valor **≥ 100**, nenhuma. Zero à direita é suprimido ("23 MB", e não
  "23,0 MB"). Exemplos observados: "4,1 KB", "12,3 KB", "139 KB", "213 KB",
  "963 KB", "4,4 MB", "16,1 MB", "32 MB", "592 MB", "824 MB", "1,6 GB",
  "2,8 GB" e "4,5 GB". [E4]
- O separador decimal segue o locale ("4,5 GB" em pt-BR, "4.5 GB" em en), e
  entre o número e a unidade há um espaço. [E4]
- O tamanho **0** aparece como "0 KB". Para valores entre 1 e 49 bytes, o
  arredondamento também dá "0 KB". [E4, E5]
- Arredondamento: meio para o par (half-even), que é o padrão do formatador
  numérico do CleanMyMac. Se, depois do arredondamento, o valor chegar a 1000,
  ele sobe para a unidade seguinte ("999 960 bytes" → "1 MB"). Esse caso não foi
  observado (é uma decisão nossa). [E5]
- O `ByteCountFormatter` da Apple **não** produz esse formato (ele mostra
  "4 KB" e "1,62 GB"). Por isso o `SizeFormatter` precisa ser nosso. [E6]

Tabela para o `SizeFormatterTests`:

| bytes | pt-BR | en |
|---|---|---|
| 0 | 0 KB | 0 KB |
| 4096 | 4,1 KB | 4.1 KB |
| 12288 | 12,3 KB | 12.3 KB |
| 139264 | 139 KB | 139 KB |
| 213000 | 213 KB | 213 KB |
| 16100000 | 16,1 MB | 16.1 MB |
| 23000000 | 23 MB | 23 MB |
| 824000000 | 824 MB | 824 MB |
| 1600000000 | 1,6 GB | 1.6 GB |
| 4500000000 | 4,5 GB | 4.5 GB |
| 999960 | 1 MB | 1 MB |

## 3. Exclusões globais

### 3.1 `.DS_Store`
- Um arquivo chamado exatamente `.DS_Store` nunca vira item nos caches e nos
  registros (usuário, sistema e sandbox). Isso vale tanto para os filhos diretos
  das raízes quanto para os arquivos listados dentro de pastas de registro. [E7]
- Dentro de uma pasta de cache que vira item inteiro, o `.DS_Store` conta no
  tamanho da pasta, porque a pasta é medida por inteiro. [E7]

### 3.2 Lista de ignorados da base de conhecimento (`isIgnoreItem` / `isPathIgnored`)
- Todo scanner de caches e de registros consulta a base de conhecimento (KB)
  com o **caminho completo** e com o **último componente** de cada candidato. Se
  qualquer das duas consultas disser "ignorar", o candidato sai. [E8]
- Nos caches agrupados, a KB também é consultada com o **identificador do
  grupo** (ex.: `com.apple.Safari`). Um grupo ignorado some inteiro. [E9]
- A KB é um banco cifrado que vem no app (`info.cmmkb`) e pode ser atualizado
  pelo servidor. Existe também a lista de ignorados do próprio usuário,
  configurável no app. [E10]
- Caches e registros pertencentes a ferramentas de IA (Claude, Codex etc.) são
  ignorados nesses grupos, porque aparecem em "Detritos de IA". [E11, E12]
- **Regra nossa:** não lemos a KB. Cada grupo tem, no próprio JSON de regras,
  uma lista `exclude` de globs **derivada da observação** (as specs de grupo
  listam cada uma) e herda a lista `exclude` global abaixo. A lista do usuário
  fica fora da v1.

Lista `exclude` global (vale para todos os grupos de caches e registros):
- `.DS_Store`
- os caminhos que a spec `ai-agents-junk.md` reivindicar. Na observação, foram
  estes: `~/Library/Caches/claude-cli-nodejs`, `~/Library/Caches/Codex`,
  `~/Library/Caches/com.anthropic.claudefordesktop*`,
  `~/Library/Caches/com.openai.codex*`, `~/Library/Caches/com.openai.sky.*`,
  `$DARWIN_USER_CACHE_DIR/com.anthropic.claudefordesktop*`,
  `$DARWIN_USER_CACHE_DIR/com.openai.codex*`, `~/Library/Logs/Claude`,
  `~/Library/Logs/com.openai.codex`.

### 3.3 Proteção do sistema (SIP) e pastas protegidas
- `isFileProtectedByRootless` responde se um caminho é protegido pelo SIP
  (atributo `com.apple.rootless` ou flag `SF_RESTRICTED`). Os scanners de
  caminho fixo pulam arquivos "restritos". [E13]
- `isProtectedFolderAtPath` / `ProtectedFolderSet`: na hora de remover, o
  CleanMyMac recusa apagar **a própria pasta** de qualquer diretório-padrão do
  sistema ou do usuário (todos os `FileManager.SearchPathDirectory` em todos os
  domínios, `/Volumes`, `Application Support`, `Group Containers`,
  `Mobile Documents`, as lixeiras do iCloud, `PrivilegedHelperTools` e
  `Autosave Information`). O conteúdo dessas pastas pode ser apagado; a pasta,
  não. [E13]
- Antes de apagar, o CleanMyMac tenta remover a flag de imutável (`uchg`) do
  item. [E13]
- **Regra nossa:** a `PathPolicy` (Task 9) já recusa a raiz permitida em si, o
  que fica fora das raízes e os escapes por symlink. Além disso, a `PathPolicy`
  recusa qualquer caminho que seja exatamente um diretório-padrão
  (`FileManager.urls(for:in:)` para todos os diretórios e domínios) e qualquer
  caminho protegido pelo SIP (o `rm` falharia de qualquer jeito). Não tiramos a
  flag `uchg` na v1: o item falha com `EPERM` e o motivo vai para o log.

## 4. Seleção inicial ("autoselected" → recomendado)
- Cada item que o scanner cria leva uma flag `autoselected`. No nosso modelo, ela
  vira `JunkItem.isRecommended`. [E15]
- Um grupo/pasta com filhos é marcado se **todos** os filhos estiverem
  marcados, fica "misto" se alguns estiverem, e desmarcado se nenhum estiver.
  O próprio grupo é criado sem flag e herda o estado dos filhos. [E9, E15]
- Valores por grupo: ver as specs. Em resumo, caches e registros comuns vêm
  `autoselected = sim`. As exceções (Gradle, Spotify e os caminhos fixos de
  Telegram, WeChat etc.) vêm `não`.
- **Atenção:** na baseline, o Gerenciador de Limpeza mostrou **todos os
  checkboxes desmarcados** e "Selecionar: Nenhum" em todos os grupos, com
  "0 Item Selecionado". [E4] A flag do modelo e o estado da tela não batem.
  Hipótese: a tela aplica uma estratégia de seleção (`JunkCleanupAutoSelectableStrategy`)
  por cima da flag, ou a seleção foi zerada antes da captura. Quem define isso é
  `results-screen.md` (Task 7). Na baseline JSON, `recommended` reflete o
  checkbox observado, que é `false` em tudo.

## 5. O que vem da base de conhecimento e o que é fixo no código

| Fixo no código (reproduzimos literalmente) | Vem da KB (não reproduzimos; usamos a nossa lista) |
|---|---|
| raízes de cada grupo (`~/Library/Caches`, `/Library/Logs`, …) | lista de itens ignorados (por nome, por caminho e por id de grupo) |
| exclusão de `.DS_Store` | quais pastas de cache recebem "busca profunda" (`shouldPerformDeepSearchForItem`): a pasta vira um grupo dos seus filhos |
| limite de tamanho dos registros (> 10 240 bytes) | — |
| nomes e padrões fixos de `/private/var/log` | — |
| caminhos fixos (Telegram, WeChat, Adobe, Fotos, Migração…) | — |
| `autoselected` de cada scanner | — |
| agrupamento por identificador (último componente / container) | — |

- Sem rede, o CleanMyMac usa a KB que vem dentro do app. A atualização pelo
  servidor só troca o arquivo de trabalho. Logo, **a análise funciona offline**
  com as regras empacotadas. [E10]
- **Regra nossa:** todas as regras vão empacotadas no app
  (`Rules/Resources/rules/*.json`), sem download.

## 6. Remoção (padrão)
- Os itens de Detritos do Sistema são **apagados definitivamente**
  (`removeItem`), e não movidos para o Lixo. O remover de arquivos protegidos
  faz isso depois das checagens da seção 3.3. Os itens de root vão pelo helper
  privilegiado. A versão "mover para o Lixo" existe no `CleaningCore`, mas não é
  referenciada pelo módulo de detritos do sistema. [E13, E16]
- **Regra nossa:** `RemovalKind.delete` por padrão em caches e registros. Itens
  de grupos `requiresAdmin` vão para o lote privilegiado (Task 12).

## 7. Baseline de paridade
- Arquivo: `docs/re/parity/baseline-2026-10-20.json`. Formato:
  `{ "cmmVersion", "capturedAt", "groups": { "<GroupID>": { "totalBytes", "items": [{ "name", "bytes", "recommended" }] } } }`.
- Os valores foram convertidos dos textos da UI ("2,8 GB" → 2 800 000 000) com
  base decimal. **Eles são arredondados**: cada número tem só 2 ou 3 dígitos
  significativos (erro de até ±0,05 na unidade exibida; 1,6 GB pode ser qualquer
  valor entre 1,55 e 1,65 GB). Por isso a soma dos itens não fecha com
  `totalBytes` (ex.: em userCache, os itens somam 2,856 GB e o total diz
  2,8 GB). A comparação de paridade deve usar uma tolerância por item de meia
  unidade da casa exibida.
- `recommended` = estado do checkbox na captura (todos `false`, ver seção 4).
- Os 13 grupos mapeados estão presentes. Os grupos de "Anexos do Mail" e
  "Lixos" estavam vazios nesta máquina e não têm GroupID no mapeamento, por isso
  ficaram de fora.

## Evidências
- **E1** — pseudocódigo de `CMByteSizer` (FileManagerService):
  `_originalItemSizeAtPath:withCancellationFlag:` usa primeiro o tamanho físico
  do Spotlight; depois `fts` em modo físico, sem seguir links, somando blocos sem
  tabela de inodes, e arredonda para o tamanho de bloco. `itemSizeWithFTSEntry:`
  segue a mesma regra; `logicalByteSizeAtPath:` usa `stat.st_size`.
- **E2** — pseudocódigo de `FileSizingService.byteSizeAtURL:cancellationFlag:`
  (FileManagerService): delega para `CMByteSizer`. É o `fileSizer` dos scanners
  de cache.
- **E3** — pseudocódigo de `CMCacheScanTask _fileSizeAtURL:cancellationFlag:`
  e de `CMLogsScanTask _fileSizeAtURL:` (SystemJunkScanning): usa o helper
  privilegiado quando o tamanho dá 0 e o arquivo é ilegível, se o helper estiver
  autorizado.
- **E4** — observação da baseline `re-notes/ax/baseline-20261020-1457/*`: textos
  de tamanho de grupos e itens, checkboxes `checked=0` e "Selecionar: Nenhum".
- **E5** — pseudocódigo de `CMByteSizeFormatter displayItemSizeFromSize:base2:localized:`
  e a tabela `_vals_si` (1000, 10⁶, 10⁹, 10¹², 10¹⁵), lida do binário
  FileManagerService. O zero vira a chave localizada "ZeroKB", e o formatador
  padrão usa arredondamento half-even. As casas decimais por faixa vêm da
  observação E4.
- **E6** — teste local com `ByteCountFormatter` (estilos file, decimal e
  binary) em pt-BR: o resultado ("4 KB", "1,62 GB") difere do que a UI mostra.
- **E7** — pseudocódigo de `CMCacheScanTask scan`, `CMLogsScanTask userLogsScanTaskWithKnowledgeBase:`
  e `systemLogsScanTaskWithKnowledgeBase:` e de `CMFileNamePredicate dsStoreFileNamePredicate`
  (LegacyScanningCore): o predicado de nome compara com `.DS_Store`.
- **E8** — pseudocódigo de `CMFileIgnorePredicate shouldIgnoreObject:`
  (LegacyScanningCore): consulta `isIgnoreItem:` com o caminho e com o último
  componente.
- **E9** — pseudocódigo de `CMCachesContext addItem:toGroupWithIdentifier:` e
  `_fetchOrCreateCacheGroupWithIdentifier:`: consulta a KB pelo id do grupo e
  cria o grupo com `isAutoselected = 0`.
- **E10** — strings do KnowledgeBaseService: `KnowledgeBaseScannerService`,
  `isPathIgnored`, `CustomIgnoreItemsSnapshot`, `workingURL`, `backupURL`,
  `noKnowledgeBaseInBundle`, `KnowledgeBaseUpdaterServiceUpdatedKnowledgeBaseFile`,
  `PRAGMA cipher_default_compatibility` e os ids de scanner `userCaches`,
  `systemCaches`, `userLogs`, `systemLogs`.
- **E11** — símbolos/pseudocódigo de `AIJunkExcludingCachesKnowledgeBase` e
  `AIJunkExcludingLogsKnowledgeBase` (JunkCleanupModule): envolvem a KB e
  ignoram também o que pertence às ferramentas de IA.
- **E12** — leitura do disco comparada com a baseline: `claude-cli-nodejs`,
  `Codex`, `com.anthropic.claudefordesktop`, `com.openai.codex` (em
  `~/Library/Caches`) e `Claude` e `com.openai.codex` (em `~/Library/Logs`)
  existem e não aparecem nos grupos de cache e registro.
- **E13** — pseudocódigo de `FileManagerProvider isFileProtectedByRootless`,
  `isProtectedFolder`, `ProtectedFolderSet init` e
  `ProtectedFileRemover _removeItem` / `tryToUnlockFileIfNeeded`
  (FileManagerService), e a string "Refused to remove protected folder at path".
  Nos scanners, `CMHardcodedPathCacheScanTask _groupForURLS:…` pula arquivos
  restritos (`isFileRestrictedAtPath:`).
- **E14** — documentação pública da Apple sobre
  `URLResourceKey.totalFileAllocatedSizeKey` (tamanho alocado, incluindo
  metadados).
- **E15** — pseudocódigo de `CMFileModel modelWithValue:size:autoselected:`,
  `CMFileURLSequenceModel modelWithValue:autoselected:`, `CMTreeEntity initWithValue:autoselected:`
  e `isResultAutoselectable` dos scanners de cache.
- **E16** — strings: `FileManagerServiceFileRemover` e `LogsRemover`
  (SystemJunkScanning), `MoveToTrashFileRemover` (só no CleaningCore) e
  `trashItemAtURL` (CleaningCore).

## Divergências conhecidas
- Hard links contados uma vez por item (o CleanMyMac conta cada link).
- O tamanho físico do Spotlight não é consultado. A diferença é desprezível.
- A KB é substituída por listas `exclude` derivadas da observação. Itens novos,
  que a KB ignoraria numa outra máquina, vão aparecer no CleanYourMac.
- Não existe lista de ignorados do usuário na v1.
- A flag `uchg` não é removida antes de apagar.
- A seleção inicial depende de `results-screen.md`, porque modelo e tela
  divergem (seção 4).

## Checklist de testes
- `SizeFormatter`: todos os casos da tabela da seção 2, em pt-BR e en.
- `FileSizer`: um arquivo de 1 byte → 4096 (em APFS); uma pasta com arquivos de
  4096, 10 000 e 1 byte → soma dos alocados (4096 + 12 288 + 4096); um symlink
  para uma pasta de 1 MB fora da árvore → total inalterado; dois hard links do
  mesmo arquivo de 1 MB no mesmo item → conta 1 MB; uma subpasta com `chmod 000`
  → conta 0, sem lançar erro.
- Exclusão global: `R/.DS_Store` como filho direto de uma raiz de cache ou
  registro → não vira item.
- `PathPolicy`: `~/Library/Caches` (a pasta-padrão em si) → recusado;
  `~/Library/Caches/Foo` → aceito; `/System/Library/Caches/x` (SIP) →
  recusado.
- Baseline: `baseline-2026-10-20.json` decodifica, tem os 13 GroupIDs, e cada
  `totalBytes` é múltiplo de 10ᵏ coerente com o texto da UI.

## Baseline observada
Totais por grupo (texto da UI → bytes):
userCache 2,8 GB; systemCache 765 MB; universalBinaries 32 MB; userLogs
16,1 MB; systemLogs 10,1 MB; languageFiles 213 KB; aiAgentsJunk 824 MB;
brokenLoginItems, documentVersions, deletedUsers, brokenPreferences, iosBackups
e localModels com 0 KB. Detalhe por item em `docs/re/parity/baseline-2026-10-20.json`.
