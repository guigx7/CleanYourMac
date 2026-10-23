# Acúmulos: Imagens similares (`similarImages`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon (arm64), 2026-10-23.
Só análise estática (`OrganizeModule`, com o código embutido de `SimilarImagesScanning` e
`ImageProcessing`; `OrganizeScanning`), dumps AX já gravados
(`re-notes/ax/clutter-20261023/`) e leitura do disco. **A fototeca e o app Fotos não foram
abertos**; nada foi clicado no CleanMyMac. Método de leitura do código: disassembly anotado em
`re-notes/disasm/` (ver `duplicates.md`, "Versão de referência").

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa.

## 1. Fontes

### O que o CleanMyMac faz
- **Duas fontes** [E1][E2]:
  1. **Imagens soltas na pasta pessoal** (`realHomeDirectory`), pela mesma enumeração de
     Duplicatas (`FileNodeEnumerator`, 16 pastas em paralelo).
  2. **Fototeca do Fotos** (`DirectoryURLProvider.photoLibrary`), pelo `PhotoLibraryEnumerator`
     (log "… similar image from photo library candidates").
- **Regras para as imagens soltas** = regras comuns (`duplicates.md` §1: regex de nomes, 79
  extensões, `/System`, `/Library`, `~/Library`, `~/Music/Music`, `~/Music/iTunes`, ocultos,
  pacotes `photoslibrary`/`musicLibrary` fora) **mais** as próprias de Similares
  (`similarImagesSpecificRules`, 4 regras) [E3]:
  - tamanho mínimo **102.400 bytes (100 KiB)**;
  - **só conteúdo do tipo imagem** (`AcceptedContentKindIgnoreRule`; o tipo vem de
    `ContentKindEvaluator`, que testa conformidade com `UTType.image` / `UTType.movie` a partir
    de `contentType`);
  - extensões **`psd` e `psb`** fora (arquivos do Photoshop);
  - extensão **`xcassets`** fora.
