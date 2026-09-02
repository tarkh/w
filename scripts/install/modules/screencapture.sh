# modules/screencapture.sh — screen capture stack (Wayland/Hyprland).
# apply.sh context: runs on the live system as root. Post-boot only.
#
# One module owns the whole "screen capture" concern (essentials.md boundary rule).
# Native wlr-screencopy stack, chosen over Flameshot (which on Wayland only works
# through the portal and the Hyprland wiki itself steers away from):
#   • grim + slurp — capture + region/window selection (same screencopy path
#                    hyprlock already uses); all in the official extra repo.
#   • satty        — annotation UI (extra); GTK4, so its chrome is themed by the
#                    gtk axis, its palette/font by the w-style `satty` axis.
#   • wl-clipboard — wl-copy for the quick, non-annotated grabs.
#   • libnotify    — notify-send confirmations (Quickshell is the notif server).
# The orchestrator is the w-screenshot script (deployed by --rootfs, and here too
# so a standalone --screencapture is self-contained). Keybinds live in the skel
# hyprland.lua (deployed by --hyprland). The satty theme axis ships with the
# w-style library tree (deployed by --style), so nothing axis-related is done here.
#
# TODO (future session): add screen VIDEO recording here — a `record` subcommand
# in w-screenshot (wf-recorder / wl-screenrec) plus a Quickshell bar indicator.

mod_screencapture() {
  info "Installing screen capture stack (grim + slurp + satty)..."
  w_pac -S --needed --noconfirm grim slurp satty wl-clipboard libnotify

  info "Deploying w-screenshot..."
  install -Dm755 "$SRC/rootfs/usr/bin/w-screenshot" /usr/bin/w-screenshot

  # Ensure the default save directory exists for every human account (satty and
  # `w-screenshot --save` write PNGs into ~/Pictures/Screenshots; the tool mkdir -p's
  # it too, so this is a convenience — but a per-user one, not a primary-user one).
  local -a wusers=(); local entry wuser home_dir
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping Screenshots dir."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    install -d -o "$wuser" -g "$wuser" "$home_dir/Pictures/Screenshots"
  done

  info "Screen capture installed. Bind: \$mod+Ctrl+S → region → satty. Palette themes via --style."
}
