# modules/flatpak.sh — sandboxed third-party apps: Flatpak + Flathub + Bazaar
# + Flatseal + W theme overrides (security.md, point Г / step ⑨)
#
# Userspace layer, apply-only (like files/firewall/dns — the installer stays
# minimal-base). Flatpak is the W standard for untrusted/third-party GUI apps;
# pacman stays for the base system and W components. Isolation = bubblewrap
# (namespaces + seccomp) + xdg-desktop-portals (XDPH + gtk already installed).
#
# THE HARD PART — carrying the W theme into the sandbox. A Flatpak app sees the
# runtime's /usr and a private $HOME, NOT the host's themes/configs. /usr/share/
# themes and /usr/share/icons are BLACKLISTED (a --filesystem bind there is a silent
# no-op). What does work, per toolkit (all verified on VM):
#
#   • GTK3 — flatpak mounts the Gtk3theme EXTENSION whose name equals the host
#     gtk-theme (reported via xdg-desktop-portal-gtk → gsettings), which the
#     appearance axis flips between w-gtk and w-gtk-alt for live host recolor. The
#     w-gtk twins @import an ABSOLUTE adw-gtk3 path the sandbox can't resolve, so the
#     extensions must be SELF-CONTAINED. This module does NOT build them — the w-style
#     `gtk` axis does (sync_flatpak_gtk3), so they track every theme switch, for BOTH
#     names, user-scope (rendered at login by env-hyprland). No GTK_THEME env is set
#     (the portal already names the theme; any value — even empty — breaks GTK3/GTK4).
#   • GTK4/libadwaita — ignores named themes; reads ~/.config/gtk-4.0/gtk.css (bound)
#     for the brand @define-colors and the portal's icon-theme for icons. (GTK_THEME
#     would break it — left unset.)
#   • Qt — qt5ct/qt6ct platform themes do NOT load in the sandbox (no plugin in the
#     runtimes). The KDE runtime ships KDEPlasmaPlatformTheme, so QT_QPA_PLATFORMTHEME=
#     kde drives Qt brand from bound kdeglobals: the W KColorScheme, [Icons] Theme, and
#     [General] font (the only Qt font channel in the sandbox — w-style writes it). The
#     widget engine is Kvantum (QT_STYLE_OVERRIDE=kvantum + the KStyle.Kvantum engine
#     extension matching each KDE runtime branch). Non-KDE-runtime Qt apps degrade
#     gracefully (Kvantum colors, no platform icons/font).
#   • Icons — /usr/share/icons is blacklisted and Flathub has no Papirus Icontheme
#     extension, so mirror_icons_to_users reflink-copies host Papirus into each user's
#     ~/.local/share/icons (bindable). GTK (portal icon-theme=Papirus-Dark) and Qt
#     (kdeglobals [Icons] Theme=Papirus-Dark) both resolve their icons there.
#   • The brand overlays (GTK4 css, Kvantum theme, kdeglobals + W.colors, fontconfig)
#     ride in via home-dir binds (xdg-config/* — these ARE allowed).
#
# KNOWN LIMIT — Qt theming is version-coupled best-effort: a Qt app installed AFTER
# this module pulls a new KDE runtime branch with no matching KStyle.Kvantum yet;
# re-run `apply.sh --flatpak` (idempotent) to fetch it.
#
# GUIs:
#   • Store (discover/search/install) = Bazaar — native pacman pkg (extra/bazaar),
#     GTK4/libadwaita so the W gtk axis themes it. Native (not Flatpak) on purpose:
#     the store is W infrastructure, drives the SYSTEM flatpak install via libflatpak,
#     and avoids needing a store to install the store. No PackageKit, no GNOME Shell.
#   • Per-app permissions = Flatseal (Flatpak app from Flathub).

FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATSEAL_ID="com.github.tchx84.Flatseal"

