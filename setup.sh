#!/usr/bin/env bash
# setup.sh — put the `claude-sandbox` command on your PATH.
#
# Idempotent: appends a single PATH line to your shell rc, guarded by a marker
# so re-running does nothing. Works from wherever the repo is cloned.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$REPO_DIR/bin"
MARKER="# claude-sandbox PATH"
LINE="export PATH=\"$BIN_DIR:\$PATH\"  $MARKER"

# Pick the rc file for the user's login shell.
shell_name="$(basename "${SHELL:-}")"
case "$shell_name" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    *)    RC="${RC:-$HOME/.profile}" ;;
esac

chmod +x "$BIN_DIR/claude-sandbox" "$REPO_DIR/run.sh" 2>/dev/null || true

if [[ -f "$RC" ]] && grep -qF "$MARKER" "$RC"; then
    echo "setup: already installed in $RC — nothing to do."
else
    printf '\n%s\n' "$LINE" >> "$RC"
    echo "setup: added claude-sandbox to PATH in $RC"
fi

echo "setup: open a new shell (or 'source $RC'), then run: claude-sandbox -h"
echo "setup: tip — alias it to taste, e.g.  alias claudey='claude-sandbox'"
