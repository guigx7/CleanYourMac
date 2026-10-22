# Tela de Resultados do módulo Desempenho

Esta spec descreve a tela que aparece depois da análise do Desempenho: cabeçalho,
botão do Gerenciador, cartões (condição, ordem, botões, estados) e o estado "não
há tarefas recomendadas". Os textos aqui são paráfrases do **sentido** (as
chaves de localização são citadas como referência técnica); os textos finais da
UI são nossos. Cada afirmação está marcada como **EVIDÊNCIA** (fonte entre
colchetes) ou **INFERÊNCIA**. As seções citadas estão em `login-items.md`,
`background-items.md` e na spec de tarefas de manutenção desta pasta.

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83). Árvore de Acessibilidade de
2026-10-22 (`re-notes/ax/perf-baseline-20261022-0228/results.txt`), baseline
`docs/re/parity/perf-baseline-2026-10-22.json` e análise estática de
`PerformanceModule` e `ModuleCore` (strings, `Localizable.stringsdict`, Ghidra e
`otool`). Nunca clicamos em nenhum botão de cartão no CleanMyMac.

## 1. Cabeçalho
- **EVIDÊNCIA** — título do módulo ("Desempenho") e, abaixo, uma frase em duas
  linhas no sentido de "aplique as recomendações selecionadas ou rode tarefas
  de manutenção à mão" (`scan_results_header_title`) [E1][E2].
- **EVIDÊNCIA** — botão principal **Ver Todas as Tarefas**
  (`scan_results_open_data_manager_button`), que abre o **Gerenciador de
  Desempenho** [E1][E3].
- **EVIDÊNCIA** — o título, o subtítulo e o botão dependem de um único sinal
  "há resultados" [E3]:

  | Sinal | Título | Subtítulo | Botão |
  |---|---|---|---|
  | há resultados | `scan_results_header_title` | nenhum | Ver Todas as Tarefas |
  | não há | `scan_results_nothing_found_title` ("não há tarefas recomendadas") | `scan_results_nothing_found_subtitle` ("o Mac está em ótima forma") | **Recomeçar** (texto comum do ModuleCore, `start_over_button`) |

- Na barra de cima, **Recomeçar**, como nos outros módulos (pede confirmação,
  descarta os resultados e volta à Intro; ver `../results-screen.md` §1.4) [E1].
- Não há total em bytes no cabeçalho [E1].

## 2. Cartões

### 2.1 Montagem e ordem
- **EVIDÊNCIA** — o mapeador dos cartões junta três blocos, **nesta ordem** [E4]:
  1. bloco de **manutenção**, com até três cartões, nesta ordem:
     **Liberar RAM**, **Manutenção semanal** (o "coquetel" de tarefas) e
     **Diminuir Capturas do Time Machine**;
  2. bloco de **Itens de Início** (um cartão);
  3. bloco de **Itens em Segundo Plano** (um cartão).
- Cada construtor devolve "nada" quando o cartão não se aplica, e os "nadas"
  são descartados [E4].
- **Ordem dos dados**: Liberar RAM → Manutenção semanal → Capturas do Time
  Machine → Itens de Início → Itens em Segundo Plano.
- **Observado nesta máquina** (árvore AX): Itens de Início (4) → Manutenção
  semanal (5) → Itens em Segundo Plano (9) [E1]. A ordem dos dados seria
  Manutenção → Início → Segundo Plano. Como no módulo Aplicativos
  (`../apps/results-screen.md` §3.1), a árvore AX de uma grade com cartão
  grande não segue necessariamente a ordem dos dados: o cartão de manutenção é o
  grande (3 ícones e 2 botões). **INFERÊNCIA**: o layout põe o cartão grande em
  destaque e os outros ao lado. **Na v0.3 vale a ordem dos dados**, com o
  cartão de manutenção como destaque.

### 2.2 Tabela dos cartões

