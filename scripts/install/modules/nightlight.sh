# modules/nightlight.sh — night light / blue-light filter (w-nightlight + hyprsunset).
#
# Userspace layer: wired into apply.sh only (post-boot; the installer stays
# minimal-base), same as mod_power and mod_kbdlight.
#
# Two things happen here and nothing else: the daemon's user unit is globally
# enabled so every login session gets one, and the config it reads is rendered
# from W's layered config. Both are idempotent, so a routine `apply.sh --all`
# just re-renders — which is how an improved vendor default (a better night
# temperature, say) actually reaches an installed machine.
#
# There is deliberately no "should the filter be on" decision in this module: the
# shipped default is MODE=off and `w-nightlight` renders an identity profile for
# it. The daemon runs either way, which keeps the Hub's live preview and the
# toggle key working with no unit state to keep in sync. See w-nightlight.md.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_nightlight() {
  # Post-boot only: the installer runs this module through apply.sh at firstboot.
  # There is no session (and no user systemd) inside the chroot to render for.
  [[ -n "${MNT:-}" ]] && return 0

  # hyprsunset is in packages/pacman.txt, but a standalone --nightlight run may
  # predate it — install on demand.
  command -v hyprsunset >/dev/null 2>&1 \
    || { ui_info "Installing hyprsunset..."; w_pac -S --needed --noconfirm hyprsunset; }

  # hyprsunset.service ships with the `hyprsunset` package itself. Global (not
  # per-user) enable mirrors hypridle in mod_power: every login user's uwsm
  # session raises graphical-session.target and must get its own daemon, not just
  # whoever happened to be logged in during apply. The greeter runs a separate
  # compositor that never raises that target, so its screen stays untinted —
  # a known and documented limitation, not an oversight.
  systemctl daemon-reload
  systemctl --global enable hyprsunset.service 2>/dev/null || true

  # W's own tick: hyprsunset can only switch instantly at a time, so the schedule
  # is evaluated here, once a minute. Same global enable, same reason.
  #
  # Its companion w-nightlight-ramp.service (which owns the transition itself) is
  # deliberately NOT enabled and NOT wanted by anything: `w-nightlight` starts it
  # on demand and it exits as soon as the screen has arrived. The daemon-reload
  # above is what makes a newly shipped unit visible to `systemctl --user start`
  # in an already-running session.
  systemctl --global enable w-nightlight-tick.timer 2>/dev/null || true
  # The oneshot too, not only its timer. It costs one comparison at session start
  # and buys an evaluation that does not depend on the timer having started: with
  # only the timer enabled, anything that keeps the timer down (it was condition-
  # skipped for a whole session before the `After=` fix) also meant the schedule
  # was never evaluated even once. Two independent paths to the same cheap check.
  systemctl --global enable w-nightlight-tick.service 2>/dev/null || true

  if ! command -v w-nightlight >/dev/null 2>&1; then
    echo "  WARN: nightlight: w-nightlight not found (run apply.sh --rootfs first)" >&2
    return 0
  fi

  # Render ~/.config/hypr/hyprsunset.conf for EVERY account, not just the first
  # one: every key of this subsystem is user-scope, so each account has its own
  # window and temperature and needs its own render. Before this loop a second
  # user had no hyprsunset.conf at all and the night light simply did not exist
  # for them.
  #
  # Each call also STARTS the daemon in that user's running session (w-nightlight's
  # reload() uses `restart`, not `try-restart`). That matters specifically on the
  # update path: the global enable above only affects sessions started after it, so
  # a machine that receives this subsystem while logged in would otherwise sit with
  # the unit enabled-but-inactive and the night light silently doing nothing until
  # the next login. At firstboot there is no session and the start is skipped by the
  # unit's ConditionEnvironment — correct, the session will start it.
  local -a wusers=(); local entry wuser
  mapfile -t wusers < <(w_home_users)
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"
    w-nightlight --user "$wuser" apply \
      || echo "  WARN: nightlight: could not render hyprsunset.conf for $wuser" >&2
    # Start the tick in an ALREADY-RUNNING session too, for the same reason the
    # daemon is started above. Best-effort: an account with no session has no user
    # manager to talk to, and that must not fail the module for the others.
    if [[ -d /run/systemd/system ]]; then
      systemctl --user --machine="${wuser}@.host" daemon-reload 2>/dev/null || true
      systemctl --user --machine="${wuser}@.host" start w-nightlight-tick.timer 2>/dev/null || true
      # …and force ONE evaluation inside that session right now. The `apply` above
      # runs as root, where there is no HYPRLAND_INSTANCE_SIGNATURE and therefore
      # no way to reach the user's hyprsunset — it renders the file and no more.
      # This oneshot runs with the session's own environment, so it is what
      # actually eases the screen to a changed vendor default without a relogin.
      systemctl --user --machine="${wuser}@.host" start w-nightlight-tick.service 2>/dev/null || true
    fi
  done

  local mode; mode="$(w-conf get nightlight MODE off 2>/dev/null || echo off)"
  ui_info "Night light ready (mode: $mode). Change it with: w-nightlight mode <off|schedule|always>, or W Hub -> Displays -> Night light."
}
