# modules/network.sh — live Wi-Fi association, connectivity gate, and enabling
# NetworkManager + SSH on the target (plus persisting live Wi-Fi profiles so the
# firstboot `apply --all` comes up online without re-entering credentials).

# ── Wizard-time helpers (live ISO) ────────────────────────────────────────────

# True when a Wi-Fi device exists → the `network` step is shown (steps.conf
# condition). On wired-only machines / the dev VM (virtio) there is none, so the
# step is skipped automatically.
net_has_wifi() {
  command -v nmcli &>/dev/null || return 1
  nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi
}

# True when the machine already has internet (NM connectivity or a reachability
# probe). Used both to gate pacstrap and, implicitly, to let the user skip Wi-Fi.
net_online() {
  local c
  if command -v nmcli &>/dev/null; then
    c=$(nmcli -t -f CONNECTIVITY networking connectivity 2>/dev/null) || c=""
    [[ "$c" == full || "$c" == limited ]] && return 0
  fi
  ping -c1 -W3 archlinux.org &>/dev/null && return 0
  ping -c1 -W3 1.1.1.1       &>/dev/null && return 0
  return 1
}

# Wizard widget: scan, pick an SSID, enter the passphrase, connect. Sets
# UI_RESULT to the SSID (or "skip"). Returns 0 (done) / 3 (back).
# nmcli writes the resulting profile to /etc/NetworkManager/system-connections/,
# which mod_network later copies onto the target.
#
# Every dialog call here targets `${W_TTY:-N}` for its on-screen render, not the
# bare fd. $W_TTY is a genuine dup of the real terminal, allocated by both
# install.sh and w-firstboot before anything else runs — required not just for
# firstboot (whose work phase redirects stdout+stderr to a log file, so a bare
# fd would render into the log instead of the tty) but for install.sh's wizard
# phase too: the SSID picker/password box below capture their result via
# `$(dialog ... 3>&1 1>&"$W_TTY" 2>&3)`, and inside that command substitution
# plain fd 1 is already the capture pipe, not the terminal — only a real,
# separate fd (never just the literal "1") reaches the terminal from in there.
w_network() {
  local title="$1" prompt="$2" rc ssid pw
  local -a ssids items args
  while true; do
    rc=0
    dialog "${DIALOG_COMMON[@]}" --colors --title " $title " \
      --infobox "\n  $(t net_scanning)" 5 50 1>&"${W_TTY:-1}"
    mapfile -t ssids < <(nmcli -t -f SSID device wifi list --rescan yes 2>/dev/null \
      | sed 's/\\:/:/g' | awk 'NF && !seen[$0]++')

    items=()
    (( ${#ssids[@]} == 0 )) && dialog "${DIALOG_COMMON[@]}" --colors \
      --title " $title " --msgbox "\n$(t net_none)" 8 54 1>&"${W_TTY:-1}"
    for ssid in "${ssids[@]}"; do items+=("$ssid" ""); done
    items+=("__skip__" "$(t net_skip)")

    ssid=$(dialog "${DIALOG_NAV[@]}" --default-item "${ANSWERS[wifi]:-}" \
      --title " $title " --menu "\n$prompt" 20 66 12 "${items[@]}" \
      3>&1 1>&"${W_TTY:-2}" 2>&3) || rc=$?
    (( rc == 3 )) && return 3
    (( rc == 1 )) && return 1
    [[ -z "$ssid" || "$ssid" == __skip__ ]] && { UI_RESULT=skip; return 0; }

    rc=0
    pw=$(dialog "${DIALOG_NAV[@]}" --insecure --title " $title " \
      --passwordbox "\n$(t net_password)\n\n  $ssid" 11 60 3>&1 1>&"${W_TTY:-2}" 2>&3) || rc=$?
    (( rc == 3 )) && continue   # back → rescan list

    dialog "${DIALOG_COMMON[@]}" --colors --title " $title " \
      --infobox "\n  $(t net_connecting) $ssid…" 5 50 1>&"${W_TTY:-1}"
    args=(device wifi connect "$ssid")
    [[ -n "$pw" ]] && args+=(password "$pw")
    if nmcli "${args[@]}" &>/dev/null; then
      UI_RESULT="$ssid"; return 0
    fi
    dialog "${DIALOG_COMMON[@]}" --colors --title " $(t error) " \
      --msgbox "\n$(t net_connect_fail)" 8 54 1>&"${W_TTY:-1}"
  done
}

# Firstboot-time gate: give NM's autoconnect a short grace period to associate +
# DHCP (real Wi-Fi is slower than the dev-VM's near-instant virtio net), then —
# if still offline — loop showing the same Wi-Fi picker used during install, so a
# firstboot failure (wrong password changed, AP out of range, no autoconnect) is
# recoverable without dropping to a shell. Only meaningful when a Wi-Fi device
# actually exists; on wired-only failures there is nothing to reconfigure here.
ensure_online_or_reconnect() {
  local i
  for ((i = 0; i < 6; i++)); do
    net_online && return 0
    sleep 5
  done
  # Unattended (w-firstboot exports W_UNATTENDED from install.conf): nobody can
  # answer the Wi-Fi picker — report failure to the caller instead of looping on
  # a dialog forever. w-firstboot then skips apply and powers off (E2E harness).
  if [[ -n "${W_UNATTENDED:-}" ]]; then
    echo "ERROR: still offline after the grace period (unattended)." >&2
    return 1
  fi
  while ! net_online; do
    if net_has_wifi; then
      w_network "$(t s_net_title)" "$(t s_net_prompt)"
    else
      dialog "${DIALOG_COMMON[@]}" --colors --title " $(t error) " \
        --msgbox "\n$(t err_offline)" 10 62 1>&"${W_TTY:-1}"
    fi
  done
}

# Work-phase gate: block before pacstrap (and before the disk is erased) until
# there is internet. The user can quit via the extra button. Unattended: retry
# for ~1 min, then abort — the disk has not been touched yet, so a plain die is
# a clean stop (only install.sh calls this; die is in scope).
ensure_network() {
  if [[ -n "${W_UNATTENDED:-}" ]]; then
    local i
    for ((i = 0; i < 12; i++)); do
      net_online && return 0
      sleep 5
    done
    die "No internet connection (unattended install aborted before touching the disk)."
  fi
  while ! net_online; do
    dialog "${DIALOG_COMMON[@]}" --colors --extra-button --extra-label "$(t quit)" \
      --title " $(t error) " --msgbox "\n$(t err_offline)" 10 62 1>&"${W_TTY:-1}" || die "$(t quit)"
  done
}

# ── Target configuration ──────────────────────────────────────────────────────
mod_network() {
  ui_info "Enabling network services..."
  chroot_run systemctl enable NetworkManager
  chroot_run systemctl enable sshd

  # Enable systemd-resolved from the base install so the stub resolver (127.0.0.53)
  # is alive on the very first boot. The NM drop-in 10-w-dns.conf (dns=systemd-resolved,
  # deployed by apply_rootfs at firstboot module 1) points NM at that stub, but resolved
  # itself is otherwise only enabled by mod_dns (module 24). If apply --all aborts before
  # mod_dns (e.g. a transient AUR failure in the yay module), NM ends up routing DNS to a
  # dead stub → total name-resolution failure on reboot. Enabling it here decouples DNS
  # availability from that late, fragile module; mod_dns still layers the DoT policy on top.
  chroot_run systemctl enable systemd-resolved

  # Persist Wi-Fi profiles created live so the first boot is already online. NM
  # stores them (PSK included) root-only at 0600; keep the same permissions.
  local nmdir=/etc/NetworkManager/system-connections
  if compgen -G "$nmdir/*.nmconnection" >/dev/null 2>&1; then
    ui_info "Persisting Wi-Fi profile to the target..."
    install -dm700 "$MNT$nmdir"
    cp -a "$nmdir"/*.nmconnection "$MNT$nmdir"/
    chmod 600 "$MNT$nmdir"/*.nmconnection
  fi
}
