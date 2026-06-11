# Sandbox environment

You are running inside the **claude-sandbox devcontainer**: Claude Code in YOLO
mode (`--dangerously-skip-permissions`) working on an **isolated git worktree**
of a project, behind a **default-deny egress firewall**. The point of the
sandbox is to keep the blast radius small — this workspace plus a short
allowlist of network destinations — not your real machine or the open internet.

This file lives in `~/.claude` (`/home/node/.claude`), a **persistent Docker
volume** shared across container rebuilds and across *every* project run through
the sandbox. That is why it is global memory: it describes the sandbox wrapper,
which is the same no matter which project is mounted.

## Where you are

- User `node`, home `/home/node`, default shell `zsh`, `DEVCONTAINER=true`.
- The project you're working on is mounted at `/workspaces/<project>`. It is an
  **isolated worktree on its own branch (`worktree-<name>`)** — *not* the user's
  real working tree, which is never mounted. Commit and push to share work; the
  human reviews and merges it back on the host afterwards.
- Command history persists at `/commandhistory`.

## Network — default-deny firewall

A fail-closed firewall (`init-firewall.sh`) is applied at **every** container
start. Outbound traffic is **DROP by default**; only these are reachable:

- GitHub (web / api / git IP ranges, fetched from `api.github.com/meta`)
- `api.anthropic.com`
- `registry.npmjs.org`
- `pypi.org`, `files.pythonhosted.org`
- `crates.io`, `static.crates.io`, `index.crates.io`
- VS Code: `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`,
  `update.code.visualstudio.com`
- DNS, SSH, localhost, and the host LAN (`/24`)

Everything else is **REJECTed immediately** (`icmp-admin-prohibited`). A blocked
request therefore **fails fast — it is not a flaky connection.** Do not retry it
in a loop; it will not start working.

Consequences to expect:

- Arbitrary `curl` / downloads to non-allowlisted hosts fail by design.
- **GitHub release-asset downloads** (e.g. `objects.githubusercontent.com`) are
  *not* covered by the allowlisted GitHub ranges. This is why `uv` is pinned to
  the system Python (`UV_PYTHON_DOWNLOADS=never`) and never fetches a standalone
  interpreter.
- Telemetry is disabled and deliberately not allowlisted
  (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`).

## Toolchains (already installed — don't fetch new runtimes)

Node 24 + npm (global prefix `/usr/local/share/npm-global`), Python via **`uv`**
(system Python only), Rust (`rustup` stable), plus `gh`, `git` (+ `delta`),
`jq`, `fzf`, `vim`/`nano`. Install packages only from the allowlisted registries
above.

## Auth & git

- Claude Code is authenticated with `CLAUDE_CODE_OAUTH_TOKEN` (subscription
  billing). **Never set `ANTHROPIC_API_KEY`** — it silently takes precedence and
  switches to pay-per-token API billing.
- `git` and `gh` use `GITHUB_TOKEN` / `GH_TOKEN` (a fine-grained PAT supplied
  from the host `.env`). HTTPS pushes and `gh pr create` work **only if** that
  token was provided and scoped to the repo; SSH GitHub remotes are
  auto-rewritten to HTTPS so the token is used.
- Secrets live in the host's `.env` (gitignored). **Never commit tokens or echo
  them.**
- The auto-updater is disabled for reproducible builds; the Claude Code version
  is pinned at image build time.

## If the sandbox blocks you and you think it's wrong

If you hit a limitation that comes from the sandbox — a blocked domain, a
missing tool, a denied network or permission — and you believe the restriction
is **mistaken or shouldn't apply to this task**:

- **Do NOT engineer a workaround.** No alternate hosts, mirrors, proxies, or
  tunnels; no disabling or editing the firewall; no re-routing to dodge the
  policy; no silent retry loops.
- **Surface it to the user.** Say plainly what you hit, what you were trying to
  do, and why you think the limit is wrong or misconfigured.
- **Solve it together.** The real fix is usually a deliberate config change —
  the firewall allowlist (`.devcontainer/init-firewall.sh`), the host `.env`, or
  the devcontainer definition — and those are the user's to make.

Working *within* an expected constraint (e.g. work isn't shared until you push)
is normal. This rule is for the cases where the sandbox seems to be getting in
the way incorrectly — raise those instead of hacking past them.
