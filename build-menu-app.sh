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
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
TARGET="${TARGET:-${ARCH}-apple-macosx${MACOSX_DEPLOYMENT_TARGET}}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

cp "${ROOT_DIR}/MenuBarApp/Info.plist" "${CONTENTS_DIR}/Info.plist"
printf '%s\n' "$ROOT_DIR" > "${RESOURCES_DIR}/RepoRoot.txt"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" "$SWIFTC" \
  -O \
  -parse-as-library \
  -sdk "$SDKROOT" \
  -target "$TARGET" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  "${ROOT_DIR}/MenuBarApp/AMailApp.swift" \
  -o "${MACOS_DIR}/aMail"

chmod +x "${MACOS_DIR}/aMail"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built ${APP_NAME}: ${APP_DIR}"
echo "Run it with:"
echo "  open '${APP_DIR}'"
