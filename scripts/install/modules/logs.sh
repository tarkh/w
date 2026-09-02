# modules/logs.sh — unified log retention (journald + logrotate + tmpfiles).
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
#
# W has no cron — logrotate is driven by its own logrotate.timer (systemd). The
# whole policy is one number in /etc/w/logs.conf; `w-logs apply` renders it into
# the journal drop-in, the logrotate global region + /var/log/*.log failsafe, and
# the /var/log/w tmpfiles cleaner. See w-logs.md.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_logs() {
  local mnt="${MNT:-}"

  if [[ -n "$mnt" ]]; then
    # logrotate is in packages/pacman.txt (installed by pacstrap); only wire it up.
    # The logrotate.service ExecStartPre drop-in ships via the rootfs overlay.
    chroot_run systemctl enable logrotate.timer
    # Render every node into the target. In chroot w-logs writes the files but does
    # not restart journald / run tmpfiles (guarded on /run/systemd/system).
    chroot_run w-logs apply
    return
  fi

  # Standalone apply.sh --logs: make sure logrotate is present (no-op if it is).
  command -v logrotate >/dev/null 2>&1 || { ui_info "Installing logrotate..."; w_pac -S --needed --noconfirm logrotate; }

  ui_info "Rendering log retention policy from /etc/w/logs.conf..."
  w-logs apply

  # Pick up the logrotate.service ExecStartPre drop-in (shipped by the rootfs overlay).
  systemctl daemon-reload
  systemctl enable --now logrotate.timer

  ui_info "Log retention active ($(w-logs status | sed -n 's/^Policy   : //p')). Change: sudo w-logs keep <days>; status: w-logs status."
}
