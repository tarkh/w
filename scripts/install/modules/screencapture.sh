# modules/screencapture.sh — screen capture stack (Wayland/Hyprland).
# apply.sh context: runs on the live system as root. Post-boot only.
#
# One module owns the whole "screen capture" concern (essentials.md boundary rule).
# Two annotators ship side by side, chosen at runtime by `w-conf get screenshot
# ANNOTATOR` — see /usr/share/w/defaults/screenshot.conf:
#   • flameshot    — W's default. Select and draw in ONE frozen full-monitor
#                    overlay, no second window. On Wayland it reaches the screen
#                    through the XDG screenshot portal, which here is
#                    xdg-desktop-portal-hyprland calling grim — so it rides the
#                    same wlr-screencopy path as everything else and needs no X11.
#                    (This is why the earlier verdict against Flameshot no longer
#                    holds: the portal it depends on has been in W's base since
#                    --hyprland, and upstream ships a Hyprland Lua rule set.)
#   • satty        — the previous annotator, kept as the rollback and as the only
#                    option for `full` (a Flameshot overlay is one window on one
#                    monitor, so it has no all-monitors form).
# The direct, UI-less captures (--copy/--save) stay on grim + slurp + wl-copy.
# Everything is in the official extra repo; no AUR.
#
# The orchestrator is the w-screenshot script (deployed by --rootfs, and here too
# so a standalone --screencapture is self-contained); it saves into the user's
# PICTURES folder as xdg-user-dirs names it (`xdg-user-dir PICTURES`). Keybinds live in the skel
# hyprland.lua (deployed by --hyprland); the two annotators' window rules are the
# drop-ins /usr/share/w/hypr/rules.d/{flameshot,satty}.lua (same --rootfs + here
# deal). Both theme axes ship with the w-style library tree (deployed by --style),
# so nothing axis-related is done here.
#
# TODO (future session): add screen VIDEO recording here — a `record` subcommand
# in w-screenshot (wf-recorder / wl-screenrec) plus a Quickshell bar indicator.

mod_screencapture() {
  info "Installing screen capture stack (flameshot + grim/slurp/satty)..."
  w_pac -S --needed --noconfirm flameshot grim slurp satty wl-clipboard libnotify

  info "Deploying w-screenshot..."
  install -Dm755 "$SRC/rootfs/usr/bin/w-screenshot" /usr/bin/w-screenshot
  install -Dm644 "$SRC/rootfs/usr/share/w/hypr/rules.d/satty.lua" /usr/share/w/hypr/rules.d/satty.lua
  install -Dm644 "$SRC/rootfs/usr/share/w/hypr/rules.d/flameshot.lua" /usr/share/w/hypr/rules.d/flameshot.lua
  install -Dm644 "$SRC/rootfs/usr/share/w/defaults/screenshot.conf" /usr/share/w/defaults/screenshot.conf
  install -Dm644 "$SRC/rootfs/usr/share/w/defaults/screenshot.schema" /usr/share/w/defaults/screenshot.schema

  # No ~/Pictures/Screenshots is created here any more. The folder is the user's
  # PICTURES dir (xdg-user-dirs names it in the user's language at login — see
  # mod_userdirs), resolved by w-screenshot at runtime, which mkdir -p's the
  # Screenshots subfolder on the first save. A root-side loop over homes used to
  # plant an English ~/Pictures into every account, wrong on any non-English
  # system and root-owned on the first try (see CHANGELOG).

  info "Screen capture installed. Binds: \$mod+(Shift|Ctrl)+I annotate, +Alt variants save. Themes via --style."
}