| # | Cartão | Condição para aparecer | Título (sentido; chave) | Ícone | Botões |
|---|---|---|---|---|---|
| 1 | **Liberar RAM** | a lista de tarefas de manutenção da análise contém a tarefa `freeUpRAM` [E5] | "Libere a RAM" (`tile_free_up_ram_title`) | imagem própria da tarefa (`maintenance-tasks_free-up-ram`) [E5] | um botão: **Liberar** (texto comum do ModuleCore `tile_action_free_up_ram_title`) [E5][E6] |
| 2 | **Manutenção semanal** | há pelo menos 1 tarefa de manutenção depois do filtro de 2.3 [E7] | "N tarefas de manutenção recomendadas" (`tile_weekly_maintenance_cocktail_title`, plural) | **ícones dinâmicos** das tarefas (2.4) [E7] | **Executar Tarefas** (`tile_run_tasks_button`, primário) + **Revisar** (`tile_review_button`) [E7] |
| 3 | **Diminuir Capturas do Time Machine** | a lista de tarefas contém `thinLocalSnapshots` [E8] | "Diminua as capturas do Time Machine" (`tile_thin_local_snapshots_title`) | imagem própria (`thin_local_snapshots`) [E8] | **Executar Tarefas** (`tile_run_tasks_button`) + **Saiba Mais…** (texto comum do ModuleCore `tile_action_learnMore_title`) [E8][E6] |
| 4 | **Itens de Início** | a seção Itens de Início tem pelo menos 1 item (**INFERÊNCIA**: construtor devolve "nada" com 0) [E9] | "Você tem N itens de início" (`tile_review_login_items_title`, plural) | ícones dinâmicos dos apps [E9] | só **Revisar** [E9] |
| 5 | **Itens em Segundo Plano** | a seção tem pelo menos 1 item (**INFERÊNCIA**, idem) [E10] | "N itens em segundo plano encontrados" (`tile_review_background_items_title`, plural) | ícone fixo "launch agents category" [E1][E10] | só **Revisar** [E10] |

- Descrições no estado normal (sentido): 1 "abra espaço na memória"; 2 "a rotina
  semanal está pronta, rode estas tarefas"; 3 "reduza o tamanho dos backups
  locais sem desligar os backups"; 4 "revise os apps abertos ao ligar o Mac";
  5 "revise os processos em segundo plano com permissão de rodar" [E2].
- **Observado nesta máquina**: cartões 4 (4 itens, Revisar), 2 (5 tarefas,
  Revisar + Executar Tarefas, 3 ícones) e 5 (9 itens, Revisar). Os cartões 1 e 3
  não apareceram porque as tarefas `freeUpRAM` e `thinLocalSnapshots` não
  estavam na lista (a seção de manutenção mostrou só 5 tarefas) [E1][E11].

### 2.3 Quais tarefas entram no cartão de manutenção
- **EVIDÊNCIA** — o construtor percorre as tarefas da seção de manutenção e
  monta uma lista de exclusão [E7]:
  - sempre exclui `freeUpRAM` (ela tem cartão próprio);
  - se uma condição da configuração do mapeador for falsa, exclui também
    `speedUpMail`. **INFERÊNCIA**: a condição é o acesso total ao disco (é o que
    o Acelerar o Mail exige; o módulo tem textos de "dar acesso total ao disco"
    para essa tarefa). Nesta máquina o acesso existe e o Acelerar o Mail entrou.
- **EVIDÊNCIA** — `thinLocalSnapshots` **não** está na lista de exclusão do
  cartão de manutenção [E7]. **INFERÊNCIA**: quando houver capturas, a tarefa
  pode contar nos dois cartões (2 e 3). Não foi observado.
- N = quantidade de tarefas que sobraram. Nesta máquina N = 5 = todas as
  tarefas da seção [E1][E11].
- A ordem dos identificadores de tarefa no código é: `freeUpRAM`,
  `periodicScripts`, `flushDNSCache`, `speedUpMail`, `repairDiskPermissions`,
  `reindexSpotlight`, `thinLocalSnapshots`, `launchServicesLoginItems`,
  `launchAgents`, `freeUpPurgeableSpace` [E12].

