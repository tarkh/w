#!/usr/bin/env bash
# localsend bundle — PER-USER teardown, the declared inverse of setup-user.sh.
# Run by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup localsend` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# setup-user.sh only seeded two keys (ls_theme/ls_color = "system") inside
# LocalSend's own settings file and printed instructions — no manifest row, no
# unit enabled. Nothing to undo there beyond disabling the unit IF the user
# turned it on.
#
# NOT removed, by design: ~/.local/share/org.localsend.localsend_app/ itself —
# LocalSend's own state (its TLS identity, alias, receive history, favourites).
# W seeded two settings keys inside it once; it never owned the file.
#
# Idempotent; best-effort. See pack-localsend.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }

USER_NAME="${PACK_USER:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- "$@"
  else "$@"; fi
}

# ── 1. Autostart, if this account had turned it on ────────────────────────────
if as_user systemctl --user is-enabled localsend.service &>/dev/null; then
  as_user systemctl --user disable --now localsend.service &>/dev/null \
    && info "Stopped and disabled localsend.service for $USER_NAME."
fi

# ── 2. What stays, and why ─────────────────────────────────────────────────────
info "Kept: ~/.local/share/org.localsend.localsend_app (LocalSend's own state — TLS identity, history, alias)."

info "localsend user teardown complete."
exit 0
