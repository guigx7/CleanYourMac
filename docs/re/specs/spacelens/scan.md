# Lupa de Espaço: análise e modelo de dados

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon (arm64), 2026-10-22.
**Só análise estática, dumps de Acessibilidade já gravados e leitura do disco** (`df`, `diskutil`,
`du`, `stat`, `ls -lO`, `URLResourceValues`). Nada foi clicado no CleanMyMac e nenhum `sudo` foi usado.

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa, ainda não
confirmada no binário nem por observação.

## Onde mora cada parte no CleanMyMac
| Parte | Framework | Peças principais |
|---|---|---|
| Varredura e árvore | `SpaceLensScanning` | `SpaceLensScanTasksFactory`, `SpaceLensScanTask` (ator), `SpaceLensFileSystemEntity`, `PathFilter`, `VolumeChecker`, `CloudStorageHelper`, `SpaceLensDeletionPlanner`, `SpaceLensFolderChanges` [E1] |
| Nós, telas, volume, remoção | `SpaceLensModule` | `SpaceLensNodeMapper`, `SpaceLensItemNode`/`SpaceLensRootNode`, `VolumeModelProvider`, `SpaceLensIndicatorViewModel`, `SpaceLensLiveUpdater`, `SpaceLensNodeCleaner` [E2] |
| Lista, bolhas, seleção | `SpaceLensUI` | ver `ui-and-removal.md` |

## 1. Como a árvore é montada

### O que o CleanMyMac faz
- **Entrada:** uma URL (o volume "Macintosh HD" = `/`, ou uma pasta escolhida) e uma estratégia
  de nuvem (`SpaceLensCloudScannerStrategy`) [E1].
- **Leitura de cada pasta:** pela camada de arquivos do app (`FileManagerServiceType`), que lista
  o conteúdo de uma pasta pedindo de uma vez três chaves de recurso: **tamanho lógico**
  (`fileSize`), **tamanho alocado total** (`totalFileAllocatedSize`) e **tipo**
  (`fileResourceType`) [E3]. Não há `fts`, `getattrlistbulk` direto, `NSMetadataQuery` nem
  enumerador recursivo no módulo: o único acesso "cru" é `lstat` (para nuvem, ver §6) [E4].
  - O `FileManager` da Foundation já usa `getattrlistbulk` por baixo quando a lista vem com chaves
    pré-buscadas, o que explica boa parte da velocidade (inferência).
- **Recursão:** filho do tipo *diretório* vira uma nova pasta a varrer; *arquivo comum* e *link
  simbólico* viram folhas; outros tipos (socket, dispositivo, FIFO) são ignorados (inferência
  forte, pela comparação com as três constantes de tipo na função que monta os filhos) [E3].
- **Paralelismo:** Swift Concurrency, com um `ThrowingTaskGroup` e no máximo **4 varreduras de
  pasta ao mesmo tempo** (`maxConcurrentScans = 4`) [E5].
- **Progresso:** um rastreador publica "tamanho já somado + caminho atual" a cada **0,5 s**
  (`ScanProgressValue(scannedSize:currentPath:)`) [E5].
- **Ajudante privilegiado:** **não** é usado na análise. O framework de varredura não importa o
  serviço do ajudante; pastas que o usuário não pode ler ficam de fora e só geram o log
  "Failed to scan directory at …" [E4][E6].
- **Acesso Total ao Disco (FDA):** sem FDA, a análise pula `~/Library/Reminders` (evita o pedido de
  permissão do macOS); com FDA, nada é pulado por esse motivo [E5].
- **Cache ou índice:** **não há índice persistente** nem reaproveitamento do HealthMonitor (os
  frameworks da Lupa não importam nada de `HealthMonitoring*`) [E4]. O que existe é reuso **dentro
  da sessão**: `createFolderRefreshTask(directory:knownSubdirectories:)` revarre uma pasta só,
  aproveitando as subpastas já conhecidas (`reusableSubdirectories`), e um observador de FSEvents
  (`SpaceLensLiveUpdater`) marca o resultado como desatualizado ou o atualiza (ver §8) [E1][E2].
- **Por que ~20 s para "3M itens":** 4 pastas em paralelo, listagem em lote com as chaves já
  pedidas, nenhuma leitura extra por arquivo (só `lstat` em pastas de nuvem), em SSD Apple
  (inferência; nenhum cache foi encontrado).

