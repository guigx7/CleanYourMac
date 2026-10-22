# Lupa de Espaço: telas, "Outros itens", seleção, revisão e remoção

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon (arm64), 2026-10-22.
**Só análise estática e dumps de Acessibilidade já gravados.** Nada foi clicado no CleanMyMac,
nada foi removido, nenhum `sudo`. A análise e o modelo de dados estão em `scan.md`.

Legenda: **[E*n*]** = evidência (lista no fim). **(inferência)** = conclusão nossa, ainda não
confirmada no binário nem por observação.

## 1. Telas e fluxo

### O que o CleanMyMac faz
1. **Intro** [E1][E2]: título "Lupa de Espaço", subtítulo, três categorias (Mapa visual do
   armazenamento, Descoberta de arquivos ocultos, Visão geral de pastas grandes), seletor de alvo
   ("Macintosh HD" ou "Escolher pasta…") e **Analisar**.
2. **Análise**: "Visualizando o espaço de armazenamento…", com tamanho já somado e caminho atual
   (atualizados a cada 0,5 s) e **Parar** [E1][E3].
3. **Resultados** (dois painéis) [E2][E4]:
   - topo: **Recomeçar**, nome do volume, indicador "**%@ de %@ usados**" (barra com segmentos
     Usados, Purgáveis, Selecionados, Livres; tooltip "%@ de %@" e "%@ usados");
   - painel esquerdo: item atual (nome, tamanho, "N itens"), menu **Selecionar:** e a **lista**
     (`NSOutlineView`) dos filhos da pasta atual;
   - painel direito: **mapa de bolhas**;
   - **caminho** (breadcrumb clicável), **voltar** e **avançar**;
   - rodapé: "**N item selecionado**", tamanho selecionado, botão de informação e
     **Revisar e Remover** (desabilitado com 0 itens).
4. **Revisão** ("Revise os arquivos antes da remoção") → **Remover**.
5. **Removendo arquivos…** → **Concluído** (sucesso ou falha) → **Registro de Remoção** [E1].
6. Estado vazio "**Pouco conteúdo para visualizar…**" (ver §7).

## 2. "Outros itens"

### O que o CleanMyMac faz (evidência)
- O nível atual é um `LevelInfo(currentItem:children:otherItems:)`: os filhos "principais" e,
  à parte, os "outros" [E5]. A lista mostra os principais e, se `otherItems` não estiver vazio,
  uma linha "**Outros itens**" que pode ser expandida (chevron; eventos "Reveal Other Items" /
  "Hide Other Items") [E5][E6]. No mapa, os outros viram **uma bolha** "Outros itens" com ícone
  próprio e tooltip "Diversos arquivos e pastas que ocupam espaço" [E5][E7].
- O tamanho de "Outros itens" é a soma dos itens agrupados.
- A divisão é feita no `SpaceLensModule` (o `LevelInfo` chega pronto à interface; a lista só
  monta a seção quando `otherItems` não é vazio) [E5][E8]. O critério exato **não foi localizado**
  no código decompilado (Swift sem símbolos; a função de corte não foi isolada).

### Observações nesta máquina [E4][E9]
| Pasta | Filhos | Mostrados | Em "Outros" |
|---|---|---|---|
| `/` (242 GB) | 20 | 9 (todos os com tamanho > 0, de 183 GB até `sbin` 2,5 MB) | 11 itens de 0 B (`Volumes`, `cores`, `dev`, `.file`, `.nofollow`, `.resolve`, `.vol`, links `etc`, `tmp`, `var`, `home`…) = 0 KB |
| `/Users` (183 GB) | 3 | 3, inclusive `.localized` com 0 B | nenhum (sem linha "Outros itens") |
| `~` (183 GB) | 52 | 7 (até `.cache` 2,4 GB = 1,33% da pasta) | 45 itens = 9,3 GB (o maior é `Pictures` 2,42 GB = 1,32%) |

Fatos que qualquer regra precisa explicar:
- **Não é um número fixo** (9 na raiz, 7 na pasta pessoal, 3 em `/Users`).
- **Não é um percentual fixo da pasta**: `sbin` (0,001% da raiz) aparece, `Pictures` (1,32% da
  pasta pessoal) não.
