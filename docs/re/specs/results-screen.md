# Tela de Resultados e Gerenciador de Limpeza

Esta spec descreve o comportamento das telas que vêm depois da análise:
Resultados (cartões), Gerenciador de Limpeza (revisão), Limpeza (progresso),
Concluído/Falha (com o Registro de Limpeza) e os alertas. Os textos aqui são
paráfrases do **sentido**. Os textos finais da UI são escritos por nós.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2, análise de 2026-10-20 (E1, E2, E3).

## 1. Tela de Resultados

### 1.1 Cabeçalho
- O título diz quanto de detritos o Mac tem: **o total encontrado em todas as
  categorias** (soma dos tamanhos de todos os grupos, recomendados ou não) (E1, E4).
- Há um botão principal para **revisar todos os detritos**, que abre o
  Gerenciador na primeira categoria (E1).
- Na barra, um botão **Recomeçar** (ver 1.4) (E1).

### 1.2 Cartões ("tiles")
Cada cartão mostra: o tamanho, um título com o sentido de "<X> de <tipo>
encontrados", uma descrição curta nossa, um ícone ou um conjunto de ícones, e
botões (E1, E5).

**Lista, na ordem em que o CleanMyMac monta os cartões** (E6):

| # | Cartão | Grupos que entram no cartão | Botões |
|---|---|---|---|
| 1 | Detritos do Sistema | os grupos da categoria `systemJunk` **que não têm cartão próprio**: `userCache`, `systemCache`, `userLogs`, `systemLogs`, `languageFiles`, `brokenLoginItems`, `brokenPreferences` | Revisar + **Limpar** |
| 2 | Acúmulos de IA | `aiAgentsJunk`, `localModels` | Revisar |
| 3 | Anexos do Mail | `mailAttachments` | Revisar |
| 4 | Lixos | `trash`, `mailTrash` | Revisar |
| 5 | Binários Extras | `universalBinaries` | Revisar |
| 6 | Detritos do Xcode | `xcodeJunk` | Revisar |
| 7 | Backups do iOS | `iosBackups` | Revisar |
| 8 | Usuários Apagados | `deletedUsers` | Revisar |
| 9 | Versões de Documentos | `documentVersions` | Revisar |

- **Condição para aparecer:** o tamanho total dos grupos do cartão é **maior que
  zero**. Um cartão de 0 bytes não aparece (E6).
- **O cartão Detritos do Sistema não inclui os grupos que têm cartão próprio**
  (Binários Universais, Xcode, Backups iOS, Usuários Apagados, Versões). Indícios
  (E1, E4): o cartão observado mostra os ícones dos 3 maiores grupos dele (Cache
  do Usuário, Cache do Sistema, Registros do Usuário), e **não** o de Binários
  Universais, que tinha 32 MB e era maior que Registros do Usuário (16,1 MB). O
  tamanho do cartão também fecha sem os binários.
- **Destaque:** o cartão 1 é o principal. Mostra o tamanho em evidência, os ícones
  dos até 3 maiores grupos com itens, e é o único com **Limpar** (E1). Os outros são
  cartões menores, com um ícone e só **Revisar**.
- **Botões observados:** Detritos do Sistema com Revisar e Limpar; Acúmulos de IA só
  com Revisar; Binários Extras só com Revisar (E1). Os cartões 3, 4 e 6 a 9 não
  foram observados. O código decide por cartão, a partir de uma propriedade do nó
  do cartão, se o botão Limpar aparece (E6). **Na v1, esses cartões têm só
  Revisar** (escolha segura; ver "Divergências").
- **Revisar** abre o Gerenciador já na categoria e no grupo do cartão (o primeiro
  grupo do cartão, se houver vários).
- **Limpar** (cartão 1) limpa **os itens recomendados** dos grupos do cartão, sem
  passar pelo Gerenciador, e vai direto para a tela de Limpeza (seção 3). Os itens
  não recomendados nunca entram. Isso é inferência (E6, E7): o nó do cartão aplica
  a "seleção inteligente" (marcar os itens auto-selecionáveis) aos grupos dele, e o
  Gerenciador parte sem nada marcado (seção 2.3). Por isso, o Limpar do cartão só
  pode usar a seleção recomendada.
