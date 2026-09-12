-- satty (screenshot annotation, opened by w-screenshot): float it above the
-- tiled windows, centred, 70% of the monitor. Runtime class is `com.gabm.satty`
-- (the desktop file's StartupWMClass, per hyprctl) — a bare `satty` matches
-- nothing and the window would silently tile. Owned by apply.sh --screencapture.
hl.window_rule({
  match  = { class = "^(com\\.gabm\\.satty)$" },
  float  = true,
  size   = { "monitor_w * 0.7", "monitor_h * 0.7" },
  center = true,
})
