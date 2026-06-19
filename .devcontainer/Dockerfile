# Ubuntu Noble (24.04) base — NOT the Debian-based `node` image — because Storybook
# image-snapshot suites render here natively (SNAPSHOT_NATIVE=1, see devcontainer.json)
# and their committed baselines are produced on Ubuntu Noble. Noble's font/freetype stack
# rasterises text at a different advance width than Debian bookworm's, so a Debian base
# diverges from the baselines by whole pixels (verified: 19/34 snapshots fail on size).
# Noble + `playwright install --with-deps` matches them exactly. The trade-off vs the `node`
# image is paid below: Node, curl/wget, and build tools must be added explicitly, and Ubuntu's
# default uid-1000 `ubuntu` user is replaced with `node`.
FROM ubuntu:24.04

# Build-only: silence apt's interactive prompts (e.g. tzdata) without persisting to the image.
ARG DEBIAN_FRONTEND=noninteractive

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset. Unlike the `node`/buildpack-deps base,
# bare Ubuntu ships none of ca-certificates/curl/wget/gnupg or a C toolchain, so add them:
# curl/wget are used below (NodeSource, git-delta, rustup, zsh-in-docker) and build-essential
# backs runtime `cargo build` and native npm/python builds. `gh` lives in Ubuntu universe
# (enabled by default on this image), same as on the old base.
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  wget \
  gnupg2 \
  build-essential \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Node 24 — Ubuntu's repos carry only Node 18, so install from NodeSource. This is a
# build-time fetch (before the runtime firewall exists), so deb.nodesource.com needn't be
# allowlisted.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG USERNAME=node

# Ubuntu 24.04 ships a default `ubuntu` user holding uid/gid 1000. Replace it with `node` at
# the same ids so the rest of this Dockerfile (and bind-mounted file ownership) is unchanged
# from the old `node`-image base.
RUN userdel -r ubuntu 2>/dev/null || true; \
  groupadd --gid 1000 "$USERNAME" && \
  useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash "$USERNAME"

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspaces /home/node/.claude && \
  chown -R node:node /workspaces /home/node/.claude

WORKDIR /workspaces

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Python via uv: grab the uv binary from Astral's official image (build-time pull,
# not subject to the runtime firewall), and bake a system Python for uv to use.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON_PREFERENCE=only-system

# Playwright with Chromium. The browser and its OS dependencies are baked in at
# build time as the fast, offline path for the version installed here, in a
# shared location any project's Playwright can find. A project pinning a
# different Playwright version will miss this cache and download its matching
# browser at runtime, which is why cdn.playwright.dev is allowlisted in the
# firewall.
#
# `--with-deps` is load-bearing for Storybook image-snapshot suites, NOT just
# E2E: it apt-installs the same font packages (fonts-liberation, the Noto set,
# …) the pinned `mcr.microsoft.com/playwright:v*-noble` image carries, so text
# renders at identical width here. That lets projects render snapshots NATIVELY
# in this container instead of nesting Docker (SNAPSHOT_NATIVE=1, see
# devcontainer.json). Dropping `--with-deps` would silently break that pixel
# match — keep it.
ARG PLAYWRIGHT_VERSION=latest
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx --yes playwright@${PLAYWRIGHT_VERSION} install --with-deps chromium \
  && chmod -R a+rX /ms-playwright \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Rust toolchain, installed into the node user's home
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable
ENV PATH="/home/node/.cargo/bin:${PATH}"

# Configure git credential helper to use GITHUB_TOKEN for HTTPS pushes
RUN git config --global credential.https://github.com.helper '!f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f'

# Rewrite SSH remotes to HTTPS so token auth is used inside the container.
# Host config is untouched, so host git keeps using SSH.
RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

# Sandbox self-description, baked into the image. The persistent
# /home/node/.claude volume would shadow anything written there at build time,
# so postStartCommand copies this into ~/.claude/CLAUDE.md on each container start.
COPY sandbox-CLAUDE.md /usr/local/share/claude-sandbox/CLAUDE.md

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
