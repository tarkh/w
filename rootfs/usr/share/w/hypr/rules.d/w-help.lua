-- The Help window (w-help): W's documentation site in its own Firefox instance,
-- app_id `w-help` (firefox --name). Owned by the rootfs tree, like the script.
--
-- It floats: help is consulted next to the thing it explains, and a tile would
-- reflow the very layout the reader is looking at. A share of the monitor is the
-- right measure here (unlike a dialog's fixed logical size, package-hyprland.md):
-- it is a reading surface, and the site's layout (sidebar + text column) is made
-- for a large window. Hyprland does not clamp a floating window to the monitor,
-- so the share keeps it on screen at every resolution.
--
-- A user who wants it tiled overrides this in ~/.config/hypr/rules.d/ — a later
-- rule's `tile = true` wins over this `float`:
--   hl.window_rule({ match = { class = "^(w-help)$" }, tile = true })
hl.window_rule({
  match  = { class = "^(w-help)$" },
  float  = true,
  size   = { "monitor_w * 0.62", "monitor_h * 0.86" },
  center = true,
})