### Modelo de dados (`SpaceLensFileSystemEntity`)
Campos [E1]: `path`, `size` (UInt64), `isDirectory`, `isPurgeable`, `cloudStatus`
(`notCloud`, `cloudLocal`, `cloudEvicted`), `children`. Calculados: `leavesCount`,
`removableLeavesCount`, `cloudFilesCount`, `cloudLocalFilesCount`.
- O tamanho de uma pasta é a soma dos filhos; o da pasta em si (bloco do diretório) não entra
  (inferência, coerente com §3).
- `SpaceLensEntityTree` acha um nó pelo caminho e troca os filhos de uma pasta (usado na
  revarredura) [E1].

## 2. Volumes, firmlinks e pontos de montagem

### O que o CleanMyMac faz
- **Firmlinks do APFS:** a varredura de `/` passa por `/Users`, `/Applications`, `/Library`,
  `/private`, `/opt` etc. como pastas normais (os firmlinks levam ao volume de dados). Para não
  contar duas vezes, todo caminho que começa com **`/System/Volumes/Data/`** é descartado [E3].
- **Pasta `/.nofollow`** (e o que estiver abaixo dela) é descartada [E3]. As outras pastas de
  serviço da raiz (`/.resolve`, `/.vol`) e `/dev` ficam com 0 B na prática e caem em "Outros
  itens" (observação [E7]).
- **Outros volumes montados:** o `VolumeChecker` lê a lista de volumes montados (e `/Volumes`) e o
  `PathFilter` descarta os pontos de montagem encontrados até uma profundidade máxima
  (`externalVolumes`, `maxDepthLevel`, `checkForExternalVolumes`) [E8]. Há uma lista fixa de 4
  caminhos, `/`, `/private/var/vm`, `/home`, `/net`, guardada junto (inferência: são os pontos de
  montagem que **não** contam como volume externo; `/home` e `/net` são do autofs).
- **Resultado medido:** `System` = **19,9 GB** no CleanMyMac; a soma do que está em `/System`
  **fora** de `/System/Volumes` dá 19.457.684 KiB = **19,9 GB**, enquanto só o `Preboot` teria
  29,6 GB. Ou seja, `/System/Volumes/*` inteiro fica de fora (Data pelo prefixo, os demais por
  serem volumes) [E7][E9].
- `/Volumes` aparece com 0 B (só tem o link "Macintosh HD" → `/`) [E7].
- **Não cruza volumes** em nenhum caso observado; um disco externo em `/Volumes/X` não é somado à
  análise de `/` (inferência a partir de [E8]).

## 3. Tamanho

### O que o CleanMyMac faz
- **Alocado, não lógico.** O valor usado é `totalFileAllocatedSize`. Prova numérica
  (CleanMyMac × `du`, unidades decimais) [E9]:

  | Pasta | CleanMyMac | alocado (`du -k`) | lógico (`du -A`) |
  |---|---|---|---|
  | `/Applications` | 15,8 GB | 15,85 GB | 22,2 GB |
  | `/Library` | 6,3 GB | 6,31 GB | 9,0 GB |
  | `/private` | 8,2 GB | 8,19 GB | 8,15 GB |
  | `/opt` | 3,8 GB | 3,76 GB | 3,58 GB |
  | `~/.npm` | 10,1 GB | 10,08 GB | — |
  | `~/.claude` | 8,6 GB | 8,59 GB | — |

  Arquivos esparsos e comprimidos (APFS/decmpfs) contam pelo que ocupam no disco.
- O tamanho lógico (`fileSize`) também é lido; ele é usado num ramo que depende do tipo de sistema
  de arquivos (`FileSystemType`: `hfs`, `apfs`, `ufs`, `msdos`, `exfat`, `ntfs`, `other`,
  `undefined`) (inferência: em volumes FAT/exFAT, onde o alocado não é confiável) [E3][E10].
