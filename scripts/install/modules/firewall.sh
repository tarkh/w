# modules/firewall.sh — host firewall: firewalld (nftables backend) + GUI (security.md, point В)
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
# firewalld speaks nftables natively and integrates with NetworkManager over D-Bus
# (connections without an explicit zone fall into the default zone — nothing to wire).
# W baseline default zone = `home` (default-deny inbound, but allows ssh + mdns so
# W's avahi/gvfs .local discovery keeps working). Runtime toggle: `w-firewall`.
# GUI = firewall-config (GTK3 → inherits the W gtk theme axis). See security.md (В).

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

# W baseline zone. home keeps inbound ssh (don't lock out the dev VM / remote) and
# mdns (W network discovery). `w-firewall public` switches it for untrusted networks.
W_FIREWALL_ZONE="home"

mod_firewall() {
  local mnt="${MNT:-}"

  ui_info "Installing firewalld + firewall-config..."
  w_pac -S --needed --noconfirm firewalld firewall-config

  if [[ -n "$mnt" ]]; then
    chroot_run systemctl enable firewalld
  else
    ui_info "Enabling firewalld..."
    systemctl enable firewalld
    # Assert the W baseline default zone (idempotent). Both home/public keep `ssh`.
    # If the daemon is already up (re-apply) set it live; otherwise set it offline
    # FIRST, then start — `firewall-cmd` right after `start` hits a D-Bus startup
    # race ("FirewallD is not running"), `firewall-offline-cmd` edits the config
    # directly with no daemon needed.
    ui_info "Setting default zone -> ${W_FIREWALL_ZONE}..."
    if firewall-cmd --state &>/dev/null; then
      firewall-cmd --set-default-zone="$W_FIREWALL_ZONE" >/dev/null
    else
      firewall-offline-cmd --set-default-zone="$W_FIREWALL_ZONE" >/dev/null
      systemctl start firewalld
    fi
  fi

  ui_info "Firewall active (default-deny inbound, zone '${W_FIREWALL_ZONE}'). Toggle: w-firewall public|home; rich GUI: firewall-config."
}
