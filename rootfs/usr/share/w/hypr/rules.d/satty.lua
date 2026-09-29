-- satty (screenshot annotation, opened by w-screenshot): float it above the
-- tiled windows, centred, at most 80% of the monitor. No fixed size — satty
-- asks for a window that fits the captured image, so a small region opens
-- small and only a large capture hits the 80% cap. Runtime class is
-- `com.gabm.satty` (the desktop file's StartupWMClass, per hyprctl) — a bare
-- `satty` matches nothing and the window would silently tile. Owned by
-- apply.sh --screencapture.
hl.window_rule({
  match    = { class = "^(com\\.gabm\\.satty)$" },
  float    = true,
  max_size = { "monitor_w * 0.8", "monitor_h * 0.8" },
  center   = true,
})
