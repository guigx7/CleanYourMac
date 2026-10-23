# Paridade do Acúmulos — 2026-10-23

Máquina: Apple Silicon, macOS 26.6. CleanMyMac 5.7.2 (Setapp), só análise e navegação (nenhuma remoção).

## Como foi feito
1. Dumps de Acessibilidade das telas do CleanMyMac (`re-notes/ax/clutter-20261023/`: Resultados, Fundo do Baú,
   Duplicatas com os 149 grupos, Imagens Similares, Downloads) → `clutter_ax_to_baseline.py` →
   `clutter-baseline-2026-10-23.json`.
2. A nossa análise da pasta pessoal: `cym clutter --json` (sem Acesso Total ao Disco e sem a fototeca, como o CleanMyMac
   viu: Safari 0 KB e nenhuma foto nos grupos).
3. `compare_clutter.py <baseline> <nosso>` (nomes em NFC; tamanhos com o arredondamento da tela + 1%; Downloads 5%;
   Similares e total só como notas).

## Resultado
**0 falhas, 6 notas.**

| Parte | CleanMyMac | CleanYourMac |
|---|---|---|
| Fundo do Baú | 5 arquivos (1 GB, 267 MB, 179 MB, 171 MB, 60,8 MB) | os mesmos 5, mesmos tamanhos e datas de abertura |
| Duplicatas | 149 grupos, 434 arquivos | 149 grupos, 434 arquivos, **os 149 títulos iguais** |
| Cartão de Duplicatas | 45 em Documentos, 35,6 MB | 45 em Documentos, 35,6 MB |
| Imagens Similares | 65 grupos, 264 imagens | 65 grupos, 261 imagens |
| Cartão de Similares | 13 novas (30 dias), 15,9 MB | 9, 12 MB (nota) |
| Downloads | Chrome 591 MB (219 arquivos), Slack e Safari 0 KB | Chrome 573 MB (os mesmos 219 arquivos) |
| Total ("arquivos para revisar") | 885 | 883 (nota: a diferença vem das 3 imagens similares) |

## Regras descobertas pela paridade (estão nas specs)
- **Duplicatas:** o título do grupo é a cópia que **fica**. `nome (N).ext` e `nome N.ext` **não** contam como número de
  cópia. No desempate alfabético final sai o caminho **menor**. Tudo dentro de uma pasta `.xcassets` fica de fora. O
  cartão mostra o **total** dos grupos, e não só o espaço removível.
- **Similares:** o hash do CleanMyMac foi reproduzido com a vImage (gradientes, 4 orientações, soma ≤ 15, agrupamento
  guloso). Além disso, **as cópias exatas saem das Similares**: sem essa regra seriam 140 grupos / 499 imagens.
- **Total:** cada arquivo conta uma vez, mesmo quando aparece em mais de uma seção.

## Divergências conhecidas
- **Downloads +3%:** alguns arquivos aparecem maiores no CleanMyMac do que no disco e no histórico do Chrome (o zip do
  Godot: 185 MB contra 170,6 MB). Não achamos a regra; dentro da tolerância.
- **Similares:** 3 imagens a menos e o cartão "novas" com 9 em vez de 13. A ordem do agrupamento do CleanMyMac depende das
  tarefas paralelas; a nossa é fixa (caminho, depois data). Imagens de fronteira podem cair em grupos diferentes.
- **Fototeca:** só pelo PhotoKit público, sem o tamanho das fotos ("—").
- **Remover:** sempre para o Lixo (fotos para Apagados Recentemente).
