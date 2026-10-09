#!/usr/bin/env bash
# audio bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup audio` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# Goes unconditionally — all of it is W wiring: `realtime` membership, the
# rendered Ardour theme (colours + the clearlooks.rc copy), and Ardour's
# pointer at it while it is still "w" (back to the stock "dark", or Ardour
# would fall back with a warning). What stays: sessions, recordings, Ardour's
# and Audacity's own settings, and Audacity's light/dark choice (its own key,
# a valid value either way).
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

# ── Group `realtime` ─────────────────────────────────────────────────────────
if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx realtime; then
  if [[ "$AS_ROOT" == 1 ]]; then
    gpasswd -d "$USER_NAME" realtime >/dev/null \
      && info "$USER_NAME removed from group 'realtime'." || warn "gpasswd -d $USER_NAME realtime failed."
  else
    warn "$USER_NAME is in group 'realtime'. Only an administrator can remove it:"
    warn "    sudo gpasswd -d $USER_NAME realtime"
  fi
fi

# ── Ardour theme ─────────────────────────────────────────────────────────────
rm -f "$USER_HOME"/.config/ardour*/themes/w-ardour.colors "$USER_HOME"/.config/ardour*/clearlooks.rc
rmdir "$USER_HOME"/.config/ardour*/themes 2>/dev/null
for ui in "$USER_HOME"/.config/ardour*/ui_config; do
  [[ -f "$ui" ]] && grep -q '<Option name="color-file" value="w"/>' "$ui" || continue
  sed 's/\(<Option name="color-file" value="\)w"/\1dark"/' "$ui" | as_user tee "$ui.w-new" >/dev/null \
    && as_user mv -f "$ui.w-new" "$ui" && info "Ardour: colour theme reset to its stock 'dark'."
done

info "Kept: your sessions and recordings, Ardour's and Audacity's own settings."
info "audio user teardown complete for $USER_NAME."
exit 0
