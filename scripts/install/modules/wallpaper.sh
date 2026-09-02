# modules/wallpaper.sh — W Linux wallpaper system
# apply.sh context: runs on live system as root.
#
# Deploys the theme collection (each theme ships its own wallpaper/ set) and the
# w-wallpaper utility. Must run before any module that depends on wallpaper
# (e.g. greeter). Wallpapers are resolved from the active theme at runtime.

mod_wallpaper() {
  info "Installing wallpaper dependencies..."
  w_pac -S --needed --noconfirm jq

  info "Deploying themes (wallpapers live under each theme)..."
  mkdir -p /etc/w/themes
  rsync -a --chown=root:root "$SRC/rootfs/etc/w/themes/" /etc/w/themes/
  # System-fallback pointer: create only if missing (don't clobber a sudo choice)
  [[ -e /etc/w/active-theme ]] || ln -sfn themes/w /etc/w/active-theme

  info "Deploying w-wallpaper..."
  install -m 755 "$SRC/rootfs/usr/bin/w-wallpaper" /usr/bin/w-wallpaper

  info "Deploying tmpfiles.d and creating runtime dirs..."
  install -m 644 "$SRC/rootfs/usr/lib/tmpfiles.d/w.conf" /usr/lib/tmpfiles.d/w.conf
  systemd-tmpfiles --create /usr/lib/tmpfiles.d/w.conf
}
