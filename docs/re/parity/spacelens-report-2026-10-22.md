# Paridade da Lupa de Espaço — 2026-10-22

Máquina: Apple Silicon, macOS 26.6, disco de 494 GB. CleanMyMac 5.7.2 (Setapp), só análise e navegação.

## Como foi feito
1. `python3 -I scripts/re/collect-spacelens-baseline.py`: análise do disco e clique duplo em `Users` e na pasta pessoal
   (`re-notes/ax/spacelens-20261022-0506/`) → `spacelens_ax_to_baseline.py` → `spacelens-baseline-2026-10-22-0506.json`.
2. Logo em seguida, a nossa análise pelo app de Debug (com Acesso Total ao Disco):
   `open -n -W <Debug>/CleanYourMac.app --env CYM_LENS_PARITY=lens-parity.json`.
3. `compare_spacelens.py <baseline> <nosso> spacelens-known-divergences.json` (tolerância: o arredondamento da tela —
   uma casa decimal abaixo de 100 unidades — mais 1%; contagem de itens ±meia unidade mostrada + 5%).

## Resultado
**0 falhas, 1 nota** (o purgável muda entre análises: 3,9 × 3,92 GB).

| Pasta | CleanMyMac | CleanYourMac |
|---|---|---|
| Disco | 226 GB de 494 GB usados | 225,58 GB de 494,33 GB |
| Raiz | 242 GB · 3M itens · 9 itens + Outros (0 KB) | 242,08 GB · 3,6 mi · os mesmos 9, na mesma ordem + Outros (12 KB) |
| `/Users` | guigx 183 GB, Shared, .localized | iguais |
| Pasta pessoal | 7 itens (Library … .cache) + Outros 9,3 GB | os mesmos 7 + Outros 9,32 GB |

Tempo da análise do disco inteiro: ~20 s nos dois (3,6 milhões de itens).

## Regras que explicam os números
- Tamanho alocado; hard links contados em cada caminho; links não seguidos; outros volumes e `/System/Volumes` fora.
- A raiz do disco soma o espaço purgável (242 = 238 + 3,9).
- "Usados" = capacidade − disponível para uso importante.
- "Outros itens": regra nossa (a do CleanMyMac não foi achada no binário), que reproduz as três telas — ver
  `docs/re/specs/spacelens/ui-and-removal.md`. O corte (1/75,4 da pasta) foi ajustado por duas coletas da pasta pessoal:
  `.cache` (1,331% e 1,334%) entra e `Pictures` (1,320% e 1,322%) não. Frágil por natureza.

## Depois da revisão final
Refeita em sequência (coleta `spacelens-baseline-2026-10-22-final.json` e nossa análise logo depois): **0 falhas, 1 nota**
(purgável). Na primeira tentativa, com o disco ~1 GB maior, o corte antigo (1/75) tirava `.cache` da lista e o CleanMyMac
não: daí o 1/75,4.

## Divergências conhecidas (de ação, não de análise)
- **Remover:** o CleanMyMac apaga de vez (com o ajudante quando precisa); nós movemos para o Lixo, sem o ajudante.
- Itens só na nuvem: não removíveis nos dois; itens do iCloud locais: aviso fixo na revisão (lá, alerta modal).
- Atualização ao vivo (FSEvents) e Quick Look: não implementados.
