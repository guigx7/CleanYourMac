# Paridade do módulo Desempenho — 2026-10-22

Máquina: Apple Silicon, macOS 26.6. CleanMyMac 5.7.2 (Setapp), só análise.

## Como foi feito
1. `python3 -I scripts/re/collect-perf-baseline.py`: Recomeçar → Analisar → Resultados → Ver Todas as Tarefas → as três
   seções (dump de Acessibilidade em `re-notes/ax/perf-baseline-20261022-0351/`).
2. `perf_ax_to_baseline.py` → JSON; `swift run -c release --package-path Core cym performance --json` logo em seguida.
3. `compare_perf.py <baseline> <nosso> perf-known-divergences.json`.

## Resultado
**0 falhas, 1 nota.**

| Parte | CleanMyMac | CleanYourMac |
|---|---|---|
| Tarefas | Acelerar o Mail, Esvaziar Cache do DNS, Liberar Espaço Purgável, Reindexar o Spotlight, Reparar Permissões do Disco | as mesmas 5 |
| Espaço purgável | Até 3,9 GB | Até 3,9 GB (nota: muda entre análises) |
| Itens de Início | GlucoTracker, Hidden Bar, Vorssaint, Warp | os mesmos 4 |
| Itens em Segundo Plano | 9 (Logi Options+ duas vezes) | os mesmos 9 |
| Cartões | 4 início, 5 manutenção, 9 segundo plano | iguais |

A baseline gravada mais cedo (`perf-baseline-2026-10-22.json`, coleta das 02:28) também bate.

## Divergências conhecidas (regras, sem efeito nesta máquina)
Ver `perf-known-divergences.json`: Acelerar o Mail só com `~/Library/Mail`; purgável some com estimativa 0;
Reindexar o Spotlight some com a indexação desligada; Scripts Periódicos exigem o `periodic`. Excluímos sempre
`com.apple.*`, o próprio CleanYourMac e os ajudantes da MacPaw (no CleanMyMac isso vem da base de regras cifrada).
Diferenças de execução (não de análise): Acelerar o Mail sem VACUUM, Liberar RAM com `purge`, tempos-limite em todas
as tarefas (ver `docs/re/specs/performance/maintenance-tasks.md`).
