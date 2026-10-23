# Acúmulos: Resultados, Gerenciador e remoção

Esta spec descreve o fluxo do módulo **Acúmulos** ("My Clutter") depois da análise: a tela de
Resultados (cabeçalho, cartões e suas condições), o **Gerenciador de Acúmulos** (categorias,
filtros, seleção, alerta de "Selecionar Tudo", selo "melhor para manter", galeria), a remoção
(Lixo × definitiva; fototeca), o estado "nada encontrado" e a análise parcial ("Reanalisar").
Os textos são citados pelo sentido e pela chave; os textos finais da UI são nossos. As regras de
cada categoria estão em `duplicates.md`, `similar-images.md`, `large-old-files.md` e
`downloads.md` desta pasta.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), 2026-10-23. Dumps de Acessibilidade já gravados
(`re-notes/ax/clutter-20261023/results.txt`, `manager.txt`, `duplicatas.txt`,
`imagens-similares.txt`, `downloads.txt`), `localizable-pt-BR.json` e `Localizable.stringsdict`
do `OrganizeModule`, e disassembly anotado em `re-notes/disasm/`. Nada foi clicado no
CleanMyMac para esta spec.

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa.

## 1. Intro e análise
- Intro: título **Acúmulos**, frase "Organize seus arquivos e reduza a bagunça em apenas alguns
  cliques", quatro itens ilustrados: **Arquivos grandes**, **Duplicatas**, **Imagens
  similares**, **Downloads** (`intro_*`) [E1].
- Durante a análise: "Analisando…" com o subtítulo "Buscando duplicatas e possíveis arquivos
  desnecessários" (variações por etapa: "Buscando fotos similares na fototeca", "Buscando arquivos
  grandes e não usados no Mac", "Verificando arquivos baixados…") [E1].
- As quatro análises rodam como tarefas separadas (Downloads, Duplicatas, Fundo do Baú,
  Similares), montadas juntas no construtor do módulo [E2].
- **Fluxos avulsos** (busca do app / atalhos): "Descobridor de duplicatas", "Imagens similares",
  "Fundo do baú", "Downloads", cada um com descrição e palavras-chave próprias
  (`custom_flow_*`) [E1].

## 2. Tela de Resultados

### 2.1 Cabeçalho
- **EVIDÊNCIA** [E3]: título "Acúmulos"; frase em duas linhas, no plural/singular conforme o
  número: "Você tem **N** arquivos para revisar. / Use as recomendações rápidas ou revise‑os
  manualmente." (`scan_results_header_title`, observado N = 885); botão principal **Revisar Todos
  os Arquivos** (`scan_results_open_data_manager_button`), que abre o Gerenciador; na barra de
  cima, **Recomeçar**.
- N = soma de `unwantedFilesCount` dos produtos das quatro análises (inferência pelo nome do campo
  comum `ScanProduct.unwantedFilesCount`) [E2].

### 2.2 Cartões
- Um cartão por categoria, escolhido por **regras** (`RuleBasedTileViewModelFactory`): a primeira
  regra que casa decide o título e o texto (inferência sobre a prioridade) [E2]. Botão de cada
  cartão: **Revisar** (`tile_review_button`), que abre o Gerenciador já na categoria e com a
  marcação automática aplicada (inferência).

| Categoria | Regra (nome interno) | Condição | Título (sentido, `%@`/`%d`) | Texto |
|---|---|---|---|---|
| Similares | `MostRecentSimilarsRule` ("Most Recent Similars") | imagens dos últimos 30 dias | "%d Imagens Similares Novas Encontradas" | "%@ de fotos praticamente idênticas apareceram no Mac nos últimos 30 dias" |
| Similares | `BiggestSimilarsRule` ("Large Similars") | critério de tamanho (não lido) | "%d Imagens Similares Grandes Encontradas" | "Há %@ de imagens praticamente idênticas no Mac" |
| Similares | `PathBasedSimilarsRule` ("Photos Similars") | grupos da fototeca | "%d Similares Encontradas no App Fotos" | "Talvez você queira remover até %@ de imagens desnecessárias da fototeca" |
| Similares | genérica | — | "%d Imagens Similares Encontradas" | "Revise as fotos e imagens praticamente idênticas…" |
| Duplicatas | `PathBasedDuplicatesRule` ("Dups in Desktop") | cópia em `~/Desktop` | "%d Arquivos Duplicados Encontrados na Mesa" | "Remova %@ de cópias desnecessárias…" |
| Duplicatas | idem ("Dups in Documents") | cópia em `~/Documents` | "%d Arquivos Duplicados Encontrados em Documentos" | idem |
| Duplicatas | `FreshDuplicatesRule` ("Dups from the Last 3 Months") | criadas nos últimos 90 dias | "%d Duplicatas Novas Encontradas" | "Remova %@ de arquivos duplicados dos últimos 3 meses" |
| Duplicatas | genérica (com limite de tamanho, `SizeBasedTileRule`) | — | "%d Arquivos Duplicados Encontrados" | "Remova %@ de cópias…" ou "Revise os arquivos duplicados…" |
| Fundo do Baú | `LAOFRule` | último acesso há mais de 365 dias | "%@ de Arquivos Grandes e Antigos Encontrados" | "Considere remover arquivos grandes e desnecessários que você pode ter esquecido" |
| Downloads | `DownloadsTile` | app com downloads | "%@ de Downloads do %@ Encontrados" (tamanho, app) | "Revise e remova os downloads desnecessários…" |
| (bloqueado) | "Unlock Duplicates & Similars" | plano sem o recurso | "Desbloqueie Duplicatas e Similares" | "Em média, as pessoas têm cerca de 5 GB de arquivos duplicados" + botão "Desbloquear Novos Recursos" |

