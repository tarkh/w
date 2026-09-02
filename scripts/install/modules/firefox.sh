# modules/firefox.sh — Firefox, the W default web browser.
# apply.sh context: runs on the live system as root.
#
# One module owns the whole "browser" concern (essentials.md boundary rule):
#   • Package — firefox (official extra repo; independent Gecko engine).
#   • Policy  — /etc/firefox/policies/policies.json: system-wide, authoritative,
#               conservative privacy defaults (telemetry/Pocket/studies/sponsored
#               off) that do NOT break sites. Cannot be flipped back from the UI.
#   • Profile — a single pinned profile `w.default` (profiles.ini + user.js). The
#               user.js opt-in `toolkit.legacyUserProfileCustomizations.stylesheets`
#               enables the W transparency layer; MOZ_LEGACY_PROFILES=1 (set in the
#               session env, env-hyprland) makes Firefox honour this pinned profile
#               instead of spawning its own *.default-release, so the W theme axis
#               writes userChrome.css to a deterministic path.
#   • Theme   — COLORS come live from the gtk axis (Firefox is a GTK app); only the
#               chrome TRANSLUCENCY is rendered by `w-style apply firefox` into
#               w.default/chrome/userChrome.css (concept ③). The committed default
#               render ships here; w-style re-renders it on login / theme switch.
# The default-browser MIME association (x-scheme-handler/http=firefox.desktop) is
# declared in the shared mimeapps.list, deployed by the files module.

mod_firefox() {
  info "Installing Firefox (W default browser)..."
  w_pac -S --needed --noconfirm firefox

  info "Deploying system-wide Firefox policy (privacy defaults)..."
  install -Dm644 "$SRC/rootfs/etc/firefox/policies/policies.json" \
    /etc/firefox/policies/policies.json

  info "Deploying pinned Firefox profile (profiles.ini + user.js + userChrome) to skel..."
  rsync -a --chown=root:root "$SRC/rootfs/etc/skel/.mozilla/" /etc/skel/.mozilla/

  # Every human home, not just the first account: the managed userContent.css below
  # is W-owned brand theming, and an existing second user would otherwise keep the
  # copy their account was created with (see lib/deploy.sh w_home_users).
  local -a wusers=(); local entry wuser home_dir
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping user profile copy."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Deploying Firefox profile to $home_dir..."
    # Managed static brand theming (overwrite every apply): userContent.css styles
    # about: pages with live -moz-dialog — no theme token, so it is committed here
    # rather than rendered. seed_user_file owns the parent chain; mirror that for
    # this overwrite path so the profile dirs are user-owned.
    local d
    for d in .mozilla .mozilla/firefox .mozilla/firefox/w.default \
             .mozilla/firefox/w.default/chrome; do
      install -d -o "$wuser" -g "$wuser" "$home_dir/$d"
    done
    install -Dm644 -o "$wuser" -g "$wuser" \
      "$SRC/rootfs/etc/skel/.mozilla/firefox/w.default/chrome/userContent.css" \
      "$home_dir/.mozilla/firefox/w.default/chrome/userContent.css"
    # User-owned profile (profiles.ini, user.js) — seed-if-absent from the module
    # manifest (single source of truth, see lib/deploy.sh) so user edits survive
    # re-apply. chrome/userChrome.css is NOT deployed here: it is a w-style render
    # artifact (concept ③ chrome translucency), written into this profile by
    # `w-style apply firefox` on --style / login (runs after --firefox in --all),
    # the same way shell-colors.zsh is left to w-style.
    deploy_user_manifest firefox "$wuser"
  done

  info "Firefox installed. Chrome translucency renders via --style (and login); colors live via gtk axis."
}
