---
title: Themes and wallpapers
section: guide
order: 2
summary: Switching themes, creating a theme from a wallpaper, wallpaper sets, and the Appearance panel.
sources:
  - path: .claude/library/w-theme.md
    sha256: b2a973c39eac5eebda173cfc43b710a91ab4cb68ae63a599c3ccf45e6e6eaa04
  - path: .claude/library/w-wallpaper.md
    sha256: 2499a3c31263d765ac650f83ea6e84264c64424627e28df47631e425f9740f41
---

A theme in W is one palette that the system renders onto every surface: the
Hyprland UI, the Quickshell shell, GTK and Qt applications, the terminal, GRUB,
Plymouth, the login greeter. Switching a theme re-skins all of them at once —
down to the colour of the boot logo — with a live crossfade.

## Switching themes

**Hub → Appearance** lists installed themes with wallpaper previews. Clicking a
theme switches it for your user; a system-wide change is done from the CLI by
an administrator (`w-theme set <name>` with privileges). The list has two
sections: **System** themes and **My** themes (per-user, created by you).

From a terminal: `w-theme list` and `w-theme set <name>`.

## Creating a theme from a wallpaper

**Hub → Appearance → Add** (or `w-theme new` in a terminal) builds a theme out
of an image:

1. Pick a wallpaper image and a name, choose **Dark** or **Light**.
2. W extracts the dominant colors from the image and builds an accessible
   palette around the base color you pick — contrast is checked automatically
   so text stays readable in both modes.
3. Choose an intensity (low/medium/high) for the palette ramp and confirm.

Light themes get special care: ink colors are recalculated against the light
surfaces, so buttons and icons keep their contrast.

The same screen, opened with the pencil badge on one of **your** generated
themes, rebuilds that theme from its own wallpaper (new base color, new
contrast) — the wallpaper itself does not change.

Wallpapers are per-resolution images in a small set of size tiers; a theme
ships what it ships and the system falls back to the nearest size. See
`w-wallpaper` if you maintain a theme's assets.

## The Appearance panel

- **Themes** tab — the theme grids above, plus creating and removing themes.
- **Bar** tab — which bar blocks are shown, per monitor (see `w-bar`).
- **Settings** tab — backdrop blur and animation toggles, and the bar position.

## Theming from the CLI

`w-style` renders the theme onto each subsystem, `w-theme` manages which theme
is active and what exists, `w-wallpaper` manages the wallpaper files. For
hands-on maintenance (for example after editing a system theme by hand):
`w-style apply` re-renders, `w-reset all` returns the W defaults.