- **Ordem de exibição (layout):** o cartão 1 fica em destaque (maior). Na árvore de
  Acessibilidade, o cartão de IA aparece antes do 1, o que indica uma grade em que o
  1 ocupa uma área grande e os outros vêm ao lado ou abaixo. Na v1: o cartão 1 grande
  à esquerda (ou no topo, em janela estreita) e os outros em grade, na ordem da tabela.
- **Depois de uma limpeza**, ao voltar para os Resultados, os cartões dos grupos
  limpos passam para o estado "concluído", com um título no sentido de
  "<X> de <tipo> removidos" e uma descrição positiva curta. Há variantes de texto
  "concluído" para cada um dos 9 cartões (E5).

### 1.3 Estado "nada encontrado"
Quando o total da análise é **0** (nenhum cartão), a tela mostra um estado de Mac
limpo, com uma mensagem no sentido de "o Mac está limpo, não há nada para
limpar", sem cartões e sem o botão de revisar. O botão Recomeçar continua (E5, E8).

### 1.4 Recomeçar
- Pede confirmação. O sentido é: "redefinir os resultados atuais e recomeçar? Os
  resultados não serão guardados e será preciso analisar de novo". Os botões são
  Cancelar e Recomeçar (E8).
- Ao confirmar, descarta o `ScanReport` e toda a seleção e volta para a tela
  Intro (a de antes da análise). Nada é limpo.
- Na tela Concluído, o mesmo botão volta para a Intro sem perguntar, porque não há
  resultado pendente para perder.

## 2. Gerenciador de Limpeza

### 2.1 Estrutura
Três colunas e um rodapé (E2, E3):
1. **Categorias**, sempre as 4 e sempre nesta ordem: Detritos do Sistema,
   Acúmulos de IA, Anexos do Mail, Lixos. Uma categoria aparece **mesmo vazia**.
2. **Grupos** da categoria, com título e descrição da categoria no topo, e uma
   linha por grupo: ícone, nome e tamanho total do grupo. O tamanho que aparece é
   sempre o **total do grupo**. A dica de ajuda do valor muda para "tamanho
   selecionado" quando há seleção (E9).
3. **Itens** do grupo, com o título e a descrição do grupo no topo, o menu
   **Selecionar** e uma linha por item: checkbox, ícone, nome, tamanho (total ou
   contagem dos itens incluídos) e um botão para mostrar os itens incluídos (filhos).
- No topo: o botão **Voltar** (volta para os Resultados), o título do
  Gerenciador, a **busca** e **Ordenar por**.
- No rodapé: a contagem de itens selecionados, o tamanho selecionado e o botão
  **Limpar**.

### 2.2 Ordem e visibilidade
- **Grupos:** do **maior para o menor** tamanho. Empates (inclusive os de 0 KB)
  ficam na ordem fixa da taxonomia. Observado: Cache do Usuário 2,8 GB → Cache do
  Sistema 765 MB → Binários Universais 32 MB → Registros do Usuário 16,1 MB →
  Registros do Sistema 10,1 MB → Idiomas 213 KB → Itens de Início Defeituosos 0 KB
  → Versões de Documentos 0 KB → Usuários Apagados 0 KB → Preferências Defeituosas
  0 KB → Backups iOS 0 KB (E2).
  - A ordem fixa de desempate na v1: `brokenLoginItems`, `documentVersions`,
    `deletedUsers`, `brokenPreferences`, `iosBackups` (a observada). Os demais grupos
    seguem a ordem da enumeração `GroupID`.
- **Grupos com 0 KB aparecem**, com "0 KB" e lista vazia (E2). Itens de Início
  Defeituosos aparece com 0 KB e 1 item ("Amphetamine"): itens sem tamanho contam
  como item.
  - **Exceção:** `xcodeJunk` **some** quando não tem itens. Não apareceu na
    baseline, embora o Xcode esteja instalado neste Mac (E2, E10).