- **Hard links: contados uma vez por caminho** (não deduplicados). Prova: `du -l` (que conta cada
  link) bate exatamente com o CleanMyMac e `du` sem `-l` não [E9]:

  | Pasta | CleanMyMac | `du -kl` (cada link) | `du -k` (uma vez) |
  |---|---|---|---|
  | `/bin` | 4,9 MB | 4,89 MB | 4,31 MB |
  | `/sbin` | 2,5 MB | 2,49 MB | 2,15 MB |
  | `/usr` | 831 MB | 831,4 MB | 805,1 MB |

- **Links simbólicos:** nunca seguidos; viram folhas com o tamanho do próprio link (na prática
  0 B) [E3][E7].
- **Pacotes (`.app`, `.bundle`…):** são diretórios para a varredura, então somam tudo o que têm e
  podem ser abertos como pasta (inferência: não há chave `isPackage` na lista pedida) [E3].
- **Clones do APFS:** não há como distinguir com API pública; cada clone conta inteiro
  (inferência).
- **Arquivos só na nuvem:** ver §6.

## 4. "X de Y usados", total da raiz e "Espaço Purgável"

### O que o CleanMyMac faz
- **"Y" (494 GB)** = `volumeTotalCapacity` do volume; **"usados"** = `volumeTotalCapacity −
  volumeAvailableCapacity` (chaves lidas pelo `VolumeInfoManager`) **menos o purgável**; o
  indicador registra no log quando "usado < purgável" ou "usado sem purgável < selecionado" [E11].
  - Conta nesta máquina [E12]: total 494.332.366.848 B; disponível 265.155.358.720 B; disponível
    para uso importante 269.039.584.493 B. Usado sem purgável = 494,33 − 269,04 = **225,3 GB** →
    "225 GB de 494 GB usados".
- **Purgável:** só quando a pasta analisada **é um volume** (`isVolume`) **não ejetável**
  (`volumeIsEjectable = false`); nesse caso a varredura acrescenta um filho especial com
  `isPurgeable = true` e tamanho = estimativa de recuperação do macOS [E13]. A estimativa vem de
  `CMVolumeBackupSizeCacher`, que chama **`CSDiskSpaceGetRecoveryEstimate`** (API pública do
  CoreServices, `DiskSpaceRecovery.h`), guarda o valor, só remede se o último tiver mais de
  max(10 s, 2× o tempo da última medida) e espera no máximo 200 ms [E14]. Nesta máquina:
  3,87 GB ≈ `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity` → "3,9 GB".
  Pasta comum: sem linha purgável.
- **Tamanho da raiz (242 GB)** = soma dos filhos **incluindo** o purgável:
  183 + 19,9 + 15,8 + 8,2 + 6,3 + 3,8 + 0,831 + 0,0049 + 0,0025 + 0 = 237,84 GB; + 3,87 GB =
  **241,7 GB → "242 GB"** [E7][E12].
- **Por que 242 GB > 225 GB usados:** (a) o purgável entra no total mas sai do "usados";
  (b) hard links contados a cada caminho; (c) clones do APFS contados inteiros; (d) `/System` e
  `/usr` somam 20,7 GB, mas o volume `System` consome só 12,6 GB: parte disso está no volume de
  dados por firmlinks aninhados (`/System/Library/Caches`, `/System/Library/Assets*`,
  `/usr/local`… em `/usr/share/firmlinks`) e o resto são links e blocos compartilhados do
  volume selado (inferência para c e d). O consumo real dos volumes
  de sistema e de dados é 12,6 + 203,5 = 216,1 GB [E12].

## 5. Contagem, nome e ordem

### O que o CleanMyMac faz
- **"3M itens" = `leavesCount`**, a soma das folhas (arquivos e links) abaixo da pasta; pastas não
  contam (inferência pelo nome do campo e por `removableLeavesCount`; `df` mostra 3,7 M inodes em
  uso nos dois volumes, contando pastas) [E1][E12]. Formatado em forma curta ("3M", "2M").
- **Nome na lista e no cabeçalho:** o último componente do caminho, sem localização (`Users`,
  `Library`). **No caminho (breadcrumb)** o nome é o localizado do Finder ("Usuários"), porque o
  controle de caminho recebe a URL (`pathControlURLProvider`) [E7][E15].
- **Ocultos aparecem** (`.colima`, `.npm`, `.localized`) [E7].
- **Ordem:** tamanho decrescente; "Outros itens" depois dos itens; "Espaço Purgável" por último
  [E7]. Critério de empate desconhecido.

