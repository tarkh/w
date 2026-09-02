# modules/hyprlock.sh — hyprlock lock screen + hypridle idle daemon
# apply.sh context: runs on live system as root.
#
# Module boundary (see essentials.md rule): hyprlock is its own component, so it
# owns its packages, its PAM stack and its skel config (hyprlock.conf,
# hyprlock-colors.conf — NOT hypridle.conf, that's rendered by w-power, apply.sh
# --power, see w-power.md). Colors are rendered INTO hyprlock-colors.conf by
# w-style (apply.sh --style → subsystem `hyprlock`). The lock keybind is a
# w-hotkeys default (hotkeys-catalog.lua); the hypridle autostart is its packaged
# systemd user unit, global-enabled by mod_power (apply.sh --power).

mod_hyprlock() {
  info "Installing hyprlock + hypridle + fprintd..."
  # hyprlock  — GPU lock screen (screenshot+blur background, themed input)
  # hypridle  — idle daemon: auto-lock + lock-before-sleep + DPMS
  # fprintd   — fingerprint D-Bus service; hyprlock auths against it in parallel
  #             with the password (active once a finger is enrolled, fprintd-enroll)
  w_pac -S --needed --noconfirm \
    hyprlock \
    hypridle \
    fprintd

  info "Deploying hyprlock PAM stack..."
  # Explicit auth stack (include system-auth) so password unlock always works,
  # independent of the package default.
  install -Dm644 "$SRC/rootfs/etc/pam.d/hyprlock" /etc/pam.d/hyprlock

  # Config files owned by this module (hypridle.conf is NOT among them — w-power
  # renders it, apply.sh --power). hyprlock.conf is the user's behavioural config
  # (seed-if-absent); hyprlock-colors.conf is a w-style render artifact (managed,
  # overwrite) — the committed default ships so a lock works before --style runs.
  info "Deploying hyprlock config to skel..."
  install -Dm644 "$SRC/rootfs/etc/skel/.config/hypr/hyprlock.conf" \
    /etc/skel/.config/hypr/hyprlock.conf
  install -Dm644 "$SRC/rootfs/etc/skel/.config/hypr/hyprlock-colors.conf" \
    /etc/skel/.config/hypr/hyprlock-colors.conf

  # Copy to every human home (skel does not propagate to existing accounts).
  local -a wusers=(); local entry wuser home_dir
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping user config copy."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Deploying hyprlock config to $home_dir..."
    # Colours are a w-style render artifact, not W-owned static content: skel holds
    # the baseline theme `w`, so overwriting a live home here used to drop the lock
    # screen back to W's palette on every apply (lib/deploy.sh, w_render_user_theme).
    # Seed it so a lock works before the first render, then leave it to w-style.
    seed_user_file "$SRC/rootfs/etc/skel/.config/hypr/hyprlock-colors.conf" \
      "$home_dir/.config/hypr/hyprlock-colors.conf" "$wuser" "$home_dir"
    # User-owned hyprlock.conf — seed-if-absent from the module manifest (single
    # source of truth, see lib/deploy.sh) so user edits survive re-apply.
    deploy_user_manifest hyprlock "$wuser"
  done

  info "hyprlock installed. Colors render via --style; idle timers + hypridle autostart via --power."
  info "Fingerprint unlock activates after enrolling a finger: run 'fprintd-enroll' as your user."
}
