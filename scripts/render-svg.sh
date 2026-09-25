#!/bin/bash
# Renderiza um SVG em PNG 1024×1024 com fundo transparente usando o Chrome headless
# (o motor de SVG do macOS não faz desfoque direcional). Uso: render-svg.sh in.svg out.png
set -euo pipefail
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
IN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$2"
PROFILE="$(mktemp -d)"
PAGE="$PROFILE/page.html"
printf '<html><body style="margin:0;background:transparent"><img src="file://%s" width="1024" height="1024" style="display:block"></body></html>' "$IN" > "$PAGE"
rm -f "$OUT"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$PROFILE" --allow-file-access-from-files \
  --default-background-color=00000000 --force-device-scale-factor=1 --window-size=1024,1024 \
  --screenshot="$OUT" "file://$PAGE" >/dev/null 2>&1 &
PID=$!
for _ in $(seq 1 60); do if [[ -s "$OUT" ]]; then break; fi; sleep 0.25; done
sleep 0.3; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
rm -rf "$PROFILE"
[[ -s "$OUT" ]] || { echo "falhou: $IN" >&2; exit 1; }
