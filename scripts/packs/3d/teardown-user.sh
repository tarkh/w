#!/usr/bin/env bash
# 3d bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run by
# `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup 3d` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# Goes unconditionally, PACK_PACKAGES or not — all of it is W wiring:
#   * the uv tool and the add-on copies the W startup module made from it
#     (~/.config/blender/<ver>/scripts/addons/blender_mcp.py — recognised by
#     upstream's bl_info name, so a same-named file of other origin stays);
#   * the theme JSON the axis rendered, the W.xml presets, the module's state,
#     the session-shim links setup-user.sh made.
# What stays: Blender's userpref.blend keeps the last W colours as its current
# theme (Preferences → Themes → pick another preset), and every .blend file —
# the user's work — is never touched.
#
# Idempotent; best-effort. See pack-3d.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── Blender MCP server ───────────────────────────────────────────────────────
if [[ -x "$USER_HOME/.local/bin/mcp-for-blender" ]]; then
  if command -v uv >/dev/null; then
    info "Removing mcp-for-blender for $USER_NAME (uv tool uninstall)..."
    as_user uv tool uninstall mcp-for-blender >/dev/null 2>&1 || warn "uv tool uninstall mcp-for-blender failed"
  else
    warn "uv not found — cannot uninstall mcp-for-blender; remove ~/.local/bin/mcp-for-blender by hand"
  fi
fi

# ── What the W startup module wrote into Blender's per-version trees ─────────
for f in "$USER_HOME"/.config/blender/*/scripts/addons/blender_mcp.py; do
  [[ -f "$f" ]] && grep -q '"name": "MCP for Blender"' "$f" && rm -f "$f" && info "Removed $f"
done
rm -f "$USER_HOME"/.config/blender/*/scripts/presets/interface_theme/W.xml \
      "$USER_HOME"/.config/blender/*/scripts/startup/w_session_shim.py \
      "$USER_HOME/.config/w/blender-theme.json" "$USER_HOME/.local/state/w/blender.json"
# The data-sharing answer setup-user.sh pre-recorded — only while it is still W's.
consent="$USER_HOME/.config/blender-mcp/consent_prompt.json"
grep -q '"set_by": "w-pack 3d"' "$consent" 2>/dev/null && grep -q '"action": "decline"' "$consent" \
  && rm -f "$consent" && rmdir "$(dirname "$consent")" 2>/dev/null

info "Kept: your .blend files, and Blender's current theme (Preferences → Themes to change it)."
info "3d user teardown complete for $USER_NAME."
exit 0
