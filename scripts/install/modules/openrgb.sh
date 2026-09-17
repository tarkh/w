# modules/openrgb.sh — RGB lighting: OpenRGB + i2c-tools (extra)
#
# OpenRGB controls per-device RGB (keyboards, mice, mainboards, RAM, fans,
# monitors) from one CLI, and its Arch udev rules carry TAG+=uaccess, so an
# unprivileged user inside a graphical session can read the devices directly —
# no daemon, no polkit. W drives it from the w-style `600-rgb` axis: every theme
# switch and every login render pushes the active theme's W_PRIMARY to all
# detected devices (see w-style.md).
#
# i2c-tools rides along because mainboard/RAM address-space access needs the
# i2c-dev interface exposed; harmless on hardware without it.
# No systems service is enabled on purpose: the axis renders colors one-shot via
# the CLI (`openrgb --noautoconnect --color RRGGBB`), so the SDK server
# (openrgb.service, :6742) is not needed.

command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_openrgb() {
  ui_info "Installing OpenRGB (RGB lighting) + i2c-tools..."
  w_pac -S --needed --noconfirm openrgb i2c-tools

  ui_info "openrgb installed. Verify with: openrgb --list-devices"
}