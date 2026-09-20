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
# so a standalone --screencapture is self-contained); it saves into the user's
# PICTURES folder as xdg-user-dirs names it (`xdg-user-dir PICTURES`). Keybinds live in the skel
# hyprland.lua (deployed by --hyprland); satty's float/center window rule is the
# drop-in /usr/share/w/hypr/rules.d/satty.lua (same --rootfs + here deal). The
# satty theme axis ships with the w-style library tree (deployed by --style), so
# nothing axis-related is done here.
#
# TODO (future session): add screen VIDEO recording here — a `record` subcommand
# in w-screenshot (wf-recorder / wl-screenrec) plus a Quickshell bar indicator.

mod_screencapture() {
  info "Installing screen capture stack (grim + slurp + satty)..."
  w_pac -S --needed --noconfirm grim slurp satty wl-clipboard libnotify

  info "Deploying w-screenshot..."
  install -Dm755 "$SRC/rootfs/usr/bin/w-screenshot" /usr/bin/w-screenshot
  install -Dm644 "$SRC/rootfs/usr/share/w/hypr/rules.d/satty.lua" /usr/share/w/hypr/rules.d/satty.lua

  # No ~/Pictures/Screenshots is created here any more. The folder is the user's
  # PICTURES dir (xdg-user-dirs names it in the user's language at login — see
  # mod_userdirs), resolved by w-screenshot at runtime, which mkdir -p's the
  # Screenshots subfolder on the first save. A root-side loop over homes used to
  # plant an English ~/Pictures into every account, wrong on any non-English
  # system and root-owned on the first try (see CHANGELOG).

  info "Screen capture installed. Bind: \$mod+Ctrl+S → region → satty. Palette themes via --style."
}
