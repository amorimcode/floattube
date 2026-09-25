#!/bin/bash
# Renderiza as imagens da loja e do site com o Chrome headless. Uso: store/render.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE="$(mktemp -d)"
PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$PROFILE"' EXIT
sleep 1
shot() { # página largura altura saída
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$PROFILE" --window-size="$2,$3" \
    --virtual-time-budget=4000 --blink-settings=preferredColorScheme=1 --screenshot="$4" "http://127.0.0.1:$PORT/$1" >/dev/null 2>&1 &
  local pid=$!
  rm -f "$4"
  for _ in $(seq 1 40); do if [[ -s "$4" ]]; then break; fi; sleep 0.25; done
  sleep 0.5; kill $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
  echo "$4"
}
shot store/screenshot-1.html 1280 800 store/screenshot-1.png
shot store/screenshot-2.html 1280 800 store/screenshot-2.png
shot store/promo-small.html 440 280 store/promo-small.png
shot store/og.html 1200 630 site/og.png
# Imagens para o portfólio (bruno-next), sem texto em português
mkdir -p store/portfolio
shot store/portfolio-1.html 1600 1000 store/portfolio/floattube-1.png
shot store/portfolio-2.html 1280 720 store/portfolio/floattube-2.png
shot store/portfolio-3.html 1600 640 store/portfolio/floattube-3.png
exit 0
