# modules/sudo.sh — memory-safe privileges: sudo-rs as the default sudo (security.md, point Б)
# Userspace layer: wired into apply.sh only (the installer stays minimal-base).
# base-devel pins the C `sudo` (can't be removed) and sudo-rs doesn't `provides` it,
# so the two coexist: we shadow the `sudo` command with a /usr/local/bin symlink to
# sudo-rs (/usr/local/bin precedes /usr/bin in the default PATH). sudo-rs reads the
# existing /etc/sudoers + sudoers.d unchanged. run0 needs nothing (ships with systemd).

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_sudo() {
  local mnt="${MNT:-}"
  local target="/usr/bin/sudo-rs"
  local shadow="${mnt}/usr/local/bin/sudo"

  ui_info "Ensuring sudo-rs is installed..."
  w_pac -S --needed --noconfirm sudo-rs

  # Lockout guard: shadow `sudo` only once the rs binary is really present, otherwise
  # `sudo` would resolve to a dangling link and lock the user out of privileges.
  [[ -x "${mnt}${target}" ]] || die "sudo-rs binary missing (${target}); refusing to shadow sudo."

  ui_info "Shadowing 'sudo' -> sudo-rs via /usr/local/bin..."
  install -d "${mnt}/usr/local/bin"
  ln -sf "$target" "$shadow"

  ui_info "sudo-rs active as default 'sudo'. run0 stays available for GUI (polkit/fingerprint)."
}