- **Observado** [E3], nesta ordem: "13 Imagens Similares Novas Encontradas / 15,9 MB…",
  "45 Arquivos Duplicados Encontrados em Documentos / Remova 35,6 MB…", "591 MB de Downloads do
  Google Chrome Encontrados". **Sem cartão do Fundo do Baú**, embora a categoria tivesse 1,7 GB:
  nenhum arquivo passava de 1 ano sem acesso.
- **Depois da remoção**, cada cartão troca para o título de conclusão ("%d Duplicatas Removidas da
  Mesa", "%@ de Arquivos Grandes Removidos", "%@ de Downloads do %@ Removidos", "%d Fotos
  Similares Removidas"…) e o texto "Você acabou de economizar %@ de espaço" / "Agora você tem
  mais %@ para as suas memórias" [E4].

### 2.3 Nada encontrado
- Título "Como você atingiu esse nível de organização?" e subtítulo "Não há acúmulos para buscar"
  (`scan_results_nothing_found_*`) [E1]. Botão principal: **Recomeçar** (padrão do `ModuleCore`,
  como no Desempenho; inferência por analogia com `../performance/results-screen.md` §1).

### 2.4 Análise parcial ("Reanalisar")
- Duplicatas e Similares têm `isPartial` no produto (`DuplicatesScanProduct.isPartial`,
  `SimilarImagesScanProduct.isPartial`) [E2]. Quando verdadeiro, aparece o botão **Reanalisar**
  com o tooltip "Não foi possível completar a análise de alguns itens. Faça outra análise para
  incluí‑los, a qual poderá levar mais tempo do que o normal" (`partial_scan_result_*`; o texto
  original tem o erro de digitação "Não for possível") [E1].
- Gatilho provável: tempo limite do observador (`OrganizeWatcherTiming.timeout`) ou itens que
  falharam (imagem que não abriu, fototeca sem permissão) (inferência).

## 3. Gerenciador de Acúmulos

### 3.1 Estrutura [E3][E5]
- Barra de cima: **Voltar**, título "Gerenciador de Acúmulos", busca "Busque nos itens
  encontrados", **Ordenar por: Tamanho** (menu).
- Barra lateral de categorias, nesta ordem: **Fundo do Baú**, **Duplicatas**, **Imagens
  Similares**, **Downloads**.
- Rodapé: "%d Item(ns) Selecionado(s)" + tamanho, e **Remover** (desabilitado sem seleção).
- Cabeçalho de cada categoria: nome + frase de descrição (`*_category_description`).

### 3.2 Filtros
- **Fundo do Baú**: lista de filtros com totais — Todos os Arquivos, Selecionados; **Por Tipo**
  (Arq. Comp., Documentos, Imagens, Vídeos, Outro); **Por Tamanho** (Pequeno, Médio, Imenso);
  **Por Data de Acesso** (Semana Passada, Há Uma Semana, Há Um Mês, Há Seis Meses, Há Um Ano).
  Só aparecem os filtros com itens. Limites exatos em `large-old-files.md` §4 [E5].
- **Duplicatas**: menu **Mostrar:** Todos os Arquivos, Selecionados, Aplicativos, Arquivos
  Comprimidos, Áudio, Documentos, Imagens, Vídeos, Outros (`duplicates.md` §4) [E5].
- **Imagens Similares** e **Downloads**: sem filtro de tipo.

### 3.3 Grupos e linhas
- **Duplicatas**: linha de grupo = ícone, nome do arquivo, tamanho total do grupo e o número de
  cópias ("O total de duplicatas do arquivo"); ao abrir, um menu **Selecionar:** (começa em
  "Nenhum") e as cópias com caixa, nome, caminho, **data de criação** e tamanho; contador
  "O número de duplicatas selecionadas para remoção" [E5].
