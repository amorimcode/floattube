#!/bin/bash
# Gera os ícones a partir de assets/:
#   - macos/AppIcon.icns: reserva para macOS 14/15 (a partir do SVG)
#   - assets/icon-glass.png: o ícone Liquid Glass (assets/AppIcon.icon) como o macOS o desenha
#   - chrome-extension/icons e site/: PNGs derivados
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -O -o "$TMP/render" scripts/render-icon.swift

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  "$TMP/render" assets/icon.svg "$size" "$ICONSET/icon_${size}x${size}.png"
  "$TMP/render" assets/icon.svg "$((size * 2))" "$ICONSET/icon_${size}x${size}@2x.png"
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
"$TMP/render" "$PREVIEW" 1024 assets/icon-glass.png

mkdir -p chrome-extension/icons site
"$TMP/render" assets/icon-tiny.svg 16 chrome-extension/icons/icon16.png
"$TMP/render" assets/icon-tiny.svg 32 chrome-extension/icons/icon32.png
sips -z 48 48 assets/icon-glass.png --out chrome-extension/icons/icon48.png >/dev/null
sips -z 128 128 assets/icon-glass.png --out chrome-extension/icons/icon128.png >/dev/null
sips -z 512 512 assets/icon-glass.png --out site/icon.png >/dev/null
sips -z 180 180 assets/icon-glass.png --out site/apple-touch-icon.png >/dev/null
"$TMP/render" assets/icon-tiny.svg 64 site/favicon.png
echo "Ícones gerados."
