# Tela de Resultados do módulo Aplicativos

Esta spec descreve a tela que aparece depois da análise do módulo Aplicativos:
cabeçalho, botão do Gerenciador, cartões (condição, ordem, botões, estados) e o
estado "nenhum app". Os textos aqui são paráfrases do **sentido**; os textos
finais da UI são escritos por nós. Os grupos citados estão em `updater.md`,
`installers.md`, `leftovers.md` e `removal.md`.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Reconhecimento AX de
2026-10-21 (`re-notes/ax/apps-start-*`, `apps-scanning-*`, `apps-results-*`,
`apps-results2-*`, `apps-manager*-*`) e análise estática de `ApplicationsModule`
e `ModuleCore` (strings, `Localizable.stringsdict`, reflexão Swift e Ghidra).
Nunca clicamos em nenhum botão de cartão no CleanMyMac.

## 1. Fluxo até os Resultados
- **Intro**: título do módulo, um subtítulo curto, as três categorias
  (Desinstalador, Atualizador, Sobras) e o botão Analisar [E2].
- **Análise**: título no sentido de "analisando os apps", subtítulo "buscando
  apps, atualizações e sobras" e um botão **Parar** na barra de baixo [E2].
- **Resultados**: aparecem quando a análise principal termina. Na barra lateral,
  o módulo ganha um indicador de "há resultados" [E1].

## 2. Cabeçalho
- Título do módulo e uma frase com o **número de apps encontrados**, no sentido de
  "encontramos N apps no Mac". N é a contagem do inventário do Desinstalador, a
  mesma do filtro "Todos os Aplicativos" (26 nesta máquina) [E1][E3][E12].
- A frase tem formas de singular e plural (1 app / N apps). A forma "zero"
  também mostra o número, mas na prática não é usada, porque com 0 apps entra o
  estado da seção 5 [E4][E12].
- Abaixo, o botão principal **Gerenciar Aplicativos**, que abre o Gerenciador de
  Aplicativos na seção **Desinstalador**, com o filtro **Todos os Aplicativos**
  (a primeira seção e o primeiro filtro; ver `apps-manager-*`) [E1][E3][E12].
- Na barra de cima, **Recomeçar**, com o mesmo comportamento da Limpeza
  (`../results-screen.md` §1.4): pede confirmação, descarta os resultados e volta
  para a Intro [E1].
- **Não há total em bytes** no cabeçalho (diferente da Limpeza) [E1].

## 3. Cartões

### 3.1 Montagem e ordem
O código monta a lista de cartões juntando quatro blocos, **nesta ordem** [E6][E7]:

1. bloco do **macOS**: o cartão de atualizações do sistema, se houver;
2. bloco do **Atualizador**: o cartão de atualizações de apps, se houver;
3. bloco do **Desinstalador**: o cartão "considere remover apps" e depois o de
   apps de 32 bits, cada um se houver;
4. bloco das **Sobras**: o cartão de sobras (ou o cartão de "buscando sobras",
   ver 3.4) e depois o de instaladores, cada um se houver.

Cada bloco devolve zero ou mais cartões; um cartão sem conteúdo não entra (o
construtor devolve "nada"). A ordem final, então, é:

