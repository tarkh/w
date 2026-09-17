---
name: w-theming
description: >-
  How theming works on W Linux: the theme model (one source of truth), switching
  themes with w-theme (per-user vs system scope, seamless crossfade), re-rendering
  individual axes with w-style, resolution-aware wallpapers with w-wallpaper, and
  per-user overrides (bar position, blur, animations, RGB backlight + saturation)
  with w-appearance that beat the active theme without editing it. Load this for
  anything about colors, dark/light, fonts, geometry, effects, wallpapers,
  adding/switching themes, or turning off blur/animations/moving the bar / recoloring
  RGB devices for just one user.
sources:
  - path: .claude/library/w-theme.md
    sha256: 846128d6fe4b73cfc9b4e833d75e0390f2023e89d1a2e07a8e9b6dae05e28e08
  - path: .claude/library/w-style.md
    sha256: e64419af33ab98c8afb42dbacf9e0a0bcb324f3f70a439fae33328ec4392fba5
  - path: .claude/library/w-wallpaper.md
    sha256: 7cdb354e1eb86ed817b8bb5356db0a35b05a7fa05020e2c126217c83b65b7b68
  - path: .claude/library/w-appearance.md
    sha256: 635f4abe38c80529de495e85ff44b201642ab2e6d42b61ddfcb09010afbe5dab
tools:
  - w_theme_status
  - w_theme_set
  - w_theme_new
  - w_theme_rm
---

# W Theming

Everything visual on W is driven from **one source per theme**: a `theme.conf` of tokens.
A single renderer (`w-style`) fans those tokens out to every subsystem — Hyprland,
Quickshell, Ghostty, GTK, Qt, the lock screen, the greeter, GRUB, and Plymouth — so the
whole system stays consistent. Three tools cooperate: `w-theme` (switch themes),
`w-style` (render axes), and `w-wallpaper` (wallpapers).

## The theme model

A theme is a directory:

```
/etc/w/themes/<name>/        # system themes
~/.config/w/themes/<name>/   # optional per-user themes
```

Each theme has `theme.conf` (color / geometry / effect / appearance tokens) and a
`wallpaper/` directory. It may optionally add `motion.conf`, `font.conf`, and
`geometry.conf`; if absent, those are inherited from the baseline theme `w`. The
`theme.conf` also carries the meta-token `W_APPEARANCE=dark|light`.

