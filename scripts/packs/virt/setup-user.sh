#!/usr/bin/env bash
# virt bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup virt` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Desktop virtualization per-user setup is exactly one thing: add the account to
# the `libvirt` group so libvirt's shipped polkit rule (50-libvirt.rules) grants
# passwordless `org.libvirt.unix.manage` against qemu:///system. Without group
# membership the user is prompted for an admin password on every virt-manager /
# virsh connect, or refused outright.
#
# That is the whole per-user layer — no socket (that's the root daemon), no image
# store (that's /var/lib/libvirt/images, root-owned), no UID mapping. Adding the
# group is genuinely root's call (usermod edits /etc/group), so an account catching
# itself up without root gets the exact command to ask for.
#
# Idempotent; best-effort. See packs.md / pack-virt.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# ── 1. Group `libvirt` membership ────────────────────────────────────────────
# libvirt ships 50-libvirt.rules (polkit): unix-group:libvirt → manage qemu:///system
# without a password prompt. `usermod -aG libvirt` adds the group; the effect is at
# the NEXT login (a new group list is read at session start, not mid-session).
info "Adding $USER_NAME to group 'libvirt' (passwordless qemu:///system)..."
if [[ "$AS_ROOT" == 1 ]]; then
  if usermod -aG libvirt "$USER_NAME" >/dev/null 2>&1; then
    info "$USER_NAME added to group 'libvirt'."
  else
    warn "usermod -aG libvirt failed — the account may already be a member, or usermod errored."
  fi
else
  # Adding a user to a group is root's call (it edits /etc/group). An account
  # catching itself up without root gets the exact command to ask for — a silent
  # skip would leave it prompting for a password on every connect with no clue why.
  if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx libvirt; then
    info "$USER_NAME is already in group 'libvirt' — nothing to do."
  else
    warn "$USER_NAME is not in group 'libvirt'. Only an administrator can add it:"
    warn "    sudo usermod -aG libvirt $USER_NAME"
    warn "  then log out and back in (group membership applies at login), and re-run:"
    warn "    w-pack setup virt"
  fi
fi

# ── 2. Offline verification ──────────────────────────────────────────────────
# Confirm the group exists (it comes from the libvirt package's sysusers). No
# daemon connect here — this runs at firstboot with no session.
if getent group libvirt >/dev/null 2>&1; then
  : # group present
else
  warn "group 'libvirt' not found — the libvirt package's sysusers did not create it?"
  warn "  The package may not be installed yet; re-run after 'sudo w-pack install virt'."
fi

info "virt user setup complete for $USER_NAME."
info "  Group membership applies at the NEXT login. Connect with virt-manager,"
info "  Boxes, or 'virsh' (LIBVIRT_DEFAULT_URI=qemu:///system set at next login)."
exit 0
