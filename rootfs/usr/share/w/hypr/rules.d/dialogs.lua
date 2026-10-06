-- File dialogs (Open / Save As / Select Folder) of the W base. Owned by apply.sh
-- --files. Every "pick a file" window in W opens at 1000x640 logical px; packs
-- carry the rules for their own apps (office.lua, 3d.lua, graphics.lua).
--
-- ① GTK3 + the portal: GTK keeps the size, the compositor only floats it.
--
-- W leaves the SIZE of the GTK file chooser to GTK itself: GTK3 saves it on close
-- in gsettings (org.gtk.Settings.FileChooser window-size) and restores it on open —
-- one key shared by every GTK3 app (GIMP, Firefox, LibreOffice, Nemo) and by the
-- portal below (Chromium/Electron, Flatpak), so stretching it once resizes it
-- everywhere and for good. The first-open size is W's vendor default for that key,
-- /usr/share/glib-2.0/schemas/50_w-filechooser.gschema.override (1000x640 logical,
-- the size flameshot's Qt Save dialog gets in flameshot.lua ③). No `size` here: a
-- compositor size would override the size the user chose.
--
-- What the compositor MUST guarantee is that the dialog floats. A tiled dialog is
-- stretched to its tile, and GTK then saves THAT as the user's size — after one
-- tiled open, every app's dialog opens full-height. The portal dialog tiles
-- whenever its caller passes no parent window (it is a separate process, so
-- Hyprland sees no transient parent). Class `xdg-desktop-portal-gtk` is the
-- portal's app_id — stable, not a translated title. It also hosts the portal's
-- other dialogs ("Open With", print): floating and centred is right for them too.
--
-- min_size is a floor so a saved size cannot shrink the dialog into uselessness;
-- deliberately no max_size — a user who wants it bigger drags it bigger.
hl.window_rule({
  match    = { class = "^(xdg-desktop-portal-gtk)$" },
  float    = true,
  min_size = { 600, 420 },
  center   = true,
})

-- ② File Roller (--files): a GTK4 app on the legacy in-process chooser. GTK4 apps
-- on the modern GtkFileDialog (Document Scanner) go through the portal and are ①.
-- The legacy GtkFileChooserDialog stays in-process even with GDK_DEBUG=portals,
-- and GTK4 (4.22) neither saves nor reads its size — the gtk4 gsettings key stays
-- (-1,-1) — so it opens at ~870x390 every time; the compositor gives the size.
-- No stable marker of its own: the class is the app's and it sets no xdg-dialog
-- `modal` flag, so it is matched by its chooser titles, in both languages W ships
-- (from file-roller.mo). Its other dialogs (errors, passwords, "New Archive")
-- have other titles and keep their own size.
hl.window_rule({
  match    = { class = "^(org\\.gnome\\.FileRoller)$",
               initial_title = "^(Open|Extract|Add Files|Открыть|Извлечь|Добавить файлы)$" },
  float    = true,
  size     = { 1000, 640 },
  min_size = { 600, 420 },
  center   = true,
})
