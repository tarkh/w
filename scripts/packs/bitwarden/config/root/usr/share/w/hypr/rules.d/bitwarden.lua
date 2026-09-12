-- Bitwarden desktop: the window is summoned out of the tray by the SSH agent —
-- "unlock your vault" when it is locked, then the key-approval dialog — for a
-- single click, then hidden again with Super+Q (close-to-tray). Float it so it
-- never lands in the tiling layout, centred like W's own auth card that follows
-- it, and sized as a dialog: a fixed 800×790 logical px (790 is the app's own
-- default height, 800 fits its unlock/approve views) — NOT a share of the
-- monitor, which would balloon on a 4K panel at scale 1. Hyprland does not clamp
-- a floating window to the monitor (a too-big one overflows at negative
-- coordinates), so min() caps it at 90% on small screens; monitor_h is the full
-- height, bar included, hence the margin. min() is not in the wiki but the
-- expression parser accepts it (verified on 0.56.2); should a later release
-- drop it, the size is reported in `hyprctl configerrors` and ignored — the
-- window still floats, centred, at Electron's own size.
-- Runtime class is `Bitwarden` (StartupWMClass), but Electron app_ids differ in
-- case across builds — match both. Owned by the bitwarden bundle (manifest).
hl.window_rule({
  match  = { class = "^([Bb]itwarden)$" },
  float  = true,
  size   = { "min(800, monitor_w * 0.9)", "min(790, monitor_h * 0.9)" },
  center = true,
})
