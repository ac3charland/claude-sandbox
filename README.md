# Claude Code Sandbox

A portable devcontainer setup for running Claude Code in YOLO mode
(`--dangerously-skip-permissions`) against a **disposable clone** of a project,
behind a **default-deny firewall**. It isolates the agent from your real repos,
your host filesystem, and the open internet, reducing the blast radius to a
throwaway code copy plus a short allowlist of domains.

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

`run.sh` expects a disposable **clone** as its argument — never your real repo, or
the agent gets direct write access to your real working tree.

```
# Once per project: make the throwaway clone + a working branch
git clone ~/code/projects/myproject ~/code/projects/myproject-sandbox
cd ~/code/projects/myproject-sandbox && git switch -c sandbox/attempt-1

# Launch the sandbox against the CLONE
~/claude-sandbox/run.sh ~/code/projects/myproject-sandbox
```

Pull the agent's work back, reviewed and reversible, from your **real** repo:

```
cd ~/code/projects/myproject
git fetch ~/code/projects/myproject-sandbox sandbox/attempt-1:sandbox/attempt-1
git diff main..sandbox/attempt-1     # review everything it touched
git merge sandbox/attempt-1          # accept wholesale, or cherry-pick specific commits
```

To throw an experiment away, just delete the clone directory — nothing leaves it
unless you explicitly merge.


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