# modules/harden.sh — kernel/sysctl/cmdline hardening (security.md, point A)
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
# sysctl drop-ins + w-kernel arrive via apply_rootfs (--rootfs); this module
# activates them and patches the boot cmdline.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

# Hardening boot params. Toggled as a set; w-kernel harden off removes them.
W_HARDEN_CMDLINE="init_on_alloc=1 init_on_free=1 slab_nomerge \
randomize_kstack_offset=1 page_alloc.shuffle=1 vsyscall=none debugfs=off"

# Append only the missing tokens to GRUB_CMDLINE_LINUX_DEFAULT, preserving what's
# already there (splash/quiet from plymouth). Idempotent — re-running adds nothing.
harden_add_cmdline() {
  local file="$1" tokens="$2" tok
  grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file" \
    || echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$file"
  for tok in $tokens; do
    # match the bare token inside the quoted value, word-bounded
    grep -qE "^GRUB_CMDLINE_LINUX_DEFAULT=\".*(^|[\" ])${tok//./\\.}([\" ]|\$)" "$file" \
      && continue
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${tok}\"|" "$file"
  done
  # collapse any accidental double/leading spaces introduced by appends
  sed -i 's|^\(GRUB_CMDLINE_LINUX_DEFAULT="\) *|\1|; s|  *\("$\)|\1|; s|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)  *|\1 |g' "$file"
}

mod_harden() {
  local mnt="${MNT:-}"
  local grub_default="${mnt}/etc/default/grub"

  ui_info "Applying sysctl hardening..."
  if [[ -z "$mnt" ]]; then
    sysctl --system >/dev/null
  fi

  ui_info "Adding hardening boot params to kernel cmdline..."
  harden_add_cmdline "$grub_default" "$W_HARDEN_CMDLINE"

  ui_info "Regenerating GRUB config (cmdline + microcode initrd)..."
  if [[ -n "$mnt" ]]; then
    chroot_run grub-mkconfig -o /boot/grub/grub.cfg
  else
    grub-mkconfig -o /boot/grub/grub.cfg
  fi

  ui_info "Hardening applied. Reboot required for cmdline params to take effect."
}
