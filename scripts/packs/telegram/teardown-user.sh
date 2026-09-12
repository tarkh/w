#!/usr/bin/env bash
# telegram bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup telegram` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# setup-user.sh only triggered an axis render; its artefact in this account is
# the palette file the axis wrote — and the axis itself was just removed from
# the w-style drop-in root by w-pack. Take the file with it, or the account
# keeps a themed file nothing left on the machine will ever refresh again.
#
# What this CANNOT undo: the palette Telegram already uses. It lives in the
# app's encrypted tdata as a cached copy (whether seeded by setup-user.sh
# before the first launch or picked by hand) — with the file gone, Telegram
# keeps showing the last W colours it read (readThemeUsingKey falls back to
# its cache when the path no longer exists). Switching back to a built-in
# theme is one click in Chat settings; W writes into tdata only the one-time
# seed of a tdata that did not exist, never into a live one.
#
# NOT removed, by design: ~/.local/share/TelegramDesktop/ itself (tdata = the
# user's sessions, media cache) — user data, never touched.
#
# Idempotent; best-effort. See pack-telegram.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# ── 1. The axis-rendered palette ───────────────────────────────────────────────
f="$USER_HOME/.local/share/TelegramDesktop/w.tdesktop-theme"
if [[ -f "$f" ]]; then
  rm -f "$f" && info "Removed $f"
  info "Telegram keeps the last applied colours cached; pick a built-in theme in"
  info "  Settings → Chat settings to return to its own look."
else
  info "No W palette file for this account — nothing to undo."
fi

# ── 2. What stays, and why ─────────────────────────────────────────────────────
info "Kept: ~/.local/share/TelegramDesktop (your sessions and cache — Telegram's own state)."

info "telegram user teardown complete."
exit 0
