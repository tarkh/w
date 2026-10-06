-- Krita's file dialogs (graphics bundle; vendor layer, manifest row in ../manifest).
--
-- GIMP and Inkscape are GTK3 — their chooser floats and takes W's size from GTK
-- (dialogs.lua). Krita is Qt6: W pins QT_QPA_PLATFORMTHEME=qt6ct, which has no
-- file-dialog helper, so Krita's chooser is an in-process QFileDialog that opens
-- at ~900x420 and remembers nothing (kritarc stays untouched across a resize).
-- The compositor gives it the W size, 1000x640 logical.
--
-- Matched by the dialog captions Krita sets (KoFileDialog: Open / Import /
-- Save As / Export), which are translated — both languages W ships, taken from
-- krita.mo — plus the " — Krita" suffix Qt appends to every window title. Not
-- by `modal`: Krita's message boxes are modal too and must keep their size.
hl.window_rule({
  match    = { class = "^(krita)$",
               initial_title = "^(Open Images|Import Images|Saving As|Exporting|Открыть изображения|Импорт изображений|Сохранение как|Экспорт) — Krita$" },
  float    = true,
  size     = { 1000, 640 },
  min_size = { 600, 420 },
  center   = true,
})
