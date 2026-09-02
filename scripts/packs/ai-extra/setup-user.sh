#!/usr/bin/env bash
# ai-extra bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup ai-extra` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Everything here belongs to ONE account. The machine half — Ollama, its model
# store, the service, python-numpy — is in setup.sh and is installed once.
#
# What is per-user and why: `uv tool install` puts its binaries in ~/.local/bin,
# so the search/extract provider chains in w-mcp's modules/web.py light up for
# the account that has them and for no one else. That is exactly the asymmetry
# that used to make `w-pack status` lie to a second administrator: the bundle was
# on the machine, their ddgs was not. Idempotent; best-effort. See pack-ai-extra.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root when invoked over
# sudo/ssh, or a service dir at firstboot) the target user cannot chdir there and
# any spawned child fails with EACCES before execve. Move to the user's own home so
# every as_user call runs from an accessible cwd.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── uv-managed web CLIs (ddgs, trafilatura) ──────────────────────────────────
# Lights up modules/web.py's search/extract provider chains without any config
# change — they auto-detect via _which() (PATH or ~/.local/bin fallback).
info "Installing ddgs + trafilatura for $USER_NAME (uv tool install)..."
if command -v uv >/dev/null; then
  as_user uv tool install ddgs || warn "uv tool install ddgs failed (offline? retry later)."
  as_user uv tool install trafilatura || warn "uv tool install trafilatura failed (offline? retry later)."
else
  warn "uv not found — install the 'uv' module first (apply.sh --uv). Skipping ddgs/trafilatura."
fi

# ── Offline verification ─────────────────────────────────────────────────────
# No network calls here — the tool installs above already tried, and their outcome
# does not gate the bundle (a machine may legitimately be offline right now).
info "Verifying the ai-extra user layer for $USER_NAME (offline)..."
[[ -x "$USER_HOME/.local/bin/ddgs" ]] && info "ddgs: OK" || warn "ddgs: not found in ~/.local/bin"
[[ -x "$USER_HOME/.local/bin/trafilatura" ]] && info "trafilatura: OK" || warn "trafilatura: not found in ~/.local/bin"

info "These live in the account's .local/bin, which joins PATH at the next login;"
info "w-mcp finds them right away — no relogin needed for the AI's web tools."
info "ai-extra user setup complete for $USER_NAME."
exit 0
