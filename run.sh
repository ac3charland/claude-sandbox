#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
CLONE="${1:?usage: run.sh /path/to/clone}"
CONFIG="$SCRIPT_DIR/.devcontainer/devcontainer.json"
set -a; source "$SCRIPT_DIR/.env"; set +a
devcontainer up   --workspace-folder "$CLONE" --config "$CONFIG"
devcontainer exec --workspace-folder "$CLONE" --config "$CONFIG" claude --dangerously-skip-permissions