## 6. Nuvem

### O que o CleanMyMac faz
- Em raízes de nuvem (`Mobile Documents`, contêineres do iCloud; `CloudStorageHelper`,
  `cloudRootPaths`) cada item é classificado [E1][E16]:
  - **`cloudEvicted`** (só na nuvem): `lstat` com a flag **`SF_DATALESS`** em `st_flags`, ou
    `ubiquitousItemDownloadingStatus = notDownloaded`.
  - **`cloudLocal`**: item ubíquo com dados locais.
  - **`notCloud`**: o resto.
- Item `cloudEvicted` **não pode ser removido** aqui: o motivo mostrado é "este item só existe na
  nuvem; gerencie no módulo Limpeza de Nuvem" (`spacelens_cloud_evicted_protection_reason`)
  [E17]. Ele conta em `cloudFilesCount`, mas não em `removableLeavesCount` [E1].
- Item `cloudLocal` pode ser removido, com o alerta descrito em `ui-and-removal.md`.

## 7. Proteções

### O que o CleanMyMac faz
Dois níveis, ambos calculados no nó (`SpaceLensItemNode`, com `isProtected` preguiçoso) [E2][E18]:
1. **Item essencial do sistema** (`isProtected`, texto `space_lens_list_info_essential_item`,
   **não pode ser apagado**). É verdadeiro se **qualquer** um vale:
   - o caminho tem um alias do iCloud (`iCloudAliasPathFor:`);
   - uma das duas consultas à base de conhecimento cifrada (`info.cmmkb`, não decifrada) diz que é
     protegido;
   - `isFileRestrictedAtPath:` (flag `SF_RESTRICTED`);
   - `isFileProtectedByRootlessAtPath:` (SIP).
2. **Pasta do sistema** (`isSystemFolder`, tooltip "Pasta do sistema", texto
   `space_lens_system_folder_info_checkbox_text`): pastas-padrão do sistema e do usuário
   (`ProtectedFolderSet`: todos os diretórios de `FileManager.SearchPathDirectory` em todos os
   domínios, `/Volumes`, `Application Support`, `Group Containers`, `Mobile Documents`, lixeiras
   do iCloud…; ver `common.md` §3.3) (inferência forte: `~/Downloads` e `~/Library` aparecem sem
   caixa, mas `~/Projetos` e `~/.colima` têm caixa) [E7][E19].
- **Observado** [E7]: na raiz, **todos** os 9 itens aparecem com o ícone de informação no lugar da
  caixa (inclusive `/opt`, que não tem `restricted` nem é pasta-padrão: deve vir da base
  cifrada). Em `/Users`, `guigx` e `Shared` sem caixa; `.localized` com caixa. Na pasta pessoal,
  `Library` e `Downloads` sem caixa; o resto com caixa.
- Flags nesta máquina [E20]: `restricted` em `/System`, `/bin`, `/sbin`, `/usr`; `sunlnk` em
  `/Applications`, `/Library`, `/Users`, `/private`; nada em `/opt`.

## 8. Atualização ao vivo (só na sessão)
- `SpaceLensLiveUpdater` observa a pasta analisada com FSEvents (fila
  `com.macpaw.cmm.space-lens.live-updates`; campos `streamLatency`, `debounceInterval`,
  `maxPendingFolders`, `maxFoldersPerPass`) [E2].
- Modos: `off`, `notify`, `apply`. Estados: `pending`, `outdated`, `upToDate`. Motivos de
  desatualização: `changesDetected`, `tooManyChanges`, `scannedFolderChanged`,
  `watchUnavailable` [E2].
- Mudanças logo abaixo da pasta analisada marcam o resultado como desatualizado; nas demais, revarre
  só a pasta afetada e aplica a diferença (`SpaceLensFolderChanges`: adicionados, removidos,
  redimensionados, delta de tamanho) [E1][E2].

## Para o CleanYourMac (forma proposta)

### Algoritmo de varredura (só API pública)
1. **Entrada:** URL do volume (`/`) ou de uma pasta. Guardar `dev_t` da raiz (`lstat`) e a lista de
   volumes montados (`FileManager.mountedVolumeURLs(includingResourceValuesForKeys:options: [])`).
