#!/usr/bin/env bash
# ai-extra bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup ai-extra` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# The uv tools go unconditionally, PACK_PACKAGES or not. They are not the user's
# software in the sense pacman packages are: `uv tool install ddgs` was run by W,
# into this account's ~/.local/bin, purely to light up w-mcp's provider chains.
# Nothing else on the machine refers to them, and leaving them behind would keep
# the AI's web tools reporting a capability the bundle no longer backs.
#
# Idempotent; best-effort. See pack-ai-extra.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; a root-only one (e.g. /root over sudo/ssh) makes every
# spawned child fail with EACCES before execve.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── uv-managed web CLIs ──────────────────────────────────────────────────────
if command -v uv >/dev/null; then
  for t in ddgs trafilatura; do
    [[ -x "$USER_HOME/.local/bin/$t" ]] || continue
    info "Removing $t for $USER_NAME (uv tool uninstall)..."
    as_user uv tool uninstall "$t" >/dev/null 2>&1 || warn "uv tool uninstall $t failed"
  done
else
  warn "uv not found — cannot uninstall ddgs/trafilatura; remove them by hand if present"
fi

info "w-mcp's web tools fall back to their built-in providers from the next call."
info "ai-extra user teardown complete for $USER_NAME."
exit 0
