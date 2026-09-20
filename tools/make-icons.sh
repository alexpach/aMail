#!/usr/bin/env bash
# Regenerate the app icon and favicon from the envelope.open.fill SF Symbol.
# Output: MenuBarApp/Assets/AppIcon.icns
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT_DIR}/tools"
ASSETS="${ROOT_DIR}/MenuBarApp/Assets"
ICONSET="${ROOT_DIR}/tmp/icon/AppIcon.iconset"

mkdir -p "$ASSETS" "$ICONSET" "${ROOT_DIR}/webapp/public" "${ROOT_DIR}/tmp/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/tmp/swift-module-cache"

render() { swift "${TOOLS}/render-symbol.swift" "$1" "$2"; }

# App icon: all .iconset sizes from the 1024 master
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 \
    256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    px="${spec%%:*}"
    name="${spec#*:}"
    render "${ICONSET}/icon_${name}.png" "$px"
done
iconutil -c icns "$ICONSET" -o "${ASSETS}/AppIcon.icns"

render "${ROOT_DIR}/webapp/public/favicon.png" 64
render "${ROOT_DIR}/webapp/public/apple-touch-icon.png" 180

# Menu bar uses the same SF Symbol directly, no asset needed.

echo "Icons written to ${ASSETS}"
