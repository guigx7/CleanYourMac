# Acúmulos: Duplicatas (`duplicates`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon (arm64), 2026-10-23.
Só análise estática (`OrganizeModule`, onde está embutido o código `DuplicatesScanning`, e
`OrganizeScanning`), dumps de Acessibilidade já gravados em
`re-notes/ax/clutter-20261023/` e leitura do disco. Nada foi clicado no CleanMyMac.

O Ghidra desta máquina ficou sem o decompilador nativo (versão 12.2), então a leitura do
código foi feita no **disassembly anotado** (`otool -tV` + nomes de função de
`dyld_info -function_starts` + stubs resolvidos pelos *fixups* + strings Swift curtas
remontadas dos `mov/movk`). Os arquivos ficam em `re-notes/disasm/` (ignorado pelo git),
com os scripts usados.

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa, ainda não
confirmada no binário nem por observação.

## Onde mora cada parte no CleanMyMac
| Parte | Onde | Peças |
|---|---|---|
| Enumeração de arquivos | `OrganizeScanning` | `FileNodeEnumerator`, `BatchBasedEnumerator`, `IgnoreStatus`, `InternalIgnoreRules` [E1] |
| Fototeca | `OrganizeScanning` | `PhotoLibraryEnumerator`, `PhotosItemInfo` [E1] |
| Agrupamento e hash | `OrganizeModule` (módulo `DuplicatesScanning`) | `DuplicatesGroupCollector` (atores `sizeBucketsActor` e `fileHashBucketsActor`), `FileNodeBucketItemCalculator`, `BundleNodeBucketItemCalculator`, `RegularFileHashCalculator`, `DataHashCalculator`, `FileHash` [E2] |
| Regras | `OrganizeModule` | `DuplicateScanRules(knowledgeBaseIgnoreRule:ignoreRules:)`, `DuplicatesKnowledgeBaseIgnoreRule` [E2] |
| Resultado | `OrganizeModule` | `DuplicatesScanProduct` (`groups`, `isPartial`), `DuplicateGroupModel` (`duplicates`, `hash`, `kind`, `size`, `title`), `DuplicateFileModel` (`isAutoselected`, `creationDate`, `modificationDate`, `resourceLocator`) [E2] |

## 1. Onde procura

