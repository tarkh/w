# modules/time.sh — network time: systemd-timesyncd + W's NTP server selection.
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
#
# Sibling of mod_dns, and deliberately shaped like it: both front a systemd service
# whose real config W keeps in its own layered files and RENDERS into a drop-in.
# For time that is /usr/share/w/defaults/time.conf (the vendor catalog + default
# selection) plus /etc/w/time.conf (this machine's deviations) → `w-time apply`
# writes /etc/systemd/timesyncd.conf.d/10-w-ntp.conf.
#
# Why this module exists at all (added 2026-08-05): nothing in the apply path ever
# called `w-time apply`, so on a fresh machine the drop-in was simply never written
# — timesyncd fell back to its compiled-in servers and W's declared selection (and
# any FALLBACK the admin set) was inert until somebody happened to switch server
# sets by hand. The clock still synced, which is exactly why it went unnoticed. It
# also gave the subsystem no apply flag, so a changed vendor catalog had nowhere to
# route in sync-map. Found while splitting the config layers; see w-conf.md.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_time() {
  local mnt="${MNT:-}"

  if [[ -n "$mnt" ]]; then
    # systemd's own preset already enables timesyncd; enabling it explicitly costs
    # nothing and keeps the module honest if that preset ever changes (same
    # reasoning as mod_dns with systemd-resolved).
    chroot_run systemctl enable systemd-timesyncd
    chroot_run w-time apply   # render the selection (no restart in chroot)
    return
  fi

  ui_info "Rendering NTP server selection from the layered config..."
  w-time apply   # writes /etc/systemd/timesyncd.conf.d/10-w-ntp.conf (+ restart if active)

  # Whether network time is ON is the ADMIN's decision (`w-time ntp on|off` →
  # timedatectl), and an apply must never quietly reverse it — that is the whole
  # point of the layered-config work. So: render the selection always, but only
  # touch the unit when the machine says NTP should be running. `enable --now`
  # covers the fresh-install case where the preset enabled the unit without
  # starting it; a machine with NTP deliberately off is left exactly as it is.
  if [[ "$(timedatectl show -p NTP --value 2>/dev/null)" == yes ]]; then
    systemctl enable --now systemd-timesyncd
    ui_info "Network time active (server set '$(w-conf get time SERVERS)'). Switch: sudo w-time servers <name>; status: w-time status."
  else
    ui_info "NTP is off on this machine — server set '$(w-conf get time SERVERS)' staged, timesyncd left off. Turn it on: sudo w-time ntp on."
  fi
}