- **Categoria sem nenhum item** (total 0 e nenhum item em todos os grupos): a coluna
  de grupos e a de itens dão lugar a um estado vazio, no sentido de "não há nada
  para limpar nesta área, tudo em ordem". O rodapé continua, com Limpar
  desabilitado. Foi o que se observou em Anexos do Mail e em Lixos (E3).
- **Itens:** pela ordenação atual (padrão: tamanho, do maior para o menor). Os
  filhos usam a mesma ordenação.

### 2.3 Seleção inicial
- Ao abrir o Gerenciador pelo botão de revisar todos ou por um Revisar de cartão,
  **nenhum item vem marcado**. O menu Selecionar de cada grupo mostra o estado
  "Nenhum" (E2).
- **Isso é o padrão, não estado salvo.** Os indícios:
  1. as 10 telas da baseline, em todas as categorias, estão sem nada marcado e com
     "Selecionar: Nenhum", inclusive grupos cujos itens são auto-selecionáveis;
  2. o domínio de preferências `com.macpaw.CleanMyMac-setapp` não tem nenhuma chave
     de seleção, ordenação ou limpeza; tem só chaves de serviço (E11);
  3. a seleção recomendada é uma **ação** do usuário: há a opção "seleção
     inteligente" no menu Selecionar e o comando de menu "aplicar seleção
     inteligente" (E9, E12).
- A seleção vive só durante a sessão de resultados. Ao voltar do Gerenciador para
  os Resultados depois de mudar a seleção, o app pede confirmação, com o sentido de
  "voltar e perder as mudanças de seleção?" (Cancelar / Voltar). Ao confirmar, a
  seleção volta a "Nenhum" (E8).
- A marca **recomendado** de cada item (`isRecommended`) aparece na linha do item
  mesmo sem estar marcado, como um selo ou indicador discreto nosso. É ela que
  define o que a seleção inteligente marca.

### 2.4 Menu "Selecionar" (por grupo)
Fica no topo da coluna de itens. O rótulo mostra o **estado** atual (E9, E12):

| Estado | Quando |
|---|---|
| Nenhum | nenhum item do grupo marcado |
| Tudo | todos os itens marcados |
| Inteligentemente | o conjunto marcado é **exatamente** o conjunto dos recomendados (e há ao menos um) |
| Manualmente | qualquer outra combinação |

Opções do menu na v1:
- **Seleção inteligente**: marca exatamente os recomendados do grupo e desmarca
  os outros. Fica desabilitada se o grupo não tem nenhum recomendado.
- **Selecionar tudo**.
- **Desmarcar tudo**.

O CleanMyMac tem ainda as opções Maiores, Menores, Mais Recentes e Mais Antigas
(E12). No módulo Limpeza só há uma opção extra própria, a de "mais antigos", usada
em Acúmulos de IA (E13). Ela fica para a spec `local-models.md` / `ai-agents-junk.md`.
Se essas specs não a pedirem, fica fora da v1.

Marcar e desmarcar propaga: pai ↔ filhos, com estado misto no pai. Marcar um item
que tem alerta de seleção (ver 4) dispara o alerta antes de marcar.

### 2.5 Ordenar por
- Padrão: **Tamanho**, do maior para o menor (E2).
- Opções na v1: **Tamanho** e **Nome**. Ao escolher de novo o critério atual, a
  direção alterna entre crescente e decrescente. Nome começa crescente (A→Z, com
  comparação localizada que ignora maiúsculas/minúsculas). Tamanho começa
  decrescente. Data e Contagem de Itens existem no CleanMyMac para outros módulos e
  ficam fora (E12).
- A ordenação vale para a coluna de itens e os filhos, e é a mesma para todos os
  grupos.

