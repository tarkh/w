# modules/dns.sh — DNS privacy: systemd-resolved + DNS-over-TLS (security.md, point Е)
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
# systemd-resolved ships with systemd (no package). NetworkManager is routed
# through it via rootfs drop-in /etc/NetworkManager/conf.d/10-w-dns.conf
# (dns=systemd-resolved) so DoT actually applies. The resolver catalog + active
# selection live in /etc/w/dns.conf (source-of-truth); `w-dns` renders the chosen
# provider into /etc/systemd/resolved.conf.d/. W default = Quad9, opportunistic.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_dns() {
  local mnt="${MNT:-}"

  if [[ -n "$mnt" ]]; then
    chroot_run systemctl enable systemd-resolved
    # NetworkManager hands DNS to resolved, which serves /etc/resolv.conf via its
    # stub — point the symlink at it.
    chroot_run ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    chroot_run w-dns apply   # render the default policy (no restart in chroot)
    return
  fi

  ui_info "Enabling systemd-resolved (DNS-over-TLS)..."
  systemctl enable systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

  ui_info "Rendering DNS policy from /etc/w/dns.conf..."
  w-dns apply   # writes /etc/systemd/resolved.conf.d/10-w-dns.conf + restarts resolved

  # NetworkManager must re-read conf.d to start routing DNS through resolved.
  # Restart keeps active connections up (devices are re-adopted), so SSH survives.
  systemctl is-active --quiet NetworkManager && systemctl restart NetworkManager || true

  ui_info "DNS active (resolved + DoT, provider '$(w-dns list | sed -n 's/^  \* //p')'). Switch: w-dns provider <name>; mode: w-dns on|strict|off; status: w-dns status."
}