- **Não é "acumulado até 95%"** nem "cauda ≤ 5%": na raiz isso esconderia `opt`, `usr`, `bin`,
  `sbin`.
- Zero bytes não é motivo sozinho (`.localized` aparece em `/Users`).

### Hipótese mais provável (inferência)
O corte acompanha o que cabe no mapa de bolhas: o mapa só desenha bolhas com diâmetro ≥ um
mínimo (`minimumRenderingItemsSize`) e ajusta a escala dos raios para desenhar o máximo possível
(§3). Com poucos itens (raiz: 9 com tamanho, `/Users`: 3) cabe tudo que tem tamanho; com muitos
(pasta pessoal: 52), só os maiores cabem e o resto vira "Outros itens". Isso explicaria as três
observações, e o número de itens visíveis mudaria com o tamanho da janela. **Não confirmado**.

## 3. Mapa de bolhas

### O que o CleanMyMac faz
- **Layout:** *circle packing* (empacotamento de círculos irmãos com círculo envolvente; tipos
  `PackedNode<BubblePackingLayoutItem>` com `x`, `y`, `r`, `parent`, `children`) [E7][E10].
- **Um nível:** só os filhos da pasta atual (+ a bolha "Outros itens"); não há netos dentro das
  bolhas (observação: um botão de Acessibilidade por item do nível) [E4].
- **Escala dos raios:** função de potência (`scalingFunction`, `power`) sobre o tamanho; o expoente
  é procurado por bisseção (10 iterações, faixa 0,01–0,333 num modo) para **minimizar a
  quantidade de bolhas abaixo do diâmetro mínimo** e, no empate, maximizar o menor diâmetro.
  Bolhas abaixo do mínimo ficam ocultas [E10]. Por isso a bolha não é proporcional ao tamanho:
  `sbin` (2,5 MB) tem bolha visível ao lado de `Users` (183 GB).
