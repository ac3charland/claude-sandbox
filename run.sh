#!/usr/bin/env zsh
# run.sh — internal container launcher. Takes a ready-made workspace path plus
# any flags to pass through to `claude`, resolves the worktree's parent gitdir,
# and brings up the devcontainer. Workspace/worktree management lives in
# bin/claude-sandbox; this layer knows nothing about worktrees.
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

# When the workspace is a git worktree, its .git file points back to the parent
# repo at an absolute host path. Mount the parent repo at that same path inside
# the container so git can resolve the gitdir reference. The workspace itself is
# also mounted at its identical host path (see devcontainer.json), so the parent's
# back-link (worktrees/<name>/gitdir -> worktree/.git) resolves too.
# For a plain checkout, fall back to the clone itself (harmless duplicate mount).
if [[ -f "$CLONE/.git" ]] && grep -q "^gitdir:" "$CLONE/.git" 2>/dev/null; then
  GITDIR=$(sed 's/^gitdir: //' "$CLONE/.git" | tr -d '[:space:]')
  [[ "$GITDIR" != /* ]] && GITDIR="$(cd "$CLONE/$(dirname "$GITDIR")" && pwd)/$(basename "$GITDIR")"
  export PARENT_REPO_GIT_DIR="$(cd "$GITDIR/../../.." && pwd)/.git"
else
  export PARENT_REPO_GIT_DIR="$CLONE/.git"
fi

devcontainer up   --workspace-folder "$CLONE" --config "$CONFIG" ${REBUILD:+--remove-existing-container}
devcontainer exec --workspace-folder "$CLONE" --config "$CONFIG" claude --dangerously-skip-permissions "${CLAUDE_ARGS[@]}"