| # | Cartão (nome nosso) | Condição para aparecer | Título (sentido) | Botões |
|---|---|---|---|---|
| 1 | **Atualizações do macOS** | o resultado do Atualizador tem pelo menos 1 item que é atualização do **sistema**. Só um cartão, montado a partir do primeiro item desse tipo [E8][E11] | fixo: "há atualizações do macOS" | **Ver a atualização** (primário) + **Revisar** |
| 2 | **Atualizações de Apps** | pelo menos 1 atualização de **app** passa pelo filtro do cartão (ver 3.3) [E8][E11] | "N atualizações de apps disponíveis" (plural) | **Atualizar** (primário) + **Revisar** |
| 3 | **Desinstalador** ("considere remover alguns apps") | pelo menos 1 app do inventário passa pelo filtro do cartão (ver 3.3) [E8][E11] | fixo, sem número nem tamanho | só **Revisar** |
| 4 | **Apps de 32 bits** | pelo menos 1 app marcado como 32 bits [E8][E11] | "N apps sem suporte encontrados" (plural) | **Desinstalar** (primário) + **Revisar** |
| 5 | **Sobras de Apps** | o grupo de sobras (`appLeftovers`) tem pelo menos 1 item; enquanto as sobras ainda carregam, entra o cartão de espera (3.4) [E7][E14] | "<tamanho> de sobras de apps encontradas" | **Remover** (primário) + **Revisar** |
| 6 | **Instaladores** | o grupo de instaladores (`appInstallers`) tem pelo menos 1 DMG [E7][E8] | "<tamanho> de arquivos de instalação encontrados" | só **Revisar** |

- **Observado nesta máquina**: cartões 5 (49,2 KB, Revisar + Remover), 3
  (Revisar) e 6 (187 MB, Revisar), nessa ordem na árvore de Acessibilidade [E1].
  A ordem dos dados é 3, 5, 6. A árvore de Acessibilidade de uma grade não segue,
  necessariamente, a ordem dos itens: o módulo tem três formatos de cartão (grande
  horizontal, grande vertical e padrão), escolhidos pelo layout [E5]. **Na v0.2
  vale a ordem dos dados** (a da tabela).
- Cada cartão tem: título, uma descrição curta (nossa), um ícone e os botões. Os
  cartões 5 e 6 mostram tamanho; os 2 e 4 mostram contagem; os 1 e 3 não mostram
  número [E4][E8][E9].
- Cada cartão guarda se já foi "revisado" (o clique em um botão marca o cartão),
  o que só serve para a aparência e para as métricas [E10].

### 3.2 O que cada botão faz
O cartão tem dois botões possíveis: o **primário** (ação direta) e o de
**Revisar**. As ações possíveis de um cartão são: revisar, processar, desbloquear
(versão paga), abrir um link e uma ação própria [E10].

| Cartão | Revisar abre o Gerenciador em… | Botão primário |
|---|---|---|
| 1 macOS | seção **Atualizador**, no item da atualização do sistema [E8] | ação própria do cartão. Inferência: abre a Atualização de Software nos Ajustes do Sistema, o mesmo destino do aviso do Atualizador para itens do sistema [E8][E15] |
| 2 Atualizações | seção **Atualizador**, numa lista própria com título "Atualizações de Apps" e a descrição da categoria Atualizador [E8] | **processa** o cartão: no CleanMyMac, instala as atualizações listadas no cartão sem passar pelo Gerenciador. Inferência (não clicamos) [E8][E10] |
| 3 Desinstalador | seção **Desinstalador**, filtro **Todos os Aplicativos** (o nó do cartão usa o nome e a descrição da categoria Desinstalador) [E8] | — |
| 4 32 bits | seção **Desinstalador**, numa lista própria com título "Aplicativos de 32 bits" e uma descrição sobre a arquitetura antiga [E8] | **processa** o cartão: desinstala os apps de 32 bits listados nele. Inferência [E8][E10] |
| 5 Sobras | seção **Sobras**, grupo **Arquivos de Sobras** [E8] | **processa** o cartão: remove as sobras do cartão sem passar pelo Gerenciador e vai para a tela de ação. Inferência [E8][E10] |
| 6 Instaladores | seção **Sobras**, grupo **Instaladores** [E8] | — |

- A ação direta usa os nós do cartão (o cartão é um nó com seus próprios
  "controles de seleção"), e não a seleção do Gerenciador [E10]. Ela passa pelas
  mesmas confirmações da ação feita no Gerenciador (apps abertos, Redefinir etc.;
  ver `removal.md`).
