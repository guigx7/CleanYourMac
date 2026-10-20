#!/bin/bash
# Roda os testes do app e imprime só o resumo (o xcodebuild é muito verboso).
set -uo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
log=$(mktemp)
xcodebuild -scheme CleanYourMac -destination 'platform=macOS' test > "$log" 2>&1
status=$?
grep -E "✘|\.swift:[0-9]+:[0-9]+: error:|Test run with|TEST (SUCCEEDED|FAILED)" "$log" | tail -20
exit $status
