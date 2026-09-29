---
title: w-screenshot
section: reference
order: 0
summary: Capture the screen — region/window/output, annotate/copy/save.
---

`w-screenshot` — Capture the screen — region/window/output, annotate/copy/save.

## Usage

```
Usage: w-screenshot <mode> [action] | get [KEY] | set KEY VALUE

Info: Capture the screen — region/window/output, annotate/copy/save.

Modes:
  region    Select a rectangular region
  window    Capture the focused window (Hyprland geometry)
  output    Capture the focused monitor
  full      Capture all monitors

Actions (default: annotate):
  --annotate   Select and draw in one frozen overlay (Flameshot; its toolbar
               copies, saves or pins). Back to the two-step satty stack:
               `w-screenshot set ANNOTATOR satty`; return with
               `w-screenshot set ANNOTATOR flameshot`.
               `full --annotate` is always satty: a Flameshot overlay is one
               window on one monitor.
  --copy       Copy the capture straight to the clipboard (wl-copy), no UI
  --save       Save the capture to $SCREENSHOT_DIR and notify

Commands:
  get          Print the settings as KEY=value, or one value
  set          Change a setting for your account

Settings (in effect from the next capture):
  ANNOTATOR      flameshot | satty — the editor `--annotate` opens
  WINDOW_SHADOW  yes | no — a `window` capture gets transparent rounded corners;
                 yes also adds a soft drop shadow. Not applied in Flameshot, which
                 saves its own frame: only `--copy`/`--save` and satty.

Exit codes:
  0  Success or user-cancelled selection
  1  Runtime error
  2  Usage error

Examples:
  w-screenshot region                # drag an area and draw on it in place
  w-screenshot output --copy         # focused monitor → clipboard
  w-screenshot full --save           # every monitor → PNG file
  w-screenshot set ANNOTATOR satty   # annotate in satty from the next capture
  w-screenshot set WINDOW_SHADOW no  # window shots: rounded corners, no shadow
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-screenshot help`.
