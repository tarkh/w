---
title: w-appearance
section: reference
order: 0
summary: Per-user overrides that beat the active theme (W Hub -> Appearance -> Settings).
---

`w-appearance` — Per-user overrides that beat the active theme (W Hub -> Appearance -> Settings).

## Usage

```
Usage: w-appearance <command> [value]

Info: Per-user overrides that beat the active theme (W Hub -> Appearance -> Settings).

Commands:
  status [--porcelain]              Show the three overrides and their effective values
  bar-position <theme|top|bottom>   Pin the status bar's edge, or hand it back to the theme
                                    (GUI: Appearance -> Bar, with the rest of the bar)
  blur <theme|off>                  Force Hyprland blur off, or hand it back to the theme
  motion <theme|off>                Force Hyprland animations off, or hand it back to the theme
  help                              Show this help

Config: ~/.config/w/appearance.conf (BLUR/MOTION) + config/bar.json (position)
GUI: W Hub -> Appearance -> Settings (blur, animations)
     W Hub -> Appearance -> Bar      (bar position; the bar's composition is `w-bar`)

Exit codes:
  0  Success   1  Runtime error   2  Usage error
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-appearance help`.
