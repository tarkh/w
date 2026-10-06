#!/usr/bin/env bash
# 3d bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup 3d` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# 1. The blender w-style axis for this account — w-pack rendered it as root
#    into /etc/skel only (future accounts).
# 2. mcp-for-blender — `uv tool install` into ~/.local/bin, pinned (it runs
#    model-written code inside Blender; an upgrade is a reviewed W change, not
#    whatever PyPI serves today). The mcp.d drop-in the machine layer registered
#    becomes active for this account the moment the binary exists. Its Blender
#    half (the add-on) is NOT installed here: the W startup module copies it
#    from this tool into whichever Blender version runs, and enables it.
# 3. The session shim, linked into the startup folder of the installed Blender
#    version: BLENDER_SYSTEM_SCRIPTS (env.d) reaches apps only from the next
#    login — the launcher starts them in its own, older environment (uwsm app
#    = a scope, not the user manager's env) — and the shim bridges exactly that
#    gap, so the very first Blender launch is already W-themed with the bridge
#    on. Inert once the variable is there (session-shim.py).
#
# Network is expected (PyPI) and may legitimately be absent; each step degrades
# with a named warning and the retry command. Idempotent; best-effort.
# See pack-3d.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

MCP_PKG="mcp-for-blender==2.1.3"
SHIM="/usr/share/w/blender/session-shim.py"

# runuser inherits our cwd; move to one the account can read (packs.md).
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
# HOME is passed explicitly — runuser keeps the caller's environment, and uv
# would otherwise install the tool into /root/.local/bin.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Blender theme for this account ────────────────────────────────────────
if command -v w-style >/dev/null; then
  as_user w-style apply blender >/dev/null \
    || warn "w-style apply blender failed (renders at next login instead)."
fi

# ── 2. Blender MCP server (uv tool, pinned) ──────────────────────────────────
if command -v uv >/dev/null; then
  info "Installing $MCP_PKG for $USER_NAME (uv tool install)..."
  as_user uv tool install --quiet "$MCP_PKG" \
    || warn "uv tool install $MCP_PKG failed (offline? retry: w-pack setup 3d)"
else
  warn "uv not found — install the 'uv' module first (apply.sh --uv). Skipping the Blender MCP server."
fi
# Its first-run "contribute session data?" question is NOT covered by
# DISABLE_TELEMETRY (the drop-in's env): the server asks through MCP
# elicitation, which pops up mid-task in the user's assistant. W answers it
# the privacy way in advance — the answer upstream would record for "no", plus
# a marker for teardown — and only when no answer exists yet; opting in stays
# a checkbox in Blender (Preferences → Add-ons → Blender MCP). The version
# matches the pinned release's CONSENT_PROMPT_VERSION: a re-ask upstream
# decides on after an upgrade is theirs to make.
consent="$USER_HOME/.config/blender-mcp/consent_prompt.json"
if [[ ! -e "$consent" ]]; then
  as_user install -d "$(dirname "$consent")" \
    && printf '{"action": "decline", "prompt_version": 2, "set_by": "w-pack 3d"}\n' \
      | as_user tee "$consent" >/dev/null \
    || warn "could not pre-answer the Blender MCP data-sharing question (it will ask once)."
fi

# ── 3. Session shim for the installed Blender version ────────────────────────
# Blender's per-user tree is ~/.config/blender/<major.minor>/ — read the
# version from pacman (epoch:M.m.p-rel), not from a Blender start.
ver="$(pacman -Q blender 2>/dev/null | sed -E 's/^blender ([0-9]+:)?([0-9]+\.[0-9]+).*/\2/')"
if [[ "$ver" =~ ^[0-9]+\.[0-9]+$ ]]; then
  startup="$USER_HOME/.config/blender/$ver/scripts/startup"
  as_user install -d "$startup" && as_user ln -sfn "$SHIM" "$startup/w_session_shim.py" \
    || warn "could not link the session shim — Blender gets the W integration from the next login."
fi

# ── Offline verification ─────────────────────────────────────────────────────
info "Verifying the 3d user layer for $USER_NAME (offline)..."
[[ -x "$USER_HOME/.local/bin/mcp-for-blender" ]] && info "mcp-for-blender: OK" \
  || warn "mcp-for-blender: not found in ~/.local/bin"
[[ -f "$USER_HOME/.config/w/blender-theme.json" ]] && info "Blender W theme: OK" \
  || warn "Blender W theme: not rendered yet (renders at next login)"

info "The AI assistant (w-ai) sees the Blender server from its next launch; the"
info "bridge answers while Blender runs (its add-on listens on localhost:9876)."
info "3d user setup complete for $USER_NAME."
exit 0
