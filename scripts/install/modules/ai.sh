# modules/ai.sh — W Linux OS AI integration (apply.sh --ai)
# apply.sh context: runs on the live system as root; post-boot only. Depends on
# --rootfs, which lays down the whole AI layer: the knowledge tree
# /usr/share/w/ai/ (AGENTS.md + skills), the MCP server
# /usr/bin/w-mcp, and the w-hyprwiki-update systemd units. This module adds
# only the runtime bits that generic rsync cannot: package deps, seeding the
# Hyprland wiki checkout, and arming its refresh timer.
#
# Phase 3: read-only MCP server (Tier 0) + knowledge-as-resources + the
# hyprland-wiki deploy/refresh. Phase 4: the host layer — Goose as the default
# host, the `w-ai` wrapper + /etc/w/ai.conf + host presets (all ride --rootfs),
# keyring-backed secrets (via gnome-keyring, already in W). Phase 5 (this): the
# Tier-1 safe/reversible tools (w_theme_set, w_memory_store) and the agent's
# cross-host memory — a SQLite FTS5 store over markdown facts, all inside w-mcp
# and needing no new package (FTS5 ships with the stdlib sqlite3). The memory
# lives per-user under ~/.local/state/w/ai/ and is created on first use, so this
# module installs nothing extra for it. Provider CLIs (claude-code/codex) and
# local runtimes (ollama, also the future opt-in embedding backend for semantic
# recall) stay opt-in — see their presets under /usr/share/w/ai/hosts/. Phase 6
# (this): Tier-2 privileged actuation — w-mcp's dns/firewall/fwupd/pacman/apply/run
# tools exec the root dispatcher /usr/lib/w/w-ai-actuate through pkexec + the
# com.w.ai.actuate polkit action (both ride --rootfs), so the polkit agent (w-authd) prompts
# and journald audits every privileged step; per-tool switches (W_AI_TOOL_*) live
# in ai.conf. See ai-integration.md for the roadmap.
#
#   python-mcp        — official MCP SDK; w-mcp runs on it (python itself is
#                     explicit in packages/base.txt, see modules/uv.sh).
#   git, tree         — skills/hyprland/install.sh clones the wiki + builds MAP.md.
#   goose (the `goose` binary) — the default host; installed from upstream's
#                     prebuilt CLI (the codename-goose-bin AUR package was removed
#                     when goose moved GitHub orgs to aaif-goose/goose), not pacman.
# Order in --all: late, after the subsystems the assistant introspects.

mod_ai() {
  info "Setting up W AI integration (knowledge + w-mcp)..."

  # The knowledge tree, w-mcp, w-ai, the Tier-2 dispatcher and its polkit action
  # all ride --rootfs. Guard so a standalone --ai before --rootfs fails loudly
  # instead of half-configuring.
  if [[ ! -d /usr/share/w/ai || ! -x /usr/bin/w-mcp || ! -x /usr/bin/w-ai ]]; then
    echo "  WARN: /usr/share/w/ai, w-mcp or w-ai missing — run 'apply.sh --rootfs' first."
    return
  fi
  # Tier-2 (phase 6): privileged actuation goes through pkexec + the
  # com.w.ai.actuate polkit action. Both files ship via --rootfs (polkit re-reads
  # its actions dir automatically, no daemon reload needed); warn if either is
  # absent so the reads/Tier-1 still work but Tier-2 fails closed with a clear hint.
  if [[ ! -x /usr/lib/w/w-ai-actuate || ! -f /usr/share/polkit-1/actions/com.w.ai.policy ]]; then
    echo "  WARN: Tier-2 dispatcher or polkit action missing — re-run 'apply.sh --rootfs'."
  fi

  w_pac -S --needed --noconfirm python-mcp git tree

  # Default host: Goose (single-binary, MCP-native). Upstream ships a prebuilt CLI
  # via an install script; install it system-wide to /usr/local/bin (root scope, so
  # every user gets it) and non-interactively (CONFIGURE=false — w-ai seeds the
  # per-user config on first run). Needs network on first run; non-fatal if offline
  # — the knowledge/MCP layers work standalone and goose can be added later with
  # 'apply.sh --ai'. Provider CLIs and local runtimes stay opt-in (see their presets).
  #
  # Run the piped upstream script under `env -u SHELLOPTS HOME=/root`: apply.sh's
  # `set -euo pipefail` is auto-exported via SHELLOPTS and would leak `-u` into this
  # child bash, and w-firstboot.service (root oneshot, no PAM session) sets no $HOME
  # — download_cli.sh reads $HOME with no default and would abort with "HOME: unbound
  # variable" before any network call. Stripping SHELLOPTS resets the child to
  # default options (the upstream script manages its own); HOME=/root gives it a
  # writable home (CONFIGURE=false + GOOSE_BIN_DIR keep it from writing config there).
  local goose_url=https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh
  if command -v goose >/dev/null 2>&1; then
    info "goose already installed ($(command -v goose)); skipping host install."
  else
    info "Installing default AI host (goose CLI, upstream)..."
    curl -fsSL "$goose_url" | env -u SHELLOPTS HOME=/root \
      GOOSE_BIN_DIR=/usr/local/bin CONFIGURE=false bash \
      || crit "goose install failed (offline?); add later with 'apply.sh --ai'. AI is a mandatory part of W, not optional — this must not happen where network is available (e.g. e2e)."
  fi

  # Seed the Hyprland wiki checkout once (clone + MAP.md). Needs network on first
  # run; the timer retries later, and install.sh keeps any existing checkout if a
  # refresh fails offline, so a miss here is non-fatal.
  local hyprwiki=/usr/share/w/ai/skills/hyprland/install.sh
  if [[ -x "$hyprwiki" ]]; then
    info "Seeding Hyprland wiki for the 'hyprland' skill..."
    "$hyprwiki" || echo "  WARN: wiki seed failed (offline?); the refresh timer will retry."
  fi

  # Arm the periodic system-scope refresh (root writes the checkout under /usr/share).
  if [[ -f /etc/systemd/system/w-hyprwiki-update.timer ]]; then
    systemctl enable w-hyprwiki-update.timer
  fi

  info "W AI ready. Knowledge: /usr/share/w/ai. MCP server: w-mcp (stdio)."
  info "Tools: Tier-0 reads + Tier-1 safe (theme, memory) + Tier-2 privileged"
  info "(dns/firewall/fwupd/pacman/apply/run) via polkit + journald audit. Tier-2"
  info "toggles: W_AI_TOOL_* in ai.conf (all on except w_run). Memory shared across"
  info "hosts (w-ai memory list). Launch: 'w-ai'. Key: 'w-ai key set openrouter'."
  info "Config: /etc/w/ai.conf (+ ~/.config/w/ai.conf)."
}
