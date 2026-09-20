# modules/quickshell.sh — Quickshell UI shell (launcher, and future components)
# apply.sh context: runs on live system as root.
#
# Module boundary (see essentials.md rule): Quickshell is its own UI system, so it
# owns BOTH its package and its skel config (unlike the launcher, whose config rode
# the hypr/ sync). Theme colors and motion are rendered INTO this config by w-style
# (apply.sh --style → subsystems `quickshell` + `motion`). Autostart and the $mod+D
# global shortcut live in hyprland.lua (apply.sh --hyprland).

mod_quickshell() {
  info "Installing Quickshell UI shell..."
  # quickshell        — QtQuick/QML Wayland shell (official Arch repo)
  # papirus-icon-theme — the active icon theme Papirus-Dark; resolves launcher app
  #   icons (Quickshell.iconPath, via Qt's QIcon theme). breeze-icons — the
  #   breeze-dark fallback Papirus-Dark inherits for gaps. Kept here so
  #   `apply.sh --quickshell` stays standalone.
  # cliphist            — clipboard-history store (text + images). Fed by the two
  #   `wl-paste --watch w-cliphist-store` daemons in hyprland.lua (w-cliphist-store is
  #   a rootfs gate that honours the manager on/off + password-filter toggles in
  #   clipboard.json before `cliphist store`); browsed by the Quickshell Clipboard
  #   component ($mod+V). Rides here (a UI component, not its own module). Depends on
  #   wl-clipboard (already pulled by --screencapture).
  # wl-clip-persist     — keeps the live Wayland clipboard alive after the source
  #   app closes (cliphist only records history; Wayland selection dies with the
  #   owner client). Autostarted in hyprland.lua alongside the cliphist watchers.
  w_pac -S --needed --noconfirm \
    quickshell \
    papirus-icon-theme breeze-icons \
    cliphist wl-clip-persist

  # w-notify — the notification subsystem's CLI (Do Not Disturb, history, per-app
  # mute), backing the Hub Notifications panel, the bar's DND block, the `dnd` hotkey
  # and the AI tools. It rides this module rather than owning one: the notification
  # server IS Quickshell, and the tool only ever writes that shell's user config +
  # state. apply_rootfs already lays it down for `--all`; installing it explicitly
  # keeps a standalone `apply.sh --quickshell` self-contained (as in --style).
  install -Dm755 "$SRC/rootfs/usr/bin/w-notify" /usr/bin/w-notify

  # Config (QML + default colors.json/motion.json) and the Qt icon-theme hint +
  # KDE colour scheme. Deployed to BOTH /etc/skel (the template for accounts yet to
  # be created) AND every existing human home (skel does not propagate to accounts
  # that already exist). Qt resolves themed icons (Quickshell.iconPath) via QIcon::fromTheme,
  # whose theme name the unix platform theme reads from kdeglobals [Icons]; KDE apps
  # (Dolphin) read [UiSettings] ColorScheme=W and load the W.colors scheme file. The
  # Kvantum config (kvantum.kvconfig + w/{w.kvconfig,w.svg,w.colors}) is the SVG widget engine
  # for themes with W_QT_STYLE=kvantum. All are rendered by the w-style qt axis; copied
  # here so they exist pre-login.
  info "Deploying Quickshell config + kdeglobals + W.colors + Kvantum to skel..."
  mkdir -p /etc/skel/.config/quickshell
  rsync -a --chown=root:root "$SRC/rootfs/etc/skel/.config/quickshell/" /etc/skel/.config/quickshell/
  install -Dm644 "$SRC/rootfs/etc/skel/.config/kdeglobals" /etc/skel/.config/kdeglobals
  install -Dm644 "$SRC/rootfs/etc/skel/.config/cliphist/config" /etc/skel/.config/cliphist/config
  install -Dm644 "$SRC/rootfs/etc/skel/.local/share/color-schemes/W.colors" \
    /etc/skel/.local/share/color-schemes/W.colors
  install -Dm644 "$SRC/rootfs/etc/skel/.config/Kvantum/kvantum.kvconfig" \
    /etc/skel/.config/Kvantum/kvantum.kvconfig
  install -Dm644 "$SRC/rootfs/etc/skel/.config/Kvantum/w/w.kvconfig" \
    /etc/skel/.config/Kvantum/w/w.kvconfig
  install -Dm644 "$SRC/rootfs/etc/skel/.config/Kvantum/w/w.svg" \
    /etc/skel/.config/Kvantum/w/w.svg
  install -Dm644 "$SRC/rootfs/etc/skel/.config/Kvantum/w/w.colors" \
    /etc/skel/.config/Kvantum/w/w.colors

  # Every human account, not just the first one: skel is a template for accounts
  # yet to be created, so an existing second user only ever gets an update from
  # here (see lib/deploy.sh w_home_users). Managed content below is overwritten
  # for each of them; the user-owned config/*.json stays seed-if-absent.
  local -a wusers=(); local entry wuser home_dir
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping user config copy."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Deploying Quickshell config to $home_dir..."
    # `install -D <file>`'s -o/-g apply ONLY to the file, so the .local + .local/share
    # parents it auto-creates for W.colors below land ROOT-owned — and nobody re-owns
    # .local afterwards (mod_shell only fixes .config). That breaks every user-scope
    # write under ~/.local at login: `w-style apply user` aborts on .local/share/
    # color-schemes/W.colors (set -e), killing the icons/qt/gtk axes, and atuin can't
    # create ~/.local/share/atuin. Pre-create + own the chain (install -d -o also
    # re-owns dirs a previous root deploy left behind — same pattern as mod_shell).
    # .local/state/w is where the shell writes the notification history and w-notify
    # writes the DND state; neither can mkdir a root-owned parent, so pre-create the
    # chain here (w-update's updates.json lives in the same dir).
    local d
    for d in .local .local/share .local/share/color-schemes .local/state .local/state/w; do
      install -d -o "$wuser" -g "$wuser" "$home_dir/$d"
    done
    mkdir -p "$home_dir/.config/quickshell"
    # Managed content (the QML tree + the static core/i18n.json) is overwritten
    # every apply; the user-owned config/*.json (bar/launcher/… behaviour) is
    # excluded here and seeded seed-if-absent below so user edits survive re-apply.
    #
    # The theme-derived core/*.json is excluded for a THIRD reason (lib/deploy.sh,
    # w_render_user_theme): those files are w-style output for whatever theme the
    # ACCOUNT runs, and skel's copy is the baseline theme `w`. Copying it into a
    # live home reset every custom theme on every update — the shell fell back to
    # W's palette while the rest of the desktop kept the user's. apply.sh re-renders
    # them for real at the end of the run instead. Add an exclude here whenever a
    # new w-style axis starts writing into core/.
    rsync -a --chown="$wuser:$wuser" --exclude='config/' \
      --exclude='core/colors.json' --exclude='core/logo.json' \
      --exclude='core/effects.json' --exclude='core/geometry.json' \
      --exclude='core/motion.json' --exclude='core/font.json' \
      "$SRC/rootfs/etc/skel/.config/quickshell/" "$home_dir/.config/quickshell/"
    # Own the parent first: `install -D` creates a missing parent with root's
    # attributes and only chowns the file, which is how ~/.config/cliphist ended
    # up root-owned on every account (the seed_user_file trap, for a managed file).
    install -d -o "$wuser" -g "$wuser" "$home_dir/.config/cliphist"
    install -Dm644 -o "$wuser" -g "$wuser" \
      "$SRC/rootfs/etc/skel/.config/cliphist/config" "$home_dir/.config/cliphist/config"
    # kdeglobals, W.colors and the Kvantum theme are w-style's qt axis in full (it
    # rewrites each whole file), so they are render artifacts like the JSON above:
    # deployed to skel for accounts yet to be created, seeded here only when absent,
    # never overwritten. The render at the end of the apply owns their content.
    seed_user_file "$SRC/rootfs/etc/skel/.config/kdeglobals" \
      "$home_dir/.config/kdeglobals" "$wuser" "$home_dir"
    seed_user_file "$SRC/rootfs/etc/skel/.local/share/color-schemes/W.colors" \
      "$home_dir/.local/share/color-schemes/W.colors" "$wuser" "$home_dir"
    seed_user_file "$SRC/rootfs/etc/skel/.config/Kvantum/kvantum.kvconfig" \
      "$home_dir/.config/Kvantum/kvantum.kvconfig" "$wuser" "$home_dir"
    seed_user_file "$SRC/rootfs/etc/skel/.config/Kvantum/w/w.kvconfig" \
      "$home_dir/.config/Kvantum/w/w.kvconfig" "$wuser" "$home_dir"
    seed_user_file "$SRC/rootfs/etc/skel/.config/Kvantum/w/w.svg" \
      "$home_dir/.config/Kvantum/w/w.svg" "$wuser" "$home_dir"
    seed_user_file "$SRC/rootfs/etc/skel/.config/Kvantum/w/w.colors" \
      "$home_dir/.config/Kvantum/w/w.colors" "$wuser" "$home_dir"
    # install -D creates parent dirs as root; hand the whole tree to the user so a
    # later user-scope render (login w-style apply) can recreate files if needed.
    chown -R "$wuser:$wuser" \
      "$home_dir/.config/quickshell" "$home_dir/.config/Kvantum"

    # User-owned component config (config/*.json: bar/launcher/clipboard/…). Seeded
    # seed-if-absent from the module manifest (single source of truth for deploy +
    # w-reset + drift, see lib/deploy.sh) so user edits survive re-apply.
    deploy_user_manifest quickshell "$wuser"

    # Live-reload the running shell so the freshly-deployed QML loads. Quickshell
    # watches its files, but rsync's atomic rename swaps the inode and the per-file
    # watch misses it, so an explicit restart is needed. Relaunch must happen inside
    # the user's Hyprland session (it needs WAYLAND_DISPLAY), so we drive it through
    # Hyprland IPC. Silent no-op when there is no live session or no running instance
    # (e.g. at install time, before first login) — nothing prints, nothing fails.
    #
    # `pkill -9 -x quickshell` (not `qs -c w kill`) is deliberate: it clears EVERY
    # instance, including crash-handler children left behind by an earlier abort. A
    # graceful one-instance kill races with Quickshell's own crash-auto-restart and
    # leaves two instances fighting over the single-instance Wayland layer surfaces,
    # which aborts (qFatal). SIGKILL can't be caught, so it never triggers the crash
    # handler's restart — we then launch exactly one fresh instance after a short
    # settle so the compositor releases the old surfaces.
    local ruid runtime hyprdir his
    ruid=$(id -u "$wuser" 2>/dev/null)
    runtime="/run/user/$ruid"
    # `|| true`: on a fresh first boot apply.sh --all runs from a TTY before any
    # login, so /run/user/$UID/hypr/* does not exist; the failing glob would trip
    # `set -euo pipefail` and abort the whole run mid-module (silently swallowing
    # every later module: sensors/files/shell/style). Neutralise it — the block is
    # meant to be a no-op when there is no live session.
    hyprdir=$(ls -dt "$runtime"/hypr/* 2>/dev/null | head -1) || true
    his=""; [[ -n "$hyprdir" ]] && his=$(basename "$hyprdir")
    if [[ -n "$ruid" && -n "$his" ]] \
       && pgrep -u "$wuser" -x quickshell >/dev/null 2>&1; then
      info "Reloading running Quickshell for $wuser..."
      runuser -u "$wuser" -- env \
        XDG_RUNTIME_DIR="$runtime" \
        HYPRLAND_INSTANCE_SIGNATURE="$his" \
        hyprctl dispatch \
          'hl.dsp.exec_cmd("pkill -9 -x quickshell; sleep 1; uwsm app -- quickshell -c w")' \
        >/dev/null 2>&1 || true
    fi
  done

  info "Quickshell installed. Colors/motion render via --style; autostart + \$mod+D via --hyprland."
}
