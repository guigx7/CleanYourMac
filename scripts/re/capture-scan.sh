#!/bin/bash
# Captura os acessos a arquivos do CleanMyMac durante uma análise.
# Uso: sudo scripts/re/capture-scan.sh <rótulo> [segundos=180]
# Saída: re-notes/fs/<rótulo>-<timestamp>.log (fora do git)
set -euo pipefail

label=${1:?uso: capture-scan.sh <rótulo> [segundos]}
seconds=${2:-180}
repo="$(cd "$(dirname "$0")/../.." && pwd)"
out="$repo/re-notes/fs"
mkdir -p "$out"
file="$out/$label-$(date +%Y%m%d-%H%M%S).log"

if [ "$(id -u)" -ne 0 ]; then
  echo "fs_usage precisa de root: rode com sudo" >&2
  exit 1
fi

# Processos do CleanMyMac (app, agent privilegiado e helpers).
pids=$(pgrep -f 'com.macpaw.CleanMyMac|CleanMyMac.app|CleanMyMac_5' | tr '\n' ' ' || true)
if [ -z "$pids" ]; then
  echo "CleanMyMac não está rodando; abra o app primeiro" >&2
  exit 1
fi
echo "capturando PIDs: $pids por ${seconds}s → $file"
echo "agora clique em Analisar no CleanMyMac"

# fs_usage aceita nomes de processo ou PIDs no fim da linha de comando.
# shellcheck disable=SC2086
fs_usage -w -f filesys $pids > "$file" 2>/dev/null &
fs_pid=$!
sleep "$seconds"
kill "$fs_pid" 2>/dev/null || true
wait "$fs_pid" 2>/dev/null || true

# O usuário original deve conseguir ler as notas.
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER" "$repo/re-notes"
echo "linhas capturadas: $(wc -l < "$file")"
