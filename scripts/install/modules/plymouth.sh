# modules/plymouth.sh — Plymouth boot splash with W theme

mod_plymouth() {
  ui_info "Configuring Plymouth..."

  # mkinitcpio: insert plymouth hook after kms (before filesystems)
  if ! grep -q 'plymouth' "$MNT/etc/mkinitcpio.conf"; then
    sed -i 's/\bkms\b/kms plymouth/' "$MNT/etc/mkinitcpio.conf"
  fi

  # GRUB: add quiet splash to kernel cmdline
  if ! grep -q '\bsplash\b' "$MNT/etc/default/grub"; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' \
      "$MNT/etc/default/grub"
  fi
  if ! grep -q '\bquiet\b' "$MNT/etc/default/grub"; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet"/' \
      "$MNT/etc/default/grub"
  fi

  # plymouthd's config (theme + DeviceScale=1, see the file's own header). Deployed
  # from rootfs/ here rather than post-boot for the same reason as the theme below:
  # this initramfs is the one the first boot runs on.
  mkdir -p "$MNT/etc/plymouth"
  cp "$SRC/rootfs/etc/plymouth/plymouthd.conf" "$MNT/etc/plymouth/plymouthd.conf"

  # Seamless transition: keep splash until Wayland compositor takes over
  local dropin_dir="$MNT/etc/systemd/system/plymouth-quit.service.d"
  mkdir -p "$dropin_dir"
  cp "$SRC/rootfs/etc/systemd/system/plymouth-quit.service.d/override.conf" "$dropin_dir/override.conf"

  # Pause the wall-clock boot-progress estimate while the LUKS prompt is up. Deployed
  # here too (not just by apply.sh) for the same reason as the theme below: on the
  # encrypted path the install-time initramfs is what Limine stages for the very first
  # boot — the one that always asks for the passphrase.
  local ask_dropin_dir="$MNT/etc/systemd/system/systemd-ask-password-plymouth.service.d"
  mkdir -p "$ask_dropin_dir"
  cp "$SRC/rootfs/etc/systemd/system/systemd-ask-password-plymouth.service.d/10-w-pause-progress.conf" \
    "$ask_dropin_dir/10-w-pause-progress.conf"

  # Deploy the Plymouth theme + seed its logo BEFORE rebuilding, so the theme is
  # actually present in the install-time initramfs. rootfs/ is only laid down post-boot
  # by apply.sh, so without this the initramfs ships `Theme=w` but no themes/w/ — and
  # on the encrypted path the Limine first-boot seed stages exactly this initramfs onto
  # the ESP, leaving the very first boot (LUKS prompt) on the default/unthemed splash.
  ui_info "Deploying Plymouth theme..."
  mkdir -p "$MNT/usr/share/plymouth"
  cp -a "$SRC/rootfs/usr/share/plymouth/." "$MNT/usr/share/plymouth/"
  # The logo is COPIED at its master size here, not rendered to this panel's size the
  # way apply.sh --plymouth and w-style do it: rendering needs ImageMagick, which is
  # in neither the ISO nor the freshly pacstrapped chroot (it arrives with
  # packages/pacman.txt on first boot). The only splash that shows this copy is the
  # very first boot — the LUKS prompt on the encrypted path — where there is no
  # wallpaper on screen to compare it against; firstboot's apply run replaces it with
  # the correctly sized render and rebuilds the initramfs.
  install -Dm644 "$SRC/rootfs/etc/w/themes/w/logo/W-logo-256x256.png" \
    "$MNT/usr/share/plymouth/themes/w/logo.png"
  chown -R root:root "$MNT/usr/share/plymouth"

  # Rebuild initramfs with plymouth hook. Raw mkinitcpio (NOT w-mkinitcpio) on purpose:
  # this is the install-time chroot, where rootfs isn't deployed yet (no w-mkinitcpio) and
  # the AUR limine-mkinitcpio-hook shim doesn't exist either (it's pulled live by mod_limine,
  # not in the chroot). ESP staging here is handled separately by limine_bootstrap_esp.
  ui_info "Rebuilding initramfs (plymouth hook)..."
  chroot_run mkinitcpio -P
}
