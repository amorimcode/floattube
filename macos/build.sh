#!/bin/bash
# Compila o FloatTube.app sem abrir o Xcode. Uso: ./build.sh [install|release]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/FloatTube.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Binário universal (Apple Silicon + Intel).
BIN_TMP="$(mktemp -d)"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" Sources/*.swift -o "$BIN_TMP/FloatTube-$arch"
done
lipo -create "$BIN_TMP"/FloatTube-* -output "$APP/Contents/MacOS/FloatTube"
rm -rf "$BIN_TMP"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # reserva para macOS 14/15
# Ícone Liquid Glass (macOS 26+). Precisa do Xcode; sem ele, fica só o .icns.
if xcrun --find actool >/dev/null 2>&1; then
  ICON_TMP="$(mktemp -d)"
  xcrun actool "$PWD/../assets/AppIcon.icon" --compile "$ICON_TMP" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null
  cp "$ICON_TMP/Assets.car" "$APP/Contents/Resources/"
  rm -rf "$ICON_TMP"
fi
codesign --force --sign - "$APP"
echo "Gerado: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x FloatTube || true
  while pgrep -x FloatTube >/dev/null; do sleep 0.2; done
  rm -rf /Applications/FloatTube.app
  cp -R "$APP" /Applications/
  open /Applications/FloatTube.app
  echo "Instalado em /Applications e aberto."
fi

if [[ "${1:-}" == "release" ]]; then
  mkdir -p ../dist
  rm -f ../dist/FloatTube.zip ../dist/FloatTube-Chrome-Extension.zip
  ditto -c -k --keepParent "$APP" ../dist/FloatTube.zip
  (cd ../chrome-extension && zip -qr -X ../dist/FloatTube-Chrome-Extension.zip . -x ".*")
  echo "Pacotes em dist/:"; ls -lh ../dist
fi