2. **Leitura de pasta:** abrir com `open(O_DIRECTORY)` e ler em lote com **`getattrlistbulk`**
   pedindo nome, tipo, `ATTR_CMN_DEVID`, `ATTR_CMN_FILEID`, `ATTR_CMN_FLAGS`, `ATTR_FILE_LINKCOUNT`,
   `ATTR_FILE_ALLOCSIZE` (+ tamanho do fork de recursos, para igualar `totalFileAllocatedSize`)
   e `ATTR_FILE_DATALENGTH`. Alternativa mais simples (e ainda rápida):
   `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:[.fileResourceTypeKey,
   .totalFileAllocatedSizeKey, .fileSizeKey, .linkCountKey, .fileResourceIdentifierKey],
   options: [])`, que usa `getattrlistbulk` por baixo.
3. **Paralelismo:** fila de pastas pendentes consumida por N trabalhadores
   (`N = min(8, núcleos)`, o CleanMyMac usa 4); cada pasta é uma unidade; a árvore é montada no
   fim de cada pasta (sem trava global por arquivo). Cancelamento checado por pasta.
4. **Regras:**
   - **não seguir symlinks** (tipo `symbolicLink` = folha de tamanho do link);
   - **não cruzar volumes**: pular filho cujo `devid` ≠ o da pasta-pai, **exceto** os firmlinks do
     volume de dados quando a raiz é `/` (lista em `/usr/share/firmlinks`: `/Users`,
     `/Applications`, `/Library`, `/private`, `/opt`, `/cores`, e também aninhados como
     `/System/Library/Caches`, `/System/Library/Assets*`, `/usr/local`); pular `/System/Volumes`
     inteiro, `/.nofollow`, `/.resolve`, `/.vol`, `/dev`, `/Volumes/*` (outros volumes), `/home`
     e `/net` (autofs);
   - **tamanho alocado** (`ATTR_FILE_ALLOCSIZE` / `totalFileAllocatedSize`); lógico só em FAT e
     exFAT;
   - **hard links contados uma vez**: para arquivo com `linkCount > 1`, guardar `(dev, inode)`
     num conjunto; a segunda ocorrência entra com tamanho 0 (o item continua listado);
   - sem FDA, pular pastas que disparam pedido de permissão (`~/Library/Reminders`, e as demais da
     lista de TCC do projeto).
5. **Purgável:** só se a raiz for um volume interno; valor = `CSDiskSpaceGetRecoveryEstimate`
   (pública) ou, como reserva, `volumeAvailableCapacityForImportantUsage −
   volumeAvailableCapacity`. Vira um filho especial da raiz.
6. **"X de Y usados":** `Y = volumeTotalCapacity`; `X = Y − volumeAvailableCapacityForImportantUsage`
   (= total − disponível − purgável).
7. **Memória:** por nó guardar só nome (não o caminho inteiro), tamanho, folhas, flags e filhos;
   o caminho se reconstrói pelos pais.

### Como reproduzir os números do CleanMyMac
- Tamanho: alocado (`totalFileAllocatedSize`), unidades decimais (1 GB = 10⁹ B), uma casa decimal
  abaixo de 100 ("19,9 GB", "831 MB", "4,9 MB").
- Excluir `/System/Volumes/*` e outros volumes; manter os firmlinks; não seguir links.
- **Hard links:** o CleanMyMac conta cada caminho. Para bater exatamente (ex.: `/usr` 831 MB),
  contar cada link; o padrão nosso conta uma vez (`/usr` daria 805 MB). Ver divergências.
- Total da raiz = soma dos filhos + purgável; "usados" = total − disponível para uso importante.

## requiresAdmin
- Análise: **não** (nem o CleanMyMac usa o ajudante para analisar).
- Remoção: ver `ui-and-removal.md`.

## Evidências
- **E1** — `re-notes/static/SpaceLensScanning/symbols.txt`: `SpaceLensFileSystemEntity.init(path:size:isDirectory:isPurgeable:cloudStatus:)`,
  `leavesCount`, `removableLeavesCount`, `cloudFilesCount`, `cloudLocalFilesCount`,
  `SpaceLensEntityTree.entity(at:in:)` / `replacingChildren(…)`, `SpaceLensFolderChanges(addedPaths, removedPaths, resizedPaths, sizeDelta)`,
  `SpaceLensScanTasksFactory.createScanTask(directory:strategy:)` e
  `createFolderRefreshTask(directory:knownSubdirectories:strategy:)`; nomes de campo do
  `__swift5_reflstr` (`notCloud`, `cloudEvicted`, `cloudLocal`, `cloudRootPaths`, `reusableSubdirectories`).
