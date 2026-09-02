# modules/session.sh — session memory (w-session: windows, workspaces, focus).
#
# Userspace layer: wired into apply.sh only (post-boot; the installer stays
# minimal-base), same as mod_nightlight and mod_kbdlight.
#
# This module owns almost nothing at runtime, and that is by design. The vendor
# config and the relaunch table are plain files that apply_rootfs has already
# dropped; `w-session` reads them on every invocation, so a file drop IS the
# activation for those. What a file drop is NOT enough for is the daemon: a unit
# rsynced onto the disk is a unit systemd has never been told about. Hence the
# daemon-reload here, plus the start in already-running sessions below — the
# same "copy is not activation" rule that makes mod_mirrors own its timer.
#
# There is deliberately no "should the session be remembered" decision here. The
# shipped default is MODE=off; hyprland.lua starts the daemon and calls the
# restore unconditionally, and `w-session` returns 0 immediately when the mode
# says there is nothing to do. One gate, in the config, where the Hub and the
# CLI both write it. See w-session.md.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_session() {
  # Post-boot only: the installer runs this module through apply.sh at firstboot.
  # There is no session (and no user systemd) inside the chroot.
  [[ -n "${MNT:-}" ]] && return 0

  if ! command -v w-session >/dev/null 2>&1; then
    echo "  WARN: session: w-session not found (run apply.sh --rootfs first)" >&2
    return 0
  fi

  # Global (not per-user) enable, mirroring hypridle in mod_power and the night
  # light tick in mod_nightlight: every login session raises
  # graphical-session.target and must get its own pair of units, not just
  # whoever happened to be logged in during apply.
  #
  # Enabling them unconditionally is correct even though the feature ships off.
  # Whether anything is recorded or reopened is a per-user SETTING, and both
  # entry points read it themselves and return 0 when it says `off`. Gating the
  # unit state on the config instead would give the same question two answers —
  # and the systemd one would win on a machine where the setting changed while
  # logged out.
  #
  # The daemon-reload is what makes a newly shipped unit visible to
  # `systemctl --user` inside a session that is already running.
  systemctl daemon-reload
  systemctl --global enable w-session-save.service 2>/dev/null || true
  systemctl --global enable w-session-restore.service 2>/dev/null || true

  # Bring an ALREADY-RUNNING session up to date. The global enable above only
  # affects sessions started after it, so without this a machine that receives
  # the subsystem while logged in would sit with the units enabled-but-inactive
  # and the snapshot daemon silently not running until the next login. `restart`
  # rather than `start` so a running daemon re-reads a vendor default that
  # changed in this very update.
  #
  # Only the daemon is started here. w-session-restore is deliberately NOT run:
  # it reopens the session saved BEFORE this apply, and doing that in the middle
  # of a live session would drop a second copy of every window on the user.
  #
  # Best-effort per account: one user without a live session must not fail the
  # module for the others. `w-session daemon` exits 0 on its own when the config
  # says there is nothing to record, so restarting it unconditionally is correct
  # — it is the config, not this module, that decides.
  local -a wusers=(); local entry wuser
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: session: no W user account found (uid 1000-65533)." >&2
  if [[ -d /run/systemd/system ]]; then
    for entry in "${wusers[@]}"; do
      wuser="${entry%%$'\t'*}"
      systemctl --user --machine="${wuser}@.host" daemon-reload 2>/dev/null || true
      systemctl --user --machine="${wuser}@.host" restart w-session-save.service 2>/dev/null || true
    done
  fi

  local mode; mode="$(w-conf get session MODE off 2>/dev/null || echo off)"
  ui_info "Session memory ready (mode: $mode). Change it with: w-session mode <off|save|restore>, or W Hub -> System -> Session."
}