### 2.6 Busca
- Campo no topo, com dica no sentido de "buscar nos itens encontrados" (E2, E12).
- Filtra os itens (e os filhos) do **grupo mostrado** cujo nome contém o texto, sem
  diferenciar maiúsculas/minúsculas nem acentos. Um pai aparece se ele ou algum
  filho combina. A busca roda com um pequeno atraso depois da digitação (debounce,
  E14).
- Sem resultado: uma mensagem no sentido de "nada encontrado em <grupo>" (E12).
- A busca não muda a seleção. O rodapé conta a seleção inteira, inclusive o que
  está escondido pelo filtro.

### 2.7 Rodapé
- À esquerda: "<N> item/itens selecionado(s)" (plural pelo número) e o tamanho
  somado dos selecionados. Com nada marcado, a baseline mostrou "0 Item
  Selecionado" e "0 KB" (E2, E12).
- N conta os **itens folha selecionados com ação de remoção**, em todas as
  categorias. O tamanho soma os bytes deles, sem contar um mesmo caminho duas vezes.
- Botão **Limpar**: desabilitado com N = 0 (E2). Ao clicar, vai para a Limpeza
  (seção 3) com os itens selecionados.

### 2.8 Menu de contexto do item
O CleanMyMac oferece: mostrar no Finder, Visualização Rápida, marcar/desmarcar o
item, marcar/desmarcar todos os itens de um grupo e adicionar à lista de ignorados
(E12). Na v1: **Mostrar no Finder**, **Visualização Rápida** e marcar/desmarcar. A
lista de ignorados fica fora.

## 3. Limpeza

### 3.1 Progresso
- Tela própria, com animação. O título tem o sentido de "limpando <nome do
  item/grupo atual>…" (E5). Há uma barra ou indicador do total removido até agora.
- Botão **Parar**: pede confirmação no sentido de "parar todas as tarefas? Itens
  ficarão sem limpar", com os botões "continuar" e "parar" (E8). Ao confirmar, os
  itens que ainda não foram processados ficam com o estado **Parado**.
- Se houver itens que pedem admin (`GroupID.requiresAdmin` ou o fallback por
  permissão), a senha é pedida **uma vez** no início do lote com privilégio (design).
  Se o usuário cancelar, esses itens falham com o motivo "não autorizado" (E12).

### 3.2 Concluído (sucesso)
- Título no sentido de "limpeza concluída!" e o total removido, por tipo de
  categoria: um valor para detritos (Detritos do Sistema e Acúmulos de IA), um para
  Anexos do Mail e um para Lixos, cada um só se for maior que zero (E5).
- Botão **OK**, que volta para os Resultados com os cartões no estado "concluído"
  (1.2).

### 3.3 Falha (total ou parcial)
- Título no sentido de "a limpeza falhou…" e uma explicação: alguns itens não foram
  removidos; feche os apps relacionados e tente de novo (E5).
- Botões: **Ver Registro** (que vira **Ocultar Registro** quando aberto),
  **Revisar Itens Restantes** (volta ao Gerenciador com os itens que falharam ainda
  marcados) e **OK** (E12).

### 3.4 Registro de Limpeza
- Lista os itens processados que **não** saíram limpos, cada um com o estado (E12):
  - **Falhou**: com o erro;
  - **Parcial**: o item foi limpo em parte (ex.: alguns filhos falharam);
  - **Parado**: não foi limpo porque o usuário apertou Parar.
- Ao clicar num item, abre um painel com a lista de erros, cada um com o motivo
  (ex.: sem permissão do macOS; o usuário não autorizou; motivo desconhecido; app da
  App Store que não pode ser removido, com "Mostrar no Finder"), e um botão para
  **copiar** os erros para a área de transferência (E12).