- **E2** — strings de `SpaceLensModule`: classes `SpaceLensNodeMapper`, `SpaceLensItemNode`,
  `SpaceLensLiveUpdater`, `VolumeModelProvider`, `SpaceLensIndicatorViewModel`; campos `mode`,
  `streamLatency`, `debounceInterval`, `maxPendingFolders`, `maxFoldersPerPass`, `pending`, `outdated`,
  `upToDate`, `changesDetected`, `tooManyChanges`, `scannedFolderChanged`, `watchUnavailable`,
  `$__lazy_storage_$_isProtected`; log "folders changed right under the scanned folder; the result is reported outdated.".
- **E3** — Ghidra, `re-notes/decomp/SpaceLensScanning/FUN_0000b610.c` (montagem dos filhos de uma
  pasta): pede `NSURLFileSizeKey`, `NSURLTotalFileAllocatedSizeKey`, `NSURLFileResourceTypeKey`;
  compara com os tipos diretório/regular/link; descarta prefixo de 21 caracteres (o literal
  `/System/Volumes/Data/` em `__cstring`) e o literal `/.nofollow` / `/.nofollow/`; ramo com o
  tipo de sistema de arquivos.
- **E4** — `nm -m` de `SpaceLensScanning`: importa só `URL.resourceValues`, chaves de recurso,
  `lstat`, `withThrowingTaskGroup`, `FullDiskAccessPermissionProviderType`,
  `CMVolumeBackupSizeCacher`; nenhum símbolo de `fts_*`, `getattrlistbulk`, `NSMetadataQuery`,
  `HealthMonitoring*` ou do ajudante privilegiado.
- **E5** — Ghidra, `SpaceLensScanTasksFactory._createScanTask.c`: `maxConcurrentScans = 4`,
  `includesPurgeableSpace = true`, `kind = "Scan"`, rastreador de progresso com intervalo
  500.000.000 ns; quando o FDA não está autorizado, o filtro recebe `NSHomeDirectory() +
  "/Library/Reminders"` (literal de 18 caracteres em `__cstring`).
- **E6** — string "Failed to scan directory at " em `SpaceLensScanning`.
- **E7** — dumps de Acessibilidade `re-notes/ax/spacelens-20261022/{root,users,home}.txt`
  (rótulos, tamanhos, ordem, caixas × ícone "Informações", caminho "Macintosh HD › Usuários").
- **E8** — Ghidra: `FUN_0000f96c` (filtro compara a profundidade com `maxDepthLevel` e procura o
  caminho em `externalVolumes`) e `FUN_000029b8` (monta o `VolumeChecker` com `/Volumes`); campos
  `isFDAGranted`, `customIgnorePaths`, `checkForExternalVolumes`, `remindersPath`,
  `externalVolumes`, `maxDepthLevel`; vetor estático em `__DATA` (0x1d3b0) com 4 cadeias:
  `/`, `/private/var/vm`, `/home`, `/net`.
- **E9** — medidas nesta máquina (sem `sudo`): `du -skx` e `du -skxA` das pastas da raiz;
  `du -skl` e soma de `st_blocks` por arquivo em `/bin`, `/sbin`, `/usr`; `du -skl` de cada
  subpasta de `/System` exceto `Volumes` (soma 19.457.684 KiB); `du -skl` dos filhos de `~`.
- **E10** — enum `FileSystemType` (`hfs`, `apfs`, `ufs`, `msdos`, `exfat`, `ntfs`, `other`,
  `undefined`) e log "File system type: " em `SpaceLensScanning`.
- **E11** — Ghidra `re-notes/decomp/FileManagerService/FUN_0000ff80.c` / `FUN_0000f554.c`
  (`VolumeInfoManager`: `VolumeTotalCapacity`, `VolumeAvailableCapacity`, `VolumeIsReadOnly`,
  `VolumeIsEjectable`, `VolumeUUIDString`, `VolumeLocalizedName`); logs do módulo
  "SpaceLensIndicatorViewModel: Used size is less than purgeable space" e "… Used without
  purgeable space is less than selected".
