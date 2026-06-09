#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REBUILD=0
if [[ "${1:-}" == "--rebuild" || "${1:-}" == "-r" ]]; then
  REBUILD=1
  shift
fi
CLONE="${1:?usage: run.sh [-r|--rebuild] /path/to/clone [claude flags...]}"
shift
CLAUDE_ARGS=("$@")
CONFIG="$SCRIPT_DIR/.devcontainer/devcontainer.json"
set -a; source "$SCRIPT_DIR/.env"; set +a
devcontainer up   --workspace-folder "$CLONE" --config "$CONFIG" ${REBUILD:+--remove-existing-container}
devcontainer exec --workspace-folder "$CLONE" --config "$CONFIG" claude --dangerously-skip-permissions "${CLAUDE_ARGS[@]}"