- O registro também é gravado em disco (design: "toda limpeza gera um registro
  local"), com data, itens removidos, bytes e falhas.

## 4. Alertas de seleção
São alertas que aparecem **ao marcar** um item, não na hora de limpar. Se o usuário
cancelar, o item fica desmarcado (E15).
- **Backup iOS mais recente** (`iosBackups`): quando a seleção inclui o backup mais
  recente de um dispositivo (o que tem o selo "mais recente"). O sentido: "ao remover
  os backups mais recentes, não será possível restaurar esses dispositivos ao estado
  atual". Os botões são Cancelar e "remover mesmo assim" (E5). Os detalhes estão em
  `ios-backups.md`.
- **Modelos locais** (`localModels`): ao marcar modelos locais. O sentido: "os
  modelos ainda podem estar em uso nos projetos; removê-los pode causar erros até
  baixá-los de novo". Os botões são Cancelar e Continuar (E5). Os detalhes estão em
  `local-models.md`.
- A seleção inteligente e o Selecionar tudo também disparam o alerta quando o
  resultado inclui esses itens. Um alerta por ação, não um por item.

## 5. Outros
- **Análise:** o botão Parar pede confirmação, no sentido de "parar a análise? O
  resultado ficará incompleto" (E8). Ao parar, os Resultados mostram o que já foi
  achado.
- **Imagens de disco não usadas** (`UnusedDiskImagesScanning`): **não** alimentam
  nenhum grupo da Limpeza. O framework é usado pelo módulo Aplicativos, não pelo
  módulo de Limpeza (E16). **Fica fora da v1** e fica registrado para o módulo
  Aplicativos.
- O alerta de "todas as análises desativadas nos Ajustes" e a propaganda da limpeza
  de e-mail ficam fora da v1, porque não temos ajustes por grupo nem esse módulo.

## requiresAdmin
Não se aplica a esta tela. Ela só agrega os grupos.

## Evidências
- **E1**: observação `re-notes/ax/test-2026-10-20T175126Z.txt` (Resultados): o
  título com 4,5 GB, o botão de revisar todos, Recomeçar, o cartão de IA (824 MB,
  Revisar), o cartão Detritos do Sistema (3,6 GB, 3 ícones: cache do usuário, cache
  do sistema e registros do usuário, Revisar e Limpar) e o cartão de binários extras
  (32 MB, Revisar).
- **E2**: observação `re-notes/ax/review-all-2026-10-20T175643Z.txt` e
  `baseline-20261020-1457/*/*.txt`: a ordem dos grupos por tamanho, os grupos de
  0 KB presentes, o Xcode ausente, todos os checkboxes com `checked=0`,
  "Selecionar: Nenhum", "Ordenar por: Tamanho", "0 Item Selecionado / 0 KB" e
  Limpar desabilitado.
- **E3**: observação `baseline-20261020-1457/Anexos do Mail/_category.txt` e
  `Lixos/_category.txt`: as 4 categorias na barra lateral e o estado vazio da
  categoria, sem grupos.
- **E4**: conta com os tamanhos observados. Os grupos sem os binários somam
  ≈ 3,59 GB, o que bate com o cartão de 3,6 GB. Somando os binários e a IA, chega-se
  a ≈ 4,45 GB, o que bate com o cabeçalho de 4,5 GB, dado o arredondamento.
- **E5**: textos `re-notes/static/JunkCleanupModule/localizable-pt-BR.json` e
  `localizable-en.json`: as chaves `tiles_*_normal_*` e `tiles_*_completed_*` dos 9
  cartões, `tiles_action_review/clean`, `scan_results_*`, `cleanup_in_progress_title`,
  `cleanup_complete_*`, `cleanup_view_log_title`, os alertas de backup iOS e de
  modelos locais.
- **E6**: pseudocódigo da função do JunkCleanupModule que monta a lista de cartões
  (chama nove montadores em sequência) e dos montadores de cartão. Cada montador só
  cria o cartão quando o tamanho é maior que zero e consulta uma propriedade do nó do
  cartão antes de acrescentar ações. Os nomes analíticos dos cartões são
  "System Junk Tile", "AI Clutter Tile", "Mail Attachments Tile",
  "Trash Bins Tile", "Universal Binaries Tile", "Xcode Junk Tile",
  "iOS Backups Tile", "Deleted Users Tile" e "Documents Versions Tile".
- **E7**: os símbolos `JunkCleanupAutoSelectableStrategy` (JunkCleanupModule) e
  `SmartSelectionControlNodeType.smartSelect()` / `containsAutoSelectedValues`
  (ModuleCore), e o tipo `JunkCleanupTileNode`.
- **E8**: textos do ModuleCore (`ModuleCore.framework/…/pt-BR.lproj/Localizable.strings`):
  as chaves `alert_start_over_*`, `alert_back_*`, `alert_stop_clean_*`,
  `alert_stop_scan_*`, `no_data_description` e `navigation_back_button_scan_results`.
- **E9**: textos do ModuleCore: `group_cell_subtitle_tooltip`,
  `group_cell_selectedValue_tooltip`, `select_state_title_*` e
  `menu_item_apply_smart_selection`.
- **E10**: leitura do disco: `/Applications/Xcode.app` e `~/Library/Developer/Xcode`
  existem.
- **E11**: `defaults read com.macpaw.CleanMyMac-setapp` (somente leitura): só chaves
  de serviço (`FRService…`, `MenuAppEnabled`, `STP_*`, …), nenhuma de seleção ou
  ordenação.
- **E12**: textos do ModuleCore: `select_option_title_*`, `sort_by_*`,
  `sort_ascending/descending`, `search_control_icon_tooltip`, `search_nothing_found`,
  o plural `selected_items_count`, `cleanup_complete_*_button_title`,
  `cleanup_items_*`, `error_description_*` e as ações de contexto (`Reveal_In_Finder_Title`,
  `QuickLook_Action_Tile_Format`, `Select_*`, `Ignore_Action_Tile_Format`).
- **E13**: as strings `AIClutterOldestSelectionControlOption` e
  `AIClutterOldestSelectionControlNodeType` (JunkCleanupModule).
- **E14**: a string `init(rootNode:ignoreUndoManager:moduleConfiguration:analytics:lockedFunctionalityPerformer:selectionConfirmationPresenter:searchScheduler:searchDebounce:)`
  (JunkCleanupModule).
- **E15**: os símbolos `MobileBackupsModel.selectionConfirmation`,
  `MobileBackupsGroupModel.selectionConfirmation` e
  `JunkCleanupRootNode : ModuleCore.SelectionConfirmable` (JunkCleanupModule): a
  confirmação é ligada à seleção.
- **E16**: `otool -L`: o `UnusedDiskImagesScanning` é ligado só pelo
  `ApplicationsModule` e pelo `ApplicationsModuleDomain`, não pelo JunkCleanupModule.
  As strings e os símbolos do JunkCleanupModule não mencionam imagens de disco.

## Divergências conhecidas
- **Limpar só no cartão Detritos do Sistema.** Os cartões não observados (Mail,
  Lixos, Xcode, iOS, Usuários Apagados, Versões) ficam só com Revisar. Se uma
  observação futura mostrar Limpar neles, basta ligar a mesma ação (limpar os
  recomendados do cartão).
- O que o Limpar do cartão limpa (só os recomendados) é inferência, não observação.
  Não clicamos em Limpar no CleanMyMac.
- A posição dos cartões na grade é aproximada (a árvore de Acessibilidade não dá
  coordenadas).
- Ficam fora da v1: a lista de ignorados, as dicas inteligentes por item (o ícone
  de "informações inteligentes" ao lado de cada item, E2), as opções de seleção
  Maiores/Menores/Recentes/Antigas, as ordenações por Data e por Contagem, a
  propaganda da limpeza de e-mail e o alerta de análises desativadas.

## Baseline observada
- Resultados: cabeçalho de 4,5 GB. Cartões: Acúmulos de IA 824 MB [Revisar];
  Detritos do Sistema 3,6 GB [Revisar, Limpar], com os ícones de cache do usuário,
  cache do sistema e registros do usuário; Binários Extras 32 MB [Revisar].
- Gerenciador, Detritos do Sistema: Cache do Usuário 2,8 GB; Cache do Sistema
  765 MB; Binários Universais 32 MB; Registros do Usuário 16,1 MB; Registros do
  Sistema 10,1 MB; Arquivos de Idioma 213 KB; Itens de Início Defeituosos 0 KB (1
  item); Versões de Documentos, Usuários Apagados, Preferências Defeituosas e Backups
  iOS com 0 KB (0 itens). Detritos do Xcode não apareceu.
- Acúmulos de IA: Detritos de IA 824 MB (Claude Code 560 MB, Claude 222 MB, Codex
  37,7 MB, OpenCode 4,5 MB); Modelos locais 0 KB.
- Anexos do Mail e Lixos: estado vazio.
- Em todas as telas: nada marcado, "Selecionar: Nenhum", "Ordenar por: Tamanho",
  rodapé "0 Item Selecionado / 0 KB" e Limpar desabilitado.

## Checklist de testes
Testes de `CleanupFlowModel` e `SelectionModel` com `ScanReport` falso.

1. Report com `userCache` = 2,8 GB e `universalBinaries` = 32 MB: os cartões são
   [Detritos do Sistema (2,8 GB), Binários Extras (32 MB)], nessa ordem. O cartão 1
   não soma os 32 MB. O cabeçalho mostra 2,832 GB.
2. Report só com `aiAgentsJunk` > 0: um único cartão, Acúmulos de IA, só com Revisar.
3. Report com tudo zero: o estado "nada encontrado", sem cartões.
4. `trash` = 0 e `mailTrash` = 0: não há cartão de Lixos. Com `mailTrash` > 0, o
   cartão aparece.
5. Limpar no cartão 1, com 3 itens de `userCache` (2 recomendados) e 1 de
   `systemLogs` não recomendado: o lote de limpeza tem exatamente os 2 recomendados.
6. Limpar no cartão 1 nunca inclui itens de `universalBinaries`, `iosBackups`,
   `xcodeJunk`, `deletedUsers` ou `documentVersions`.
7. Abrir o Gerenciador: todos os itens desmarcados, o estado de cada grupo é
   "Nenhum" e o rodapé mostra 0 itens, 0 bytes e Limpar desabilitado.
8. Seleção inteligente num grupo com 2 de 5 recomendados: 2 marcados, estado
   "Inteligentemente". Desmarcar um deles: "Manualmente". Selecionar tudo: "Tudo".
   Desmarcar tudo: "Nenhum".
9. Seleção inteligente num grupo sem recomendados: a opção fica desabilitada.
10. Ordem dos grupos: tamanhos [0, 16, 2800, 0, 765] → por tamanho, decrescente,
    com os de 0 na ordem fixa.
11. `xcodeJunk` sem itens: não aparece na coluna de grupos. `deletedUsers` sem itens:
    aparece com 0 KB.
12. Categoria `mailAttachments` sem itens: o estado vazio da categoria.
13. Ordenar por Nome: A→Z. Clicar de novo: Z→A. Ordenar por Tamanho: maior primeiro.
14. Busca "goo" no grupo `userCache` com "Google" e "Homebrew": só aparece "Google".
    A seleção de "Homebrew" continua contando no rodapé.
15. Rodapé: 1 item selecionado → singular; 2 → plural. O tamanho é a soma, sem contar
    duas vezes um URL repetido.
16. Recomeçar com resultados: pede confirmação. Cancelar mantém tudo; confirmar
    volta para a Intro e zera o report e a seleção.
17. Voltar do Gerenciador depois de mudar a seleção: pede confirmação. Ao confirmar,
    a seleção volta a vazia.
18. Marcar o backup iOS "mais recente": o alerta aparece. Cancelar → continua
    desmarcado. Confirmar → marcado.
19. Selecionar tudo em `localModels`: um único alerta.
20. Limpeza com 1 falha e 1 parado: a tela de falha, e o registro lista os dois com
    os estados "Falhou" e "Parado".
21. Limpeza só com sucesso: a tela de concluído, com o total por tipo (detritos,
    Mail, Lixos), mostrando só os valores maiores que zero.
