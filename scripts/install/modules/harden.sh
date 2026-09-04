# modules/harden.sh — kernel/sysctl/cmdline hardening (security.md, point A)
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
# sysctl drop-ins + w-kernel arrive via apply_rootfs (--rootfs); this module
# activates them and patches the boot cmdline.
#
# It is a one-line delegation to `w-kernel harden on` ON PURPOSE. The cmdline token
# set and the way it is written used to be duplicated here and in w-kernel, with a
# comment in both telling the next person to keep them in sync — and they still
# diverged the moment the encrypted install path appeared: this module wrote
# GRUB_CMDLINE_LINUX_DEFAULT and ran grub-mkconfig unconditionally, while a Limine
# system boots /etc/kernel/cmdline and never reads either. grub IS installed there
# (it is in base.txt, shared with the plain path), so nothing failed — the config was
# written, the regeneration succeeded, and the hardening cmdline simply never reached
# the kernel. One implementation, in the tool that also has to toggle it back off, is
# the only shape in which "applied at install" and "on according to the Hub" can mean
# the same thing.
#
# Ordering note: this runs long after apply_bootloader in ALL_MODULES, so
# /etc/default/limine (w-kernel's bootloader probe) already exists where it should.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_harden() {
  # apply.sh runs on the live system and never sets MNT; the installer does not call
  # this module at all. Refuse rather than silently harden the HOST from a chroot.
  if [[ -n "${MNT:-}" ]]; then
    ui_info "Hardening: skipped (no chroot support — run apply.sh --harden on the installed system)."
    return 0
  fi

  ui_info "Applying hardening profile (sysctl drop-ins + boot cmdline)..."
  w-kernel harden on
}