- **E12** — `df -k`, `diskutil info /`, `diskutil apfs list` (System 12,6 GB, Data 203,5 GB,
  Preboot 9,1 GB, VM 2,1 GB) e programa nosso com `URLResourceValues` (capacidades acima).
- **E13** — Ghidra `FUN_0000a518.c` / `FUN_0000b37c.c`: com `includesPurgeableSpace`, lê
  `NSURLIsVolumeKey` e `NSURLVolumeIsEjectableKey` da pasta; se for volume não ejetável e
  `backupSizeForVolumeAtURL:` > 0, acrescenta a entidade com `isPurgeable = true`.
- **E14** — Ghidra `FileManagerService`: `CMVolumeBackupSizeCacherItem updateIfNeededWithTimeout:completion:`
  (intervalo mínimo `max(10, 2×lastTimeToFetch)`, `dispatch_semaphore_wait` de 200 ms) e o bloco
  `FUN_00004610`, que chama `CSDiskSpaceGetRecoveryEstimate(volumeURL)`; ver também
  `docs/re/specs/performance/maintenance-tasks.md` (E16, E17).
- **E15** — símbolo `SpaceLensViewController.init(viewModel:bubblesUIConfig:pathControlURLProvider:)`;
  `URLResourceValues.localizedName` de `/Users` = "Users" no nosso processo (idioma en) e
  "Usuários" no caminho do CleanMyMac (idioma pt-BR).
- **E16** — Ghidra `FUN_0000b610.c`: `lstat` e teste do bit 30 de `st_flags` (`SF_DATALESS`);
  `FUN_0000236c` lê `NSURLIsUbiquitousItemKey` e `NSURLUbiquitousItemDownloadingStatusKey`;
  strings "Mobile Documents", "Entering cloud candidate root at: ", "Cloud candidate root scanned in %.2fs".
- **E17** — `re-notes/static/SpaceLensModule/localizable-pt-BR.json`, chave
  `spacelens_cloud_evicted_protection_reason`.
- **E18** — Ghidra `re-notes/decomp/SpaceLensModule/FUN_000245ac.c`: ordem das checagens
  `iCloudAliasPathFor:` → duas consultas da base de conhecimento → `isFileRestrictedAtPath:` →
  `isFileProtectedByRootlessAtPath:`.
- **E19** — `docs/re/specs/common.md` §3.3 (`ProtectedFolderSet`); textos
  `space_lens_tooltip_system_folder`, `space_lens_system_folder_info_checkbox_text`,
  `space_lens_list_info_essential_item` (`SpaceLensUI`); símbolos
  `SpaceLensItemViewModel.isProtected`, `.isSystemFolder`, `.protectionReason`.
- **E20** — `ls -lOd` dos itens da raiz e de `~/Library`, `~/Downloads`, `~/Projetos`.

## Divergências conhecidas
- **Hard links:** nós contamos uma vez (anti-objetivo do design: não mostrar números maiores que o
  disco); o CleanMyMac conta a cada caminho. Diferença nesta máquina: `/usr` 805 × 831 MB, `/bin`
  4,3 × 4,9 MB, `/sbin` 2,2 × 2,5 MB. Um modo de paridade pode contar cada link.
- **Itens essenciais:** a base cifrada do CleanMyMac marca mais itens (ex.: `/opt`). Nós usamos
  SIP + `SF_RESTRICTED` + a lista própria do projeto (`PathPolicy.isVital`) e as pastas-padrão.
- **Cache:** nenhum (igual ao CleanMyMac). Revarredura parcial e FSEvents ficam para depois da v0.4.

## Dúvidas em aberto
- O papel exato da lista fixa `/`, `/private/var/vm`, `/home`, `/net` (exceção de volumes ou
  exclusão). Os números de `/private` (8,2 GB, com os 2,1 GB de `/private/var/vm` dentro) indicam
  que `/private/var/vm` **não** foi excluído.
- Em que caso exato o tamanho lógico substitui o alocado (qual valor do enum de sistema de
  arquivos).
- Valor de `maxDepthLevel` do `VolumeChecker`.
