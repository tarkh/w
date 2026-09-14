#!/usr/bin/env bash
# graphics bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup graphics` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# Both bridges go unconditionally, PACK_PACKAGES or not: W put them into this
# account's home purely to wire the assistant to the editors, and with the
# mcp.d drop-ins gone nothing would launch them. The manifest rows (gimprc,
# mcpinkscape.conf) are class `user` — w-pack names them and leaves them, so a
# GIMP that keeps following the W theme after the pack is gone is by design.
# Data — images, SVGs, ~/Pictures/mcpinkscape — is never touched.
#
# Idempotent; best-effort. See pack-graphics.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"
PLUGIN_DIR="$USER_HOME/.config/GIMP/3.0/plug-ins/gimpmcp"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── Inkscape MCP server ──────────────────────────────────────────────────────
if [[ -x "$USER_HOME/.local/bin/mcpinkscape" ]]; then
  if command -v uv >/dev/null; then
    info "Removing mcpinkscape for $USER_NAME (uv tool uninstall)..."
    as_user uv tool uninstall mcpinkscape >/dev/null 2>&1 || warn "uv tool uninstall mcpinkscape failed"
  else
    warn "uv not found — cannot uninstall mcpinkscape; remove ~/.local/bin/mcpinkscape by hand"
  fi
fi
# Its private state (bridge socket dir, staged imports) is W-installed wiring, not documents.
rm -rf "$USER_HOME/.local/state/mcpinkscape"

# ── GIMP MCP bridge ──────────────────────────────────────────────────────────
if [[ -d "$PLUGIN_DIR" ]]; then
  info "Removing the GIMP MCP bridge for $USER_NAME ($PLUGIN_DIR)..."
  rm -rf "$PLUGIN_DIR"
fi

[[ -d "$USER_HOME/Pictures/mcpinkscape" ]] \
  && info "Kept (your documents): $USER_HOME/Pictures/mcpinkscape ($(du -sh "$USER_HOME/Pictures/mcpinkscape" 2>/dev/null | cut -f1))"
info "graphics user teardown complete for $USER_NAME."
exit 0
