# Capturas locais do Time Machine (`thinSnapshots` / fluxo `timeMachineSnapshot`)

## Versão de referência
CleanMyMac 5.7.2 (Setapp), macOS 26.6.2 (25G83), Apple Silicon, 2026-10-22. **Só análise
estática e leitura**: nada foi apagado nem diminuído, nenhum `sudo`.

Legenda: **[E*n*]** = evidência (lista no fim); **(inferência)** = conclusão nossa.

## Visão geral

### No CleanMyMac
- A mesma operação aparece em três lugares: a tarefa **Diminuir Capturas do Time Machine** na
  lista de Tarefas de Manutenção, o cartão **"Diminua as Capturas do Time Machine"** nos
  Resultados e o atalho **Capturas do Time Machine** da busca (fluxo `toolbox`), que analisa
  só as capturas e oferece a ação [E1].
- **Não apaga capturas por data e não usa `deletelocalsnapshots`.** Só existem no binário
  `listlocalsnapshots` e `thinlocalsnapshots` [E2].
- Tudo roda **no processo do app, como o usuário**, com `/usr/bin/tmutil` (classe
  `CMVolumeThinner` + fábrica de processos). O ajudante privilegiado não participa [E2][E3].
- Volume fixo: o de inicialização, `/` [E3][E4].

### No CleanYourMac (design)
- Mesma regra de aplicabilidade e o mesmo "diminuir" (paridade) na lista de tarefas.
- No fluxo próprio de Capturas, além de diminuir, **listar** cada captura com a data e
  permitir **remover as selecionadas** (objetivo 4 do design da v0.3), sempre só capturas
  `com.apple.TimeMachine.*`.

## Locais varridos
- Comando: `/usr/bin/tmutil listlocalsnapshots /` [E2].
- Saída esperada: uma linha de cabeçalho ("Snapshots for disk /:") e uma linha por captura, no
  formato `com.apple.TimeMachine.AAAA-MM-DD-HHMMSS.local`.

## Inclusão
O CleanMyMac [E2]:
1. Roda o comando e lê a saída padrão e a de erro.
2. Se a saída de erro **não estiver vazia**, considera "sem capturas".
3. Separa a saída padrão por quebra de linha e conta as linhas que **começam com
   `com.apple.TimeMachine`**.
4. Há capturas se a contagem for > 0 (`isThinningAvailable`).

Nós: o mesmo filtro, e de cada linha extraímos a data (`AAAA-MM-DD-HHMMSS`) para a lista do
fluxo próprio. Opcionalmente, conferir com `tmutil listlocalsnapshotdates /`.

## Exclusão
- Capturas que não começam com `com.apple.TimeMachine` (ex.: `com.apple.os.update-…`, a captura
  do sistema selado; capturas de outros apps de backup): **nunca** listadas nem tocadas [E2][E5].
- Outros volumes: fora (o CleanMyMac só olha `/`).

## Quando a tarefa e o cartão aparecem
- **Tarefa (fluxo `main` e `toolbox`)**: o app não está em sandbox **e** o volume de
  inicialização é APFS [E6] **e** a análise encontra ao menos uma captura; se não encontra,
  a tarefa de análise lança erro e a tarefa não entra na lista [E4]. Na Limpeza Inteligente
  (`smartCare`) nunca entra [E6].