- **Fototeca, como é lida** [E2][E4]:
  - permissão do Fotos pelo PhotoKit (`PHPhotoLibrary.requestAuthorization:` e o log
    "PhotoLibrary.authorizationStatus: …");
  - busca de `PHAsset` com predicado `(mediaType = %d) OR (mediaType = %d)` (imagem ou vídeo),
    **incluindo ocultos e todas as fotos de rajada** (`setIncludeHiddenAssets:`,
    `setIncludeAllBurstAssets:`);
  - para cada asset monta `PhotosItemInfo` (`identifier`, `name`, `filename`, datas, `width`,
    `height`, `isFavorite`, `location`, `albums`) e marca `isInDeletedAlbum` comparando os
    álbuns com nomes conhecidos de "Apagados Recentemente" (`knownDeletedItemsAlbumNames`);
    itens desse álbum ficam de fora (inferência pelo nome);
  - o arquivo correspondente é achado **dentro do pacote `.photoslibrary`** usando chaves não
    documentadas do `PHAsset` lidas por KVC (`originalFilename`, `thumbnailIdentifier`) e as
    pastas internas `Masters`, `Previews`, `Thumbnails` (logs "ItemPropertiesFetcher: no
    directory for …", "PHAsset: no thumbnailIdentifier for …"). **Isso é API privada; não
    vamos reproduzir.**
- **Pastas varridas na prática:** a pasta pessoal inteira menos as exclusões; `~/Pictures`
  entra, mas o pacote da fototeca só pelo caminho do PhotoKit [E3].

### Para o CleanYourMac (forma proposta)
- Imagens soltas: `~` com as mesmas exclusões; tipos aceitos = conformidade com
  `UTType.image`, menos `psd`/`psb`/`xcassets`; tamanho mínimo 100 KiB.
- Fototeca: **só PhotoKit público**. `PHAsset.fetchAssets(with: .image, options:)`
  (`includeHiddenAssets = false` por padrão, `includeAllBurstAssets = true`), miniatura por
  `PHImageManager.requestImage(targetSize: 256×256, contentMode: .aspectFit, options:
  .fastFormat + isNetworkAccessAllowed = false)`. Fotos só no iCloud (sem miniatura local)
  ficam de fora e entram na contagem de "análise parcial". Tamanho de cada asset: soma dos
  `PHAssetResource` (o valor `fileSize` por KVC é não documentado; usar
  `PHAssetResourceManager` só se o usuário pedir o total exato) (decisão nossa).

## 2. Como decide que duas imagens são "similares"

### O que o CleanMyMac faz
- **Não usa Vision.** Nenhum dos binários importa `VNGenerateImageFeaturePrintRequest` nem nada do
  Vision [E5]. Tudo sai de ImageIO + Accelerate (vImage, BLAS, LAPACK).

#### 2.1 Miniatura de entrada
- Cada candidato vira **uma miniatura** por `CGImageSourceCreateThumbnailAtIndex` com três opções:
  `kCGImageSourceThumbnailMaxPixelSize = 256`, `kCGImageSourceCreateThumbnailFromImageAlways =
  true` e `kCGImageSourceCreateThumbnailWithTransform = true` (orientação EXIF aplicada) [E16].
  O valor 256 é o mesmo da constante exportada `_CMThumbnailMaxSize` (`OrganizeScanning`,
  `__TEXT,__const` @0x2ecd0 = 256) [E16].
- A **mesma miniatura** alimenta o hash (§2.2) e as características de qualidade (§3) [E17].
  Se qualquer um dos dois falhar, sai o log "Failed to calculate image hash or characteristics
  for …" e a imagem não entra em nenhum grupo [E1].
- As miniaturas são calculadas em paralelo: `concurrentCompactMap(maxConcurrentTasks: 6)` sobre o
  fluxo de candidatos [E18].

#### 2.2 Hash (`CMImageHashForImage`, C, em `OrganizeScanning` @0x2936c) [E6][E19]
1. **Filtro de dimensões:** com L = maior lado e C = menor lado da miniatura, o hash só é
   calculado se **L ≥ 128 e C ≥ 32**; senão a função devolve falha (e a imagem sai, §2.1).
2. **Conversão para 8 bits com alfa:** `vImageConverter` da miniatura para o formato
   8 bits por canal, 32 bits por pixel, espaço sRGB, `bitmapInfo = 4`
   (`kCGImageAlphaFirst`: **ARGB com alfa não pré-multiplicado**), flags `kvImageDoNotTile`. O
   fundo passado ao conversor é {0,0,0,0}, mas como o destino tem alfa ele não é aplicado: a
   transparência **não é achatada sobre fundo nenhum**; os canais de cor ficam como vierem da
   conversão (inferência: pixels totalmente transparentes de origem pré-multiplicada viram RGB = 0,
   ou seja, preto).
3. **Luminância:** `vImageMatrixMultiply_ARGB8888ToPlanar8` com os coeficientes de
   `kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2` convertidos para inteiros em ponto fixo de 8 bits por
   truncamento: **A = 0, R = 54, G = 183, B = 18, divisor 256**, sem pré-bias, pós-bias 0. O
   alfa é ignorado. Resultado: um plano de 8 bits w × h.
4. **Gradiente (Sobel 3×3, inteiro):** dois `vImageConvolve_Planar8`, cada um com **divisor 8**,
   cor de fundo 0 e flags `kvImageBackgroundColorFill | kvImageDoNotTile` (bordas lidas como 0;
   saída saturada em 0…255, então respostas negativas viram 0). Núcleos (linha a linha):
   - núcleo 1: `[-1 -2 -1; 0 0 0; 1 2 1]` (derivada vertical);
   - núcleo 2: `[-1 0 1; -2 0 2; -1 0 1]` (derivada horizontal).
   **Os dois resultados são gravados no mesmo buffer de destino**, então o segundo
   (horizontal) sobrescreve o primeiro antes da combinação [E19].
5. **Combinação (`combineGradients`):** para cada pixel, `min(255, trunc(√(a² + b²)))`, onde a e
   b são os dois planos de gradiente. Como os dois apontam para o mesmo buffer, na prática o
   valor é `min(255, trunc(√2 · g))`, com g = resposta saturada do núcleo 2.
6. **Para ponto flutuante:** tabela de 256 entradas `i / 255` (`vImageLookupTable_Planar8toPlanarF`).
7. **Redução:** `vImageScale_PlanarF` do plano inteiro para **32 × 32** (sem manter proporção),
   flags `kvImageDoNotTile`, sem `kvImageHighQualityResampling` (inferência pela documentação da
   vImage: reamostragem Lanczos padrão).
8. **Quatro orientações:** palavra 0 = imagem 32×32; palavras 1, 2 e 3 = a anterior girada mais
   uma vez com `vImageRotate90_PlanarF` (constante de rotação 1 = **90° anti-horário**, fundo 0),
   ou seja 0°, 90°, 180° e 270° anti-horário.
9. **DCT 32×32** de cada orientação: D = M · I · Mᵀ (dois `cblas_sgemm`, linha-maior, float).
   A matriz M (32×32) é:
   - linhas k = 1…31: `M[k][n] = 0,25 · cos(k · (2n+1) · π/64)` (DCT-II ortonormal, 0,25 = √(2/32));
   - **linha 0: `M[0][n] = (1/√32) · cos((2n+1) · π/64)`**: não é a linha constante da DCT
     padrão; usa o mesmo cosseno da linha 1, com escala 1/√32 (0,176777). Isso está no código
     (constantes π/64 = 0,0490874 e 0,176777, @0x29a44…0x29b1c) e precisa ser reproduzido para o
     hash bater [E19].
10. **Binarização:** pega o bloco **8 × 8 de canto** D[u][v], u, v = 0…7 (64 valores, inclui
    D[0][0]); limiar = **média** dos 64 (soma × 1/64); bit (8u + v) = 1 se D[u][v] **≥** média
    (bit 0 = D[0][0], bit 63 = D[7][7]).
11. **Saída:** `ImageHash.hashes` = **4 × UInt64**, na ordem [0°, 90° ah, 180°, 270° ah]
    (array de 4 alocado e preenchido pelo C) [E17].

#### 2.3 Comparação (`ImageSimilarityCalculator.areHashesSimilar`) [E7]
- Distância = **soma, sobre as 4 palavras, de popcount(h1[i] XOR h2[i])** (palavra i com palavra
  i: 0° com 0°, 90° com 90° etc.; **não** é o mínimo entre rotações). Total em 0…256.
- Similar se **distância ≤ 15** (o código compara `threshold ≥ soma`; `threshold = 15`, passado
  em `ImageSimilarityCalculator.init(threshold:)` com `w0 = 0xf`).

#### 2.4 Agrupamento (coletor de `SimilarImagesGroupCollector`) [E20]
- **Guloso, incremental, sem fusão de grupos** (não é union-find nem componentes conexas):
  1. a lista de grupos começa vazia;
  2. cada imagem que sai do fluxo é comparada com **todos os membros** de cada grupo, na ordem em
     que os grupos foram criados, membro a membro na ordem de entrada;
  3. no **primeiro** membro similar (§2.3), a imagem é **anexada ao fim daquele grupo** e a busca
     para;
  4. se nenhum membro de nenhum grupo for similar, a imagem abre um **grupo novo** com ela só.
  Uma imagem nunca une dois grupos existentes; o encadeamento só acontece dentro de um grupo
  (cada nova imagem só precisa parecer com um membro qualquer).
- **Ordem de processamento:** a ordem de chegada no fluxo de resultados do
  `concurrentCompactMap` (6 tarefas), que segue a enumeração (`FileNodeEnumerator`, 16 pastas em
  paralelo, e a fototeca), sem ordenação por data, nome ou tamanho. Logo a ordem **não é
  determinística** (inferência pela concorrência).
- **Sem limite de tamanho de grupo**, sem janela de tempo, sem filtro de proporção: não há
  constante nem comparação desse tipo no coletor nem na finalização [E20][E21].
- **Finalização** de cada grupo [E21]:
  1. tira os membros que a base de conhecimento marca com `IgnoreStatus.skipGrouping`
     (`SimilarImagesKnowledgeBaseIgnoreRule`; a base é `info.cmmkb`, não decifrada);
  2. se sobrar **1 membro ou nenhum**, o grupo é descartado;
  3. calcula a "melhor para manter" (§3) e monta `SimilarImageGroupModel`.
- Filtros antes do hash (§1): ≥ 100 KiB, tipo imagem, sem `psd`/`psb`/`xcassets`. Filtros dentro
  do hash: miniatura com maior lado ≥ 128 e menor lado ≥ 32 (§2.2 passo 1).
- **Grupo na interface** (`SimilarImageGroupModel`): título = **data** do grupo (observado: "4 de
  set. de 2024"), tamanho = soma das imagens, contador = total de instâncias [E8]. Grupos
  observados com 2 a 12 imagens, de 4,1 MB a 8,2 MB, ordenados por tamanho.

### Para o CleanYourMac (forma proposta)
- **Reproduzir o hash do CleanMyMac com APIs públicas, sem Vision** (código nosso; os passos e
  constantes acima são fatos técnicos):
  - miniatura: `CGImageSourceCreateThumbnailAtIndex` com max 256, `FromImageAlways` e
    `WithTransform`; descartar se maior lado < 128 ou menor lado < 32;
  - usar as **mesmas funções da vImage** com os mesmos parâmetros (conversor para ARGB8888
    não pré-multiplicado sRGB; `vImageMatrixMultiply_ARGB8888ToPlanar8` com {0, 54, 183, 18}/256;
    `vImageConvolve_Planar8` com divisor 8, fundo 0, `BackgroundColorFill`; combinação
    `min(255, trunc(√2·g))` usando só o núcleo horizontal; tabela i/255; `vImageScale_PlanarF`
    para 32×32; `vImageRotate90_PlanarF` com constante 1). Assim arredondamento, saturação e
    reamostragem ficam iguais sem reimplementar a vImage;
  - DCT com a matriz M descrita em §2.2 passo 9 (incluindo a linha 0 "torta") via
    `cblas_sgemm` ou `vDSP_mmul`, em `Float`;
  - bits do bloco 8×8 contra a média dos 64, bit 8u+v; 4 palavras [0°, 90°, 180°, 270°].
- Comparação: soma dos popcounts das 4 palavras, **≤ 15**.
- Agrupamento: o mesmo **guloso de primeiro grupo compatível, sem fusão**, com descarte de grupos
  com menos de 2. **Divergência deliberada:** processar as imagens em **ordem determinística**
  (caminho completo, comparação simples de strings; depois fototeca por `creationDate`) para que
  duas análises da mesma pasta deem os mesmos grupos (o CleanMyMac depende da ordem de chegada
  das tarefas paralelas).
- Sem janela de tempo para a fototeca (o CleanMyMac não tem; a regra de ±10 min proposta antes
  foi abandonada).
- Nossa "base de conhecimento" não existe: o passo `skipGrouping` fica vazio.
- **Cópias exatas ficam fora** (observado pela paridade, 2026-10-23): toda imagem que está num
  grupo de Duplicatas sai das Similares antes do agrupamento. Com isso, 65 grupos / 261 imagens
  nesta máquina contra 65 / 264 do CleanMyMac (sem a regra: 140 / 499). Inferência: é o efeito da
  base de conhecimento ou do `skipGrouping`.
- **Implementado** em `Core/Sources/CleanYourMacCore/Clutter/SimilarImages.swift` com a vImage;
  autovalores do ruído por Jacobi (mesmo resultado do `dsyev_`, sem depender da interface LAPACK).

## 3. "Melhor para manter" e falhas visuais

### O que o CleanMyMac faz
- Para cada imagem calcula `ImageCharacteristics(metrics:width:height:)` sobre a **mesma
  miniatura de 256 px** do hash [E9][E17]. `metrics` é uma lista de `ImageMetric` (enum com valor
  `Double`: caso 0 = `noise`, 1 = `blur`, 2 = `dynamicRange`); cada métrica pode faltar.
  `width`/`height` = dimensões da miniatura (não do arquivo original) [E22].
- **Base comum:** a miniatura é desenhada num `CGBitmapContext` cinza (`DeviceGray`, 8 bits,
  sem alfa, bytesPerRow = largura) e lida como bytes [E22].
- **`dynamicRange`** = **20 · log10(máx / mín)** dos níveis de cinza (dB). Se o mínimo for 0 a
  métrica fica ausente [E22].
- **`blur`** (apesar do nome, mede detalhe fino: maior = mais nítido, inferência pela fórmula)
  [E23]:
  1. transformada de **Haar 2D completa** nos níveis de cinza (`Double`): primeiro cada linha,
     depois cada coluna, com a Haar 1D a seguir;
  2. Haar 1D de comprimento L: para i em 0…⌊L/2⌋−1, média `(x[2i] + x[2i+1]) / 2` vai para a
     posição i e diferença `(x[2i] − x[2i+1]) / 2` vai para ⌊L/2⌋ + i; repete na primeira metade
     enquanto o comprimento do nível anterior for > 3 (inferência: com L ímpar a última amostra
     do nível não é transformada);
  3. `blur` = **variância populacional** (÷ N) da **segunda metade do array achatado** (linha a
     linha) do resultado, ou seja, das linhas ⌊h/2⌋… do coeficiente 2D.
- **`noise`** (estimativa de nível de ruído por PCA de blocos de textura fraca) [E24]:
  1. exige largura e altura ≥ 8;
  2. blocos **8 × 8** em passo de **7 px** nas duas direções (posições 0, 7, 14 … enquanto
     posição < dimensão − 7), cada bloco vira um vetor de 64 níveis;
  3. variância de cada bloco; ordena crescente; limiar = a variância na posição ⌊n/10⌋ (**10º
     percentil**); se esse limiar for ≤ 0, usa a primeira variância positiva da lista;
  4. mantém só os blocos com variância ≤ limiar;
  5. matriz de covariância 64 × 64 desses blocos e autovalores com `dsyev_` (`jobz = 'N'`,
     `uplo = 'U'`);
  6. `noise` = **menor autovalor estritamente positivo** (inferência: é uma variância, σ²).
- **"Melhor para manter"** (pontuação por grupo) [E10][E25]:
  1. mínimo e máximo **do grupo** de `noise`, `blur`, `dynamicRange`, `width` e `height`
     (ignorando métricas ausentes);
  2. normalização de cada valor: `(v − mín) / (máx − mín)`; se máx = mín, usa o **valor bruto**
     sem normalizar. Ausentes: `noise` vira 1, `blur` vira 0, `dynamicRange` vira 0;
  3. **pontuação = √((ruídoN − 1)² + nitidezN²) + 0,3 · faixaN + 0,1 · larguraN + 0,1 · alturaN**
     (o código guarda `(1 − blurN) − 1 = −blurN`, que ao quadrado dá `blurN²`);
  4. ordena por pontuação **decrescente** (`sort` da biblioteca padrão do Swift; empates ficam na
     ordem do grupo, inferência);
  5. marca `isBestInGroup` nas **k primeiras**, com k pelo tamanho do grupo: **2–3 membros → 1;
     4–6 → 2; 7 ou mais → 3**. Daí o texto "Uma das melhores para manter"
     (`image_best_to_keep_tooltip`).
- **Favorita do Fotos não pesa:** `isFavorite` é lido do PhotoKit, mas não entra na pontuação nem
  é consultado pelo módulo (inferência pela ausência de chamadas) [E11].
- **Falhas visuais:** selo "Falhas Visuais" com as variantes **Desfoque** e **Ruído**
  (`image_flaws_*`) [E12]. **O critério não foi achado:** nenhuma comparação de `blur`/`noise` com
  constante aparece em `OrganizeModule` (os getters de `noise`/`blur`/`dynamicRange` só são
  chamados no mín./máx. e na pontuação acima) [E25].

### Para o CleanYourMac (forma proposta)
- Reproduzir as três métricas e a pontuação **exatamente** como acima (miniatura de 256 px em
  cinza; Haar 2D; PCA 8×8 com passo 7 e 10º percentil, autovalores por LAPACK do Accelerate
  `dsyev_`; 20·log10(máx/mín)), com o mesmo k de melhores (1/2/3).
- **Divergência deliberada:** favorita do Fotos entra como desempate (vence entre pontuações
  iguais), não sobrepõe a pontuação.
- Falhas visuais (regra nossa até achar a do CleanMyMac): selo "Desfoque" se `blurN` ≤ 0,25 e o
  grupo tem `blur` máx./mín. ≥ 2; "Ruído" se `noiseN` ≥ 0,75 e máx./mín. ≥ 2 (a calibrar).

## 4. Seleção
- Como em Duplicatas: no Gerenciador a seleção começa vazia (dump AX) e o menu "Selecionar" do
  grupo tem as opções de `SelectionControlFactory.makeSimilarImages` [E8][E13]. A marcação
  automática deixa a "melhor" de fora (inferência).
- **Nosso app:** marcação automática = todas menos a melhor; nunca todas sem o alerta "Selecionar
  Tudo".

## 5. Cartões
Regras (tela em `results-and-manager.md`) [E14]:
- **"N Imagens Similares Novas Encontradas"** (`MostRecentSimilarsRule`, "Most Recent Similars"):
  imagens dos **últimos 30 dias** (`Calendar.date(byAdding: .day, value: -30)`); texto "%@ de
  fotos praticamente idênticas apareceram no Mac nos últimos 30 dias". Observado: "13 Imagens
  Similares Novas Encontradas / 15,9 MB …" [E8].
- **"N Imagens Similares Grandes Encontradas"** (`BiggestSimilarsRule`, "Large Similars"):
  "Há %@ de imagens praticamente idênticas no Mac"; critério de "grande" não lido
  (`SizeBasedTileRule`).
- **"N Similares Encontradas no App Fotos"** (`PathBasedSimilarsRule`, "Photos Similars"):
  grupos da fototeca; "Talvez você queira remover até %@ de imagens desnecessárias da
  fototeca".
- **"N Imagens Similares Encontradas"**: genérico.

## 6. Remoção da fototeca
- `PhotoLibraryRemover` usa **`PHPhotoLibrary.performChangesAndWait`** com
  **`PHAssetChangeRequest.deleteAssets:`** [E15]. Pelo comportamento do PhotoKit, o macOS mostra a
  confirmação do sistema e os itens vão para **"Apagados Recentemente"** (podem ser recuperados
  por 30 dias). Há um removedor de depuração que só registra "[SIMULATE]: Photo library removal"
  (`DebugPhotoLibraryRemover`), escolhido por configuração (`ConfigDependentPhotoLibraryRemover`).
- Imagens soltas: ver `results-and-manager.md` §6.
- **Nosso app:** fototeca só por `PHAssetChangeRequest.deleteAssets` (uma chamada para todo o
  lote, para o sistema pedir uma única confirmação); se o usuário negar, nada muda e mostramos
  "Remoção cancelada". Imagens soltas: Lixo.

## 7. Permissões
- **CleanMyMac:** permissão **Fotos** (PhotoKit) e leitura do pacote da fototeca; a pasta pessoal
  depende do Acesso Total ao Disco para Mesa/Documentos/Downloads (provedores
  `sandboxAccessProviders` / `homeFolderSandboxAccessProvider`) (inferência sobre o caso exato).
- **Nosso app:** pedir **Fotos** (`PHPhotoLibrary.requestAuthorization(for: .readWrite)`) só ao
  entrar em Imagens similares; sem a permissão, analisar só as imagens soltas e mostrar o aviso.
  Acesso Total ao Disco segue a regra geral do app (já existe na aba Configurações).

## requiresAdmin
- Análise: não. Limpeza: não.

## Evidências
- **E1** — strings de `OrganizeModule`: "Enumerating similar image candidates...", " similar image
  candidates.", " similar image from photo library candidates.", "Failed to calculate image hash
  or characteristics for ", "Collecting groups from processed candidates stream...".
- **E2** — disasm `re-notes/disasm/OrganizeModule.d.s`: `SimilarImagesScanTaskFactory` e funções
  vizinhas leem `realHomeDirectory` e `DirectoryURLProvider.photoLibrary`.
- **E3** — disasm `re-notes/disasm/OrganizeScanning.d.s` @0x18518 (`similarImagesSpecificRules`):
  array de 4 regras (`MinimumFileSizeIgnoreRule` com `(102400, 7)`,
  `AcceptedContentKindIgnoreRule`, `FilePathExtensionsRule` `["psd","psb"]` e `["xcassets"]`);
  `ContentKindEvaluator.contentKind` com `UTType.image`/`.movie`.
- **E4** — strings de `OrganizeScanning`: "(mediaType = %d) OR (mediaType = %d)",
  `setIncludeHiddenAssets:`, `setIncludeAllBurstAssets:`, `requestAuthorization:`,
  "originalFilename", "thumbnailIdentifier", "Masters", "Previews", "Thumbnails" (montadas de
  `mov/movk`), `PhotosItemInfo.knownDeletedItemsAlbumNames`, `isInDeletedAlbum`,
  `OrganizeScanning/PhotoKitLibraryItemsBuilder.swift`.
- **E5** — `otool -L` e `nm -u` de `OrganizeModule`/`OrganizeScanning`: Photos, ImageIO,
  Accelerate, CryptoKit, QuickLookThumbnailing; nenhum `Vision`.
- **E6** — disasm `OrganizeScanning.d.s` `_CMImageHashForImage` (@0x2936c) e `_combineGradients`
  (detalhes em E19):
  `vImageMatrixMultiply_ARGB8888ToPlanar8` com `kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2`,
  2 × `vImageConvolve_Planar8` 3×3, `vImageLookupTable_Planar8toPlanarF`, `vImageScale_PlanarF`,
  `vImageRotate90_PlanarF`, `cos`, `cblas_sgemm`; símbolos `ImageHash.hashes: [UInt64]`,
  `_CMThumbnailMaxSize`, `ImageAttributesCalculator.generateImageThumbnail(from:)`.
- **E7** — disasm `OrganizeModule.d.s` `ImageSimilarityCalculator.areHashesSimilar` (@0xa0cc8,
  linhas 169048–169080): laço sobre `hash1.count` palavras (trava se `hash1.count >
  hash2.count`), XOR palavra a palavra + `cnt`/`addv`, soma com checagem de estouro, resultado
  `cmp threshold, soma; cset hs` (soma ≤ threshold); chamada
  `ImageSimilarityCalculator.init(threshold:)` com `w0 = 0xf` (@0x9c204).
- **E8** — `re-notes/ax/clutter-20261023/imagens-similares.txt` e `results.txt`.
- **E9** — símbolos `ImageCharacteristics.blur/noise/dynamicRange/width/height/metrics`,
  `ImageAttributesCalculator.calculateImageCharacteristics`; `nm -u` de `OrganizeModule`:
  `_dsyev_`.
- **E10** — disasm `OrganizeModule.d.s` @0x96bb0 e @0x98420: mínimos/máximos por grupo de
  `noise`, `blur`, `dynamicRange`; subtração/divisão (normalização), `1 − blur`, constantes
  0,3 e 0,1; `SimilarImageModel.isBestInGroup`.
- **E11** — `isFavorite` aparece só em `OrganizeScanning` (construtor e getter de
  `PhotosItemInfo`); zero ocorrências em `OrganizeModule.d.s`.
- **E12** — `localizable-pt-BR.json`: `image_flaws_title`, `image_flaws_tooltip`,
  `image_flaws_variant_blur`, `image_flaws_variant_noise`, `image_best_to_keep_tooltip`.
- **E13** — símbolo `SelectionControlFactory.makeSimilarImages(node:)`.
- **E14** — strings "Most Recent Similars", "Large Similars", "Photos Similars" e tipos
  `MostRecentSimilarsRule`, `BiggestSimilarsRule`, `PathBasedSimilarsRule`; disasm @0x44474
  (`Calendar.date(byAdding: .day, value: -30 …)`); `Localizable.stringsdict` (pt-BR) com
  `tile_recent_similars_found_title`, `tile_large_similars_found_title`,
  `tile_photos_similars_found_title`, `tile_similars_found_title`.
- **E15** — `nm -u`: `PHAssetChangeRequest`, `PHPhotoLibrary`; strings `deleteAssets:`,
  `performChangesAndWait:error:`, "[SIMULATE]: Photo library removal ",
  `ConfigDependentPhotoLibraryRemover`, `DebugPhotoLibraryRemover`,
  `OrganizeModule/PhotoLibraryRemover.swift`.
- **E16** — disasm `OrganizeModule.d.s` linhas 169269–169289 (@0xa1008–0xa1058): dicionário de
  opções da miniatura com `kCGImageSourceThumbnailMaxPixelSize` = `0x100`,
  `kCGImageSourceCreateThumbnailFromImageAlways` = 1, `kCGImageSourceCreateThumbnailWithTransform`
  = 1, seguido de `CGImageSourceCreateThumbnailAtIndex` (linha 169557). `nm` de
  `OrganizeScanning`: `_CMThumbnailMaxSize` @0x2ecd0; leitura de `__TEXT,__const` = 256.
- **E17** — `OrganizeModule.d.s` 168525–168811: `calculateImageAttributes` gera a miniatura uma vez
  (@0xa06e4) e chama o hash (@0xa0710 → 0xa282c) e as características (@0xa0770 → 0xa4ca8) sobre
  ela; @0xa282c (linha 170847): aloca array de **4** `UInt64` zerados e chama
  `_CMImageHashForImage` (linha 170866); falha → `nil`.
- **E18** — `OrganizeModule.d.s` linha 164187 (@0x9c4d8): `concurrentCompactMap` com
  `maxConcurrentTasks` = 6; linha 164005 (@0x9c200): `ImageSimilarityCalculator.init(threshold:)`
  com 15; o mesmo bloco cria `SimilarImagesGroupCollector` (@0x9c214).
- **E19** — `OrganizeScanning.d.s` (função @0x2936c, linhas 42302–42610): linhas 42329–42341
  (maior lado ≥ 128.0 e menor ≥ 32.0); 42393–42423 (formato de destino: `(8, 32)` lido de
  @0x2eca8, sRGB, `bitmapInfo` 4; `vImageConvert_AnyToAny`); 42452–42480 (coeficientes 709
  convertidos com `fcvtzs …, #8`, alfa 0, divisor `0x100`); 42489–42537 (duas
  `vImageConvolve_Planar8` 3×3, divisor 8, flags `0x14`; destino da 1ª copiado de `sp+0x90` na
  linha 42494 e da 2ª na 42516, o mesmo buffer); núcleos copiados por @0x2983c (linhas
  42612–42663) de @0x2ecd8 = `(-1,-2,-1,0,0,0,1,2,1)` e @0x2ecea = `(-1,0,1,-2,0,2,-1,0,1)`
  (leitura de `__TEXT,__const`); `_combineGradients` 42666–42700 (`sqrt(a²+b²)`, satura 255);
  tabela i/255 em @0x29990 (42702–42725); 42550–42570 (`vImageScale_PlanarF` para 32×32,
  rowBytes 128); 42578–42605 (laço de 4: `vImageRotate90_PlanarF` com constante 1 a partir da 2ª
  volta e hash por @0x299ec); @0x299ec (42727–42958): linha 0 da matriz com π/64 (0,0490874) e
  0,176777 (42750–42804), linhas 1…31 com `0,25·cos(k·(2n+1)·π/64)` (42805–42830, constante
  @0x2ecb0 = π/64), transposta (42837–42851), 2 × `cblas_sgemm` 32×32×32 (42858–42898), bloco
  8×8 e soma (42906–42929), média = soma × `0x3c800000` (1/64) e bits por `fcmp …; cset ge` do
  índice 63 ao 0 (42930–42941).
- **E20** — `OrganizeModule.d.s` @0x93148 (linha 154420): para cada item do fluxo chama @0x95554
  com a lista de grupos atual; @0x95554 (156777–156953): laço externo nos grupos, interno nos
  membros, chamada ao `areHashesSimilar` via tabela do protocolo (@0x95620); no primeiro `true`
  anexa ao grupo (156869…) e retorna; sem correspondência cria grupo de 1 (156843…).
- **E21** — `OrganizeModule.d.s` @0x9580c (156953–158212): filtra `IgnoreStatus.skipGrouping`;
  linha 157252 `cmp x25, #0x1; b.ls` (≤ 1 membro → sem grupo); 157263–157299: k de melhores por
  tamanho (constantes 3/5/7 = fim de fatia 1/2/3, função de fatia @0x98328, linhas 159766–159825);
  `SimilarImageGroupModel.init(similarImages:)` no fim.
- **E22** — `OrganizeModule.d.s` @0xa4ca8 (linha 173204…): chama @0xa28a0 (cinza: 
  `CGColorSpaceCreateDeviceGray`, `CGBitmapContextCreate(…, 8, largura, …, 0)`), @0xa3d80
  (`noise`), @0xa49f8 (`blur`), mín./máx. dos bytes e `log10` × 20.0 (linha 173303); enum
  `ImageMetric` lido pelos getters @0xa09ac/0xa09e8/0xa0a28 (tags 0/1/2);
  `ImageCharacteristics.height` = 2º `Double`.
- **E23** — `OrganizeModule.d.s` @0xa4394 (172615…, Haar 1D com 0,5·(a±b), laço até
  comprimento ≤ 3), @0xa4650 (172794…, linhas e depois colunas), @0xa49f8 (173030…, média e
  variância da metade final do array).
- **E24** — `OrganizeModule.d.s` @0xa3d80 (172224…: exige ≥ 8, passos `+7` nas linhas 172254 e
  172259, 8 leituras de 8 bytes por bloco), @0xa29ec (170963…: variância por bloco, ordenação,
  índice n/10 via multiplicação por `0x6666…67` na linha 171283, fallback na 1ª variância > 0,
  seleção `≤`), @0xa3a64/@0xa3868 (covariância e `dsyev_` com `'N'`/`'U'`, linha 171976; menor
  autovalor > 0, linha 172190).
- **E25** — `OrganizeModule.d.s` @0x96bb0 (158212–158328: mín./máx. de noise, blur,
  dynamicRange, altura, largura); @0x98420 (159832–160140: normalização, ausentes = 1/0/0,
  `fsqrt`, 0,3 e 0,1 nas linhas 159922–159926, soma na 160022); @0x97958 (159128…: ordenação por
  inserção que só troca se anterior < atual, ou seja decrescente). `grep` de `noise.getter`,
  `blur.getter`, `dynamicRange.getter`: só chamados de @0x96bb0 e @0x98420; nenhuma constante
  de limiar de falhas visuais em `OrganizeModule`.

## Divergências conhecidas
- Hash, comparação e agrupamento reproduzidos (§2); a ordem de processamento é determinística no
  nosso app e de chegada das tarefas paralelas no CleanMyMac, então grupos de fronteira podem
  sair diferentes.
- Fototeca só por PhotoKit público (miniaturas de 256 px pelo `PHImageManager`), sem ler o
  pacote `.photoslibrary`; a miniatura pode diferir da que o ImageIO gera do arquivo.
- Favorita do Fotos não pesa (igual ao CleanMyMac); o tamanho das fotos da fototeca fica
  desconhecido ("—"), porque não há API pública barata para ele.
- Sem base de conhecimento (`skipGrouping`).
- Falhas visuais com regra nossa.

## Dúvidas em aberto
- Critério do selo "Falhas Visuais" (Desfoque/Ruído): não está em `OrganizeModule`; pode estar no
  módulo de interface que monta o detalhe da imagem.
- Se a vImage aplica o núcleo como correlação ou convolução verdadeira (muda qual borda sobrevive
  à saturação); usando a própria `vImageConvolve_Planar8` a questão some.
- Critério do cartão "Imagens Similares Grandes".
- Se ocultos da fototeca entram também em Similares (o predicado inclui ocultos; o filtro de
  álbuns não foi lido).
