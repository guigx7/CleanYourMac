#!/bin/bash
# Percorre o Gerenciador de Limpeza do CleanMyMac (já aberto em "Revisar Todos os Detritos")
# e despeja a tela de cada grupo em re-notes/ax/baseline-<data>/<categoria>/<grupo>.txt.
# Só navega: dump-ax.swift recusa qualquer elemento que pareça ação de limpeza.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
# Compilado é muito mais rápido: swiftc -O scripts/re/dump-ax.swift -o re-notes/dump-ax
if [ -x "$repo/re-notes/dump-ax" ]; then ax="$repo/re-notes/dump-ax"; else ax="swift $repo/scripts/re/dump-ax.swift"; fi
out="$repo/re-notes/ax/baseline-$(date +%Y%m%d-%H%M)"
mkdir -p "$out"

categories=("Detritos do Sistema" "Acúmulos de IA" "Anexos do Mail" "Lixos")
for cat in "${categories[@]}"; do
  $ax "cat" --press "$cat" > /dev/null
  latest=$(/bin/ls -t "$repo"/re-notes/ax/cat-*.txt | head -1)
  mkdir -p "$out/$cat"
  cp "$latest" "$out/$cat/_category.txt"
  # Grupos: linha "X | X" seguida da linha de tamanho total do grupo.
  groups=$(awk '/Tamanho total dos itens no grupo/ { print prev } { prev = $0 }' "$latest" \
           | sed -E 's/^ *AXStaticText: (.*) \| .*$/\1/')
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    $ax "grp" --press "$g" > /dev/null || { echo "falhou: $cat / $g"; continue; }
    cp "$(/bin/ls -t "$repo"/re-notes/ax/grp-*.txt | head -1)" "$out/$cat/$g.txt"
    echo "ok: $cat / $g"
  done <<< "$groups"
done
rm -f "$repo"/re-notes/ax/cat-*.txt "$repo"/re-notes/ax/grp-*.txt
echo "$out"
