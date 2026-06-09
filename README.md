# Claude Code Sandbox

A portable devcontainer setup for running Claude Code in YOLO mode
(`--dangerously-skip-permissions`) against an **isolated copy** of a project,
behind a **default-deny firewall**. It isolates the agent from your host filesystem
and the open internet, reducing the blast radius to a contained workspace plus a
short allowlist of domains. The recommended isolation strategy is a git worktree
(`--worktree`), though a manual clone works too.

## Repo contents

- `run.sh` — one-command launcher: builds/starts the container and drops you into Claude Code.
- `.devcontainer/devcontainer.json` — container definition (network caps, mounts, env, firewall hook).
- `.devcontainer/Dockerfile` — Node + Python (via `uv`) + Rust toolchains. Multi-arch (Intel and Apple Silicon).
- `.devcontainer/init-firewall.sh` — default-deny egress firewall; allowlists only the registries the toolchains need.
- `.env` — **not committed.** Holds your auth token. Recreated per machine (see setup).
- `.gitignore` — keeps `.env` out of version control.

## Prerequisites (per machine)

- macOS, Intel **or** Apple Silicon — the image is multi-arch, so no edits are needed for either. A new machine just rebuilds the image from scratch the first time (slow once, cached after).
- Docker Desktop, installed and running. Verify with `docker info` (this checks the daemon, not just the CLI).
- Node.js, plus the devcontainer CLI: `npm install -g @devcontainers/cli`
- Claude Code on the host: `npm install -g @anthropic-ai/claude-code` — needed only to mint the token in step 2.
- An active Claude Pro/Max subscription (the token bills against it).

## First-time setup on a new machine

1. **Clone this repo.** Either clone it to `~/claude-sandbox`, or use the self-locating `run.sh` (see "Portability" below) so it can live anywhere.

2. **Mint a long-lived, subscription-billed token:**
   ```
   claude setup-token
   ```
   Copy the `sk-ant-oat01-...` value it prints — it is not saved anywhere else.

3. **Create `.env`** in the repo root (this file is gitignored — never commit it):
   ```
   export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...your token...
   ```
   ```
   chmod 600 .env
   ```

4. **Make the launcher executable:**
   ```
   chmod +x run.sh
   ```

5. **Verify prerequisites:** `docker info` and `devcontainer --version` should both succeed.

## Usage (per project)

`run.sh` takes a workspace path followed by any flags to pass through to `claude`:

```
~/claude-sandbox/run.sh [--rebuild|-r] /path/to/workspace [claude flags...]
```

### Recommended: git worktrees

Pass `--worktree [name]` to have Claude create an isolated git worktree automatically.
The worktree gets its own branch, shares history with your real repo, and can be
reviewed and merged normally when the session ends.

```
# From inside your project directory:
~/claude-sandbox/run.sh "$(pwd)" --worktree feature-auth

# Omit the name for an auto-generated one (e.g. bright-running-fox):
~/claude-sandbox/run.sh "$(pwd)" --worktree
```

By default, worktrees land in `.claude/worktrees/` inside your project. To redirect
them to a global location (e.g. `~/claude-worktrees/<repo>/<name>`), add a
`WorktreeCreate` hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'NAME=$(jq -r .name); REPO=$(basename $(git rev-parse --show-toplevel)); DIR=\"$HOME/claude-worktrees/$REPO/$NAME\"; mkdir -p \"$HOME/claude-worktrees/$REPO\" >&2 && git worktree add \"$DIR\" -b \"worktree-$NAME\" >&2 && echo \"$DIR\"'"
          }
        ]
      }
    ]
  }
}
```

### Shell wrapper example

A shell function in your profile can hide the path boilerplate. The `claude-sandbox` function
below runs the sandbox against the current directory, forwarding `-b <name>` as the
worktree name and `--rebuild`/`-r` to force a fresh container image:

```zsh
claude-sandbox() {
    local rebuild_flag=""
    local branch_name=""
    local other_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rebuild|-r)
                rebuild_flag="--rebuild"
                ;;
            -b)
                shift
                branch_name="$1"
                ;;
            *)
                other_args+=("$1")
                ;;
        esac
        shift
    done

    local worktree_args=("--worktree")
    [[ -n "$branch_name" ]] && worktree_args+=("$branch_name")

    ~/claude-sandbox/run.sh $rebuild_flag "$(pwd)" "${worktree_args[@]}" "${other_args[@]}"
}
```

```
# Auto-named worktree from current directory:
claude-sandbox

# Named worktree:
claude-sandbox -b feature-auth

# Rebuild the container image first:
claude-sandbox -r -b feature-auth
```

### Alternative: manual clone

If you prefer full control over the isolated copy, clone the repo yourself and pass
the clone path directly — no `--worktree` needed:

```
git clone ~/code/projects/myproject ~/code/projects/myproject-sandbox
cd ~/code/projects/myproject-sandbox && git switch -c sandbox/attempt-1
~/claude-sandbox/run.sh ~/code/projects/myproject-sandbox
```

Pull the work back from your real repo once done:

```
cd ~/code/projects/myproject
git fetch ~/code/projects/myproject-sandbox sandbox/attempt-1:sandbox/attempt-1
git diff main..sandbox/attempt-1
git merge sandbox/attempt-1
```


## Notes: why these files diverge from Anthropic's reference

These are hard-won fixes. If you ever re-pull the upstream `.devcontainer` to take
updates, re-apply them or you'll reintroduce the bugs:

- **Token in `containerEnv`, not `remoteEnv`.** `remoteEnv` is not reliably injected
  by a bare `devcontainer exec`; `containerEnv` is, and every exec inherits it.
  Confirm with `/status` inside Claude Code — the **Auth token** field should read
  `CLAUDE_CODE_OAUTH_TOKEN` (subscription billing). **Never set `ANTHROPIC_API_KEY`**
  anywhere in the chain — it silently takes precedence and switches you to
  pay-per-token API billing.
- **`ipset add -exist`** in the firewall, so CDN-shared IPs (e.g. `pypi.org` and
  `files.pythonhosted.org`, both on Fastly) don't abort the fail-closed script when
  the second domain re-adds an IP the first already added.
- **Telemetry domains removed** from the firewall allowlist (`statsig.anthropic.com`
  et al.). `statsig.anthropic.com` doesn't resolve, which would abort the script, and
  telemetry is disabled via `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` anyway.
- **No comments inside the firewall's `for domain in \ ...` list.** A `#` inside a
  backslash-continued list silently truncates the list and breaks parsing. Keep
  annotations out of that loop (or convert it to a bash array, where comments are legal).
- **System Python for `uv`** (`UV_PYTHON_DOWNLOADS=never`,
  `UV_PYTHON_PREFERENCE=only-system`), so `uv` never tries to fetch a standalone
  interpreter from the GitHub release-asset CDN, which the firewall doesn't allow.
- **Single mount at `/home/node/.claude`** (`claude-sandbox-config`). Two volumes at
  one target fails container creation; the stable-named volume persists trust and
  session state across rebuilds and across different project clones.

## First launch on a fresh machine

The named Docker volumes (`claude-sandbox-config`, command history) start empty, so
the first build runs from scratch (no cache) and Claude Code will ask you to trust
`/workspace` once. After that, trust and config persist.