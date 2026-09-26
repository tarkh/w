-- gaming bundle window rules — verified live on the dev VM (hyprctl clients),
-- not from memory (gaming-plan.md's own rule).
--
-- Steam: the client's own dialogs (login, Friends List, Settings) are
-- non-resizable XWayland windows and Hyprland ALREADY auto-floats +
-- auto-centers them by their size hints alone — verified live: "Sign in to
-- Steam" (700x440) came up floating and exactly centered with zero rules
-- installed. This entry is deliberate belt-and-braces anyway, for the same
-- reason bitwarden.lua is explicit rather than relying on the same default:
-- a future Steam build that stops setting those hints (or runs one of these
-- dialogs maximized-by-default) must not silently start tiling a login box.
-- Runtime class is lowercase "steam" (verified; XWayland, not native Wayland).
-- A SEPARATE "Steam"-titled dialog was also observed ("Steamwebhelper is not
-- responding") but it is a bare zenity(1) crash notice Steam shell-launches,
-- not a Steam window — matching class=steam only, deliberately not zenity.
hl.window_rule({
  match  = { class = "^steam$", title = "^(Sign in to Steam|Friends List|Settings)$" },
  float  = true,
  center = true,
})

-- Lutris and Heroic: verified live (both launched, both windows present at
-- once) — their MAIN windows tile correctly with zero rules (class
-- "net.lutris.Lutris" / "heroic", floating=false, laid out side by side by
-- the default layout exactly like any other app). No override is written
-- here on purpose: both toolkits (GTK4/libadwaita for Lutris, Electron for
-- Heroic) set correct dialog/modal window-type hints, which Hyprland already
-- auto-floats the same way it did for Steam's login dialog above — adding a
-- rule for a problem that was checked and is not there would be exactly the
-- kind of memory-based guess gaming-plan.md asks not to make. Revisit only if
-- a real modal is observed misbehaving (e.g. a Lutris "Add Game" or Heroic
-- "Settings" dialog tiling instead of floating).
