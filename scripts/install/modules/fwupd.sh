# modules/fwupd.sh — firmware updates: fwupd + LVFS (security.md, point 7)
#
# fwupd updates UEFI/BIOS, SSD, dock and peripheral firmware from LVFS
# (the Linux Vendor Firmware Service). Userspace, apply-only (like dns/keyring).
#
# Config: none — LVFS defaults work out of the box.
# Units:  fwupd.service is socket/D-Bus-activated on demand (NOT enabled here);
#         only fwupd-refresh.timer is enabled — it keeps LVFS metadata fresh.
# Frontend: W has no GNOME Software/Discover, so updates run via `fwupdmgr` CLI
#           (fwupdmgr get-updates / update). A notification surface is a TODO.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_fwupd() {
  local mnt="${MNT:-}"

  ui_info "Installing fwupd (firmware updates via LVFS)..."
  w_pac -S --needed --noconfirm fwupd

  if [[ -n "$mnt" ]]; then
    chroot_run systemctl enable fwupd-refresh.timer
    return
  fi

  ui_info "Enabling fwupd-refresh.timer (periodic LVFS metadata refresh)..."
  systemctl enable fwupd-refresh.timer

  ui_info "fwupd active. Check firmware: fwupdmgr get-devices; refresh: fwupdmgr refresh; update: fwupdmgr update."
}
