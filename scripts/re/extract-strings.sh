#!/bin/bash
# Extrai evidência estática de um framework do CleanMyMac.
# Uso: scripts/re/extract-strings.sh <Framework> [app]
# Saída: re-notes/static/<Framework>/{strings.txt,symbols.txt,localizable-<lang>.json}
set -euo pipefail

name=${1:?uso: extract-strings.sh <Framework> [caminho do app]}
app=${2:-/Applications/Setapp/CleanMyMac.app}
repo="$(cd "$(dirname "$0")/../.." && pwd)"
fw="$app/Contents/Frameworks/$name.framework/Versions/A"
bin="$fw/$name"
out="$repo/re-notes/static/$name"

[ -f "$bin" ] || { echo "binário não encontrado: $bin" >&2; exit 1; }
mkdir -p "$out"

strings -a -n 4 "$bin" > "$out/strings.txt"
nm -gU "$bin" 2>/dev/null | swift demangle --compact > "$out/symbols.txt" || true

for dir in "$fw"/Resources/*.lproj; do
  [ -d "$dir" ] || continue
  lang=$(basename "$dir" .lproj)
  for f in "$dir"/Localizable.strings; do
    [ -f "$f" ] && plutil -convert json -o "$out/localizable-$lang.json" "$f"
  done
done

wc -l "$out"/strings.txt "$out"/symbols.txt | sed "s|$repo/||"
