# modules/files.sh — File management stack (CLI + GUI + network + removable media)
# apply.sh context: runs on the live system as root.
#
# One module owns the whole "files" concern (essentials.md boundary rule):
#   • CLI  — yazi (+ preview/search helpers); themed by w-style `yazi` axis.
#   • GUI  — Nemo (GTK3), auto-themed live by the W gtk axis (no work here).
#   • Net  — avahi + nss-mdns (LAN discovery) + gvfs backends (dnssd/wsdd/SMB/NFS/
#            AFC/MTP). gvfs's bundled gvfsd-fuse exposes mounts at
#            /run/user/$UID/gvfs so yazi/CLI see them too.
#   • Disks— udisks2 + udiskie (auto-mount) + NTFS/exFAT/APFS drivers.
#   • Media— lightweight Wayland viewers the FMs hand files off to: imv (images),
#            mpv (video + audio, with a brand audio spectrogram), zathura +
#            zathura-pdf-mupdf (PDF/EPUB/CBZ/XPS). Their palettes are w-style axes
#            (imv/mpv/zathura); this module owns the packages + mimeapps defaults.
#   • Editors — terminal text editors: micro (default EDITOR/VISUAL, set in
#            /etc/environment via apply_rootfs; vim stays in base.txt as
#            fallback) + helix (secondary modal editor). Themed by the w-style
#            `micro`/`helix` axes.
#
# Skel config shipped here: yazi.toml + mimeapps.list (defaults + file
# associations) + mpv.conf (behaviour; its colours come from w-style via an
# included fragment) + micro/settings.json + helix/config.toml (both select
# colorscheme/theme "w", rendered by w-style). yazi's COLORS (theme.toml), imv's
# config, zathura's zathurarc, micro's colorschemes/w.micro and helix's
# themes/w.toml are owned/rendered by w-style, not here — same split as
# Quickshell (config in rootfs, palette from the theme). udiskie autostart lives
# in hyprland.lua (apply.sh --hyprland), like every other user-session exec-once.

