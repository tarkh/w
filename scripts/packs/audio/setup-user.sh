#!/usr/bin/env bash
# audio bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup audio` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# 1. Membership in `realtime` (realtime-privileges: rtprio 98, unlimited
#    memlock) — what lets Ardour's and PipeWire-JACK's audio threads run at
#    realtime priority, i.e. small buffers without xruns. Root's call (gpasswd
#    edits /etc/group), effective from the next login.
# 2. The ardour and audacity w-style axes for this account — w-pack rendered
#    them as root into /etc/skel only (future accounts).
# 3. An Ardour that ran before the pack keeps its own ui_config (the manifest
#    seeds only when absent), so the W theme is selected in it — but only over
#    Ardour's stock choice (no color-file, or "dark"); a theme the user picked
#    is theirs.
#
# Idempotent; best-effort. See pack-audio.md.

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

# ── 1. Group `realtime` ──────────────────────────────────────────────────────
if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx realtime; then
  info "$USER_NAME is already in group 'realtime'."
elif [[ "$AS_ROOT" == 1 ]]; then
  gpasswd -a "$USER_NAME" realtime >/dev/null \
    && info "$USER_NAME added to group 'realtime' (realtime audio from the next login)." \
    || warn "gpasswd -a $USER_NAME realtime failed."
else
  warn "$USER_NAME is not in group 'realtime'. Only an administrator can add it:"
  warn "    sudo gpasswd -a $USER_NAME realtime"
  warn "  then log out and back in (group membership applies at login)."
fi

# ── 2. Theme axes for this account ───────────────────────────────────────────
if command -v w-style >/dev/null; then
  as_user w-style apply ardour >/dev/null || warn "w-style apply ardour failed (renders at next login instead)."
  as_user w-style apply audacity >/dev/null || warn "w-style apply audacity failed (renders at next login instead)."
fi

# ── 3. Select the W theme in an Ardour config that predates the pack ─────────
ui="$USER_HOME/.config/ardour9/ui_config"
if [[ -f "$ui" ]]; then
  cur="$(sed -n 's/.*<Option name="color-file" value="\([^"]*\)".*/\1/p' "$ui")"
  case "$cur" in
    w) ;;
    ""|dark)
      if [[ -n "$cur" ]]; then sed 's/\(<Option name="color-file" value="\)dark"/\1w"/' "$ui"
      else sed 's|<UI>|<UI>\n    <Option name="color-file" value="w"/>|' "$ui"; fi \
        | as_user tee "$ui.w-new" >/dev/null && as_user mv -f "$ui.w-new" "$ui" \
        && info "Ardour: W colour theme selected (at its next start)." \
        || warn "could not select the W theme in $ui"
      ;;
    *) info "Ardour: your colour theme '$cur' kept (W's is 'w' in Preferences → Appearance → Colors)." ;;
  esac
fi

# ── Offline verification ─────────────────────────────────────────────────────
info "Verifying the audio user layer for $USER_NAME (offline)..."
compgen -G "$USER_HOME/.config/ardour*/themes/w-ardour.colors" >/dev/null && info "Ardour W theme: OK" \
  || warn "Ardour W theme: not rendered yet (renders at next login)"

info "The AI assistant can drive Ardour once you enable its MCP surface in Ardour:"
info "  Edit → Preferences → Control Surfaces → MCP HTTP Server (Experimental)."
info "audio user setup complete for $USER_NAME."
exit 0
