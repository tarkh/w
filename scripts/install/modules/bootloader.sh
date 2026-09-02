# modules/bootloader.sh — GRUB + grub-btrfs (UEFI)

mod_bootloader() {
  ui_info "Installing GRUB bootloader..."
  chroot_run grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=W \
    --removable \
    --recheck

  # grub-btrfs: detect btrfs snapshots in GRUB menu
  chroot_sh "echo 'GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION=true' \
    >> /etc/default/grub"

  ui_info "Generating GRUB config..."
  chroot_run grub-mkconfig -o /boot/grub/grub.cfg
}