- **Imagens Similares**: linha de grupo = **data** (ou o nome, quando é imagem solta, ex.
  "Captura de Tela …jpg"), tamanho total e número de instâncias. Ao abrir, uma **galeria**
  (`MediaGalleryView`) com miniaturas, caixa por imagem, selo **"Uma das melhores para manter"**
  (vários por grupo: num grupo de 6 havia 2) e um painel de pré‑visualização com metadados:
  Modificação, Criação, Tamanho, Tipo do arquivo, Captura, Dimensões, Resolução, Espaço de cores,
  Perfil de cores; selo **"Falhas Visuais"** (Desfoque / Ruído) quando houver [E5][E6].
- **Fundo do Baú**: linhas soltas com caixa, nome, caminho, **data do último acesso** e tamanho.
- **Downloads**: grupo por app (Google Chrome, Slack, Safari) com total, frase "Revise os arquivos
  que você baixou com o %@", menu "Selecionar:" e as linhas dos arquivos.

### 3.4 Seleção
- **Seleção inicial vazia** em todas as categorias quando se entra por "Revisar Todos os
  Arquivos" (todas as caixas `checked=0`, "0 Item Selecionado") [E3][E5].
- Menu **Selecionar:** do grupo: opções por critério (Maior, Menor, Mais recente, Mais antigo;
  `Largest/Smallest/Newest/OldestSelectionControlOption`) que marcam todos menos o que o
  critério escolhe para manter (`splitNodes`) [E2].
- **"Selecionar Tudo" num grupo** (marcar todas as cópias/instâncias) dispara um alerta [E1]:
  - mensagem: "Tem certeza de que deseja selecionar todos os itens deste grupo?";
  - informação: "Todas as instâncias do arquivo serão removidas";
  - botões: **Selecionar Tudo** e **Cancelar**.
  (`SelectionAlerterType` no código) [E2].
- **"Melhor para manter"** (Similares): `isBestInGroup` vindo da pontuação de qualidade
  (`similar-images.md` §3). Em Duplicatas não há selo; a cópia que fica é a da cadeia de
  desempate (`duplicates.md` §3).

## 4. Remoção

### 4.1 Fluxo
- Botão **Remover** → tela de progresso "Removendo arquivos…" → conclusão [E1]:
  - sucesso: "Remoção concluída!" / "Remoção bem‑sucedida", com o resumo ("%d itens") e o botão
    **Revisar Mais Itens** (`cleanup_complete_review_remaining_button_title`);
  - falha: "A remoção falhou…" / "Não foi possível remover alguns arquivos. Verifique se nenhum
    app os está usando e tente novamente";
  - registro: "Registro de Acúmulos" (`cleanup_view_log_title`).
- Duplicatas usam uma tarefa própria (`DuplicateRemovalTask`) [E2].

### 4.2 Lixo ou definitiva?
- **EVIDÊNCIA** [E7]: o construtor do módulo escolhe o removedor pelo tipo de configuração
  (`OrganizeModuleConfig.Kind`): em **dois** dos casos sem dados usa **`MoveToTrashFileRemover`**
  (vai para o Lixo); nos demais usa **`FileRemover`** (remoção definitiva via `FileManager`),
  embrulhado num `ConfigDependentFileRemover` (que permite simular a remoção em depuração).
- **INFERÊNCIA**: os dois casos do Lixo são os do Smart Care (`smartCare`, `smartCareLAOF`), e
  o módulo Acúmulos aberto pela barra lateral apaga **definitivamente**. Não confirmamos qual
  caso é qual; fica como dúvida (§ "Dúvidas").
- Arquivos protegidos (`ProtectedFileRemover`, com a lista de pastas protegidas) são tratados pelo
  serviço comum de arquivos (`../common.md` §3.3) [E7].

### 4.3 Fototeca
- Itens da fototeca **não** passam pelo removedor de arquivos: vão para o `PhotoLibraryRemover`,
  que chama `PHPhotoLibrary.performChangesAndWait` com `PHAssetChangeRequest.deleteAssets:`.
  O macOS pede confirmação e as fotos vão para **Apagados Recentemente** [E8]
  (`similar-images.md` §6).

## 5. Para o CleanYourMac (forma proposta)
- **Resultados:** mesmo cabeçalho (texto nosso) e **um cartão por categoria**, com a prioridade:
  Similares (30 dias → fototeca → genérico), Duplicatas (Mesa → Documentos → 90 dias →
  genérico), Fundo do Baú (> 1 ano), Downloads (app de maior total). Sem cartão de bloqueio.
- **Nada encontrado** e **Reanalisar**: iguais em comportamento; "parcial" quando houver item que
  não pôde ser lido (permissão negada, foto só no iCloud, imagem corrompida), com a contagem.