### 2.4 Ícones do cartão de manutenção
- **EVIDÊNCIA** — os ícones vêm de `TileDynamicIcons.sorted(from:)` sobre o nó das
  tarefas do cartão: ícones das tarefas, na ordem de ordenação do nó (por
  **nome**) [E7][E13].
- **Observado**: **3 ícones**, das três primeiras tarefas por nome em pt-BR:
  Acelerar o Mail, Esvaziar Cache do DNS, Liberar Espaço Purgável (a seção tinha
  5 tarefas: + Reindexar o Spotlight e Reparar Permissões do Disco) [E1].
- **INFERÊNCIA**: o limite é 3 ícones (igual ao cartão da Limpeza,
  `../results-screen.md`). Com menos de 3 tarefas, mostra só as que houver.
- O cartão de Itens de Início usa a mesma função (ícones dos apps, por nome);
  a árvore AX não expõe essas imagens [E9][E1].

## 3. O que cada botão faz

| Botão | Ação |
|---|---|
| **Ver Todas as Tarefas** (cabeçalho) | abre o Gerenciador de Desempenho; **INFERÊNCIA**: na primeira seção, **Tarefas de Manutenção** (as seções são: Tarefas de Manutenção, Itens de Início, Itens em Segundo Plano) [E3][E11] |
| **Revisar** (cartão 2) | abre o Gerenciador na seção **Tarefas de Manutenção** [E7][E13] |
| **Revisar** (cartão 4) | abre o Gerenciador na seção **Itens de Início** [E9][E13] |
| **Revisar** (cartão 5) | abre o Gerenciador na seção **Itens em Segundo Plano** [E10][E13] |
| **Executar Tarefas** (cartão 2) | **processa** o cartão: roda as tarefas do cartão (as N de 2.3) sem passar pelo Gerenciador e vai para a tela de execução/conclusão. **INFERÊNCIA** (não clicamos), pela ação "processar" do ModuleCore [E7][E13] |
| **Liberar** (cartão 1) | processa o cartão: roda só `freeUpRAM`. **INFERÊNCIA** [E5] |
| **Executar Tarefas** (cartão 3) | processa o cartão: roda `thinLocalSnapshots`. **INFERÊNCIA** [E8] |
| **Saiba Mais…** (cartão 3) | abre um link explicativo. **INFERÊNCIA** (ação "abrir link" do ModuleCore) [E6][E13] |

- **INFERÊNCIA** — a ação direta usa os nós do próprio cartão (não a seleção do
  Gerenciador), como nos outros módulos (`../apps/results-screen.md` §3.2).
- Itens de Início e Itens em Segundo Plano **não têm ação direta**: nada vem
  marcado nessas seções, então exigem revisão (`login-items.md`,
  `background-items.md`).

## 4. Estados dos cartões
- **EVIDÊNCIA** — o cartão tem dois estados: **normal** e **concluído**
  (`TileNodeRepresentation` com `markAsCompleted()` e
  `didUpdateAfterCleanup`) [E13].
- No estado concluído, título e descrição trocam [E2]:

  | Cartão | Título concluído (sentido; chave) | Descrição concluída (sentido) |
  |---|---|---|
  | 1 Liberar RAM | "RAM liberada" (`tile_free_up_ram_completed_title`) | o Mac está pronto para mais (`tile_free_up_ram_completed_description`) |
  | 2 Manutenção | "N tarefas de manutenção concluídas" (`tile_weekly_maintenance_cocktail_completion_title`, plural) | o Mac está em forma melhor (`tile_weekly_maintenance_cocktail_completed_description`) |
  | 3 Capturas | "capturas do Time Machine diminuídas" (`tile_thin_local_snapshots_completed_title`) | aproveite o espaço livre (`tile_thin_local_snapshots_completed_description`) |
  | 4 Itens de Início | "N itens de início removidos" (`tile_review_login_items_completion_title`, plural) | o Mac vai abrir menos coisas no próximo início (`tile_review_login_items_completed_description`) |
  | 5 Segundo Plano | "N itens em segundo plano removidos" (`tile_review_background_items_completion_title`, plural) | o Mac tem menos itens desnecessários rodando (`tile_review_background_items_completed_description`) |

