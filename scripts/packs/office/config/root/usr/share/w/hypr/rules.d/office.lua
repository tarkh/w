-- LibreOffice dialogs (office bundle; vendor layer, manifest row in ../manifest).
--
-- Document and Start Center windows carry the app_id `libreoffice-<app>`; every
-- other LibreOffice toplevel — the GTK file chooser, Options, Tip of the Day — is
-- plain `soffice`. Opened from a document those dialogs have a transient parent
-- and Hyprland floats them on its own; opened from the Start Center they have
-- none and tile, the file chooser stretched to its tile — and GTK then saves that
-- stretch as the user's chooser size for every GTK app (see dialogs.lua). The
-- class is the only stable marker: the titles are translated.
--
-- No size: the file chooser takes its size from GTK (dialogs.lua), the other
-- dialogs from their own content.
hl.window_rule({
  match  = { class = "^(soffice)$" },
  float  = true,
  center = true,
})