### O que o CleanMyMac faz
- **Raiz: a pasta pessoal real** (`DirectoryURLProvider.realHomeDirectory`), mais a
  **fototeca do Fotos** (`DirectoryURLProvider.photoLibrary`), enumerada à parte pelo
  `PhotoLibraryEnumerator` (log "Scan started in Photo library … N duplicate photo
  candidates") [E3][E4].
- **Enumeração:** até **16 pastas em paralelo** (`maxConcurrentScans = 16`), em lotes, pedindo de
  uma vez: data de modificação, data de criação, tamanho lógico (`fileSize`), tamanho alocado,
  oculto, tipo de recurso, identificador de tipo (UTI) e `isUbiquitousItem` [E5].
- **Regras comuns a Duplicatas, Fundo do Baú e Imagens similares** (`InternalIgnoreRules.default`,
  quatro regras) [E6]:
  1. **Nome por expressão regular** (`FileNameRegularExpressionIgnoreRule`), 13 padrões:
     `\.git`, `\.svn`, `\.Trash`, `\.DS_Store`, `credits.?`, `infoplist.?`, `web-inf.?`,
     `backups\.backupdb`, `licence.?`, `license.?`, `node_modules`, `gems`,
     `bower_components`.
  2. **Extensão** (`FilePathExtensionsRule`), 79 extensões típicas de código, build e
     sistema: `framework`, `build`, `lproj`, `a`, `so`, `h`, `pch`, `c`, `hpp`, `h++`, `cpp`,
     `c++`, `m`, `swift`, `java`, `class`, `idea`, `py`, `rb`, `php`, `css`, `js`, `json`,
     `jar`, `lib`, `dylib`, `dll`, `ocx`, `pth`, `db`, `rpl`, `hds`, `info`, `def`,
     `properties`, `proofingtool`, `bup`, `ar`, `tmp`, `hg`, `vsd`, `xsd`, `xslt`, `xsl`,
     `entitlements`, `xcconfig`, `sparsebundle`, `dsym`, `cer`, `crt`, `applescript`,
     `version`, `asset`, `prefab`, `unity`, `html`, `scss`, `sh`, `bash`, `scala`, `sc`,
     `cs`, `cake`, `coffee`, `cshtml`, `csx`, `ts`, `vim`, `vue`, `plist`, `yml`, `yaml`,
     `gradle`, `md`, `ruby`, `gemfile`, `gem`, `sql` (`py` aparece duas vezes na lista).
     Os pacotes **`photoslibrary`** e **`musicLibrary`** também saem da enumeração comum
     (a fototeca entra só pelo caminho do PhotoKit).
  3. **Prefixo de caminho** (`FilePathPrefixIgnoreRule`): `/System/`, `/Library/`,
     `~/Library/`, `~/Music/Music/` e `~/Music/iTunes/`.
  4. **Ocultos** (`HiddenURLIgnoreRule`): itens com `isHidden` ficam de fora.
- **Regras próprias de Duplicatas** (`InternalIgnoreRules.duplicatesSpecificRules`) [E7]:
  - **tamanho mínimo de 102.400 bytes (100 KiB)** (`MinimumFileSizeIgnoreRule`);
  - extensão **`xcassets`** fora (catálogos de assets do Xcode).
- **Base de conhecimento:** uma regra extra (`DuplicatesKnowledgeBaseIgnoreRule`) consulta a base
  cifrada do app; o conteúdo não foi decifrado [E2].
- **Resultado do ignorar** (`IgnoreStatus`, conjunto de opções): `skipEnumeration`,
  `skipGrouping`, `skipHashing`; o valor `7` gravado junto das regras de tamanho mínimo é
  a união dos três (inferência pelo valor) [E1][E7].
- **iCloud:** a chave `isUbiquitousItem` é pedida; como ela é tratada não foi lido
  (inferência: itens só na nuvem são pulados, já que não dá para ler o conteúdo sem baixar).
- **Pacotes (`.app` e afins):** `ContentKindEvaluator.isBundle` testa conformidade com
  `UTType.bundle`, `.package` e `.applicationBundle`; pacotes têm calculadora própria
  (`BundleNodeBucketItemCalculator`, `bundleHashCalculator`) e entram **como um item só**, o que
  alimenta o filtro "Aplicativos" [E2][E8].
- **Observado** (dump AX) [E9]: arquivos de `~/Projetos/**/build/…/SDKExplicitPrecompiledModules`
  e `DerivedData` aparecem (a regra de extensão `build` pega só itens **com** essa extensão, não
  a pasta `build`). Grupos com 2 a 11 cópias, de 4,1 MB a 13 MB.

### Para o CleanYourMac (forma proposta)
- Raiz: `~` (via `FileManager.homeDirectoryForCurrentUser`), com as mesmas exclusões (são
  fatos técnicos razoáveis) e, no nosso caso, também `~/Library` inteira, `~/.Trash`,
  pastas de outros volumes e tudo que a `PathPolicy` já recusa.
- Tamanho mínimo: 100 KiB (igual).
- Ocultos: fora. Itens só na nuvem (`ubiquitousItemDownloadingStatus != .current`): fora.
- Fototeca: fora do MVP de Duplicatas (ver "Divergências").

## 2. Como compara

### O que o CleanMyMac faz
- **1ª etapa: tamanho.** Os candidatos vão para "baldes" por tamanho (`sizeBucketsActor`,
  `FileNodeBucketItemCalculator.nodeSize`) [E2].
- **2ª etapa: hash do conteúdo.** Só os baldes com 2 ou mais itens são lidos
  (`fileHashBucketsActor`, `nodeHash`) (inferência pelo par de atores e pelo nome
  `HashPair`).
- **Hash:** **SHA-1** do CryptoKit (`Insecure.SHA1`), sobre o **arquivo inteiro**, lido com
  `FileHandle.read(upToCount:)` em blocos de **1 MiB** (`0x100000`) [E10]. Não há indício de
  hash parcial (só começo/fim) nem de comparação byte a byte depois do hash.
  - Antes de ler, o tamanho é conferido de novo (`URLResourceValues.fileSize`); arquivo vazio não
    é lido [E10].
- **Pacotes:** hash do conjunto do conteúdo (`BundleNodeBucketItemCalculator`) (inferência sobre
  a forma exata de combinar os arquivos internos).
- **Hard links e clones do APFS:** **não são distinguidos**. Nenhum dos dois binários importa
  chaves de identidade de arquivo (`fileResourceIdentifier`, contagem de links, `stat`), então
  dois caminhos para o mesmo inode, ou dois clones, viram duplicatas como quaisquer outras
  [E11] (inferência pela ausência).
- **Grupo** (`DuplicateGroupModel`): os arquivos com o mesmo `FileHash` (dados do SHA-1 +
  tamanho) [E2]. O título é o nome de um dos arquivos; o tamanho do grupo é a **soma de todas as
  cópias** (observado: 3 × 4,3 MB → "13 MB") [E9]. O contador do grupo mostra o total de cópias
  (tooltip `duplicates_total_items_in_group_tooltip`).

### Para o CleanYourMac (forma proposta)
- Etapas: tamanho → hash dos primeiros 64 KiB (corte barato) → SHA-256 do arquivo inteiro
  (CryptoKit, blocos de 1 MiB), tudo em `TaskGroup` com limite de concorrência.
- **Hard links:** agrupar antes por `fileResourceIdentifier` (`URLResourceValues`) e tratar
  links do mesmo inode como **um** item (remover um link não libera espaço). **Clones:** não há
  API pública para saber se blocos são compartilhados; mostrar normalmente, mas o "espaço a
  liberar" é uma estimativa (anotar na UI).

## 3. Qual cópia fica desmarcada (a "original")

### O que o CleanMyMac faz
- Cada arquivo tem `isAutoselected`; o seletor automático (`DuplicateAutoselectorType`) aplica
  uma **cadeia de critérios de desempate**, nesta ordem (nomes do próprio log) [E12]:
  1. "Select in Downloads folder": a cópia em `~/Downloads` (pasta de Downloads do sistema ou
     `~/Downloads` montado a partir da pasta pessoal) é a marcada para sair;
  2. "Select with greater copy number": a de número de cópia maior (ex.: `nome (2).ext`,
     `nome copy 2`) sai;
  3. "Select not in Photo library": a cópia **fora** da fototeca sai, a da fototeca fica;
  4. "Select older modified": a de modificação mais antiga sai;
  5. "Select deeper path": a de caminho mais profundo sai;
  6. "Select shorter filename": a de nome mais curto sai;
  7. "Select by file path alphabetically": desempate final pela ordem alfabética do caminho.
  Fica **uma** cópia desmarcada por grupo (inferência pelo propósito; nunca vimos um grupo com
  todas marcadas sem o alerta de "Selecionar Tudo").
- **No Gerenciador a seleção começa vazia:** o dump AX mostra todos os itens com
  `checked=0`, "0 Item Selecionado" e o menu de grupo "Selecionar: Nenhum" [E9]. A marcação
  automática é usada pelos atalhos (cartões "Revisar", Smart Care) e pelo menu "Selecionar"
  (inferência).
- Menu "Selecionar" do grupo (`SelectionControlFactory.makeDuplicates`): opções
  **Maior**, **Menor**, **Mais recente**, **Mais antigo** (`LargestSelectionControlOption`,
  `SmallestSelectionControlOption`, `NewestSelectionControlOption`,
  `OldestSelectionControlOption`), que dividem o grupo em "fica"/"sai" pelo critério escolhido
  (`splitNodes`) [E2].

- **Ajustes pela paridade (2026-10-23, 149/149 títulos iguais):** o título do grupo é o nome da
  cópia que **fica**; `nome (N).ext` e `nome N.ext` **não** contam como número de cópia (a cópia
  "(2)" mais nova fica); no desempate alfabético final sai o caminho **menor**; arquivos dentro de
  uma pasta `.xcassets` ficam de fora (a regra pula a pasta inteira); o cartão "… em Documentos"
  mostra o **total** dos grupos (35,6 MB para 45 arquivos), não só o removível.

### Para o CleanYourMac (forma proposta)
- Mesma cadeia de desempate (é regra de negócio razoável, não código), mas **sempre** deixando
  exatamente uma cópia desmarcada; a "melhor para manter" ganha um selo.
- Seleção inicial vazia no Gerenciador; o cartão "Revisar" aplica a marcação automática.

## 4. Tipos (filtro "Mostrar:")

### O que o CleanMyMac faz
- `DuplicateKind` tem 7 valores, mostrados como filtros: **Todos os Arquivos**,
  **Selecionados**, e por tipo **Aplicativos**, **Arquivos Comprimidos**, **Áudio**,
  **Documentos**, **Imagens**, **Vídeos**, **Outros** [E13].
- **Classificação por UTI** (conformidade de `UTType`) [E14]:

  | Filtro | Tipo testado |
  |---|---|
  | Aplicativos | `UTType.application` (pacotes `.app`) |
  | Arquivos Comprimidos | `UTType.archive` |
  | Áudio | `UTType.audio` |
  | Documentos | `UTType.text` |
  | Imagens | `UTType.image` |
  | Vídeos | `UTType.movie` |
  | Outros | o resto |

  A ordem dos testes não foi lida (inferência: do mais específico ao mais geral). Atenção: com
  esse critério, **PDF não é "Documento"** (`com.adobe.pdf` não conforma a `public.text`) e cai
  em "Outros" (inferência a partir da hierarquia de UTIs).
- Filtros sem itens não aparecem (observado no Fundo do Baú, mesmo componente) [E9].

### Para o CleanYourMac (forma proposta)
- Mesma tabela, mas "Documentos" = `public.text` **ou** `com.adobe.pdf` **ou**
  `public.composite-content` (corrige o caso do PDF; divergência documentada).

## 5. Cartões ligados a Duplicatas
Detalhes da tela em `results-and-manager.md`. Aqui, só as regras [E15]:
- **"N Arquivos Duplicados Encontrados na Mesa"** (`PathBasedDuplicatesRule`, nome interno
  "Dups in Desktop"): grupos com cópia em `~/Desktop`.
- **"N Arquivos Duplicados Encontrados em Documentos"** ("Dups in Documents"): idem em
  `~/Documents`. Observado nesta máquina: "45 Arquivos Duplicados Encontrados em Documentos /
  Remova 35,6 MB de cópias desnecessárias" [E9].
- **"N Duplicatas Novas Encontradas"** (`FreshDuplicatesRule`, "Dups from the Last 3 Months"):
  duplicatas criadas nos **últimos 90 dias** (`Calendar.date(byAdding: .day, value: -90)`);
  texto "Remova %@ de arquivos duplicados dos últimos 3 meses".
- **"N Arquivos Duplicados Encontrados"**: cartão genérico, com texto de tamanho
  (`tile_duplicates_sizeable_found_description`) quando passa de um limite de tamanho
  (`SizeBasedTileRule` do `ModuleCore`; valor não lido).
- **Bloqueio:** sem a assinatura certa, o cartão vira "Desbloqueie Duplicatas e Similares" ("Em
  média, as pessoas têm cerca de 5 GB de arquivos duplicados") [E13].

### Smart Care: "Downloads Duplicados"
- O módulo tem duas configurações para o Smart Care: `OrganizeModuleConfig.smartCare` e
  `.smartCareLAOF` [E2]. A categoria do Smart Care chama-se **"Downloads Duplicados"** ("Baixar um
  mesmo arquivo várias vezes…") [E13] (inferência: são os grupos em que a cópia autoselecionada
  está em `~/Downloads`, regra 1 da cadeia do §3; o recorte exato não foi lido).

## 6. Remoção
- Ver `results-and-manager.md` §6 (Lixo × definitiva; fototeca).
- **Para o CleanYourMac:** sempre para o **Lixo** (`FileManager.trashItem`), nunca o último
  exemplar de um grupo, recusando o que a `PathPolicy` protege e arquivos abertos por apps
  (checagem com `lsof`-equivalente não é API pública; usamos tentativa + erro amigável).

## requiresAdmin
- Análise: não (só a pasta pessoal; o que o usuário não lê fica de fora).
- Limpeza: não.

## Evidências
- **E1** — `re-notes/static/OrganizeScanning/symbols.txt`: `FileNodeEnumerator`,
  `BatchBasedEnumerator`, `PhotoLibraryEnumerator`, `IgnoreStatus.skipEnumeration/skipGrouping/
  skipHashing`, `InternalIgnoreRules.default/duplicatesSpecificRules/…`; tipos de regra
  `FileNameRegularExpressionIgnoreRule`, `FilePathExtensionsRule`, `FilePathPrefixIgnoreRule`,
  `HiddenURLIgnoreRule`, `MinimumFileSizeIgnoreRule`, `AcceptedContentKindIgnoreRule`
  (`strings.txt`).
- **E2** — `re-notes/static/OrganizeModule/symbols.txt` e `strings.txt`: tipos e campos citados
  na tabela (`DuplicatesScanning.*`, `sizeBucketsActor`, `fileHashBucketsActor`, `HashPair`,
  `BundleNodeBucketItemCalculator`, `bundleHashCalculator`, `OrganizeModuleConfig.smartCare`,
  `.smartCareLAOF`, opções de seleção).
- **E3** — disasm `re-notes/disasm/OrganizeModule.d.s`: as fábricas de tarefa recebem a pasta
  de `FileManagerProvider.realHomeDirectory`; `DirectoryURLProvider.photoLibrary` é lido nas
  funções de Duplicatas e de Similares.
- **E4** — strings de log: "Scan started in Photo library", ". Enumerating photos...",
  " duplicate photo candidates.", "Enumerating duplicate candidates...",
  " duplicate file candidates.", " groups of duplicate files.".
- **E5** — disasm `OrganizeScanning.d.s`, `FileNodeEnumerator.maxConcurrentScans` (`mov w0,
  #0x10`) e `urlResourceKeysToPrefetch` (8 chaves citadas).
- **E6** — disasm `OrganizeScanning.d.s`, função de inicialização de
  `InternalIgnoreRules.default` (@0x175e4): metadados das 4 regras e os arrays estáticos em
  `__DATA,__data` (decodificados por `re-notes/disasm/arrays.py`); prefixos montados com
  `systemDirectory`, `libraryDirectory`, `userLibraryDirectory`, `userMusicDirectory` +
  "Music" / "iTunes" e barra final.
- **E7** — disasm `OrganizeScanning.d.s` @0x1822c (`duplicatesSpecificRules`): array de 2 regras;
  `MinimumFileSizeIgnoreRule` com a constante `(102400, 7)` em `__TEXT,__const` @0x2e640;
  `FilePathExtensionsRule` com `["xcassets"]`.
- **E8** — `ContentKindEvaluator.isBundle` e importações `UTType.bundle`, `.package`,
  `.applicationBundle` (`re-notes/disasm/OrganizeScanning.d.s`).
- **E9** — `re-notes/ax/clutter-20261023/duplicatas.txt`, `results.txt`, `manager.txt`.
- **E10** — disasm `OrganizeModule.d.s` @0x82208–0x82bf4: `Insecure.SHA1.init/update/finalize`,
  bloco `0x100000`, `NSFileHandle.read(upToCount:)`, `URLResourceValues.fileSize`
  (`RegularFileHashCalculator.calculateHash(at:)`); `nm -u` mostra só `Insecure.SHA1` do
  CryptoKit.
- **E11** — `nm -u` de `OrganizeModule` e `OrganizeScanning`: nenhuma chave de identidade de
  arquivo nem `stat`.
- **E12** — disasm `OrganizeModule.d.s` @0x78b3c–0x78fbc: strings "Select in Downloads folder",
  "Select with greater copy number", "Select not in Photo library", "Select older modified",
  "Select deeper path", "Select shorter filename", "Select by file path alphabetically", na
  ordem; leitura de `userDownloadsDirectory`, `realHomeDirectory` + "Downloads" e
  `photoLibrary`.
- **E13** — `re-notes/static/OrganizeModule/localizable-pt-BR.json`: `duplicates_*`,
  `smart_care_duplicates_*`, `tile_unlock_*`.
- **E14** — disasm `OrganizeModule.d.s` @0x89c04: `UTType.application`, `.archive`, `.audio`,
  `.text`, `.image`, `.movie`.
- **E15** — strings "Dups in Desktop" (montada de `mov/movk`), "Dups in Documents", "Dups from
  the Last 3 Months"; disasm @0x404b0 (`Calendar.date(byAdding:value:-90…)` com componente
  `.day`); `Localizable.stringsdict` (pt-BR) com `tile_desktop_duplicates_found_title`,
  `tile_documents_duplicates_found_title`, `tile_fresh_duplicates_found_title`.

## Divergências conhecidas
- **Hash:** nós usamos SHA-256 com corte prévio pelos primeiros 64 KiB (mais rápido em arquivos
  grandes de mesmo tamanho); o CleanMyMac usa SHA-1 do arquivo inteiro.
- **Hard links:** deduplicamos por inode; o CleanMyMac não.
- **Documentos:** incluímos PDF e conteúdo composto.
- **Fototeca:** fora do MVP. Comparar fotos da fototeca exige ler os originais dentro do pacote
  `.photoslibrary`, o que o CleanMyMac faz com caminhos internos e chaves não documentadas do
  `PHAsset`; com API pública, o caminho seria `PHAssetResourceManager` (copiar cada recurso para
  calcular o hash), caro demais para o MVP.

## Dúvidas em aberto
- Tratamento exato de itens do iCloud (`isUbiquitousItem`) na enumeração.
- Como o hash de pacote combina os arquivos internos.
- Recorte exato da categoria "Downloads Duplicados" do Smart Care.
- Limite do `SizeBasedTileRule` que troca o texto do cartão genérico.
