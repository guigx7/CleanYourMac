#!/bin/bash
# Cria um app de teste mínimo (assinado ad-hoc) para os testes de remoção do módulo Aplicativos.
# Uso: scripts/make-test-app.sh <pasta> <nome> <bundleID> [--feed URL] [--version V] [--agent]
#   --agent  também gera <pasta>/<bundleID>.agent.plist (launchd) apontando para o executável.
# Nunca escreve fora de <pasta>.
set -euo pipefail

dir=${1:?uso: make-test-app.sh <pasta> <nome> <bundleID> [--feed URL] [--version V] [--agent]}
name=${2:?nome}
bundle_id=${3:?bundleID}
shift 3
feed="" version="1.0" agent=0
while [ $# -gt 0 ]; do
  case "$1" in
    --feed) feed=$2; shift 2 ;;
    --version) version=$2; shift 2 ;;
    --agent) agent=1; shift ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
done

app="$dir/$name.app"
exe_name=$(printf '%s' "$name" | tr -cd 'A-Za-z0-9')
[ -n "$exe_name" ] || exe_name=TestApp
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

src=$(mktemp -t cymtestapp).c
printf 'int main(void){return 0;}\n' > "$src"
clang -o "$app/Contents/MacOS/$exe_name" "$src"
rm -f "$src"

feed_entry=""
[ -n "$feed" ] && feed_entry="<key>SUFeedURL</key><string>$feed</string>"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleExecutable</key><string>$exe_name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSUIElement</key><true/>
$feed_entry
</dict></plist>
EOF
codesign -s - --force "$app" >/dev/null 2>&1

if [ "$agent" -eq 1 ]; then
  cat > "$dir/$bundle_id.agent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$bundle_id.agent</string>
<key>ProgramArguments</key><array><string>$app/Contents/MacOS/$exe_name</string></array>
</dict></plist>
EOF
fi
echo "$app"
