-- Windows of the audio bundle's apps (vendor layer, manifest row in ../manifest).
-- The W size of every "pick a file" window is 1000x640 logical (dialogs.lua);
-- the two file windows below (① ③) size themselves to nothing W can read
-- back, so the compositor gives the size (package-files.md "Файловые
-- диалоги", rule ③).
--
-- Audacity is wxGTK3: its Open/Export are the GTK3 chooser — GTK keeps that
-- size, nothing to do here. Ardour's session Open lives inside its compact,
-- centred session window — left as it is.

-- ① Ardour "Add Existing Media" (Ctrl+I): Ardour's own window — a file chooser
-- plus import options — that opens at ~940x550 in a screen corner. XWayland,
-- class "Ardour"; its title comes from gtk2_ardour9.mo (both languages W ships).
hl.window_rule({
  match    = { class = "^(Ardour)$",
               initial_title = "^(Add Existing Media|Добавить существующие данные)$" },
  float    = true,
  size     = { 1000, 640 },
  min_size = { 600, 420 },
  center   = true,
})

-- ② Ardour's Preferences window asks XWayland for position 0,0 — under the
-- bar, cut off at the top. Every other Ardour window places itself sensibly
-- (at the pointer, or where it was last closed), so only this one is centred.
hl.window_rule({
  match  = { class = "^(Ardour)$", initial_title = "^Ardour - (Preferences|Параметры)$" },
  center = true,
})

-- ③ qpwgraph's patchbay and palette files: Qt QFileDialog (qt6ct has no dialog
-- helper), ~630x410, remembers nothing. qpwgraph ships no translations, so its
-- captions are English only; Qt appends " — <application display name>".
hl.window_rule({
  match    = { class = "^(org\\.rncbc\\.qpwgraph)$",
               initial_title = "^(Open Patchbay File|Save Patchbay File|Import File - .*|Export File - .*) — .*$" },
  float    = true,
  size     = { 1000, 640 },
  min_size = { 600, 420 },
  center   = true,
})