- **Gerenciador:** mesmas quatro categorias, mesmos filtros (com a correção de "Documentos"),
  seleção inicial vazia, menu "Selecionar" por grupo, alerta de "Selecionar Tudo".
- **Proteções de seleção:** o botão Remover fica **desabilitado** se algum grupo de Duplicatas ou
  Similares estiver com todas as cópias marcadas e o usuário não tiver confirmado o alerta
  daquele grupo; nunca removemos o único exemplar de um conteúdo sem essa confirmação explícita.
- **Remoção:** sempre **Lixo** (`FileManager.trashItem`) para arquivos (padrão do projeto, inclusive
  fora do Smart Care); fototeca só pelo PhotoKit (`deleteAssets`, um lote por remoção). Recusa
  pela `PathPolicy`; erro por item ("em uso", "sem permissão") no registro, sem abortar o lote.
- Volta automática para a lista com os itens removidos fora, e os totais recalculados.

## requiresAdmin
- Análise: não. Limpeza: não.

## Evidências
- **E1** — `re-notes/static/OrganizeModule/localizable-pt-BR.json` (153 chaves): `intro_*`,
  `scan_*`, `custom_flow_*`, `scan_results_*`, `partial_scan_result_*`, `selection_alerter_*`,
  `cleanup_*`, `tile_*`.
- **E2** — `re-notes/static/OrganizeModule/symbols.txt` e `strings.txt`:
  `OrganizeScanResultsViewModel.init(node:title:subtitle:buttonTitle:tiles:…:hasMoreItemsAvailable:…)`,
  `RuleBasedTileViewModelFactory`, `SizeBasedTileRule`, `PlainScanProduct.unwantedFilesCount`,
  `DuplicatesScanProduct.isPartial`, `SimilarImagesScanProduct.isPartial`,
  `OrganizeWatcherTiming.timeout`, `SelectionAlerterType`, `SelectionControlFactory`,
  `*SelectionControlOption.splitNodes`, `DuplicateRemovalTask`; disasm @0x58ab8 (as quatro
  fábricas de tarefa).
- **E3** — `re-notes/ax/clutter-20261023/results.txt` e `manager.txt`.
- **E4** — `Localizable.stringsdict` (pt-BR) do `OrganizeModule`: `scan_results_header_title`,
  `tile_*_found_title`, `tile_*_completion_title`, `data_manager_footer_selected_items_count`,
  `cleanup_complete_success_generic_items_title`.
- **E5** — `re-notes/ax/clutter-20261023/manager.txt`, `duplicatas.txt`,
  `imagens-similares.txt`, `downloads.txt`.
- **E6** — símbolos `MediaGalleryView`, `MediaGalleryPreviewViewController`,
  `MediaGalleryMetadataRowViewModel`; `OrganizeScanning` importa `kMDItemPixelWidth/Height`,
  `kMDItemResolutionWidth/HeightDPI`, `kMDItemColorSpace`, `kMDItemProfileName`,
  `kMDItemContentCreationDate`, `kMDItemAcquisitionMake/Model`, `kMDItemDurationSeconds`.
- **E7** — disasm `re-notes/disasm/OrganizeModule.d.s` @0x14e98: teste do caso de
  `OrganizeModuleConfig.Kind` (`getEnumTagSinglePayload` com 3 casos vazios; casos 1 e 2 →
  `MoveToTrashFileRemover`, demais → `FileRemover.init(fileManager:)`), depois
  `ConfigDependentFileRemover.init(from:)`; `ProtectedFileRemover.shared` em @0x2d980 e @0x732a8.
- **E8** — `nm -u`: `PHAssetChangeRequest`, `PHPhotoLibrary`; strings `deleteAssets:`,
  `performChangesAndWait:error:`, `PhotoLibraryRemover`, `ConfigDependentPhotoLibraryRemover`,
  "[SIMULATE]: Photo library removal ".

## Divergências conhecidas
- Remoção sempre para o Lixo (o CleanMyMac apaga definitivamente em pelo menos uma
  configuração).
- Sem cartão de bloqueio/plano.
- Bloqueio do Remover enquanto houver grupo inteiro marcado sem confirmação (o CleanMyMac só
  alerta no momento de marcar).

## Dúvidas em aberto
- Qual caso de `OrganizeModuleConfig.Kind` usa o Lixo e qual apaga direto (confirmar sem
  remover nada: por exemplo, olhando o registro de uma limpeza já feita pelo usuário).
- Prioridade exata entre as regras de cartão de uma mesma categoria e a ordem dos cartões
  (observado: Similares, Duplicatas, Downloads).
- O que exatamente liga `isPartial` (tempo limite × falhas).
