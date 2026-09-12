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

  # Client-side TCP Fast Open off BEFORE the first DoT stream is opened (the
  # drop-in itself arrives with apply_rootfs; boot applies it, but on firstboot
  # the packs phase runs in this very session, so the running kernel needs it now).
  # Why: /etc/sysctl.d/80-w-dns.conf.
  sysctl -q -p /etc/sysctl.d/80-w-dns.conf || true

  ui_info "Rendering DNS policy from /etc/w/dns.conf..."
  w-dns apply   # writes /etc/systemd/resolved.conf.d/10-w-dns.conf + restarts resolved

  # NetworkManager must re-read conf.d to start routing DNS through resolved.
  # Restart keeps active connections up (devices are re-adopted), so SSH survives.
  systemctl is-active --quiet NetworkManager && systemctl restart NetworkManager || true

  local provider; provider="$(w-dns list | sed -n 's/^  \* //p')"
  ui_info "DNS active (resolved + DoT, provider '$provider'). Switch: w-dns provider <name>; mode: w-dns on|strict|off; status: w-dns status."
  dns_probe "$provider"
}

# Sanity probe through the stub, right after the policy went live. Not a gate —
# apply never fails on it (offline apply is legitimate) — but a DoT path that
# hangs used to surface only as 200 lines of "Resolving timed out" from pacman
# in the packs phase; this names the cause in one line, where a reader looks
# first. Two names, so one cold cache miss does not count as a verdict.
dns_probe() {
  local n ok=0
  for n in archlinux.org geo.mirror.pkgbuild.com; do
    timeout 5 resolvectl query --legend=no "$n" &>/dev/null && ok=$((ok + 1))
  done
  (( ok > 0 )) && return 0
  echo -e "\033[1;33mWARNING:\033[0m lookups through the resolver ('$1') time out." \
    "Package downloads will fail the same way. Check the network first; 'w-dns off'" \
    "hands DNS back to the network's own server until the cause is found." >&2
}
