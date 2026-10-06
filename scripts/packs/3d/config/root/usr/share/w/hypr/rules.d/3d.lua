-- Blender's file browser (3d bundle; vendor layer, manifest row in ../manifest).
--
-- Open / Save As / Import / Export in Blender is not a system dialog but a
-- Blender window of its own (class `blender`), and on Wayland it asks for a
-- 320x240 surface — unusable until dragged bigger, every time. Same size as the
-- GTK file chooser's W default (dialogs.lua) and flameshot's Save dialog ③, so
-- every "pick a file" window in W opens alike.
--
-- Matched by initialTitle, the title the window is created with ("Blender File
-- View" comes later). It IS translated by Blender's own interface language, so
-- the pattern lists both languages W ships: "File Browser" / "Браузер файлов".
-- The other Blender sub-windows are left alone on purpose — the render window
-- sizes itself to the render resolution.
hl.window_rule({
  match    = { class = "^(blender)$", initial_title = "^(File Browser|Браузер файлов)$" },
  float    = true,
  size     = { 1000, 640 },
  min_size = { 600, 420 },
  center   = true,
})
