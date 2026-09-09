---
title: w-theme
section: reference
order: 0
summary: Switch, add and manage W themes with seamless crossfade.
---

`w-theme` — Switch, add and manage W themes with seamless crossfade..

## Usage

```
Usage: w-theme <command> [options]

Info: Switch, add and manage W themes with seamless crossfade.

Commands:
  set <name> [--no-fade]  Switch theme.
                            no root → this user, instant, crossfade
                            sudo    → system fallback + skel + boot/greeter
                            --no-fade  skip the crossfade
  reset                   Drop your personal theme, follow the system fallback
  new <name> --wallpaper <image> [opts]
                          Build a theme from an image: the wallpaper is
                          cover-cropped to every resolution tier and the palette
                          is extracted from it (matugen + OKLCH mapping).
                            no root → ~/.config/w/themes/, sudo → /etc/w/themes/
                            --appearance dark|light   default dark
                            --contrast low|medium|high
                                                      how much the surfaces are
                                                      tinted and how far apart
                                                      the tones sit; low is the
                                                      pastel end, default medium
                            --seed-index <n>          which base colour of the
                                                      image to build from
                                                      (0 = most dominant)
                            --scheme <matugen type>   default: adaptive
                            --activate                switch to it once built
                            --json                    print the palette matrix
                                                      only, create nothing: every
                                                      base colour the image
                                                      offers × dark/light × every
                                                      contrast level (GUI preview;
                                                      the other options are then
                                                      irrelevant, it returns all
                                                      of them)
  edit <name> [opts]      Rebuild a generated theme's palette in place, keeping
                          its wallpaper. Same options as `new` minus the image
                          (a different wallpaper is a different theme — use
                          `new`), plus --rename <newname>; anything not given
                          keeps what the theme already has. Re-skins the session
                          (or the system) if that theme is the active one.
                          Hand-authored themes are refused.
  rm <name>               Delete a theme (sudo for a system one). If it is your
                          active theme, the pin is reset first.
  list [--porcelain]      List system and local themes (* = active here)
                            --porcelain  TSV: name, scope, dir, active, generated
  current                 Show the effective user and system themes

Theme dirs:
  system  /etc/w/themes/<name>/
  local   ~/.config/w/themes/<name>/    (each: theme.conf + wallpaper/)

A generated theme carries only theme.conf, wallpaper/ and preview.webp — motion,
geometry, effects, fonts and the Kvantum base are inherited from the baseline
theme 'w', so it keeps up with W instead of freezing a copy.

Exit codes:
  0  Success
  1  Runtime error
  2  Usage error

Examples:
  w-theme list
  w-theme set midnight
  sudo w-theme set midnight
  w-theme reset
  w-theme new sunset --wallpaper ~/Pictures/sunset.jpg --activate
  w-theme new garden --wallpaper ~/Pictures/park.jpg --seed-index 1 --contrast low
  sudo w-theme new corporate --wallpaper /srv/brand.png
  w-theme edit sunset --contrast low
  w-theme rm sunset
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-theme help`.
