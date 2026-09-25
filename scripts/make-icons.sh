#!/bin/bash
# Gera todos os ícones a partir de assets/:
#   - icon.svg (grid do macOS)        → macos/AppIcon.icns (reserva para macOS 14/15), extensão 48/128, site
#   - icon-tiny.svg (simplificado)    → extensão 16/32 e favicon
#   - icon-layers/*.svg               → camadas do ícone Liquid Glass (assets/AppIcon.icon)
#   - assets/icon-glass.png           → o ícone Liquid Glass como o macOS 26 o desenha
# Os SVGs usam desfoque direcional, então são renderizados pelo Chrome (scripts/render-svg.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RENDER=scripts/render-svg.sh
swiftc -O -o "$TMP/render-app" scripts/render-icon.swift

$RENDER assets/icon.svg "$TMP/icon.png"
$RENDER assets/icon-tiny.svg "$TMP/tiny.png"
$RENDER assets/icon-layers/background.svg assets/AppIcon.icon/Assets/background.png
$RENDER assets/icon-layers/tile.svg assets/AppIcon.icon/Assets/tile.png
cp assets/icon-layers/bezel.svg assets/icon-layers/progress.svg assets/AppIcon.icon/Assets/

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o macos/AppIcon.icns

# App descartável só para o sistema desenhar o ícone de vidro.
PREVIEW="$TMP/IconPreview$RANDOM.app"
mkdir -p "$PREVIEW/Contents/Resources" "$PREVIEW/Contents/MacOS"
xcrun actool "$PWD/assets/AppIcon.icon" --compile "$PREVIEW/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$TMP/partial.plist" >/dev/null
cat > "$PREVIEW/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.amorim.floattube.iconpreview$RANDOM</string>
  <key>CFBundleExecutable</key><string>preview</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
cp /usr/bin/true "$PREVIEW/Contents/MacOS/preview"
"$TMP/render-app" "$PREVIEW" 1024 assets/icon-glass.png

mkdir -p chrome-extension/icons site
sips -z 16 16 "$TMP/tiny.png" --out chrome-extension/icons/icon16.png >/dev/null
sips -z 32 32 "$TMP/tiny.png" --out chrome-extension/icons/icon32.png >/dev/null
sips -z 48 48 "$TMP/icon.png" --out chrome-extension/icons/icon48.png >/dev/null
sips -z 128 128 "$TMP/icon.png" --out chrome-extension/icons/icon128.png >/dev/null
sips -z 512 512 "$TMP/icon.png" --out site/icon.png >/dev/null
sips -z 180 180 "$TMP/icon.png" --out site/apple-touch-icon.png >/dev/null
sips -z 64 64 "$TMP/tiny.png" --out site/favicon.png >/dev/null
echo "Ícones gerados."
