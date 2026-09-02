# modules/greeter.sh — greetd login manager (Quickshell greeter)
# apply.sh context: runs on live system as root.
#
# Backend: greetd. Frontend: the W Quickshell greeter (rootfs/etc/greetd/quickshell/w),
# launched by a minimal greeter Hyprland session.

mod_greeter() {
  info "Installing greeter packages..."
  # quickshell: the greeter frontend (Greetd service ships in the extra build).
  # hypridle: idle DPMS for the login screen (greeter Hyprland exec-once, own config).
  w_pac -S --needed --noconfirm greetd quickshell hypridle

  info "Deploying greetd config (incl. Quickshell greeter)..."
  mkdir -p /etc/greetd
  rsync -a --chown=root:root "$SRC/rootfs/etc/greetd/" /etc/greetd/
  chmod 640 /etc/greetd/config.toml
  chmod 644 /etc/greetd/hyprland.lua
  chmod 755 /etc/greetd/w-greeter-wrapper.sh
  chown -R greeter:greeter /etc/greetd 2>/dev/null || true

  info "Setting up greeter HOME (/var/lib/w-greeter)..."
  # Writable HOME so Qt has a shader cache — without it Qt software-renders and
  # pegs the CPU (the lesson learned with regreet's HOME=/).
  mkdir -p /var/lib/w-greeter/.cache
  chown -R greeter:greeter /var/lib/w-greeter
  # Actually assign it as greeter's home — the greetd package leaves HOME=/, so the
  # greeter's `systemd --user` (PipeWire/WirePlumber) can't write its state into
  # /.local/state (Permission denied). Pointing home at the writable dir above fixes
  # that cleanly and realises the shader-cache intent. -d only (no -m): dir is ready.
  usermod -d /var/lib/w-greeter greeter

  info "Rendering greeter theme from the system theme..."
  # Best-effort: committed defaults already make the greeter themed; this re-renders
  # it from the active system theme. Skipped silently if w-style isn't deployed yet
  # (mod_style runs later in --all and re-renders everything anyway).
  command -v w-style >/dev/null 2>&1 && w-style apply greeter || true

  info "Suppressing greetd console output..."
  mkdir -p /etc/systemd/system/greetd.service.d
  cp "$SRC/rootfs/etc/systemd/system/greetd.service.d/override.conf" \
    /etc/systemd/system/greetd.service.d/override.conf
  systemctl daemon-reload

  info "Enabling greetd.service..."
  systemctl enable greetd.service

  # Disable getty on tty1 to prevent conflict
  systemctl disable getty@tty1.service 2>/dev/null || true
}
