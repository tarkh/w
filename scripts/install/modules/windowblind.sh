# modules/windowblind.sh — w-windowblind utility
# apply.sh context: runs on live system as root.

mod_windowblind() {
  info "Installing w-windowblind deps..."
  w_pac -S --needed --noconfirm gtk4-layer-shell

  info "Building w-windowblind..."
  # shellcheck disable=SC2046  # pkg-config output is a flag list, must word-split
  gcc -O2 -o /usr/bin/w-windowblind \
    "$SRC/rootfs/usr/share/w/src/w-windowblind.c" \
    $(pkg-config --cflags --libs gtk4 gtk4-layer-shell-0)
}