- **Cartão "Diminua as Capturas do Time Machine"** (com o estado "Capturas do Time Machine
  Diminuídas" depois de rodar): **(inferência)** aparece nos Resultados quando a tarefa é
  aplicável, como os outros cartões do módulo; o binário não mostra um tamanho para ele (não há
  subtítulo "Até X" nessa tarefa) [E1].
- **Atalho "Capturas do Time Machine"**: análise própria ("Verificando as capturas locais do
  Time Machine"); sem capturas, mostra o estado "Não há tarefas recomendadas" [E1].

### Nesta máquina
`tmutil listlocalsnapshots /` devolveu só o cabeçalho, sem nenhuma captura. O Time Machine não
tem destino configurado (`tmutil destinationinfo` → nenhum destino) e a única captura APFS do
volume é a `com.apple.os.update-…` do sistema [E5]. Por isso a tarefa e o cartão **não
apareceram**.

## Recomendado
Quando aplicável, vem marcada como as outras tarefas do fluxo principal (ver
`maintenance-tasks.md`, seção "Recomendada"; inferência).

## Cálculo de tamanho
O CleanMyMac não estima quanto espaço as capturas ocupam [E1][E3]. O `tmutil` não informa
tamanho por captura, e o `diskutil apfs listSnapshots` também não. Nós também não mostramos
tamanho; o resultado é medido como espaço livre do `/` depois − antes
(`volumeAvailableCapacityKey`).

## Remoção (execução)
O CleanMyMac [E3][E7]:
- Comando: `/usr/bin/tmutil thinlocalsnapshots / 1073741824 3` (pede ao sistema para recuperar
  **1 GiB** com **urgência 3**, numa escala de 1 a 4). O próprio macOS decide quais capturas
  apagar (normalmente as mais antigas) até chegar ao pedido. **Não** é "apagar todas".
- Roda num executor com progresso; pode ser cancelado ("TaskCancelledError"); falha com
  "Failed to thin local snapshots" se o `tmutil` sair com erro.
- **Root**: não (processo do app). O `man tmutil` diz que alguns verbos exigem root e Acesso
  Total ao Disco; o CleanMyMac trata o `thinlocalsnapshots` como verbo de usuário
  (**inferência**: funciona sem root; confirmar no teste real).
- **Tempo-limite**: nenhum explícito.

Nossa forma:
- **Diminuir (tarefa da lista, paridade)**: `/usr/bin/tmutil thinlocalsnapshots / 1073741824 3`,
  como o usuário. Se o `tmutil` recusar por privilégio, repetir por uma operação tipada do
  ajudante (mesmos argumentos fixos). Tempo-limite: 10 min.
- **Remover selecionadas (fluxo próprio)**: para cada data escolhida,
  `/usr/bin/tmutil deletelocalsnapshots AAAA-MM-DD-HHMMSS`. A data vem da nossa lista,
  revalidada logo antes (a captura `com.apple.TimeMachine.<data>.local` ainda existe em `/`).
  Tentar como usuário; se recusar, o ajudante, que valida de novo o formato da data e a
  existência da captura antes de rodar. Nunca `deletelocalsnapshots /` (que apaga todas de
  uma vez) sem uma confirmação explícita de "remover todas".
- Confirmação antes de remover: avisar que as capturas locais servem para restaurar arquivos
  sem o disco de backup, e que os backups no destino do Time Machine não são afetados.
- Sem capturas: tarefa e fluxo mostram o estado vazio.

## Alertas e selos
- Nenhum alerta específico no CleanMyMac além dos erros genéricos de tarefa (cancelada, falhou,
  tempo esgotado) [E1].
- Nós: confirmação na remoção por data (acima).

## requiresAdmin
- Análise: não (`tmutil listlocalsnapshots /` funcionou sem `sudo` nesta máquina [E5]).
- Limpeza: não no CleanMyMac; nós tentamos como usuário, com o ajudante de reserva.

## Teste real sugerido
Esta máquina não tem capturas. Para testar de verdade (com o ok do usuário):
`tmutil localsnapshot` cria uma captura local (pode exigir root e Time Machine configurado;
verificar), depois `tmutil listlocalsnapshots /` deve listá-la, a tarefa deve aparecer, e o
diminuir/remover deve fazê-la sumir.

## Evidências
- **E1**: chaves do PerformanceModule: `thin_local_snapshots_title/description`,
  `tile_thin_local_snapshots_*` (título, normal, concluído), `custom_flow_timeMachineSnapshot_*`,
  `performance_timeMachine_scan_subtitle`, `scan_results_nothing_found_*`; classes
  `TimeMachineSnapshotFlowCoordinator` e `TimeMachineSnapshotScannerConfig`.
- **E2**: strings de PerformanceService: `com.apple.TimeMachine`, `/usr/bin/tmutil`,
  `listlocalsnapshots`, `thinlocalsnapshots` (sem `deletelocalsnapshots`);
  `CMVolumeThinner _isLocalSnapshotAvailable` decompilado (roda a listagem, saída de erro não
  vazia → falso, filtro por prefixo, contagem > 0).
- **E3**: `CMVolumeThinnerProcessesFactory init` (`/usr/bin/tmutil`),
  `makeListProcessWithVolumeURL:` (`listlocalsnapshots <caminho>`),
  `makeThinningProcessWithVolumeURL:requestedSize:urgency:` (`thinlocalsnapshots <caminho>
  <tamanho> <urgência>`), `performThinningWithRequestedSize:urgency:error:`, todos via
  `CMProcess` no app.
- **E4**: `ThinLocalSnapshotsTaskRunner` (FUN_0000b2b0, URL `/`, `CMExecutor`, erros de falha e
  cancelamento) e FUN_0000b0e0 (tamanho 0x40000000 = 1 GiB, urgência 3); tarefa de análise do
  PerformanceScanning (FUN_00004f38: `CMVolumeThinner("/")`, `isThinningAvailable`, erro
  `ThinLocalSnapshotsScanTaskError` se falso).
- **E5**: comandos nesta máquina: `tmutil listlocalsnapshots /` → só "Snapshots for disk /:";
  `tmutil listlocalsnapshotdates /` → só o cabeçalho; `tmutil destinationinfo` → "No
  destinations configured"; `diskutil apfs listSnapshots /` → 1 captura
  `com.apple.os.update-…`; `diskutil info /` → APFS.
- **E6**: `PerformanceMaintenanceTaskAvailability.isScanTaskAvailable`: para
  `thinLocalSnapshots`, `main`/`toolbox` → não sandbox **e** APFS; `smartCare` → falso.
- **E7**: `man tmutil` (verbos `listlocalsnapshots`, `listlocalsnapshotdates`,
  `deletelocalsnapshots {mount_point | date}`, `thinlocalsnapshots mount_point [purge_amount]
  [urgency]`, urgência 1–4; "Several, but not all, verbs require root").

## Divergências conhecidas
- **Remover por data** no fluxo próprio (o CleanMyMac só diminui 1 GiB com urgência 3).
- **Reserva pelo ajudante** se o `tmutil` recusar como usuário.
- **Tempo-limite** de 10 min (o CleanMyMac não tem).
- **Resultado medido** pelo espaço livre antes e depois (o CleanMyMac só diz que concluiu).
