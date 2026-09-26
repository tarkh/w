#!/usr/bin/env bash
# gaming bundle — PER-USER teardown, the declared inverse of setup-user.sh.
# Run by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup gaming` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# setup-user.sh did three things; each has a different correct inverse:
#   1. carved the game library into snapshot-excluded subvolumes — that is
#      DATA (games, saves, Proton prefixes). Named and kept, never deleted.
#   2. added the `gamemode` group — removed here, same root-only rule as add.
#   3. pointed Heroic at W's theme — reverted here, and this one is NOT
#      cosmetic: `document.body.className` comes from the selected file name, so
#      a `theme` of "w.css" whose stylesheet the pack just removed leaves Heroic
#      painting an undefined `body.w` — a half-styled window with no way for the
#      user to guess why. The theme goes back to Heroic's own default.
#
# Idempotent; best-effort. See pack-gaming.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; move to one the account can read (packs.md).
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Remove from group `gamemode` ────────────────────────────────────────
# The counterpart of `usermod -aG gamemode`. Best-effort: if the account is
# not in the group (already removed, or never added), gpasswd reports it and
# we move on.
info "Removing $USER_NAME from group 'gamemode'..."
if [[ "$AS_ROOT" == 1 ]]; then
  if gpasswd -d "$USER_NAME" gamemode >/dev/null 2>&1; then
    info "$USER_NAME removed from group 'gamemode'."
  else
    info "$USER_NAME is not in group 'gamemode' — nothing to do."
  fi
else
  # Removing a user from a group is root's call (it edits /etc/group). An account
  # acting for itself without root gets the exact command to ask for.
  if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx gamemode; then
    warn "$USER_NAME is in group 'gamemode'. Only an administrator can remove it:"
    warn "    sudo gpasswd -d $USER_NAME gamemode"
    warn "  Membership applies at the next login. Then re-run: w-pack unsetup gaming"
  else
    info "$USER_NAME is not in group 'gamemode' — nothing to do."
  fi
fi

# ── 2. Heroic back to its own theme ────────────────────────────────────────
# The JSON half goes through the same helper that wrote it (`--revert` only
# clears values still equal to ours, so a theme the user has since changed
# survives); the stylesheet is this script's to delete — packs.md puts an axis's
# home-side artifacts in the bundle's teardown, since `remove_wstyle` only takes
# back the module under /usr/lib/w.
heroic_conf="$USER_HOME/.config/heroic"
heroic_css="$heroic_conf/themes/w.css"

if [[ -d "$heroic_conf" ]]; then
  if pgrep -u "$USER_NAME" -x heroic >/dev/null 2>&1; then
    warn "Heroic is running — its config is left as-is (quit it and run 'w-pack unsetup gaming')."
  else
    info "Reverting Heroic to its own theme for $USER_NAME..."
    as_user python3 "$BUNDLE_DIR/heroic-seed.py" \
      --config-dir "$heroic_conf" --theme "$heroic_css" --revert \
      || true   # codes 3 (nothing to do) and 2 (warned already) are both non-fatal
  fi
fi

if [[ -e "$heroic_css" ]]; then
  rm -f "$heroic_css" && info "Removed $heroic_css."
  # Only if W left it empty — a CSS file of the user's own must not disappear.
  rmdir "$heroic_conf/themes" 2>/dev/null \
    && info "Removed the now-empty $heroic_conf/themes."
fi

# ── 3. What stays, and why ───────────────────────────────────────────────────
for d in ".local/share/Steam" "Games" ".local/share/lutris"; do
  p="$USER_HOME/$d"
  [[ -e "$p" ]] || continue
  size="$(du -sh "$p" 2>/dev/null | cut -f1 || echo '?')"
  info "Kept: $p ($size) — your games/saves, W never deletes them."
  if btrfs subvolume show "$p" >/dev/null 2>&1; then
    info "  It is a btrfs subvolume; to reclaim the space:"
    info "      btrfs subvolume delete $p"
  fi
done

info "gaming user teardown complete for $USER_NAME."
info "  Group membership change applies at the next login."
exit 0
