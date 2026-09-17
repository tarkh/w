#!/usr/bin/env bash
# virt bundle — MACHINE teardown, the declared inverse of setup.sh. Run by
# `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# Undoes what setup.sh did imperatively: disable the libvirtd socket and remove
# the default-network autostart symlink. The manifest row (/etc/w/env.d/virt.sh)
# is removed and backed up by w-pack itself — not duplicated here.
#
# Data is never deleted: the image pool /var/lib/libvirt/images, defined VMs in
# /etc/libvirt/qemu/, and /var/lib/libvirt/ hold the user's disks and machine
# definitions. They are printed with their size, not touched — a teardown is a
# wiring rollback, not a disk wipe. The packages are pacman's subject (w-pack
# prints / runs the -Rns line itself when --packages is given).
#
# Idempotent; best-effort. See packs.md / pack-virt.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. libvirtd socket ────────────────────────────────────────────────────────
# `disable --now` stops a running daemon and removes the socket symlink. Best-
# effort: if VMs are running the daemon refuses to stop, which is the right call
# — we warn, not force.
info "Disabling libvirtd.socket..."
if systemctl disable --now libvirtd.socket >/dev/null 2>&1; then
  info "libvirtd.socket disabled."
else
  warn "could not disable libvirtd.socket (running VMs hold it? 'virsh list --all')"
fi

# ── 2. Default network autostart symlink ─────────────────────────────────────
NET_DST="/etc/libvirt/qemu/networks/autostart/default.xml"
if [[ -L "$NET_DST" ]]; then
  info "Removing default network autostart symlink..."
  rm -f "$NET_DST" || warn "could not remove $NET_DST"
fi

# ── 3. What stays, and why ───────────────────────────────────────────────────
# Three things are deliberately NOT undone, all for the same reason as every
# other bundle: they are data or machine-level properties, not W wiring.
print_dir() {
  local dir="$1" label="$2"
  if [[ -e "$dir" ]]; then
    local size
    size="$(du -sh "$dir" 2>/dev/null | cut -f1 || echo '?')"
    info "Kept: $dir ($size) — $label. W never deletes them."
  fi
}
print_dir "/var/lib/libvirt/images" "your VM disk images (qcow2)"
print_dir "/etc/libvirt/qemu"        "your VM definitions and networks"
print_dir "/var/lib/libvirt"         "libvirt runtime state (check for running domains)"

# The `libvirt` group is the package's, not this bundle's — added to an account
# by setup-user.sh, removed by teardown-user.sh. The group itself stays with the
# package (or until pacman -Rns, which w-pack offers but does not run by default).
info "Group 'libvirt' belongs to the package — accounts are removed from it by"
info "  teardown-user.sh; the group itself stays unless packages are removed."

info "virt machine teardown complete."
exit 0
