# modules/mirrors.sh — package-mirror maintenance (w-mirrors + its timer).
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
#
# Layer 3 of the package-delivery plan (installer.md §5). Layer 1 ranks mirrors on
# the ISO and pacstrap bakes that list into the machine; nothing on the machine
# could rebuild it afterwards, because reflector was in no W package list. This
# module closes exactly that: it puts reflector on the machine and hands the list's
# upkeep to a timer.
#
# What it deliberately does NOT do is rank. On a firstboot, layer 1 ranked minutes
# ago; on a later apply, the list is whatever the timer last made it. A ~260 MB job
# is not something an apply should start behind the user's back — `w-mirrors rank`
# is a decision, and the timer takes it on its own schedule.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_mirrors() {
  local mnt="${MNT:-}"

  if [[ -n "$mnt" ]]; then
    # reflector is in packages/pacman.txt (installed by install_packages); only
    # wire the timer up. In chroot w-mirrors writes nothing live — the unit comes
    # up enabled on first boot.
    chroot_run systemctl enable w-mirrors.timer
    return
  fi

  command -v reflector >/dev/null 2>&1 \
    || { ui_info "Installing reflector..."; w_pac -S --needed --noconfirm reflector; }

  ui_info "Enabling periodic mirror ranking..."
  w-mirrors apply

  ui_info "Mirror upkeep active. Status: w-mirrors status; re-rank now: sudo w-mirrors rank."
}