mod_files() {
  info "Installing file-management packages..."
  # APFS support is a DKMS kernel module (linux-apfs-rw-dkms). pacman's dkms hook
  # builds it against the headers of the running kernel — for W that is
  # linux-zen-headers (base.txt). We deliberately do NOT pull vanilla linux-headers
  # here: with linux-zen as the kernel that would install headers for a kernel that
  # isn't present, and the dkms autoinstall hook then fails trying to build apfs for
  # the missing vanilla modules tree. Switching kernels installs the paired headers
  # via w-kernel, so the running kernel always has its headers.
  w_pac -S --needed --noconfirm \
    yazi ffmpegthumbnailer 7zip poppler fd ripgrep fzf zoxide jq \
    imv mpv zathura zathura-pdf-mupdf \
    nemo cinnamon-translations nemo-fileroller file-roller tumbler \
    avahi nss-mdns gvfs gvfs-dnssd gvfs-wsdd gvfs-smb gvfs-nfs gvfs-afc gvfs-mtp gvfs-gphoto2 \
    udisks2 udiskie \
    ntfs-3g exfatprogs linux-apfs-rw-dkms dkms \
    micro helix

  info "Enabling Avahi (mDNS/Bonjour discovery of NAS/TimeCapsule/SMB hosts)..."
  systemctl enable --now avahi-daemon.service

  info "Wiring mDNS into NSS hostname resolution..."
  # Resolve *.local names via avahi. Insert mdns_minimal before `resolve` (or
  # `dns`), once — idempotent across re-runs.
  local nss=/etc/nsswitch.conf
  if [[ -f "$nss" ]] && ! grep -q '^hosts:.*mdns' "$nss"; then
    if grep -qE '^hosts:.*\bresolve\b' "$nss"; then
      sed -i -E 's/^(hosts:.*)\bresolve\b/\1mdns_minimal [NOTFOUND=return] resolve/' "$nss"
    else
      sed -i -E 's/^(hosts:.*)\bdns\b/\1mdns_minimal [NOTFOUND=return] dns/' "$nss"
    fi
  fi

  info "Deploying yazi + mpv + mimeapps.list + udiskie + micro + helix config to skel..."
  mkdir -p /etc/skel/.config/yazi
  rsync -a --chown=root:root "$SRC/rootfs/etc/skel/.config/yazi/" /etc/skel/.config/yazi/
  install -Dm644 "$SRC/rootfs/etc/skel/.config/mpv/mpv.conf" /etc/skel/.config/mpv/mpv.conf
  install -Dm644 "$SRC/rootfs/etc/skel/.config/mimeapps.list" /etc/skel/.config/mimeapps.list
  install -Dm644 "$SRC/rootfs/etc/skel/.config/udiskie/config.yml" /etc/skel/.config/udiskie/config.yml
  # micro: settings.json selects colorscheme "w" (rendered by the w-style
  # `micro` axis at login into colorschemes/w.micro).
  install -Dm644 "$SRC/rootfs/etc/skel/.config/micro/settings.json" /etc/skel/.config/micro/settings.json
  # helix: config.toml selects theme "w" (rendered by the w-style `helix` axis
  # at login into themes/w.toml).
  install -Dm644 "$SRC/rootfs/etc/skel/.config/helix/config.toml" /etc/skel/.config/helix/config.toml

  local -a wusers=(); local entry wuser home_dir
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping user config copy."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Deploying file-manager config to $home_dir..."
    # Pre-create the per-user config dirs OWNED BY the user. seed_user_file owns
    # the parent chain of each seeded file, but the w-style axes render their
    # theme artifacts into SIBLING dirs (yazi/theme.toml, mpv/w-theme.conf,
    # micro/colorschemes/w.micro, helix/themes/w.toml) that no seed file parents —
    # `install -D`/w-style would otherwise create them root-owned and unwritable.
    local d
    for d in .config/yazi .config/mpv .config/udiskie \
             .config/micro/colorschemes .config/helix/themes; do
      install -d -o "$wuser" -g "$wuser" "$home_dir/$d"
    done
    # User-owned layout (yazi.toml, mpv.conf, mimeapps.list, udiskie, micro/helix
    # behaviour). seed-if-absent so a user's edits survive re-apply — the deploy
    # list lives in the module manifest (single source of truth for deploy +
    # w-reset + drift), see lib/deploy.sh. Their COLORS/themes render via w-style.
    deploy_user_manifest files "$wuser"
    # Default micro plugin set (core + extras). micro -plugin install writes into
    # the invoking user's ~/.config/micro/plug/, so run as that user. Needs network
    # — best-effort, never fail the module if offline.
    #
    # Seeded ONCE per account, not on every apply: this is the only place in the
    # base modules where a module runs a THIRD-PARTY installer that reaches the
    # network and writes into someone's home (the pack SDK's `uv tool install` is
    # the other one, outside the base). Re-running it per account per apply would
    # cost N network round-trips every update and would fight a user who removed a
    # plugin on purpose. A populated plug/ means the seed already happened.
    if [[ -z "$(ls -A "$home_dir/.config/micro/plug" 2>/dev/null)" ]]; then
      info "Installing micro plugins for $wuser (best-effort)..."
      runuser -u "$wuser" -- env HOME="$home_dir" \
        micro -plugin install fzf detectindent editorconfig manipulator quoter wc \
        >/dev/null 2>&1 || echo "  WARN: micro plugin install skipped (offline?)."
    fi
  done

  # APFS DKMS build status — surface failures (e.g. missing headers) without aborting.
  if command -v dkms &>/dev/null; then
    if dkms status 2>/dev/null | grep -qi 'apfs.*installed'; then
      info "APFS DKMS module built and installed."
    else
      echo "  WARN: APFS DKMS module not reported installed — check 'dkms status'." >&2
    fi
  fi

  info "Files installed. yazi/imv/mpv/zathura/micro/helix colors render via --style; udiskie autostart via --hyprland; micro is the default EDITOR."
}
