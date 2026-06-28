#!/bin/bash
# SessionStart hook for Claude Code on the web: installs everything needed to run
# this Godot project's GUT test suite (and regenerate sheet-driven content) in a
# fresh remote container. GUT itself is vendored in addons/gut/, so the only real
# dependency is the Godot engine binary plus openpyxl for the tools/ generators.
#
# Synchronous on purpose: the session waits until deps are ready, so the first
# `godot --headless -s addons/gut/gut_cmdln.gd` can't race the install.
set -euo pipefail

# The engine ships on local dev machines — only fetch it in the remote env.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GODOT_VERSION="4.6-stable"                       # matches project.godot config/features
GODOT_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
INSTALL_DIR="$HOME/.local/godot"
GODOT_BIN="$INSTALL_DIR/godot"

# 1) Python deps for the sheet-driven content generators (tools/*.py use openpyxl).
python3 -m pip install --quiet openpyxl >&2 2>/dev/null || \
  python3 -m pip install --quiet --user openpyxl >&2 2>/dev/null || \
  echo "warning: openpyxl install failed (content generators may not run)" >&2

# 2) Godot engine — the GUT test runner. Idempotent: skip if already installed.
if [ ! -x "$GODOT_BIN" ]; then
  echo "Installing Godot ${GODOT_VERSION}..." >&2
  mkdir -p "$INSTALL_DIR"
  tmp="$(mktemp -d)"
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_NAME}.zip"
  curl -fsSL -o "$tmp/godot.zip" "$url"
  unzip -q -o "$tmp/godot.zip" -d "$tmp"
  mv "$tmp/${GODOT_NAME}" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  rm -rf "$tmp"
fi

# 3) Expose godot on PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  echo "export GODOT_BIN=\"$GODOT_BIN\"" >> "$CLAUDE_ENV_FILE"
fi

# 4) Warm the import cache so the first headless test run doesn't pay the asset
#    import pass. Best-effort + time-capped: the cache rebuilds lazily otherwise.
timeout 300 "$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >&2 2>&1 || true

echo "Godot ready: $GODOT_BIN" >&2
