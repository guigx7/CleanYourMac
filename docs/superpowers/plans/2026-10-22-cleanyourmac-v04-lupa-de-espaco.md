# CleanYourMac v0.4 — Lupa de Espaço: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Módulo Lupa de Espaço: varredura rápida do disco ou de uma pasta, lista + mapa de bolhas com navegação,
"Outros itens", seleção, revisão e remoção para o Lixo, com a análise batendo com a do CleanMyMac nesta máquina.

**Architecture:** Specs em `docs/re/specs/spacelens/` → Core (`Core/Sources/CleanYourMacCore/SpaceLens/`: árvore compacta,
scanner paralelo com `fts`/`lstat`, agrupamento, proteção, remoção) + `cym spacelens` → app (`App/SpaceLens/`) →
paridade → revisão → teste real → release.

**Tech Stack:** Swift 6, SwiftUI (`Canvas` para as bolhas), macOS 14+, Swift Testing, Python 3 (paridade).

**Spec:** `docs/superpowers/specs/2026-10-22-cleanyourmac-v04-lupa-de-espaco-design.md` e `docs/re/specs/spacelens/*.md`.

## Global Constraints

- Sem APIs privadas; sem dependências externas; Swift 6 strict concurrency.
- No CleanMyMac só análise e navegação.
- Remover = Lixo; nunca essenciais do sistema, `PathPolicy.isVital`, a pasta pessoal nem as pastas vitais dela.
- Tudo respeita `CYM_DRY_RUN`; teste real só em pastas de teste nossas (`io.github.guigx7.cymtest`).
- Tamanho: alocado (`st_blocks × 512`), hard links contados em cada caminho (como o CleanMyMac; medição de 2026-10-22:
  `.npm` 10,08 GB sem desconto × 10,00 com desconto × CleanMyMac 10,1 GB). A spec confirma ou corrige.
- "Usados" = capacidade − `volumeAvailableCapacityForImportantUsage` (225,26 GB → "225 GB" nesta máquina).
- pt-BR e en; cada task termina com commit e push em `main`.

## Review Focus

1. **Varredura enorme / Parar no meio**: 3 milhões de itens sem estourar memória; Parar volta à Intro em < 1 s.
2. **Firmlinks e outros volumes**: nada contado duas vezes; `/Volumes`, `/System/Volumes/*` e montagens não entram na
   análise do disco.
3. **Item mudou entre a análise e a remoção** (apagado, virou link, trocado): revalidar e recusar sem tocar em outro.
4. **Proteção**: essenciais e vitais nunca removíveis, mesmo marcando a pasta pai; aviso em pastas do sistema.
5. **Pastas ilegíveis** (sem Acesso Total ao Disco ou de root): contadas como "sem acesso", sem travar a análise.

---

### Task 1: Baseline do CleanMyMac — feita (`ea19adb`)
### Task 2: Specs `scan.md` e `ui-and-removal.md` (subagente)

### Task 3: Árvore e scanner paralelo
**Files:** `SpaceLens/SpaceNode.swift`, `SpaceLens/SpaceScanner.swift`; testes `SpaceLens/SpaceScannerTests.swift`.
- Testes (fixture): `sizesAreAllocatedAndAggregated`, `hardLinksCountedPerPath`, `symlinksNotFollowed`,
  `staysOnVolume` (função de dispositivo injetável), `unreadableFoldersMarked`, `cancelStopsQuickly`,
  `itemCountIncludesFolders`, `hiddenFilesIncluded`.
- `SpaceNode` (classe final, filhos ordenados por tamanho, `size`, `items`, `isDirectory`, `isUnreadable`).
- Scanner: um `fts` por subárvore de primeiro nível em paralelo (`DispatchQueue.concurrentPerform`), progresso.

### Task 4: Agrupamento "Outros itens", nomes e purgável
**Files:** `SpaceLens/SpaceLayout.swift`; testes. Regra da spec; nome exibido; linha purgável só na raiz do disco.

### Task 5: Proteção e remoção
**Files:** `SpaceLens/SpaceProtection.swift`, `SpaceLens/SpaceRemover.swift`; testes `essentialsNeverRemovable`,
`systemFolderNeedsConfirmation`, `removalRevalidates`, `rootItemsGoToHelper`, `dryRunTouchesNothing`.

### Task 6: `SpaceLensReport` + `cym spacelens [--json] [caminho]`

### Task 7: App — fluxo (`SpaceLensFlowModel`) e testes de estado (navegação, voltar/avançar, seleção, revisão).
### Task 8: App — Intro (alvo disco/pasta), Análise, Resultados (lista + bolhas + caminho), textos `lens.*`, arte.
### Task 9: App — Revisão, remoção, conclusão; avisos (sistema, nuvem, root).
### Task 10: Paridade (`compare_spacelens.py`, relatório, divergências).
### Task 11: Revisão final (subagente no modelo mais capaz) e correções com TDD.
### Task 12: Teste real com pasta de teste; README; versão 0.4.0; release com o ok do usuário.
