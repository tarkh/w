# modules/shell.sh — interactive shell stack (zsh + Starship + plugins)
# apply.sh context: runs on the live system as root. Post-boot, BEFORE mod_style
# (w-style renders the Starship [palettes.w] region into the just-deployed
# starship.toml).
#
# Owns: package install, default-shell switch (new accounts + every existing
# account still on bash), seeding the user-owned skel configs (.zshrc,
# starship.toml, atuin/tmux/btop) into every existing human home — seed-if-absent,
# driven by the shell.manifest (see lib/deploy.sh), so user edits survive
# re-apply. Colors are NOT set here:
# shell-colors.zsh + the Starship palette are rendered by the w-style `shell`
# axis (skel at install, $HOME at login via `w-style apply user`), like every
# theme axis. The terminal editors (micro/helix) are owned by mod_files.
#
# fzf + zoxide come from mod_files (yazi deps); .zshrc wires them if present.

mod_shell() {
  info "Installing shell stack (zsh + Starship + plugins + modern CLI)..."
  w_pac -S --needed --noconfirm \
    zsh starship zsh-autosuggestions zsh-syntax-highlighting \
    eza bat jq atuin btop tmux
  # fzf-tab is AUR (fzf-tab in aur.txt, installed by --packages); .zshrc
  # sources it if present.

  info "Setting zsh as the default shell..."
  # New accounts: default login shell for useradd (/etc/default/useradd).
  useradd -D --shell /usr/bin/zsh
  # Existing accounts (uid 1000-65533): switch now. /usr/bin/zsh is registered in
  # /etc/shells by the zsh package, so chsh accepts it.
  local -a wusers=(); local entry wuser home_dir cur_shell
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping chsh + home copy."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    # Only switch an account that is still on bash — i.e. one that never chose.
    # Unconditional chsh in this loop would undo a deliberate `chsh` on EVERY
    # update, which is the opposite of what an update may do to user state.
    cur_shell="$(getent passwd "$wuser" | cut -d: -f7)"
    case "$cur_shell" in */bash) chsh -s /usr/bin/zsh "$wuser" ;; esac
    info "Deploying shell config to $home_dir..."
    # `install -D <file>` creates missing parent dirs as ROOT (only the file gets
    # the -o/-g owner), which then blocks user-scope `w-theme set` from writing
    # theme files into them. Create (and re-own) the per-user config dirs first;
    # `install -d -o` also fixes any dir a previous buggy deploy left root-owned.
    local d
    for d in .config .config/atuin .config/atuin/themes .config/tmux .config/btop .config/btop/themes; do
      install -d -o "$wuser" -g "$wuser" "$home_dir/$d"
    done
    # User-owned layout (.zshrc, starship.toml, atuin/tmux/btop behaviour). These
    # are seed-if-absent so a user's edits survive re-apply — the deploy list
    # lives in the module manifest (single source of truth for deploy + w-reset +
    # drift), see lib/deploy.sh. Their COLORS render via w-style at login.
    deploy_user_manifest shell "$wuser"
  done

  info "Shell installed. Prompt/CLI colors render via w-style (--style); zsh active on next login."
}
