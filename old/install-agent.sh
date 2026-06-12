#!/usr/bin/env bash
# Install/reload the launchd agent so the rotator runs whenever you're logged in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LABEL="com.archive-mail.legacy-mbsync-rotate"
SRC="${SCRIPT_DIR}/${LABEL}.plist"
DST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

mkdir -p "${HOME}/Library/LaunchAgents"
cp "$SRC" "$DST"

# Bootout if loaded, then bootstrap. Ignore bootout error on first install.
launchctl bootout "gui/$(id -u)" "$DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DST"
launchctl enable "gui/$(id -u)/${LABEL}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "Installed and started ${LABEL}."
echo "Logs:"
echo "  summary : ${PROJECT_DIR}/logs/mbsync-rotate.log"
echo "  verbose : ${PROJECT_DIR}/logs/mbsync-rotate.verbose.log"
echo "  stderr  : ${PROJECT_DIR}/logs/launchd.stderr.log"
echo "Stop: launchctl bootout gui/$(id -u) ${DST}"
