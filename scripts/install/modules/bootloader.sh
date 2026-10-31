# modules/bootloader.sh — GRUB + grub-btrfs (UEFI)

mod_bootloader() {
  ui_info "Installing GRUB bootloader..."
  chroot_run grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=W \
    --removable \
    --recheck
  # Next to another OS the firmware's BootOrder already leads with that OS's own
  # loader, so a fallback-only GRUB would never be reached: register W in NVRAM as
  # well (grub-install puts its entry first). Whole-disk installs stay removable-only.
  if [[ "$CONF_DISK_MODE" == free ]]; then
    chroot_run grub-install --target=x86_64-efi --efi-directory=/boot/efi \
      --bootloader-id=W --recheck
  fi

  # grub-btrfs: detect btrfs snapshots in GRUB menu
  chroot_sh "echo 'GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION=true' \
    >> /etc/default/grub"

  ui_info "Generating GRUB config..."
  chroot_run grub-mkconfig -o /boot/grub/grub.cfg
}
