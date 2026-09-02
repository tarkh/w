# modules/update.sh — W Linux native update manager (apply.sh --update)
# apply.sh context: runs on the live system as root; post-boot only (install.sh
# never calls it). Depends on --rootfs (deploys /usr/bin/w-update and the
# systemd user units) and --quickshell (deploys the bar's Updates.qml block +
# bar.json entry). Module boundary (see essentials.md rule): the update manager is
# its own concern — it owns the checker packages and the periodic-check timer.
#
#   checkupdates (pacman-contrib) — non-root repo update count (private temp DB).
#   curl                          — `w-update news` fetches the Arch news RSS feed.
# AUR counting uses yay (already installed via --yay). Reboot detection is builtin
# (kernel modules dir). See w-update.md / quickshell-bar.md.

mod_update() {
  info "Setting up W update manager (w-update)..."
  w_pac -S --needed --noconfirm pacman-contrib curl

  # Enable the periodic-check timer for every user (creates the user-instance symlink;
  # each session's systemd --user picks it up at login). `w-update interval <min>`
  # overrides the period per user via a drop-in. The unit rides --rootfs; guard so a
  # standalone --update before --rootfs fails loudly instead of silently.
  if [[ -f /etc/systemd/user/w-update-check.timer ]]; then
    systemctl --global enable w-update-check.timer
    info "w-update ready. Bar 'updates' block + check timer (60min). Upgrade: w-update; interval: w-update interval <min>."
  else
    echo "  WARN: w-update-check.timer not found — run 'apply.sh --rootfs' first."
  fi
}