- **Regra nossa** ao voltar aos Resultados depois de uma ação (do cartão ou do
  Gerenciador):
  - todas as tarefas/itens do cartão tratados → **concluído**, com N = quantos
    foram tratados, sem botão primário (fica só Revisar, quando houver);
  - parte ficou (falha ou seleção parcial) → **normal**, recalculado com o que
    sobrou;
  - nos cartões 4 e 5, "tratado" inclui **Desativar** (extensão nossa); o título
    concluído fala em "removidos ou desativados".

## 5. Estado "não há tarefas recomendadas"
- **EVIDÊNCIA** — quando o sinal "há resultados" é falso: título
  `scan_results_nothing_found_title`, subtítulo
  `scan_results_nothing_found_subtitle` e o botão do cabeçalho vira
  **Recomeçar** (não há Ver Todas as Tarefas) [E3]. Sem cartões.
- **INFERÊNCIA** — "há resultados" = há pelo menos 1 cartão (alguma tarefa
  aplicável, algum item de início ou algum item em segundo plano). Na nossa
  implementação: sem cartões ⇒ este estado.

## 6. Textos auxiliares do fluxo (referência)
- Títulos das seções do Gerenciador e frases de cabeçalho de cada seção:
  `maintenance_tasks_category_*`, `login_items_category_*`,
  `background_items_category_*` [E2].
- Telas de ação: "executando tarefas de manutenção…", "removendo itens de
  início…", "removendo itens em segundo plano…" e as telas de sucesso/falha
  com contagem (`cleanup_complete_*`) [E2].

## Evidências
- **E1**: AX `re-notes/ax/perf-baseline-20261022-0228/results.txt` (cabeçalho, Ver Todas as Tarefas, três cartões com seus títulos, descrições, botões e imagens: `maintenance tasks speed up mai`, `maintenance tasks flush DNS ca`, `maintenance tasks purgeable sp`, `launch agents category`).
- **E2**: `re-notes/static/PerformanceModule/localizable-pt-BR.json` / `localizable-en.json` e `PerformanceModule.framework/.../pt-BR.lproj/Localizable.stringsdict` (chaves `tile_*`, `scan_results_*`, `*_completion_title`).
- **E3**: Ghidra de `PerformanceModule`: `FUN_000322a8.c` (subtítulo: `scan_results_nothing_found_subtitle` ou nenhum) e `FUN_00032370.c` (botão: `scan_results_open_data_manager_button` ou o texto comum `start_over_button` do ModuleCore); `otool` em 0x32244 (título: `scan_results_header_title` ou `scan_results_nothing_found_title` por `csel`). Mapeamento dos casos do enum de textos decodificado da tabela de saltos em 0x3a056 (casos sem argumento, ordem alfabética das chaves).
- **E4**: `FUN_0002e4e4.c` (monta o bloco de manutenção chamando `FUN_0002a898`, `FUN_0002b680`, `FUN_0002c744`, descarta os vazios, e acrescenta o bloco de `FUN_00020a0c` e o de `FUN_0001c8a4`).
- **E5**: `FUN_0002a898.c` + `otool`: procura a tarefa com identificador 0 (`freeUpRAM`); textos `free_up_ram_title/description`; imagem `maintenance-tasks_free-up-ram`; um `TileButtonViewModel` com o texto comum do ModuleCore de índice 0x71.
- **E6**: `ModuleCore.framework/.../Localizable.strings`: chaves sem argumento em ordem alfabética sem diferenciar maiúsculas; 0x6f = `start_over_button`, 0x71 = `tile_action_free_up_ram_title` ("Liberar"), 0x72 = `tile_action_learnMore_title` ("Saiba Mais…").
- **E7**: `FUN_0002b680.c` + `otool`: lista de exclusão `[freeUpRAM]` (+ `speedUpMail` sob condição), textos `maintenance_tasks_category_title`, `weekly_maintenance_cocktail_description`, botões `tile_run_tasks_button` e `tile_review_button`; `TileDynamicIcons.sorted(from:)`.
- **E8**: `FUN_0002c744.c` + `otool`: tarefa com identificador 6 (`thinLocalSnapshots`); imagem `thin_local_snapshots`; botões `tile_run_tasks_button` e o comum de índice 0x72.
- **E9**: `FUN_00020a0c.c` + `otool`: nó com `login_items_category_title/description`, `TileDynamicIcons.sorted(from:)`, botão `tile_review_button`.
- **E10**: `FUN_0001c8a4.c` + `otool`: nó com `background_items_category_title/description`, `TileDynamicIcons.default(icon:)`, botão `tile_review_button`.
- **E11**: AX `maintenance.txt`, `login-items.txt`, `background-items.txt` (seções do Gerenciador e suas contagens) e baseline JSON.
- **E12**: nomes dos casos de `PerformanceTaskIdentifier` nas strings de `PerformanceScanning` (metadados de reflexão, na ordem de declaração).
- **E13**: símbolos importados por `PerformanceModule` de `ModuleCore`: `TileNodeRepresentationViewModel.init(…primaryButton:…secondaryButton:…)`, `TileButtonViewModel`, `TileAction`, `TileNodeRepresentation.markAsCompleted()`, `didUpdateAfterCleanup`, `TileDynamicIcons.sorted/default`, `ScanResultsViewModel.openManualReview()`/`onOpenManualReview`.

