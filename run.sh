#!/usr/bin/env zsh
# run.sh — internal container launcher. Takes a ready-made workspace path plus
# any flags to pass through to `claude`, resolves the worktree's parent gitdir,
# and brings up the devcontainer. When the Claude session ends it tears the
# container back down (unless -k/--keep) so they don't accumulate. Workspace/
# worktree management lives in bin/claude-sandbox; this layer knows nothing
# about worktrees.
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REBUILD=0
KEEP=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    --rebuild|-r) REBUILD=1 ;;
    --keep|-k)    KEEP=1 ;;
    *) break ;;
  esac
  shift
done
CLONE="${1:?usage: run.sh [-r|--rebuild] [-k|--keep] /path/to/clone [claude flags...]}"
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

# Tear down this run's container when the Claude session ends — normal exit,
# Ctrl-C, or error. `devcontainer up` leaves the container running after `exec`
# returns, so without this they accumulate across sessions. The devcontainer CLI
# labels each container with its workspace path, so we remove only this run's
# container; the shared claude-sandbox-config volume is untouched. Opt out with
# -k/--keep to leave it running (e.g. to `docker exec` in and inspect afterwards).
if [[ "$KEEP" == 0 ]]; then
  cleanup() {
    local cids
    cids=$(docker ps -aq --filter "label=devcontainer.local_folder=$CLONE" 2>/dev/null) || true
    [[ -n "$cids" ]] && docker rm -f ${=cids} >/dev/null 2>&1 || true
  }
  trap cleanup EXIT
  trap 'exit 130' INT TERM
fi

devcontainer exec --workspace-folder "$CLONE" --config "$CONFIG" claude --dangerously-skip-permissions "${CLAUDE_ARGS[@]}"