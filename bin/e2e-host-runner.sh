#!/bin/bash
# e2e-host-runner.sh — restricted SSH forced-command target for sandbox iOS e2e
# delegation.
#
# Installed on the macOS host by bin/setup-e2e-delegation and pinned as the
# command="" of the dedicated key in ~/.ssh/authorized_keys. A sandbox container
# connecting with that key can therefore ONLY trigger an iOS e2e run in one of
# its own git worktrees — never get an arbitrary shell on the host.
#
# Protocol: the container sends a base64 blob as the SSH command (SSH_ORIGINAL_
# COMMAND). Decoded, it is newline-delimited: line 1 = worktree path, the rest =
# args for scripts/e2e-ios.sh. We reconstruct the call WITHOUT eval, so the blob
# cannot smuggle shell commands even if the key leaks.
#
# bash 3.2 compatible (the macOS system bash).
set -eo pipefail

reject() { echo "e2e-host-runner: $1" >&2; exit 1; }

PAYLOAD_B64="${SSH_ORIGINAL_COMMAND:-}"
[ -n "$PAYLOAD_B64" ] || reject "no payload (this key only runs the e2e delegation)"

# Reject anything that isn't pure base64 — a real shell command never is.
case "$PAYLOAD_B64" in
  *[!A-Za-z0-9+/=]*) reject "payload is not base64" ;;
esac

# macOS base64 decodes with -D; GNU coreutils with -d. Try both.
PAYLOAD="$(printf '%s' "$PAYLOAD_B64" | base64 -D 2>/dev/null)" \
  || PAYLOAD="$(printf '%s' "$PAYLOAD_B64" | base64 -d 2>/dev/null)" \
  || reject "could not decode payload"

# Line 1 = worktree path; remaining non-empty lines = e2e args.
i=0
TARGET=""
args=()
while IFS= read -r line; do
  if [ "$i" -eq 0 ]; then TARGET="$line"; i=1; continue; fi
  [ -n "$line" ] && args+=("$line")
done <<EOF
$PAYLOAD
EOF

[ -n "$TARGET" ] || reject "empty target path"

# Canonicalize and confine to ~/claude-worktrees (defeats ../ escapes and any
# attempt to run the e2e script from outside a sandbox worktree).
TARGET_REAL="$(cd "$TARGET" 2>/dev/null && pwd -P)" || reject "not a directory: $TARGET"
case "$TARGET_REAL/" in
  "$HOME/claude-worktrees/"*) ;;
  *) reject "target outside ~/claude-worktrees: $TARGET_REAL" ;;
esac
[ -x "$TARGET_REAL/scripts/e2e-ios.sh" ] || reject "no scripts/e2e-ios.sh under $TARGET_REAL"

# SSH non-login shells don't load nvm / Homebrew. The e2e script puts Maestro and
# Java on PATH itself; we add node (nvm) and brew so prebuild/pod/xcodebuild work.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1090
  . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
fi

cd "$TARGET_REAL"
exec ./scripts/e2e-ios.sh ${args[@]+"${args[@]}"}