## Divergências conhecidas
- **Ordem**: seguimos a ordem dos dados (manutenção primeiro), não a ordem da
  árvore AX.
- **Desativar** conta como tratado nos cartões 4 e 5 (extensão nossa).
- **Cartão 3 e o coquetel**: se a análise listar `thinLocalSnapshots`, o
  CleanMyMac (pelo código) pode contá-la também no cartão 2; nós a deixamos
  **só** no cartão 3 até haver observação real.
- **Condição do Acelerar o Mail** no cartão 2: usamos "acesso total ao disco
  concedido" (inferência).

## Incertezas
1. A condição exata que exclui `speedUpMail` do cartão de manutenção.
2. Se o limite de ícones do cartão de manutenção é 3 em todos os layouts.
3. O que acontece na tela depois de **Executar Tarefas** no cartão (tela de
   execução direta ou Gerenciador) — não clicamos.
4. Se o cartão de Itens de Início mostra ícones dos apps (o código pede ícones
   dinâmicos; a árvore AX não os expõe).

## Checklist de testes
1. Análise com 5 tarefas, 4 itens de início e 9 em segundo plano (esta máquina) → cartões: Manutenção (5, Executar Tarefas + Revisar, 3 ícones: as 3 primeiras por nome), Itens de Início (4, Revisar), Segundo Plano (9, Revisar).
2. Lista de tarefas com `freeUpRAM` → cartão Liberar RAM antes do de manutenção, com botão Liberar; `freeUpRAM` não conta no N do cartão de manutenção.
3. Lista com `thinLocalSnapshots` → cartão de capturas depois do de manutenção, com Executar Tarefas + Saiba Mais….
4. 0 itens de início → sem cartão 4; 0 itens em segundo plano → sem cartão 5.
5. Nenhum cartão → título "não há tarefas recomendadas", subtítulo "o Mac está em ótima forma", botão Recomeçar, sem Ver Todas as Tarefas.
6. Ver Todas as Tarefas → Gerenciador na seção Tarefas de Manutenção.
7. Revisar em cada cartão → seção correspondente.
8. Executar Tarefas → roda as N tarefas do cartão; ao voltar, cartão concluído com "N tarefas concluídas".
9. Remover/Desativar todos os itens de início no Gerenciador → ao voltar, cartão 4 concluído com N; remover só parte → cartão normal com o que sobrou.
10. Plural correto (1 item / N itens) em todos os títulos com contagem, em pt-BR e en.
11. Sem acesso total ao disco → Acelerar o Mail fora do N do cartão de manutenção (regra nossa).
