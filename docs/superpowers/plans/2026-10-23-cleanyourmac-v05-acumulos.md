# CleanYourMac v0.5 — Acúmulos: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Módulo Acúmulos com Fundo do Baú, Duplicatas, Imagens Similares e Downloads, igual ao CleanMyMac 5.7.2 nesta
máquina onde as fontes são as mesmas.

**Architecture:** Core `Core/Sources/CleanYourMacCore/Clutter/` (varredura comum com as exclusões da spec; quatro
analisadores; relatório; `cym clutter`) → app `App/Clutter/` (fluxo, Intro, Resultados, Gerenciador com 4 seções) →
paridade → revisão → teste real.

**Spec:** `docs/superpowers/specs/2026-10-23-cleanyourmac-v05-acumulos-design.md` e `docs/re/specs/clutter/*.md`.

## Global Constraints

- Sem APIs privadas; Swift 6 strict; sem dependências. CryptoKit, Vision, PhotoKit, UniformTypeIdentifiers permitidos.
- No CleanMyMac só análise e navegação. Remover = Lixo; fototeca só PhotoKit. `CYM_DRY_RUN` sempre respeitado.
- Exclusões comuns, mínimos e faixas exatamente como `docs/re/specs/clutter/duplicates.md` §1 e `large-old-files.md` §4.
- pt-BR e en; commit e push por tarefa.

## Review Focus

1. Pastas enormes (2,5 M itens na pasta pessoal): memória e tempo; Parar funciona.
2. Grupo de duplicatas inteiro marcado: só com o alerta "Selecionar Tudo"; nunca remover a única cópia.
3. Arquivo mudou entre a análise e a remoção (tamanho, identidade, virou link): recusar.
4. Fototeca: sem permissão, negada ou cancelada na confirmação do sistema → nada muda, aviso claro.
5. Arquivos só no iCloud: nunca baixar nem hashear; fora da análise.

### Task 1: Baseline (conversor dos dumps + teste) — `scripts/parity/clutter_ax_to_baseline.py`
### Task 2: Varredura comum e regras (`ClutterWalker`, `ClutterRules`) + testes das exclusões
### Task 3: Fundo do Baú (`LargeOldFiles`) + filtros (tipo, tamanho, data) + testes com as faixas da spec
### Task 4: Duplicatas (`DuplicateFinder`: tamanho → SHA-256; pacotes; desempate; tipos) + testes
### Task 5: Downloads (`DownloadsFinder`: quarentena por app; 30 dias) + testes
### Task 6: Similares (`SimilarImages`: Vision feature print, agrupamento, melhor/falhas; fonte de imagens injetável) + testes
### Task 7: `ClutterReport`/`ClutterScan`, cartões, `cym clutter [--json]` + teste de forma da paridade
### Task 8: App — fluxo (`ClutterFlowModel`): análise, cartões, Gerenciador, seleção (alerta), remoção (Lixo + PhotoKit)
### Task 9: App — telas e textos `clutter.*` (Intro, Análise, Resultados, Gerenciador com 4 seções e filtros, revisão, fim)
### Task 10: Fototeca (PhotoKit: permissão, miniaturas, remoção) no app
### Task 11: Paridade (`compare_clutter.py`, relatório, divergências)
### Task 12: Revisão final (subagente no modelo mais capaz) e correções com TDD
### Task 13: Teste real com pasta de teste; README; versão 0.5.0; release só com o ok do usuário
