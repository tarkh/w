# modules/snapshots.sh — snapper + snap-pac + grub-btrfs
#
# NOTE: snapper configs are NOT created here. `snapper create-config` needs a
# running snapperd (D-Bus), which arch-chroot doesn't provide — it silently fails.
# Config creation + retention happen live in apply.sh (fix_snapper / configure_home
# _snapper), where D-Bus is up. Leaving root unconfigured during install is also
# deliberate for the snapshot policy: snap-pac only snapshots the `root` config, so
# with no config the whole `apply` runs snapshot-free and the single `initial`
# rollback anchor is the only post-install snapshot. Here we only enable the static
# units (systemctl enable = symlinks, no D-Bus needed) and note the boot bridge.

mod_snapshots() {
  # Nothing to do in the chroot install stage. Enabling the snapper timers here is
  # actively harmful under the deferred-config policy: they'd start on firstboot and
  # fire (OnBootSec=10m) mid-`apply`, before fix_snapper creates the root config →
  # snapper-cleanup.service fails with no config. The timers (and limine-snapper-sync)
  # are enabled live in apply.sh AFTER the config + initial snapshot exist.
  :

  # Snapshot→boot bridge differs per bootloader:
  #  - plain/GRUB: grub-btrfsd watches snapshots and rebuilds the GRUB submenu.
  #  - encrypted/Limine: limine-snapper-sync (AUR) does the equivalent, enabled by
  #    mod_limine in the live context (it isn't installed in the chroot).
  if [[ "${CONF_ENCRYPT:-false}" == true ]]; then
    echo "INFO: snapshot boot entries handled by limine-snapper-sync (enabled post-boot by mod_limine)"
  else
    chroot_run systemctl enable grub-btrfsd.service 2>/dev/null || echo "WARN: grub-btrfsd.service not enabled"
  fi
}
