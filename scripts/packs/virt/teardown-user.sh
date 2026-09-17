#!/usr/bin/env bash
# virt bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run by
# `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup virt` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# Removes the account from the `libvirt` group — the only per-user thing
# setup-user.sh did. Removing a user from a group is root's call (gpasswd edits
# /etc/group), so an account catching itself up without root gets the exact
# command to ask for. Group membership applies at the next login, so a logged-in
# session keeps it until logout.
#
# Data is never touched — VM definitions and disk images live under
# /var/lib/libvirt (root-owned, machine-level), not in the user's home, so there
# is nothing per-user to leave behind. The group itself stays with the package.
#
# Idempotent; best-effort. See packs.md / pack-virt.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# ── 1. Remove from group `libvirt` ───────────────────────────────────────────
# The counterpart of `usermod -aG libvirt`. Best-effort: if the account is not in
# the group (already removed, or never added), gpasswd reports it and we move on.
info "Removing $USER_NAME from group 'libvirt'..."
if [[ "$AS_ROOT" == 1 ]]; then
  if gpasswd -d "$USER_NAME" libvirt >/dev/null 2>&1; then
    info "$USER_NAME removed from group 'libvirt'."
  else
    info "$USER_NAME is not in group 'libvirt' — nothing to do."
  fi
else
  # Removing a user from a group is root's call (it edits /etc/group). An account
  # acting for itself without root gets the exact command to ask for.
  if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx libvirt; then
    warn "$USER_NAME is in group 'libvirt'. Only an administrator can remove it:"
    warn "    sudo gpasswd -d $USER_NAME libvirt"
    warn "  Membership applies at the next login. Then re-run: w-pack unsetup virt"
  else
    info "$USER_NAME is not in group 'libvirt' — nothing to do."
  fi
fi

info "virt user teardown complete for $USER_NAME."
info "  Group membership applies at the next login."
exit 0