`geometry.conf` is where interface **shape** lives: window rounding/gaps/borders and the
shell's radius/padding scale (`W_GEO_*`), plus a dedicated `W_GEO_BAR_*` section for the
status bar — position (top/bottom), height, corner radii, margins, padding, gaps and
outlines. Radii take a number of pixels (`0` = sharp corners) or the keyword `pill`
(= half the element's height, an even stadium rounding). Edit it, then `w-style apply
geometry`; the bar and the compositor pick it up live. This is the right place for
"make everything square", "make the bar taller" — the bar's own `bar.json` holds its
blocks and colors, not its shape. For "put the bar at the bottom" **for just one
user** (not the theme itself), use `w-appearance bar-position bottom` instead — see below.

`effects.conf` (also optional, also inherited from `w`) is where **translucency and blur**
live: window opacity by focus (`W_FX_WINDOW_OPACITY_*`), blur (`W_FX_BLUR_*`), the shell's
card/menu backgrounds (`W_FX_SURFACE_OPACITY`) and overlay dimming (`W_FX_SCRIM_OPACITY`),
plus foreign-app window backgrounds (`W_FX_APP_BG_OPACITY`, terminal `W_FX_TERM_OPACITY`).
The **bar's own chrome has its own pair** — `W_FX_BAR_OPACITY` (its background plaque) and
`W_FX_BAR_BORDER_OPACITY` (its outline) — kept apart from the cards on purpose: setting
both to `0.0` dissolves the bar and leaves its blocks **floating as separate islands**
(they carry their own zone background), while menus, popups and the greeter card keep the
translucency they had. That is the answer to "make the bar transparent / floating islands":
edit the theme's `effects.conf`, then `w-style apply effects` — live, no restart. By default
the pair aliases `W_FX_SURFACE_OPACITY`, so a theme that only dials the cards moves the bar
with them. Outline *width* is shape (`W_GEO_BAR_BORDER` in `geometry.conf`), not this.

Themes resolve **user over system**: a per-user theme shadows a system one of the same
name. Adding a new theme is just creating its directory — no code changes.

Inside `theme.conf` colours live on three tiers: `W_PALETTE_*` (tier 1) are the raw
pigments and the **only** place a hex literal may appear; semantic roles (`W_SURFACE`,
`W_PRIMARY`, …) reference them; component tokens (`W_TERM_*`, `W_QS_*`, `W_GTK_*`, …)
reference the roles. Pigment names denote a role, not a hue, and stay correct in a light
theme: `SURFACE_0…3` is the background ramp (0 = canvas, 3 = most raised), `ACCENT` /
`VIVID` the two accents (each ±`_CONTAINER`/`_SOFT`/`_INK`), `TEXT_*` the foreground
tones, `DANGER_*` the critical axis, `HUE_*` the ANSI wheel, `RGB_*` (`SOFT`/
`MEDIUM`/`CRISP`) a physical-LED calibration separate from the screen accents.
To reskin a theme
wholesale, edit tier 1 and re-render; to fix one detail, edit its role or component
token.

A pigment that **fills** a shape and one that is **drawn on** a shape are different
pigments, and mixing them up is the classic way to make a light theme unreadable:
`_CONTAINER` is built to sit close to its surface so a fill reads as a gentle wash,
which is exactly what makes it invisible as a button outline, a tab label or an icon.
Those use `_INK`, which the generator holds at 4.5:1 against the raised card. So if a
control has vanished on a light theme, the token behind it is almost certainly pointing
at a container (or at a raw accent) where it should point at `W_ON_SURFACE_ACCENT` /
`W_ON_SURFACE_VIVID`.

## Building a theme from a wallpaper

`w-theme new <name> --wallpaper <image>` creates a whole theme from one picture:

- The image is cover-cropped to 16:9 and rendered into every resolution tier
  (5120/3840/2560/1920), so a 1080p pick still works on a 4K screen — upscaled, hence
  softer. Any common format is accepted (png/jpeg/webp/avif/heic/tiff/bmp/jxl) and is
  always re-encoded to webp inside the theme, so the source format never matters.
- The palette is extracted with matugen (Material HCT) from the **cropped** master and
  mapped into W's pigments in OKLCH, then every foreground is pushed until it clears its
  WCAG contrast target. A washed-out image gets its chroma synthesised so the theme still
  has an identity; a genuinely black-and-white one yields a neutral theme, with only the
  danger axis and the ANSI wheel keeping their hue (those carry meaning, not style).
- **Which colour the theme is built around is a choice.** A picture usually carries
  several dominant colours (a green garden, a blue sky, a gold fountain); the extraction
  offers up to four that are genuinely different in hue, and `--seed-index <n>` picks one
  (0 = most dominant, the default). A picture with one hue offers exactly one — the row
  is never padded.
- **`--contrast low|medium|high`** places the surfaces and how far apart the tones sit.
  `medium` is the calibrated default. `low` is the soft, pastel end: it lifts the canvas
  into the palette, which is what makes a light theme read as tinted paper rather than a
  white sheet — recommend it to anyone who finds the light theme harsh. `high` goes the
  other way, toward crisp and near-absolute. No level lowers legibility: every foreground
  still clears its contrast target.
- Other options: `--appearance dark|light` (default dark), `--activate` to switch to it
  immediately, `--json` to print the palette matrix without creating anything, `--scheme`
  to override the automatic matugen scheme.
- **No root → a personal theme** in `~/.config/w/themes/`; **with `sudo` → a system
  theme** in `/etc/w/themes/` (this is also how the shipped themes are authored).

`w-theme edit <name>` rebuilds a generated theme's palette **in place, keeping its
wallpaper**: `--seed-index`, `--contrast`, `--appearance` and `--rename` — anything not
given keeps what the theme already has. Use it for "make my theme softer / lighter /
built around the blue instead"; use `new` when the wallpaper itself should change, since
that is a different theme. If the edited theme is the one being worn, the session
re-skins immediately. Hand-authored themes are refused rather than overwritten — never
assume which those are, read the `generated` column of `w-theme list --porcelain`; `w`,
the base theme every generated theme inherits from, is always among them.

`w-theme rm <name>` deletes one. If it is the user's active theme the pin is reset first,
so the session falls back to the system theme instead of pointing at nothing. A system
theme needs `sudo`, and the baseline `w` cannot be removed — everything else inherits
from it.

A generated theme carries only `theme.conf`, `wallpaper/` and `preview.webp`; motion,
geometry, effects, fonts and the Kvantum base are inherited from `w`, so it keeps up with
W instead of freezing a copy.

## `w-theme` — switch themes

- `w-theme set <name>` — switch the active theme.
  - **Without root:** pins the choice for the current user only (`~/.config/w/`), with a
    seamless crossfade, and re-skins every user-scope axis in one pass (`w-style apply
    user`). Does not touch GRUB/Plymouth.
  - **With `sudo`:** repoints the system default (`/etc/w/active-theme`) and renders
    everything, including system-scope axes (greeter, GRUB, Plymouth). No crossfade.
    Only system themes are allowed here.
- `w-theme reset` — drop the personal pin and follow the system default (with crossfade).
- `w-theme list` — list system and user themes (`*` marks the active one).
  `--porcelain` gives TSV `name, scope, dir, active, generated` — the ground truth
  for which themes exist here and which of them `w-theme edit` will accept.
- `w-theme current` — show the effective user and system theme.

The crossfade is **per monitor**: every output is frozen with its own captured frame
(`grim -o`) under its own overlay surface, so on a multi-monitor session all screens
change together and none shows the swap happening live. It needs a live Hyprland plus
`grim` and `jq`; if any of that is missing the theme still applies, just without the
fade. `w-theme set --no-fade` skips it deliberately.

Theme resolution: user pin (`~/.config/w/theme/active`) → system default
(`/etc/w/active-theme`) → baseline `w`. A user without a pin picks up the system default
at login (theming is rendered before the compositor starts).

## `w-style` — render one axis

`w-style apply <axis>` re-renders a single theming axis (e.g. `colors`, `geometry`,
`effects`, `font`, `gtk`, `qt`, `hyprlock`, and more). It is normally invoked by
`w-theme`; call it directly to re-apply after hand-editing a theme's `theme.conf`.
`w-style apply user` renders all user-scope axes; `w-style apply all` (root) also renders
system-scope axes. Most axes reload live; a few (lock screen, greeter) take effect on the
next lock/login.

Folder colours in the file manager are one of the system-scope axes: the `icons` axis
recolours the Papirus folder icons to the theme's own tone, and only as root. So a
per-user `w-theme set` renders that account's colours but leaves folders as the machine's
system theme left them — recolouring them is `sudo w-style apply icons`, and it changes
them for everyone. Applications read the result at startup, so already-open windows keep
the old folders until they are restarted.

Note `apply all` writes the user-scope axes into `/etc/skel` when run as root, never into
a home — an existing account is re-rendered by the account itself. A system update does
that for every account at the end of the run, so **"part of my desktop went back to the
default theme after an update" is not expected behaviour**: it means that render failed.
Look for `WARN: w-style apply user failed` in `/var/log/w/apply.log`, then re-run
`w-style apply user` as that user to see the real error.

## `w-wallpaper` — wallpapers

`w-wallpaper set|get|apply` selects a resolution-appropriate wallpaper from the active
theme. It is multi-monitor and picks a per-resolution tier (1920 / 2560 / 3840 / 5120)
with **bidirectional fallback**: it steps down to a smaller master if needed, otherwise up
to a larger one — so a theme need not ship every size. Wallpapers are `webp` (preferred)
or `png`.

`w-wallpaper cover <WIDTHxHEIGHT>` reports how far the displayed master is stretched to
fill a panel of that size. The boot splash uses it so the brand mark keeps one size
across the splash, the login screen and the desktop: the logo is rendered for the panel
when the initramfs is built, so **a monitor swap or a resolution change wants a
`sudo w-style apply plymouth`** to re-render it (a theme switch does this anyway).
The mark's colour follows the theme too: a theme without its own `logo/` inherits the
brand vector tinted in `W_PLYMOUTH_LOGO` / `W_GRUB_LOGO` (the accent container; light
themes use the accent itself), while a theme that ships `logo/W-logo.svg` owns the mark
verbatim, colour included.

## `w-appearance` — per-user overrides that beat the theme

Small overrides that win over the active theme for the logged-in user only, without
editing the theme itself — no root, no GUI equivalent needed beyond W Hub →
Appearance → Settings tab:

- `w-appearance bar-position <theme|top|bottom>` — pin the bar's edge, or hand it back
  to the theme's `geometry.conf`.
- `w-appearance blur <theme|off>` — force Hyprland blur off.
- `w-appearance motion <theme|off>` — force Hyprland animations off (global toggle).
- `w-appearance rgb <on|off>` — recolor all RGB devices via the OpenRGB axis
  (600-rgb) on every login/theme render. `off` leaves devices untouched (last
  color stays — it is "don't recolor", not "lights out"); `on` = default;
  `unset` in wconf = follow the theme.
- `w-appearance rgb-level <soft|medium|crisp>` — which of the theme's three
  dedicated RGB pigments (`W_RGB_SOFT`/`_MEDIUM`/`_CRISP`, `medium` = default)
  colors the hardware. These are **not** `W_PRIMARY`/the screen accent: they are
  calibrated separately for a light-emitting device (fixed lightness, no
  dark/light split, `crisp` deliberately over-requests chroma so it lands on
  the most saturated colour that hue can produce). Independent of `rgb` on/off.
- `w-appearance status [--porcelain]` — show the overrides (porcelain also
  reports the three RGB pigments' hex).

The GUI for `bar-position` lives in Hub → Appearance → **Bar** (not the Settings tab),
together with the bar's per-monitor composition — which is a different axis and a
different tool: `w_bar_set` / the `w-bar` CLI, see the **w-desktop** skill. Position and
translucency here, WHICH BLOCKS EXIST there.

`theme` clears the override and reverts to whatever the active theme says. Every
override **survives a later `w-theme set`** — it is not baked into one theme's render,
it is read fresh on every render. There is no MCP tool for this (Hub/CLI only); if asked
to change these programmatically, run the CLI directly rather than inventing a tool call.
