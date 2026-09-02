# modules/firstboot.sh — stage the Session 2 firstboot handoff onto the target.
#
# apply.sh's modules are built to run post-boot (systemd --user, live D-Bus,
# gsettings — chroot fights all of these, see dev-workflow.md's chroot landmine).
# So `apply --all` has to run natively on the target's own first boot, not here in
# the installer's chroot. Two things must exist on the target BEFORE that reboot:
#   1. w-firstboot itself + its systemd unit — deployed directly from this source
#      tree's rootfs/, exactly like mod_plymouth stages the splash theme early,
#      because apply_rootfs (which lays down the rest of rootfs/) is one of the
#      steps w-firstboot will run, not something that has already run yet.
#   2. A full copy of scripts/+packages/+rootfs/ under /var/lib/w/src — apply.sh's
#      dev-VM workflow reaches these over a virtiofs share (/mnt/w-src) that only
#      exists in that VM; real hardware has no such share, so the target needs its
#      own persistent copy to run apply.sh against after reboot.

mod_firstboot() {
  ui_info "Staging firstboot handoff..."

  install -Dm755 "$SRC/rootfs/usr/lib/w/w-firstboot" \
    "$MNT/usr/lib/w/w-firstboot"
  install -Dm644 "$SRC/rootfs/etc/systemd/system/w-firstboot.service" \
    "$MNT/etc/systemd/system/w-firstboot.service"

  # Edge install: /var/lib/w/src is a REAL git checkout (the URL the user entered,
  # already cloned + validated in the wizard, EDGE_SRC_DIR). Copy it whole, incl
  # .git, so post-boot `w-sync` can `git pull` from it. mod_updatesys hands it to
  # the primary user and locks .git/config (creds) once the user exists at firstboot.
  # Stable install: no repo — stage the ISO-baked source as a plain copy, as before.
  mkdir -p "$MNT/var/lib/w/src"
  if [[ "${CONF_MODE:-stable}" == edge && -d "${EDGE_SRC_DIR:-}/.git" ]]; then
    ui_info "Staging edge git checkout..."
    cp -a "$EDGE_SRC_DIR/." "$MNT/var/lib/w/src/"
  else
    rsync -a --chown=root:root \
      "$SRC/scripts" "$SRC/packages" "$SRC/rootfs" "$MNT/var/lib/w/src/"
  fi

  # w-repo: the pre-built `yay` package baked onto the ISO (build-iso.sh), staged
  # here so firstboot's `apply --packages` can install it as a binary instead of
  # compiling it from AUR (chicken-and-egg: nothing can build AUR packages before
  # yay exists). Only present when booted from our own ISO — absent in the dev-VM
  # workflow (stock Arch ISO), where install_yay's makepkg fallback in apply.sh
  # still applies. Unsigned on purpose (SigLevel=Never): it's our own build, used
  # for one boot, then the [w-repo] entry is dropped again by install_yay.
  local live_w_repo="/root/w-repo"
  if [[ -d "$live_w_repo" ]]; then
    ui_info "Staging w-repo (prebuilt yay)..."
    mkdir -p "$MNT/var/lib/w/w-repo"
    cp -a "$live_w_repo/." "$MNT/var/lib/w/w-repo/"
    {
      echo "[w-repo]"
      echo "SigLevel = Never"
      echo "Server = file:///var/lib/w/w-repo"
      echo
      cat "$MNT/etc/pacman.conf"
    } > "$MNT/etc/pacman.conf.new"
    mv "$MNT/etc/pacman.conf.new" "$MNT/etc/pacman.conf"
  fi

  chroot_run systemctl enable w-firstboot.service
  # getty@tty1 races w-firstboot for /dev/tty1 (both TTYReset/TTYVTDisallocate on
  # the same VT): getty starts far earlier in boot (getty.target, well before
  # multi-user.target) and its Restart=always re-grabs the tty and HUP-kills
  # w-firstboot mid-run. mod_greeter disables it too, but that's one of the very
  # modules w-firstboot itself runs — too late for boot #1. Disable it here instead.
  chroot_run systemctl disable getty@tty1.service 2>/dev/null || true
  touch "$MNT/var/lib/w/.firstboot-pending"
}
