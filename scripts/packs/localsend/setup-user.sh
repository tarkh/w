#!/usr/bin/env bash
# localsend bundle — PER-USER layer. Run by `w-pack install` (for the
# installing account) and by `w-pack setup localsend` (for whoever asks,
# without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# One step: point LocalSend at the system accent instead of its own brand
# colour. No w-style axis involved — LocalSend already reads GTK4's live
# `accent_color` CSS variable (rendered by the core `200-gtk` w-style module)
# on its own; the pack only has to flip two of its own settings once. See
# "How the colour works" in ai/SKILL.md for what was tried and rejected
# before landing here.
#
# Autostart is deliberately NOT touched here — see the note below.
#
# Idempotent; best-effort. See pack-localsend.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; move to one the account can read (packs.md).
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Point LocalSend at the system accent ───────────────────────────────────
# LocalSend keeps its entire app state (also its HTTPS server's private key —
# see ai/SKILL.md) in one JSON file, so this is a read-merge-write of exactly
# two keys, never a wholesale rewrite:
#   ls_theme = "system"  — follow the desktop's light/dark preference
#   ls_color = "system"  — follow the desktop's accent colour (dynamic_color),
#                          NOT ls_color="localsend" (its own fixed brand hue)
PREFS_REL=".local/share/org.localsend.localsend_app/shared_preferences.json"
if ! command -v jq >/dev/null; then
  warn "jq not found — cannot seed LocalSend's theme/colour settings for $USER_NAME."
else
  target="$USER_HOME/$PREFS_REL"
  dir="$(dirname "$target")"
  install -d -o "$USER_NAME" -g "$USER_NAME" "$dir" 2>/dev/null || mkdir -p "$dir"
  tmp="$dir/.$(basename "$target").tmp.$$"
  ok=1
  if [[ -f "$target" ]]; then
    # del(ls_custom_color): drops a leftover from a pre-"system" install of
    # this pack (it seeded ls_color="custom" + this key) — inert once
    # ls_color is "system", but no reason to leave it behind.
    jq '.["flutter.ls_theme"]="system" | .["flutter.ls_color"]="system"
        | del(.["flutter.ls_custom_color"])' "$target" >"$tmp" || ok=0
  else
    jq -n '{"flutter.ls_theme":"system","flutter.ls_color":"system"}' >"$tmp" || ok=0
  fi
  if [[ "$ok" == 1 ]]; then
    chmod 600 "$tmp"
    [[ "$AS_ROOT" == 1 ]] && chown "$USER_NAME:$USER_NAME" "$tmp" 2>/dev/null
    mv -f "$tmp" "$target"
    info "LocalSend set to follow W's theme (dark/light + accent) for $USER_NAME."
  else
    rm -f "$tmp"
    warn "could not seed LocalSend's settings for $USER_NAME — it will keep its own defaults."
  fi
fi

# ── 2. What only the human (or a later, explicit ask) decides ────────────────
# A systemd user unit (localsend.service) shipped with this bundle — it is NOT
# enabled here. LocalSend starting in the tray at every login is a real
# feature (closer to AirDrop's "always ready to receive") but comes with two
# open questions this bundle does not resolve on your behalf: whether you want
# it running at all, and --hidden's own rough edges on Linux (a caught but
# logged LateInitializationError from the tray helper on start, observed on
# the dev VM — harmless so far, but worth watching before trusting it
# unattended). Turn it on/off any time, no reinstall needed:
#
#   systemctl --user enable --now localsend.service    # start in tray at login
#   systemctl --user disable --now localsend.service   # back to launch-on-demand
cat <<EOF

  LocalSend is installed, set to follow W's theme (dark/light + accent),
  reachable on the LAN (firewalld 'home' zone, port 53317) and one right-click
  away in Nemo ("Send with LocalSend").

  It does NOT start automatically — open it from the launcher when you want to
  send or receive. To make it start in the tray at every login instead:

    systemctl --user enable --now localsend.service

  (undo any time with 'disable --now' instead of 'enable --now')

EOF

info "localsend user setup complete for $USER_NAME."
exit 0
