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
# hyprland.lua (deployed by --hyprland); the two annotators' window rules and
# slurp's no-fade layer rule are the drop-ins
# /usr/share/w/hypr/rules.d/{flameshot,satty,slurp}.lua (same --rootfs + here deal). Both theme axes ship with the w-style library tree (deployed by --style),
# so nothing axis-related is done here.
#
# VIDEO recording is the other half of this module, and its own front-end:
#   • wf-recorder — the video twin of grim. It captures through wlr-screencopy
#                   too, so the recording path needs no portal, no PipeWire
#                   session and no privileged helper — unlike every heavier
#                   recorder in the Hyprland wiki's list. gpu-screen-recorder was
#                   the alternative and is NOT in the base system: it installs
#                   gsr-kms-server with a cap_sys_admin file capability, which
#                   does not belong on every machine. wl-screenrec is AUR-only.
#                   Both are reachable later through record.conf's RECORDER key.
# There is no all-monitors recording mode: wlr-screencopy works one output at a
# time, the same reason `full --annotate` has no flameshot form.
#
# w-record and w-screenshot share /usr/lib/w/w-capture-lib.sh — the save folders,
# the focused-window/output geometry and the themed slurp selection. That library
# is why slurp now draws in W's colours for BOTH tools; it has no config file, so
# there is no w-style axis for it and the colours are read from the live theme.

mod_screencapture() {
  info "Installing screen capture stack (flameshot + grim/slurp/satty + wf-recorder)..."
  w_pac -S --needed --noconfirm flameshot grim slurp satty wf-recorder wl-clipboard libnotify imagemagick

  info "Deploying w-screenshot and w-record..."
  install -Dm644 "$SRC/rootfs/usr/lib/w/w-capture-lib.sh" /usr/lib/w/w-capture-lib.sh
  install -Dm755 "$SRC/rootfs/usr/bin/w-screenshot" /usr/bin/w-screenshot
  install -Dm755 "$SRC/rootfs/usr/bin/w-record" /usr/bin/w-record
  install -Dm644 "$SRC/rootfs/usr/share/w/hypr/rules.d/satty.lua" /usr/share/w/hypr/rules.d/satty.lua
  install -Dm644 "$SRC/rootfs/usr/share/w/hypr/rules.d/flameshot.lua" /usr/share/w/hypr/rules.d/flameshot.lua
  install -Dm644 "$SRC/rootfs/usr/share/w/hypr/rules.d/slurp.lua" /usr/share/w/hypr/rules.d/slurp.lua
  install -Dm644 "$SRC/rootfs/usr/share/w/defaults/screenshot.conf" /usr/share/w/defaults/screenshot.conf
  install -Dm644 "$SRC/rootfs/usr/share/w/defaults/screenshot.schema" /usr/share/w/defaults/screenshot.schema
  install -Dm644 "$SRC/rootfs/usr/share/w/defaults/record.conf" /usr/share/w/defaults/record.conf
  install -Dm644 "$SRC/rootfs/usr/share/w/defaults/record.schema" /usr/share/w/defaults/record.schema

  # No ~/Pictures/Screenshots is created here any more. The folder is the user's
  # PICTURES dir (xdg-user-dirs names it in the user's language at login — see
  # mod_userdirs), resolved by w-screenshot at runtime, which mkdir -p's the
  # Screenshots subfolder on the first save. A root-side loop over homes used to
  # plant an English ~/Pictures into every account, wrong on any non-English
  # system and root-owned on the first try (see CHANGELOG).

  info "Screen capture installed. Binds: \$mod+(Shift|Ctrl)+I annotate, +Alt variants save, \$mod+(Ctrl|Alt)+R record. Themes via --style."
}