- **Instaladores e Desinstalador não têm ação direta**: os dois exigem revisão,
  coerente com nada vir marcado nesses grupos (`installers.md`, Recomendado).

### 3.3 Critério de cada cartão
- **Atualizações do macOS**: algum item do Atualizador é do tipo "atualização do
  sistema". No CleanMyMac, essa lista vem do servidor dele (`updater.md`); nesta
  máquina o cartão **não** apareceu, mesmo com 26.7.1 e 27.0.1 disponíveis no
  sistema [E1][E11].
- **Atualizações de Apps**: os filhos do nó do Atualizador passam por um filtro
  antes da contagem (uma propriedade booleana obtida de uma "capacidade" do nó,
  provavelmente "pode ser atualizado/selecionado por aqui"). Nesta máquina o
  Gerenciador mostrou 1 atualização (GarageBand, da App Store) e o cartão **não**
  apareceu [E1][E3][E11]. As duas explicações possíveis: o filtro exclui itens
  que o app não consegue instalar sozinho (o GarageBand é da App Store e da
  Apple), ou a checagem de atualizações ainda não tinha terminado quando a tela
  foi capturada. Ver "Incertezas".
- **Desinstalador**: há pelo menos 1 app que **não** tem uma certa marca
  booleana do modelo do app (provavelmente "protegido", isto é, apps de sistema
  que não podem ser removidos) [E11]. Na prática, aparece em qualquer Mac com um
  app removível.
- **Apps de 32 bits**: há pelo menos 1 app **com** a marca de 32 bits do modelo
  [E11]. O sentido dos textos é "apps antigos de 32 bits não funcionam neste
  sistema" [E4]. Critério nosso: o executável principal do app só tem fatias de
  32 bits (`i386` ou `ppc`), sem `x86_64` nem `arm64` (ver o teste `detects32Bit`
  do plano).
- **Sobras de Apps**: o grupo de sobras tem itens (`leftovers.md`).
- **Instaladores**: o grupo de instaladores tem itens (`installers.md`).
- **Apps Não Usados** (existe no binário, sem construtor): ver 3.6.

