-- Flameshot (screenshot annotation, opened by w-screenshot). Owned by
-- apply.sh --screencapture. The satty rule next door stays: satty is still the
-- rollback annotator (`w-conf set --user screenshot ANNOTATOR satty`).
--
-- Runtime class is `flameshot` (Qt app_id = the application name); the three
-- surfaces it can put on screen are told apart by their title, which is also
-- their initialTitle — and initialTitle is what a STATIC rule matches, since
-- static effects are evaluated once, when the window opens.
--
-- The overlay and the pin are told apart by their titles. The Save dialog is
-- NOT named anywhere here: it is matched by exclusion, so this file stays
-- correct when flameshot changes that string or when the system speaks another
-- language. See ③.

-- ① The capture overlay: a full-monitor window showing a frozen copy of that
-- monitor. Every piece of W's window chrome has to be off — a rounded, bordered,
-- shadowed, animated overlay would both look wrong and lag the selection.
-- Upstream ships the float/pin/no_anim/decorate/no_blur/no_shadow set for
-- Hyprland (docs/UsageHyprlandSwayWlroots.md); rounding/border_size/no_dim are
-- W's addition, because our theme sets those globally and `decorate = false`
-- alone does not cancel them.
hl.window_rule({
  match       = { class = "^(flameshot)$", title = "^(flameshot)$" },
  float       = true,
  pin         = true,
  no_anim     = true,
  decorate    = false,
  no_blur     = true,
  no_shadow   = true,
  no_dim      = true,
  rounding    = 0,
  border_size = 0,
  move        = { 0, 0 },
})

-- ② A pinned capture ("pin to screen" in the toolbar) is a small always-on-top
-- image window — same bare chrome, but dropped centred under the cursor.
hl.window_rule({
  match       = { class = "^(flameshot)$", title = "^(flameshot-pin)$" },
  float       = true,
  pin         = true,
  no_anim     = true,
  decorate    = false,
  no_shadow   = true,
  rounding    = 0,
  border_size = 0,
  move        = { "cursor_x-(window_w*0.5)", "cursor_y-(window_h*0.5)" },
})

-- ③ The Save dialog — the third `flameshot` window, and until now the one no
-- rule claimed, which is why it kept tiling itself into the layout.
--
-- It really is a `flameshot` window, not a portal one: W pins
-- QT_QPA_PLATFORMTHEME=qt6ct, and neither qt6ct nor QGenericUnixTheme provides
-- a file-dialog helper, so flameshot's QFileDialog is never shelled out to
-- xdg-desktop-portal — it is a plain in-process Qt widget. (`hyprctl clients`
-- on the live dialog: class `flameshot`, initialTitle `Save screenshot`.)
--
-- Matched by EXCLUSION rather than by that title, which is a tr() string —
-- "Save screenshot" in English, "Сохранить снимок" in Russian. Naming it would
-- tie W to one locale and to one flameshot release. `negative:` inverts the
-- match (Hyprland regexes are RE2, so there is no lookaround to use instead),
-- and the pattern is exactly the two titles claimed above. The three rules are
-- therefore mutually exclusive BY CONSTRUCTION: no file order can leak this
-- size into the overlay or the pin, whichever way round they are written.
--
-- Fixed LOGICAL pixels, deliberately not a share of the monitor. `size` speaks
-- logical coordinates, so a HiDPI panel scales the dialog along with
-- everything else and only its share of the screen varies — about 26% of the
-- width of a 40" 4K at scale 1, about 52% of a 1080p laptop: never full-screen,
-- never a postage stamp. A percentage (satty's 70%) is right for an annotation
-- canvas and wrong here: 70% of a 40" 4K is a 2.7k-wide file browser, 70% of a
-- 13" laptop is the whole screen. 1000x640 fits the places sidebar, the file
-- list, and flameshot's long "Files of type" combo — it filters on every mime
-- type QImageWriter supports, so that label runs long.
--
-- min_size only guards the floor so the dialog cannot be shrunk into
-- uselessness, and there is deliberately NO max_size: a user who wants it
-- bigger is free to drag it wider. Chrome stays on — this is an ordinary
-- window, so it keeps W's rounding, border and shadow; only ① needs them off.
hl.window_rule({
  match    = { class = "^(flameshot)$", title = "negative:^(flameshot|flameshot-pin)$" },
  float    = true,
  size     = { 1000, 640 },
  min_size = { 600, 420 },
  center   = true,
})
