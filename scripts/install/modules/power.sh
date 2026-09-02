# modules/power.sh — power management (power-profiles-daemon + w-power renderer).
# Userspace layer: wired into apply.sh only (post-boot; the installer stays minimal-base).
#
# power-profiles-daemon provides the profiles; w-power renders idle policy (hypridle),
# lid/power-key (logind) and the battery charge limit from /etc/w/power.conf, driven by
# the machine MODE (laptop|desktop) preset. hypridle.conf is owned here now (moved off
# mod_hyprland). The per-user AC<->battery monitor is a laptop-only user service.
# See w-power.md.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_power() {
  # power-profiles-daemon is in packages/pacman.txt, but a standalone --power run may
  # predate it — install on demand, then enable the system daemon.
  command -v powerprofilesctl >/dev/null 2>&1 \
    || { ui_info "Installing power-profiles-daemon..."; w_pac -S --needed --noconfirm power-profiles-daemon; }
  # Pick up the shipped units (w-charge-limit.service etc.) before w-power enables them.
  systemctl daemon-reload
  systemctl enable --now power-profiles-daemon 2>/dev/null || true

  # hypridle.service ships with the `hypridle` package itself (WantedBy=graphical-
  # session.target, ConditionEnvironment=WAYLAND_DISPLAY) -- global (not per-user)
  # enable mirrors w-power-monitor: every login user's uwsm session raises
  # graphical-session.target and must get its own hypridle, not just the user active
  # during apply. The greeter's hypridle is a separate exec'd process in its own
  # session (never raises graphical-session.target) -- untouched by this.
  systemctl --global enable hypridle.service 2>/dev/null || true

  # First apply detects the machine mode once (chassis / DMI / battery) and seeds the
  # whole policy; later applies just re-render from the (possibly user-edited) conf. The
  # installer answer, when present, wins over auto-detect (W_POWER_MODE — Phase B).
  install -d -m755 /var/lib/w
  local marker=/var/lib/w/power.initialized
  if [[ ! -e "$marker" ]]; then
    # Prefer the installer's "computer type" answer (install.conf, written by the
    # wizard); fall back to W_POWER_MODE (dev override) then chassis auto-detection.
    local want="${W_POWER_MODE:-auto}"
    if [[ "$want" == auto && -r /var/lib/w/install.conf ]]; then
      local ct; ct="$(sed -nE 's/^computer_type=([a-z]+).*/\1/p' /var/lib/w/install.conf)"
      [[ "$ct" == laptop || "$ct" == desktop ]] && want="$ct"
    fi
    ui_info "Seeding power policy (mode: $want)..."
    w-power mode "$want"
    : > "$marker"
  else
    # Also regenerates the vendor layer (/usr/share/w/defaults/power.conf) from
    # this release's preset table and, once per machine, migrates a pre-split
    # /etc/w/power.conf down to its actual deviations — which is what lets an
    # improved default reach a machine that was installed months ago.
    ui_info "Re-rendering power policy (vendor defaults + /etc/w/power.conf)..."
    w-power apply
  fi

  # Every account, not just the first one. The calls above render the machine nodes
  # (logind drop-in, charge threshold, the vendor layer) plus the invoker's own
  # hypridle; the idle policy itself is per-user — each account has its own
  # ~/.config/w/power.conf overrides — so it is rendered once per user, and only
  # the per-user half is repeated (`_render-user`), never the machine nodes.
  #
  # Until this loop existed a second account's hypridle.conf stayed byte-identical
  # to the /etc/skel copy it was created with: every power-policy change (w-power,
  # the Hub, a fleet policy.d mandate) reached exactly one user, and their
  # lock/blank/suspend cascade was frozen at install time. That is closer to a
  # security gap than to cosmetics — see update-system.md phase 5.
  local -a wusers=(); local entry wuser
  mapfile -t wusers < <(w_home_users)
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"
    # `|| true`: an account with no live session simply gets the file (the reload
    # is a no-op), and a single odd home must not abort the module for everyone
    # else — set -e would otherwise take the rest of apply down with it.
    w-power --user "$wuser" _render-user \
      || echo "  WARN: power: could not render idle policy for $wuser" >&2
  done
  # The template new accounts are created from. Rendered from the vendor+admin
  # layers only (no user layer applies to a template), so an account created
  # between two applies starts from THIS machine's policy instead of whatever the
  # repo shipped when the release was cut. Nothing else refreshes it: the file is
  # generated output and appears in no manifest, so w-reset never touches it.
  w-power _render-skel || echo "  WARN: power: could not render the /etc/skel template" >&2

  # The AC<->battery monitor (laptop-only) is kept in sync with the mode by `w-power`
  # itself (render_all, reached by the mode/apply calls above), so nothing to do here.
  local mode; mode="$(sed -nE 's/^MODE=([^#[:space:]]*).*/\1/p' /etc/w/power.conf 2>/dev/null)"
  ui_info "Power management active (mode: ${mode:-?}). Status: w-power status; change mode: sudo w-power mode laptop|desktop."
}