### 3.4 Sobras em segundo plano e o "Parar"
- O módulo tem um cartão de **espera** para as sobras: título no sentido de
  "buscando sobras de apps…" e um subtítulo que avisa que a busca continua em
  segundo plano e pode demorar. Ele é montado no lugar do cartão de sobras
  enquanto os arquivos das sobras ainda estão sendo carregados, e é **trocado**
  pelo cartão normal quando a carga termina (há um "substituidor de cartão de
  espera" e um ID do cartão de espera ativo) [E14].
- Durante a espera, a seção Sobras do Gerenciador mostra um aviso equivalente
  ("buscando em segundo plano") no lugar da lista [E14].
- **Observado**: nas duas capturas dos Resultados, feitas com 68 s de diferença,
  continua existindo na barra de baixo um elemento **Parar** (sem papel de
  Acessibilidade definido), o mesmo rótulo do botão da tela de análise. O cartão
  de sobras já estava no estado normal (49,2 KB) [E1][E2]. Interpretação mais
  provável: uma tarefa de fundo do módulo (carga de recursos das sobras ou a
  checagem de atualizações) ainda rodava, e o Parar a interrompe. **Não sabemos o
  que o CleanMyMac faz ao parar** (não clicamos).
- **Regra nossa (v0.2)**:
  - a busca de sobras roda em segundo plano depois que os Resultados aparecem;
  - enquanto ela roda, o cartão 5 fica no estado de espera, sem botões, e a barra
    mantém **Parar**;
  - ao terminar, o cartão de espera vira o cartão normal (ou some, se não houver
    sobras), e o Parar sai da barra;
  - ao clicar em Parar, só a busca de sobras é cancelada: o cartão de espera
    some, os outros cartões ficam, e a seção Sobras mostra que a busca foi
    interrompida e pode ser feita de novo com Recomeçar.

### 3.5 Estados dos cartões
- O tipo de estado do cartão tem **só dois valores: normal e concluído**. Não
  existe estado "parcial" nem "falha" no cartão [E10].
- No estado **concluído**, o título e a descrição trocam [E9]:

  | Cartão | Título concluído (sentido) | Descrição concluída |
  |---|---|---|
  | 2 Atualizações | "N atualizações instaladas" | os apps estão em dia |
  | 4 32 bits | "N apps sem suporte desinstalados" | o Mac ficou mais leve |
  | 5 Sobras | "<tamanho> de sobras removidas" | o Mac carrega menos peso |
  | 6 Instaladores | "<tamanho> de arquivos de instalação removidos" | aproveite o espaço |
  | 1 macOS, 3 Desinstalador | sem variante: os textos são fixos | — |

- Os cartões de instaladores e de sobras calculam o valor concluído a partir das
  mudanças feitas (há um "calculador" ligado ao cartão) [E5].
- **Regra nossa** para quando volta aos Resultados depois de uma ação (do cartão
  ou do Gerenciador):
  - todos os itens do cartão foram tratados → estado **concluído**, com o total
    tratado (bytes ou contagem) e sem botão primário (fica só Revisar);
  - parte dos itens ficou (falha, ou só uma parte estava marcada) → estado
    **normal**, recalculado com o que sobrou. É o nosso "parcial", sem texto
    próprio, como no CleanMyMac;
  - o cartão 3 não muda de estado; o cartão 1 também não (abrir os Ajustes não é
    uma ação concluída).

### 3.6 Cartão "Apps Não Usados" (no binário, não montado)
- Existem os textos completos do cartão: título com contagem ("N apps não usados
  encontrados"), descrição normal e concluída, título concluído ("N apps não
  usados desinstalados") e título/descrição para a lista no Gerenciador ("não
  usa há mais de seis meses") [E4].
- Mas **nenhum construtor de cartão usa esses textos** em 5.7.2: não existe um
  tipo de cartão "não usados" (os tipos são os seis da tabela), e os únicos usos
  encontrados dos textos da lista estão no registro de buscas/fluxos rápidos do
  módulo [E5][E13].
- **Observado**: o filtro Não Usados do Gerenciador tinha 1 app, e o cartão não
  apareceu [E1][E3]. Isso confirma que o cartão não é montado nesta versão.
- Critério (o mesmo do filtro, para quando o cartão for ligado): app aberto pela
  última vez há mais de seis meses (`inventory.md`, filtro Não Usados).
- **Na v0.2 o cartão não aparece**, por paridade. O `AppsTile.Kind` pode existir,
  mas `tiles(for:now:)` nunca o devolve.

## 4. Estados globais
- **Análise interrompida** (Parar na tela de análise): volta para a Intro, sem
  Resultados (plano, `stopReturnsToIntro`).
- **Recomeçar**: ver seção 2.

## 5. Estado "nenhum app"
- Quando o inventário tem **0 apps**, a tela mostra, no lugar do cabeçalho com
  contagem, um título no sentido de "não encontramos nenhum app neste Mac" e um
  subtítulo leve sugerindo instalar algum programa [E12].
- Nesse estado o código **não** monta o botão Gerenciar Aplicativos (o título do
  botão só é definido no outro ramo) [E12]. Sem cartões.
- Recomeçar continua (inferência, como na Limpeza).
- Não confundir com "nenhum cartão": com apps no inventário e nada de
  sobras/instaladores/atualizações, ainda aparecem o cabeçalho, o botão e, quase
  sempre, o cartão 3.

## requiresAdmin
- Tela de Resultados: não. As ações dos cartões seguem `removal.md` e
  `updater.md`.

## Evidências
- **E1**: observação AX `apps-results-2026-10-21T140341Z.txt` e
  `apps-results2-2026-10-21T140449Z.txt` (idênticas): Recomeçar; título do
  módulo; frase com 26 apps; botão Gerenciar Aplicativos; cartão de sobras
  (49,2 KB, Revisar + Remover), cartão do Desinstalador (Revisar), cartão de
  instaladores (187 MB, Revisar); indicador na barra lateral; elemento "Parar"
  sem papel na barra. Sem cartões de atualizações, 32 bits, não usados ou macOS.
- **E2**: observação AX `apps-start-2026-10-21T140216Z.txt` (Intro com três
  categorias e Analisar) e `apps-scanning-2026-10-21T140226Z.txt` (análise com
  indicador de progresso e botão Parar).
- **E3**: observação AX `apps-manager-2026-10-21T140501Z.txt`: Desinstalador com
  Todos os Aplicativos = 26, Não Usados = 1, Suspeitos = 0; e `updater.md` E10
  (Atualizador com 1 item, GarageBand, App Store).
- **E4**: `localizable-*.json` e `Localizable.stringsdict` de ApplicationsModule:
  chaves `tile_*` (`_title`, `_normal_description`, `_completion_title`,
  `_completed_description`, `_data_manager_title/_description`) para
  sobras, instaladores, atualizações, 32 bits, não usados, macOS e Desinstalador;
  botões `tile_review/remove/uninstall/update_button` e
  `tile_system_update_update_button_title`; `scan_results_header_title` (plural
  com zero, one e other), `scan_results_nothing_found_*` e
  `scan_results_open_data_manager_button`.
- **E5**: nomes de tipos em ApplicationsModule: `ApplicationsTilesMapper`,
  `UpdaterTilesMapper`, `UninstallerTilesMapper`, `LeftoversTilesMapper`,
  `SystemUpdateTileNodeRepresentation`, `UpdaterTileNodeRepresentation`,
  `AllApplicationsTileNodeRepresentation`,
  `ThirtyTwoBitApplicationsTileNodeRepresentation`,
  `LeftoversTileNodeRepresentation`,
  `UnusedDiskImagesTileNodeRepresentation(node:calculator:)`,
  `UninstallerChangesCalculator`, `LeftoversResourcesLoadingTileViewModel`,
  `LoadingTileReplacer`, `ApplicationsScanningLargeHorizontal/LargeVertical/StandardTileItemView`.
  Não há tipo de cartão para apps não usados.
- **E6**: função decompilada que monta a lista final (ApplicationsModule,
  `0x4d68c`): chama, na ordem, o construtor do cartão do sistema, o bloco do
  Atualizador, o bloco do Desinstalador e o bloco das Sobras, e concatena os
  resultados não vazios.
- **E7**: funções decompiladas dos blocos: Sobras (`0x4e388`: cartão de sobras ou
  de espera, depois instaladores), Desinstalador (`0x5242c`: "todos os apps",
  depois 32 bits; descarta os ausentes) e Atualizador (`0x54228`: um cartão).
- **E8**: funções decompiladas dos construtores de cartão (`0x54a48` macOS,
  `0x5430c` atualizações, `0x52550` Desinstalador, `0x52b5c` 32 bits, `0x4e45c`
  sobras, `0x4f208` instaladores). Cada uma devolve "nada" quando a lista do
  cartão está vazia, monta o nó que o Revisar abre (com título e descrição
  próprios, quando há) e define os botões: macOS = ver atualização + revisar;
  atualizações = atualizar + revisar; Desinstalador = revisar; 32 bits =
  desinstalar + revisar; sobras = remover + revisar; instaladores = revisar. O
  mapeamento das chamadas de texto para as chaves foi feito pela ordem dos casos
  do enum de textos (reflexão Swift) e conferido contra os botões observados (E1).
- **E9**: funções decompiladas que escolhem os textos por estado (`0x31204`,
  `0x3142c`, `0x5f85c`/`0x5f868`/`0x5f874`, `0x62cac`/`0x62cb8`/`0x62cc4`): estado
  igual a "concluído" → título e descrição de conclusão; qualquer outro → os
  normais. Textos fixos do Desinstalador (`0x5f698`/`0x5f6a8`) e do macOS
  (`0x62dc4`/`0x62dd4`).
- **E10**: reflexão Swift de ModuleCore: `TileState` = {normal, completed};
  `TileAction` = {review, process, unlock, link, customAction}; inicializador de
  `TileViewModel(state:title:description:icons:primaryButton:primaryButtonShouldMarkReviewed:secondaryButton:secondaryButtonShouldMarkReviewed:…)`,
  `wasReviewed`, `TileNodeType.selectionControlNodes`,
  `ScanningModuleMainFlowCoordinator.coordinatorDidRequestReviewOfTile(_:node:)`.
- **E11**: funções decompiladas dos filtros: Desinstalador (`0x60354`) mantém os
  apps em que uma propriedade booleana do modelo é falsa; 32 bits (`0x604ec`)
  mantém os apps em que a marca do modelo é verdadeira; atualizações (`0x5430c`)
  filtra os filhos do Atualizador por uma capacidade do nó; macOS (`0x54a48`)
  procura o primeiro filho do tipo sistema e só segue se a lista não for vazia.
- **E12**: função decompilada do modelo da tela de Resultados (`0x16920`): num
  ramo, título e subtítulo de "nenhum app"; no outro, a frase com a contagem
  (`0x17898`, texto com plural) e o título do botão Gerenciar Aplicativos.
- **E13**: busca nas chamadas de texto de ApplicationsModule (disassembly): nenhum
  uso do título/descrições do cartão de não usados; o texto da lista de não
  usados só aparece na função do registro de fluxos rápidos (`0xb934`), junto com
  as palavras-chave de busca.
- **E14**: função decompilada `0x79f98` (cartão de espera com os textos
  `tile_looking_for_leftovers_*`), chamada pelo construtor do cartão de sobras;
  `0x80980` (aviso `leftovers_bg_scan_*` usado no Gerenciador); strings
  `activeLoadingTileID`, `loadingTileReplacer`, `tilesUpdater`,
  `Leftovers Group With Resources Loading Placeholder` e
  `Leftovers resources loading completed`.
- **E15**: strings `x-apple.systempreferences:com.apple.preferences.softwareupdate`
  e `popover_system_update_*` (ver `updater.md` E8).

## Divergências conhecidas
- **Cartão de Atualizações de Apps (nosso Atualizador não instala).** No
  CleanMyMac, o primário Atualizar instala tudo do cartão. Na v0.2:
  - o cartão 2 tem **só Revisar**, que abre a seção Atualizador; não há
    Atualizar no cartão, porque cada fonte pede um destino diferente (App Store,
    o próprio app, o comando `brew` para copiar; ver `updater.md`, Botões);
  - a contagem do cartão é a das nossas atualizações de **apps** (App Store,
    Sparkle, Homebrew e as entradas de apps da Apple vindas do sistema, como o
    Safari). As entradas do macOS vão para o cartão 1;
  - o cartão não tem estado concluído na v0.2 (nada é instalado por nós). Ele só
    some depois de uma nova análise que já não encontra a atualização;
  - nesta máquina o nosso cartão **aparece** (GarageBand), e o do CleanMyMac não
    apareceu [E1].
- **Cartão do macOS.** O nosso usa as entradas do macOS de `updater.md` F4.
  Aparece se houver pelo menos 1 entrada que **não** seja de versão principal
  nova (`major`); só com a versão principal nova, não há cartão (a entrada fica
  na lista do Atualizador). O primário abre a Atualização de Software nos
  Ajustes; Revisar abre o Atualizador. Nesta máquina o nosso aparece (26.7.1), e o
  do CleanMyMac não.
- **Apps de 32 bits.** O primário Desinstalar passa pelas mesmas confirmações do
  Gerenciador e move para o Lixo (`removal.md`). Num Mac com Apple Silicon e macOS
  26, esperamos que o cartão quase nunca apareça.
- **Sobras.** O primário Remover usa todos os itens do grupo Arquivos de Sobras
  (nunca os Instaladores) e move para o Lixo, como no Gerenciador (`removal.md`).
  No CleanMyMac, apaga de vez.
- **Ordem**: seguimos a ordem dos dados (E6), não a da árvore de Acessibilidade.
- **Apps Não Usados**: não mostramos, por paridade (3.6).
- **Parar em segundo plano**: o comportamento depois de parar é nosso (3.4).

## Incertezas
1. **Por que o cartão de atualizações não apareceu** com o GarageBand na lista:
   filtro (o item não pode ser instalado pelo app) ou checagem ainda em
   andamento. Conferir numa nova captura passiva, depois de alguns minutos.
2. O que o **Parar** que fica na barra interrompe e o que acontece com os
   cartões depois.
3. A propriedade exata que o filtro do cartão 3 usa (supomos "protegido") e a
   que marca 32 bits.
4. O que o primário do cartão do macOS faz (supomos abrir os Ajustes).
5. Se a ação direta (Remover, Desinstalar, Atualizar) pede confirmação antes no
   CleanMyMac.
6. A posição visual dos cartões na grade (a árvore de Acessibilidade não dá
   coordenadas).

## Baseline observada
- Cabeçalho: 26 apps; botão Gerenciar Aplicativos; Recomeçar.
- Cartões: Sobras 49,2 KB [Revisar, Remover]; Desinstalador [Revisar];
  Instaladores 187 MB [Revisar].
- Gerenciador: Não Usados = 1 (sem cartão); Atualizador com 1 item (sem cartão).

## Checklist de testes
Testes de `AppsTile.tiles(for:now:)` com `AppsReport` falso:

1. Report com sobras (49 152 B), 26 apps removíveis e 1 DMG (187 MB) → cartões
   [Desinstalador, Sobras, Instaladores], nessa ordem; Sobras com Revisar +
   Remover, os outros dois só com Revisar.
2. Todas as condições verdadeiras → ordem [macOS, Atualizações, Desinstalador,
   32 bits, Sobras, Instaladores].
3. Report com 0 apps → estado "nenhum app": sem cartões e sem Gerenciar
   Aplicativos.
4. Só apps protegidos (de sistema) → sem o cartão Desinstalador; o cabeçalho
   ainda mostra a contagem.
5. 1 app só `i386` → cartão 32 bits com contagem 1 e os botões Desinstalar +
   Revisar; um app `x86_64` + `i386` → sem cartão.
6. App com última abertura há 7 meses → filtro Não Usados conta 1, e **nenhum**
   cartão de não usados aparece.
7. 1 atualização de app (App Store) → cartão 2 só com Revisar, contagem 1;
   Revisar abre a seção Atualizador.
8. Só a entrada macOS 27.0.1 (`major`) → sem cartão do macOS; 26.7.1 + 27.0.1 →
   um cartão do macOS.
9. Sobras ainda carregando → cartão de espera na posição 5, sem botões, e a barra
   com Parar; ao terminar com 0 sobras → o cartão some.
10. Parar durante a carga das sobras → cartão de espera removido, os outros
    cartões intactos.
11. Remover no cartão de sobras com 3 sobras e 1 DMG → o lote tem só as 3 sobras.
12. Depois de remover todas as sobras → cartão de sobras concluído, com o tamanho
    removido e só Revisar; com 1 falha → cartão normal com o que sobrou.
13. Cabeçalho: 1 app → singular; 26 → plural.
14. Gerenciar Aplicativos abre a seção Desinstalador, filtro Todos.
