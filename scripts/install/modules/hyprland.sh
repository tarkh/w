# modules/hyprland.sh — Hyprland window manager
# apply.sh context: runs on live system as root.

mod_hyprland() {
  info "Installing Hyprland packages..."
  w_pac -S --needed --noconfirm \
    hyprland \
    uwsm \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal \
    qt5-wayland \
    qt6-wayland \
    ghostty \
    foot

  info "Deploying w-term (single terminal entry point)..."
  # Every W surface (binds, bar, hub, launcher) launches the terminal via w-term;
  # it maps the active terminal to its fastest systemd/D-Bus-correct invocation.
  install -Dm755 "$SRC/rootfs/usr/bin/w-term" /usr/bin/w-term
  # Vendor default selection (TERMINAL=ghostty). Seed-if-absent so an admin edit to
  # /etc/w/terminal.conf survives re-apply; per-user override is ~/.config/w/terminal.conf.
  if [[ ! -f /etc/w/terminal.conf ]]; then
    install -Dm644 "$SRC/rootfs/etc/w/terminal.conf" /etc/w/terminal.conf
  fi

  info "Deploying uwsm-managed Hyprland session..."
  # session entry (Exec=uwsm start ...) + uwsm env preloader (theme render)
  install -Dm644 "$SRC/rootfs/usr/share/wayland-sessions/hyprland.desktop" /usr/share/wayland-sessions/hyprland.desktop
  install -Dm644 "$SRC/rootfs/etc/xdg/uwsm/env-hyprland" /etc/xdg/uwsm/env-hyprland
  # drop the duplicate "Hyprland (uwsm-managed)" entry shipped by the hyprland
  # package; a pacman hook keeps it gone across upgrades
  install -Dm644 "$SRC/rootfs/etc/pacman.d/hooks/hyprland-no-uwsm.hook" /etc/pacman.d/hooks/hyprland-no-uwsm.hook
  rm -f /usr/share/wayland-sessions/hyprland-uwsm.desktop
  # Vendor layer of the per-app rule drop-ins hyprland.lua require()s with a
  # wildcard (W modules and packs each own their <app>.lua in it; --rootfs syncs
  # the tree, this keeps a standalone --hyprland from leaving the dir absent).
  install -d -m755 /usr/share/w/hypr/rules.d

  # Session dotfiles to deploy (Hyprland config + Ghostty + foot terminal config)
  local subdirs=(hypr ghostty foot)

  info "Deploying session config to skel..."
  local d
  for d in "${subdirs[@]}"; do
    mkdir -p "/etc/skel/.config/$d"
    rsync -a --chown=root:root "$SRC/rootfs/etc/skel/.config/$d/" "/etc/skel/.config/$d/"
  done

  # Copy to every human home (skel only ever reaches accounts created later, so an
  # existing second user gets the managed hotkey catalog only from here — see
  # lib/deploy.sh w_home_users).
  local -a wusers=(); local entry wuser home_dir
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping user config copy."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Deploying session config to $home_dir..."
    # Managed content (hotkeys-catalog.lua) is overwritten every apply; user-owned
    # files are excluded here and seeded seed-if-absent below so edits survive
    # re-apply. The hypr/ dir is shared with the hyprlock module — exclude its
    # hyprlock.conf too (hyprlock's own manifest seeds it), otherwise this rsync
    # would clobber it. hypridle.conf is excluded because w-power (apply.sh --power)
    # RENDERS it into home from the machine mode + idle timers — not a seeded static
    # file anymore.
    #
    # The w-style renders — hypr/{colors,animations,effects,geometry}.lua,
    # hyprlock-colors.conf, ghostty/themes/w — are excluded for the reason spelled
    # out in lib/deploy.sh (w_render_user_theme): skel's copy is the baseline theme
    # `w`, so shipping it into a live home reset whatever theme the account runs.
    # apply.sh re-renders them for that account at the end of the run instead.
    mkdir -p "$home_dir/.config/hypr"
    rsync -a --chown="$wuser:$wuser" \
      --exclude='hyprland.lua' --exclude='hypridle.conf' \
      --exclude='hyprpaper.conf' --exclude='xdph.conf' --exclude='hyprlock.conf' \
      --exclude='keyboard.lua' --exclude='hotkeys.lua' --exclude='monitors.lua' \
      --exclude='pointer.lua' \
      --exclude='colors.lua' --exclude='animations.lua' \
      --exclude='effects.lua' --exclude='geometry.lua' \
      --exclude='hyprlock-colors.conf' \
      "$SRC/rootfs/etc/skel/.config/hypr/" "$home_dir/.config/hypr/"
    mkdir -p "$home_dir/.config/ghostty"
    rsync -a --chown="$wuser:$wuser" --exclude='config' --exclude='themes/w' \
      "$SRC/rootfs/etc/skel/.config/ghostty/" "$home_dir/.config/ghostty/"
    # Only what W owns here — never the whole ~/.config. A blanket `chown -R` over
    # the user's config root walks every application's data, and on a LIVE machine
    # (the normal case for an edge update) it races: an app that rewrites a file
    # via a temp copy (Bitwarden's data.json.tmp-*) makes chown exit non-zero, and
    # under `set -e` that aborts the entire `apply --all` at this module — every
    # later module, including mod_power, silently never runs. Caught on real
    # hardware. `|| true` for the same reason: a vanishing file in someone's live
    # session must not fail an update. Scope matches mod_quickshell's precedent.
    chown "$wuser:$wuser" "$home_dir/.config" 2>/dev/null || true
    chown -R "$wuser:$wuser" \
      "$home_dir/.config/hypr" "$home_dir/.config/ghostty" 2>/dev/null || true
    # User-owned session config (hyprland.lua, hyprpaper/xdph.conf, ghostty/config).
    # Seeded from the module manifest (single source of truth, see lib/deploy.sh) —
    # seed-if-absent, so user edits survive re-apply. (hypridle.conf is rendered by
    # w-power, not seeded — see the exclude above.)
    deploy_user_manifest hyprland "$wuser"
  done

  # Pre-warm Ghostty via its systemd/D-Bus integration. The service starts the GTK
  # process at login (uwsm exports the Wayland env to the systemd user manager), so
  # the Super+Return bind (`ghostty +new-window`) opens surfaces of one shared daemon
  # in ~20ms instead of spawning a fresh ~300ms process per window. --global enables
  # it for every user; the unit ships with the ghostty package. Guard so a
  # standalone run before the package is present doesn't fail the module.
  #
  # Hanging a vendor unit off graphical-session.target also enlists it in W's
  # NON-graphical activation of that target (mod_nightlight restarts hyprsunset,
  # whose Requires= pulls the target, in a session-less user manager at firstboot).
  # Ghostty's unit is the only one under the target without
  # ConditionEnvironment=WAYLAND_DISPLAY, so it used to really start there and die
  # on "Gtk: Failed to open display". W adds the condition back with a drop-in:
  # rootfs/etc/systemd/user/app-com.mitchellh.ghostty.service.d/10-w-wayland.conf.
  if [[ -f /usr/lib/systemd/user/app-com.mitchellh.ghostty.service ]]; then
    systemctl --global enable app-com.mitchellh.ghostty.service
    info "Ghostty pre-warm service enabled (instant windows via ghostty +new-window)."
  else
    echo "  WARN: app-com.mitchellh.ghostty.service not found — Ghostty pre-warm skipped."
  fi

  # hyprpaper.service ships with the `hyprpaper` package itself (PartOf/Requires/
  # After=graphical-session.target, ConditionEnvironment=WAYLAND_DISPLAY, Restart=
  # on-failure) -- global (not per-user) enable mirrors mod_power's hypridle.service:
  # every login user's uwsm session raises graphical-session.target and must get its
  # own hyprpaper, not just the user active during apply. Replaces the old manual
  # `uwsm app -- hyprpaper` exec in hyprland.lua (removed there) -- systemd now owns
  # the daemon's lifecycle (start on session-up, stop on session-down, auto-restart
  # on crash); `w-wallpaper apply --wait` still tells it which image to show.
  if [[ -f /usr/lib/systemd/user/hyprpaper.service ]]; then
    systemctl --global enable hyprpaper.service
    info "hyprpaper.service enabled globally (per-session wallpaper daemon)."
    # --global enable only writes the graphical-session.target.wants/ symlink; an
    # ALREADY-RUNNING user manager (any account with a pre-existing session, e.g.
    # every account on a live edge update) has its unit graph cached and won't
    # notice the new dependency without a reload -- found live on the dev VM:
    # hyprpaper.service stayed loaded+enabled but never started, invisible to
    # `list-dependencies graphical-session.target`, until reloaded. Reload every
    # existing account so the unit is live for their NEXT login, and
    # opportunistically start it now for whoever already has a graphical session
    # up, so a live desktop doesn't need a logout/login for this one daemon.
    # `--machine=<user>@.host` reaches each account's own systemd --user instance
    # from root without manual runuser+env plumbing (same shape as w-power's
    # reload_hypridle `--machine="${TARGET_USER}@.host"`).
    for entry in "${wusers[@]}"; do
      wuser="${entry%%$'\t'*}"
      systemctl --user --machine="${wuser}@.host" daemon-reload 2>/dev/null || true
      if systemctl --user --machine="${wuser}@.host" is-active --quiet graphical-session.target 2>/dev/null; then
        systemctl --user --machine="${wuser}@.host" start hyprpaper.service 2>/dev/null || true
      fi
    done
  else
    echo "  WARN: hyprpaper.service not found — hyprpaper global-enable skipped."
  fi
}
