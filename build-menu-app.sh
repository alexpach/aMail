#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="aMail"
BUNDLE_NAME="aMail.app"
BUILD_DIR="${ROOT_DIR}/build"
APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODULE_CACHE_DIR="${BUILD_DIR}/ModuleCache"
SWIFTC="$(xcrun --find swiftc)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${ARCH:-$(uname -m)}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
TARGET="${TARGET:-${ARCH}-apple-macosx${MACOSX_DEPLOYMENT_TARGET}}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

cp "${ROOT_DIR}/MenuBarApp/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ROOT_DIR}"/MenuBarApp/Assets/* "${RESOURCES_DIR}/"

# RELEASE=1: self-contained app (bundles the sync script, no machine-specific path).
# Otherwise a dev build that runs the script from this checkout.
if [ "${RELEASE:-0}" = "1" ]; then
  cp "${ROOT_DIR}/mail-sync.sh" "${RESOURCES_DIR}/mail-sync.sh"
else
  printf '%s\n' "$ROOT_DIR" > "${RESOURCES_DIR}/RepoRoot.txt"
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" "$SWIFTC" \
  -O \
  -parse-as-library \
  -sdk "$SDKROOT" \
  -target "$TARGET" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework SwiftUI \
  "${ROOT_DIR}"/MenuBarApp/*.swift \
  -o "${MACOS_DIR}/aMail"

chmod +x "${MACOS_DIR}/aMail"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built ${APP_NAME}: ${APP_DIR}"
echo "Run it with:"
echo "  open '${APP_DIR}'"