# Install the Kvantum QStyle engine for every installed KDE runtime branch, so
# QT_STYLE_OVERRIDE=kvantum resolves in those sandboxes. The extension is per-runtime
# (org.kde.KStyle.Kvantum//<branch>); match each org.kde.Platform branch present.
install_kvantum_extensions() {
  local branches br
  branches=$(flatpak list --runtime --columns=ref 2>/dev/null \
             | sed -n 's|^org\.kde\.Platform/[^/]*/||p' | sort -u)
  if [[ -z "$branches" ]]; then
    info "  No KDE runtime installed yet — Kvantum engine follows the first Qt app (re-run --flatpak)."
    return
  fi
  while read -r br; do
    [[ -n "$br" ]] || continue
    info "  Kvantum engine for org.kde.Platform//$br..."
    flatpak install -y --noninteractive flathub "org.kde.KStyle.Kvantum//$br" || true
  done <<<"$branches"
}

# Mirror the host Papirus icon set into each human user's ~/.local/share/icons — the
# bindable path the sandbox sees (xdg-data/icons in the override). /usr/share/icons is
# blacklisted and Flathub has no Papirus Icontheme extension. Papirus-Dark is mostly
# symlinks into the Papirus base, so BOTH dirs are copied. Source and homes share the
# btrfs volume, so cp --reflink=auto is copy-on-write — instant and ~zero extra space
# (verified: btrfs fi du Exclusive 0.00B). W icons are static across themes (name +
# folder hue are constants), and this runs after mod_style's folder retint.
mirror_icons_to_users() {
  info "Mirroring Papirus icons into user homes for the sandbox..."
  local u uid home d
  while IFS=: read -r u _ uid _ _ home _; do
    (( uid >= 1000 && uid < 65534 )) || continue
    [[ -d "$home" ]] || continue
    install -d -o "$u" -g "$u" "$home/.local/share/icons"
    for d in Papirus Papirus-Dark; do
      [[ -d "/usr/share/icons/$d" ]] || continue
      rm -rf "${home:?}/.local/share/icons/$d"
      cp -a --reflink=auto "/usr/share/icons/$d" "$home/.local/share/icons/$d"
      chown -R "$u:$u" "$home/.local/share/icons/$d"
    done
  done < /etc/passwd
}

mod_flatpak() {
  info "Installing Flatpak + Bazaar (store frontend)..."
  w_pac -S --needed --noconfirm flatpak bazaar

  info "Adding the Flathub remote (system-wide)..."
  flatpak remote-add --if-not-exists flathub "$FLATHUB_URL"

  info "Installing Kvantum engine extensions (Qt brand style in the sandbox)..."
  install_kvantum_extensions

  info "Applying global W theme overrides to the sandbox..."
  # Reset first — this global override is W-managed and must be DECLARATIVE. flatpak
  # override is additive and never drops keys, so an env set by an earlier version
  # lingers; crucially `--unset-env` leaves `GTK_THEME=` (empty) in [Environment],
  # and an EMPTY GTK_THEME is still an override that breaks GTK styling (GNOME PSA,
  # discourse #35200). Reset guarantees a clean slate, then we add only what we want.
  flatpak override --system --reset
  flatpak override --system \
    --filesystem=xdg-data/icons:ro \
    --filesystem=xdg-data/color-schemes:ro \
    --filesystem=xdg-config/gtk-3.0:ro \
    --filesystem=xdg-config/gtk-4.0:ro \
    --filesystem=xdg-config/Kvantum:ro \
    --filesystem=xdg-config/kdeglobals:ro \
    --filesystem=xdg-config/fontconfig:ro \
    --env=QT_QPA_PLATFORMTHEME=kde \
    --env=QT_STYLE_OVERRIDE=kvantum
  # NO GTK_THEME (the portal already reports the theme; any value, even empty, breaks
  # GTK3/GTK4). QT_QPA_PLATFORMTHEME=kde drives the KDE platform theme that reads
  # kdeglobals (KColorScheme + Papirus icons + [General] font); Kvantum is the widget
  # engine. GTK3 itself comes from the w-style-built Gtk3theme extensions, GTK4 from
  # the bound gtk-4.0 css + portal — no env needed for either.

  mirror_icons_to_users

  info "Installing Flatseal (per-app permission GUI) from Flathub..."
  if flatpak info "$FLATSEAL_ID" &>/dev/null; then
    info "Flatseal already installed."
  else
    flatpak install -y --noninteractive flathub "$FLATSEAL_ID"
  fi

  info "Flatpak active. Browse/install apps: Bazaar; tune permissions: Flatseal; CLI: flatpak install flathub <app-id>."
}
