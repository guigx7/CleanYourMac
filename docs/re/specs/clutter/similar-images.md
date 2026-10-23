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
  Vision [E5].
- **Hash perceptual próprio** (`CMImageHashForImage`, em C, dentro de `OrganizeScanning`) [E6]:
  1. imagem (ou miniatura de até `_CMThumbnailMaxSize`, gerada com
     `CGImageSourceCreateThumbnailAtIndex`) convertida para RGBA 8 bits;
  2. luminância (matriz ITU-R 709) para um plano de 8 bits;
  3. duas convoluções 3×3 (gradientes horizontal e vertical) e combinação dos gradientes
     (`combineGradients`);
  4. conversão para ponto flutuante, redução de escala e versões giradas de 90°
     (`vImageScale_PlanarF`, `vImageRotate90_PlanarF`);
  5. transformada do tipo DCT (cossenos + `cblas_sgemm`) e binarização em palavras de 64 bits.
  O resultado é `ImageHash.hashes: [UInt64]` (várias palavras; inferência: uma por orientação ou
  por bloco).
- **Comparação** (`ImageSimilarityCalculator.areHashesSimilar`): soma das **distâncias de
  Hamming** (XOR + contagem de bits) entre as palavras dos dois hashes; **similar se a soma for
  ≤ 15** (`ImageSimilarityCalculator(threshold: 15)`) [E7].
- **Janela de tempo:** não foi encontrada nenhuma constante de intervalo entre fotos no coletor de
  grupos (inferência: o agrupamento é só pelo hash; a data serve para o título).
- **Grupo** (`SimilarImageGroupModel`): título = **data** do grupo (observado: "4 de set. de
  2024"), tamanho = soma das imagens, contador = total de instâncias [E8]. Grupos observados com
  2 a 12 imagens, de 4,1 MB a 8,2 MB, ordenados por tamanho.
- Falha ao ler uma imagem só gera o log "Failed to calculate image hash or characteristics for
  …" e a imagem sai da análise [E1].

### Para o CleanYourMac (forma proposta)
- **Vision**, API pública: `VNGenerateImageFeaturePrintRequest` na miniatura; distância com
  `VNFeaturePrintObservation.computeDistance`. Limiar inicial **0,35** (revision 2), a calibrar
  com um conjunto de teste nosso (anotar o valor final na spec quando medir).
- Pré-filtro barato: dHash 64 bits (próprio, 9×8 em escala de cinza) com Hamming ≤ 12 para
  reduzir pares antes do Vision.
- Agrupamento por componentes conexas (union-find) dos pares similares; grupo com 2 ou mais.
- Para fotos da fototeca, restringir pares à mesma janela de **±10 min** de `creationDate`
  (decisão nossa, reduz falsos positivos e custo; divergência documentada).

## 3. "Melhor para manter" e falhas visuais

### O que o CleanMyMac faz
- Para cada imagem calcula `ImageCharacteristics`: **largura, altura, desfoque (`blur`), ruído
  (`noise`) e faixa dinâmica (`dynamicRange`)**, mais uma lista de `ImageMetric` [E9].
  - O ruído usa decomposição em autovalores (`dsyev_` do LAPACK) (inferência: estimativa de nível
    de ruído por PCA de blocos da imagem). O desfoque vem do mesmo pipeline de gradientes
    (inferência).
- Em cada grupo, os valores são **normalizados pelo mínimo e o máximo do grupo** e combinados
  numa pontuação com pesos fixos (aparecem as constantes 0,3 e 0,1); o desfoque entra invertido
  (menos desfoque = melhor) [E10]. Resultado: `SimilarImageModel.isBestInGroup` e o selo "Uma das
  melhores para manter" (`image_best_to_keep_tooltip`). O texto "uma das" indica que pode haver
  mais de uma (inferência).
- **Favorita do Fotos não pesa:** `isFavorite` é lido do PhotoKit, mas o módulo da interface não
  consulta esse campo (inferência pela ausência de chamadas) [E11].
- **Falhas visuais:** selo "Falhas Visuais" com as variantes **Desfoque** e **Ruído**
  (`image_flaws_*`) quando o valor passa de um limite; os limites não foram lidos [E12].

### Para o CleanYourMac (forma proposta)
- Nitidez: variância do Laplaciano (vImage, 3×3) na miniatura em cinza. Ruído: desvio padrão do
  resíduo de um filtro de mediana 3×3. Pontuação = 0,45 × resolução normalizada + 0,35 ×
  nitidez normalizada + 0,20 × (1 − ruído normalizado); **favorita do Fotos sempre vence**
  (decisão nossa). Selo "Desfoque" se a nitidez < 25 % da melhor do grupo; "Ruído" se o ruído >
  2 × o menor do grupo (limiares nossos, a calibrar).

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
- **E6** — disasm `OrganizeScanning.d.s` `_CMImageHashForImage` (@0x2936c) e `_combineGradients`:
  `vImageMatrixMultiply_ARGB8888ToPlanar8` com `kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2`,
  2 × `vImageConvolve_Planar8` 3×3, `vImageLookupTable_Planar8toPlanarF`, `vImageScale_PlanarF`,
  `vImageRotate90_PlanarF`, `cos`, `cblas_sgemm`; símbolos `ImageHash.hashes: [UInt64]`,
  `_CMThumbnailMaxSize`, `ImageAttributesCalculator.generateImageThumbnail(from:)`.
- **E7** — disasm `OrganizeModule.d.s` `ImageSimilarityCalculator.areHashesSimilar` (@0xa0cc8):
  laço de XOR + `cnt`/`addv` (contagem de bits) e `distância ≤ threshold`; chamada
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

## Divergências conhecidas
- Algoritmo: Vision feature print (nós) × hash perceptual próprio com Hamming ≤ 15 (CleanMyMac).
  Os grupos não vão bater 1:1; o teste de paridade compara só "mesmo conjunto de fotos de
  rajada / sequência" em casos óbvios.
- Fototeca só por PhotoKit público (miniaturas), sem ler o pacote `.photoslibrary`.
- Favorita do Fotos sempre é a "melhor" no nosso app.
- Janela de ±10 min para a fototeca (nossa).

## Dúvidas em aberto
- Quantas palavras de 64 bits tem `ImageHash` e o que cada uma representa.
- Pesos exatos da pontuação de "melhor" e limiares das falhas visuais.
- Critério do cartão "Imagens Similares Grandes".
- Se ocultos da fototeca entram também em Similares (o predicado inclui ocultos; o filtro de
  álbuns não foi lido).