- **Interação** [E7][E11]:
  - passar o mouse: destaque + tooltip (Tamanho, Modificação, Seleção, "Pasta inteira", "Pasta do
    sistema");
  - clique duplo numa bolha de pasta: entra nela (animação de zoom); clique duplo no fundo: sobe
    um nível (inferência pelo nome `handleBackgroundDoubleClick:`);
  - caixa de seleção na própria bolha (marcada, desmarcada, parcial);
  - menu de contexto (Mostrar no Finder, Quick Look com Espaço).
- **Navegação:** histórico com voltar/avançar (`SpaceLensNavigationHistory`: `canGoBack`,
  `canGoForward`, `previousItem`, `nextItem`); o caminho (`NSPathControl`) leva direto a qualquer
  pasta acima [E8][E12]. Na lista, seta → entra, seta ← volta, Espaço = Quick Look [E11].

## 4. Seleção

### O que o CleanMyMac faz
- **Caixa por item** na lista e na bolha. Estados: `selected`, `unselected`,
  `partiallySelected` (pasta com só parte dos filhos marcada) [E7][E11].
- **Sem caixa** (ícone "Informações" no lugar): itens essenciais e pastas do sistema
  (`scan.md` §7). O conteúdo de uma pasta do sistema pode ser marcado depois de entrar nela [E4].
- **Menu "Selecionar:"** com valor inicial "Nenhum" [E4]. As opções não foram vistas
  (inferência: Nenhum / Todos os itens do nível atual) [E13].
- **Rodapé:** "N item selecionado" + tamanho somado; a seleção vale entre pastas (o que foi
  marcado em outra pasta continua contando) [E1][E4].
- **Tooltip:** "Seleção: %@" quando parte de uma pasta está marcada; "Pasta inteira" quando ela
  toda está [E2].
- O indicador do topo ganha o segmento "Selecionados" [E2].

## 5. Revisão e remoção

### O que o CleanMyMac faz
- **Revisão:** "Revise os arquivos antes da remoção" (popover "Inclui itens de todas as pastas
  selecionadas."), lista dos itens marcados de todas as pastas ("Revise os itens antes da
  remoção") e **Remover** [E1][E2].
- **Plano de remoção** (`SpaceLensDeletionPlanner.units(for:shouldSpare:)`) [E14]:
  - pasta toda marcada e sem nada a poupar → **uma unidade "inteira"** (`wholesale`), apaga a
    pasta;
  - pasta com itens a poupar (essenciais, só na nuvem) → **unidade "filtrada"** (`filtered`):
    desce e apaga os filhos removíveis;
  - cada unidade guarda caminho, tamanho e `removableLeavesCount`.
- **Alerta de nuvem:** se algum item marcado for `cloudLocal`, antes de remover aparece "Os
  arquivos selecionados também serão removidos da nuvem" ("…serão apagados permanentemente da
  nuvem e de todos os dispositivos conectados"), com **Alterar Seleção** / **Continuar** e
  "Não mostrar novamente nesta sessão" (vale até fechar o app) [E1][E15]. Itens só na nuvem não
  são removíveis (`scan.md` §6).
- **Destino: apagar de vez, não vai para o Lixo.** A tarefa usa `FilesRemovalTask` com
  `ConfigDependentFileRemover(FileRemover)` (o real chama `removeFileAndHandleLockAtPath:`, que
  destrava `uchg` antes); o módulo não importa o `MoveToTrashFileRemover` do CleaningCore [E16].
- **Ajudante privilegiado:** quando há permissão para isso, o removedor é embrulhado num
  `PrivilegedFileRemover`, que tenta pelo ajudante (root) o que o usuário não consegue apagar [E16].
- **Duração mínima:** `MinimumTotalDurationTasksProcessor` (a tela de progresso não pisca) [E16].
- **Fim:**
  - sucesso: "Remoção concluída!" / "Remoção bem-sucedida" + **OK**; se sobraram itens que dá para
    revisar, **Revisar Mais Itens** (`canReviewRemainingItems`);
  - falha: "A remoção falhou…" / "Não foi possível remover alguns arquivos. Verifique se nenhum
    app os estão usando e tente novamente." + **Tentar Novamente**;
  - **Registro de Remoção** com cada item e o resultado [E1][E16].
- Depois da remoção a árvore é atualizada (nós removidos saem; tamanhos dos pais diminuem)
  (inferência pelo `CleanQueueResultNodesUpdater`) [E16].

## 6. "Espaço Purgável" e "Limpar Espaço Purgável"
- Linha só na raiz de um volume interno (`scan.md` §4), com ícone próprio e botão de informação
  [E4]. Não tem caixa: não se remove pela Lupa.
- Tooltip: o purgável são arquivos que o macOS pode apagar quando falta espaço (caches, dados
  temporários, conteúdo baixável de novo); **"Limpar Espaço Purgável"** leva à ferramenta
  **Desempenho** (tarefa "Liberar Espaço Purgável"; ver
  `docs/re/specs/performance/maintenance-tasks.md` §3) [E1][E17].

## 7. "Pouco conteúdo para visualizar…"
- Tela própria (`SpaceLensEmptyScanResultsScreenCoordinator`): título, "Analise uma pasta com mais
  itens para pré-visualizar seu conteúdo." e **Recomeçar** [E1][E3].
- Quando: a pasta analisada não tem filhos para desenhar (vazia, ou só itens de 0 B)
  (inferência; condição exata não localizada).

## Para o CleanYourMac (forma proposta)

### "Outros itens" (regra nossa, determinística)
Como a regra do CleanMyMac não foi confirmada, usamos uma regra simples, testável e que reproduz
as três observações:
1. Ordenar os filhos por tamanho (decrescente; empate por nome).
2. Nível com **até 3 filhos**: mostrar todos (nada em "Outros").
3. Nível com **até 10 filhos com tamanho > 0**: mostrar todos os que têm tamanho; os de 0 B vão
   para "Outros".
4. Nos demais: mostrar os itens com `tamanho × 75 ≥ total da pasta` (≥ 1,33%), no máximo **12**;
   o resto vai para "Outros".
5. "Outros itens" só existe com 2 ou mais itens; com 1, ele aparece como item normal.
6. Esperado nesta máquina: raiz = 9 + Outros (0 KB) pela regra 3; `/Users` = 3 sem Outros pela
   regra 2; pasta pessoal = 7 + Outros (9,3 GB) pela regra 4 (corte 182,9 / 75 = 2,439 GB:
   `.cache` 2,44 GB fica, `Pictures` 2,42 GB vai para Outros).

> Nota: o corte da regra 4 cai entre dois itens quase iguais (`.cache` e `Pictures`), então a
> paridade na pasta pessoal é frágil (pequenas variações de tamanho trocam um pelo outro). A regra
> é nossa; trocar pela do CleanMyMac quando ela for confirmada.

### Mapa
- Circle packing próprio em SwiftUI `Canvas`, um nível, raio = `tamanho^p` com `p` escolhido por
  bisseção (como acima) para que todas as bolhas visíveis tenham diâmetro ≥ 12 pt; "Outros itens"
  é uma bolha.
- Clique duplo entra; voltar/avançar e caminho clicável; Quick Look com Espaço.

### Seleção e remoção
- Caixa por item; estados marcado/desmarcado/parcial; "Selecionar: Nenhum / Todos".
- **Remover = mover para o Lixo** (padrão do projeto desde a v0.2), com
  `FileManager.trashItem(at:resultingItemURL:)`; o que falhar por permissão vai ao ajudante
  (`trash`, com as validações da v0.2). **Nunca apagar de vez.** Ver divergências.
- **Nunca** remover item essencial (SIP, `SF_RESTRICTED`, `PathPolicy.isVital`, a pasta pessoal e
  as pastas vitais dela, a raiz do volume, `/System/Volumes`): sem caixa.
- **Pasta do sistema** (pasta-padrão do usuário ou do sistema): sem caixa no nível onde ela
  aparece; o conteúdo pode ser marcado.
- **Nuvem:** itens só na nuvem nunca removíveis; itens locais de nuvem pedem o alerta (com
  "não mostrar de novo nesta sessão"). Mover para o Lixo um item do iCloud Drive também o tira da
  nuvem, então o alerta é obrigatório.
- Plano de remoção igual ao do CleanMyMac (pasta inteira quando nada é poupado; senão desce).
- Registro com caminho, tamanho, destino no Lixo e resultado; "Tentar de novo" só com os que
  falharam.
- `CYM_DRY_RUN` simula tudo.

## requiresAdmin
- Análise: não.
- Remoção: não, salvo itens do sistema ou de outro usuário (ajudante, `trash`).

## Evidências
- **E1** — `re-notes/static/SpaceLensModule/localizable-pt-BR.json` (+ `en`): 33 chaves (intro,
  progresso, revisão, alerta de nuvem, conclusão, registro, purgável, estado vazio).
- **E2** — `re-notes/static/SpaceLensUI/localizable-pt-BR.json` (+ `en`): 19 chaves (indicador,
  tooltips, "Outros itens", item essencial, pasta do sistema, revisão).
- **E3** — strings de `SpaceLensModule`: `SpaceLensScanProgressViewModel`,
  `SpaceLensEmptyScanResultsScreenCoordinator`, `scan_progress_title`.
- **E4** — dumps de Acessibilidade `re-notes/ax/spacelens-20261022/{root,users,home}.txt`.
- **E5** — símbolos de `SpaceLensUI`: `LevelInfo.init(currentItem:children:otherItems:)`,
  `LevelInfo.otherItems`, `SmallerItemsSpaceLensViewModel`,
  `SpaceLensViewController.spaceLensListView(didChangeSmallerItemsSectionExpansionState:)`;
  campos `mainItems`, `smallerSection`, `otherItems`, `smallerItems`, `smallerItemsViewModel`.
- **E6** — strings de `SpaceLensModule`: "Reveal Other Items", "Hide Other Items",
  `_hasMoreItemsAvailable`.
- **E7** — strings e campos de `SpaceLensUI`: `PackedNode<BubblePackingLayoutItem>`,
  `minimumRenderingItemsSize`, `scalingFunction`, `power`, `Other-Items-Icon`,
  `Smaller Items_*`, `BubblesTooltipView`, `handleDoubleClick`, `handleBackgroundDoubleClick:`,
  `zoomingItem`, `checkmark*`, `selected`/`unselected`/`partiallySelected`.
- **E8** — Ghidra `re-notes/decomp/SpaceLensUI/FUN_000309d8.c` (a seção de itens menores só é
  criada se a lista de "outros" não for vazia) e `FUN_00028564.c`/`FUN_00041710.c` (a lista
  recebe o nível pronto); `re-notes/decomp/SpaceLensModule/FUN_0002e698.c` (o módulo monta o item
  atual somando tamanhos e folhas dos filhos e publica o `LevelInfo`).
- **E9** — `du -skl` dos 52 filhos de `~` (Library 67,3 GB; Projetos 65,4; .colima 14,6; .npm
  10,1; .claude 8,6; Downloads 2,59; .cache 2,44; Pictures 2,42; .local 2,02; .vscode 1,89;
  .codex 1,72; Documents 0,87…) e `ls -la /`.
- **E10** — Ghidra `re-notes/decomp/SpaceLensUI/FUN_0001aab0.c` (layout: bisseção de 10 passos do
  expoente, contagem de bolhas com diâmetro abaixo do mínimo, quadro nulo para as ocultas),
  `FUN_00002edc.c` / `FUN_00003e14.c` (círculo envolvente), chamadores `FUN_00017adc.c`
  (`BubblesCollectionView`, oculta bolhas sem quadro).
- **E11** — símbolos `SpaceLensListViewController.handleLeftArrowKeyDown/RightArrowKeyDown/SpacebarKeyDown(in:)`;
  `SpaceLensQuickLookController` e `QLPreviewPanel` no módulo; `activateFileViewerSelectingURLs:`
  na interface.
- **E12** — símbolos importados pelo módulo: `SpaceLensNavigationHistory.addToHistory`,
  `previousItem`, `nextItem`, `canGoBack`, `canGoForward`, `findItem(for:)`; strings "Click Back
  History", "Click Forward History".
- **E13** — classe `SpaceLensModuleSelectionOption` e campo `selectionOption` no módulo.
- **E14** — símbolos `SpaceLensDeletionPlanner.units(for:shouldSpare:)`,
  `SpaceLensDeletionPlanner.Unit(path:size:removableLeavesCount:)`; campos `wholesale`,
  `filtered` no `__swift5_reflstr` de `SpaceLensScanning`.
- **E15** — strings do módulo: "showing cloud removal alert", "Cloud item selected", "alert
  auto-confirmed, suppressed for this app session", "cancelled to change selection",
  `SpaceLensCloudAlertSuppressionStorage`.
- **E16** — `nm -m` de `SpaceLensModule`: importa `CleaningCore.FilesRemovalTask`,
  `ConfigDependentFileRemover(from:)`, `FileRemover(fileManager:)`,
  `PrivilegedFileRemover(remover:privilegedAgent:…)`, `MinimumTotalDurationTasksProcessor`,
  `CleanQueueResultNodesUpdater`, `CleanLogViewModel`; **não** importa `MoveToTrashFileRemover`;
  `SpaceLensModuleBuilder.init(performer: PrivilegedOperationsPerformerServiceType?, …)`;
  semântica do `FileRemover` em `docs/re/specs/apps/removal.md` (E7).
- **E17** — chave `spacelens_results_purgeable_space_tooltip_text` ("…Clique para limpá-lo na
  ferramenta Desempenho") e o tipo `RoutingServiceAPI.RouteDispatcherType` usado pelo módulo.

## Divergências conhecidas
- **Remover:** o CleanMyMac apaga de vez; nós movemos para o Lixo (decisão do projeto). O espaço só
  volta depois de esvaziar o Lixo; a tela de conclusão diz isso.
- **"Outros itens":** regra nossa (acima) até a do CleanMyMac ser confirmada.
- **Itens essenciais:** sem a base cifrada, alguns itens que o CleanMyMac trava (ex.: `/opt`)
  ficam só como "pasta do sistema" nossa (ou travados pela `PathPolicy`).

## Dúvidas em aberto
- Regra exata do "Outros itens" (teste sugerido para quem puder observar: analisar a mesma pasta
  com a janela em dois tamanhos e ver se o número de itens visíveis muda).
- Opções do menu "Selecionar:".
- Condição exata do estado "Pouco conteúdo para visualizar…".
- Valor de `minimumRenderingItemsSize`.
