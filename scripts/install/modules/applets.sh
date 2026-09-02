# modules/applets.sh — tray applets for hardware/connectivity management.
# apply.sh context: runs on the live/installed system as root.
#
# Module boundary (see essentials.md rule): the W bar deliberately does NOT reimplement
# NetworkManager/Bluetooth control — for network it shows a light read-only indicator (the
# bar network block) and delegates all real management to upstream GTK tray applets, which
# auto-theme via the w-style `gtk` axis and give a full, battle-tested GUI. This module
# groups those applets: network (nm-applet) and Bluetooth (blueman).
#
# network-manager-applet provides:
#   - nm-applet            — the tray SNI (autostarted `--indicator` in hyprland.lua);
#                            left-click = NM menu (Wi-Fi list / connect / disconnect / VPN)
#   - nm-connection-editor — the GTK3 GUI connection editor (W's network utility; opened
#                            by the bar network block's left-click)
# libappindicator-gtk3 is required for nm-applet's `--indicator` (SNI) mode; without it the
# applet falls back to the legacy XEmbed tray, which is invisible under Wayland/Quickshell.
# NetworkManager itself is installed and enabled at install time (base.txt + network.sh).
#
# blueman provides (with bluez/bluez-utils as the backend, installed from scratch here):
#   - blueman-applet       — the tray SNI (native StatusNotifier, no libappindicator
#                            needed); right-click = context menu, left-click = primary
#                            action, icon reflects adapter/connection state. Autostarted
#                            in hyprland.lua. No bar block — the tray applet is enough
#                            (unlike network there is no Quickshell BT service to drive a
#                            cheap indicator, and the icon already shows state).
#   - blueman-manager      — the GTK3 GUI manager (W's Bluetooth utility: pair / connect /
#                            trust / remove devices)
# bluetooth.service (bluez) is enabled so the adapter comes up at boot.
#
# Autostart for both applets lives in hyprland.lua (apply.sh --hyprland), like every
# other exec-once.

mod_applets() {
  info "Installing tray applets (network, bluetooth)..."
  w_pac -S --needed --noconfirm \
    network-manager-applet \
    libappindicator-gtk3 \
    bluez \
    bluez-utils \
    blueman

  info "Enabling bluetooth.service..."
  systemctl enable bluetooth.service

  info "Tray applets installed. nm-applet + blueman-applet autostart via hyprland.lua;"
  info "GUI: nm-connection-editor (network), blueman-manager (bluetooth)."
}
