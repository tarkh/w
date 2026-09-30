-- satty (screenshot annotation, opened by w-screenshot): float it above the
-- tiled windows, centred, at most 90% of the monitor. No fixed size here —
-- w-screenshot asks satty (--resize) for the image plus its two toolbars, so a
-- small capture opens at 1:1 and only a large one hits the 90% cap (the same
-- 0.9 is w-screenshot's SATTY_CAP: past it, satty fits the image instead). A
-- region capture adds a runtime rule on top that moves the window over the
-- selection. Runtime class is `com.gabm.satty` (the desktop file's
-- StartupWMClass, per hyprctl) — a bare `satty` matches nothing and the window
-- would silently tile. Owned by apply.sh --screencapture.
hl.window_rule({
  match    = { class = "^(com\\.gabm\\.satty)$" },
  float    = true,
  max_size = { "monitor_w * 0.9", "monitor_h * 0.9" },
  center   = true,
})
