---
title: w-screenshot
section: reference
order: 0
summary: Capture the screen — region/window/output, annotate/copy/save.
---

`w-screenshot` — Capture the screen — region/window/output, annotate/copy/save.

## Usage

```
Usage: w-screenshot <mode> [action]

Info: Capture the screen — region/window/output, annotate/copy/save.

Modes:
  region    Select a rectangular region
  window    Capture the focused window (Hyprland geometry)
  output    Capture the focused monitor
  full      Capture all monitors

Actions (default: annotate):
  --annotate   Select and draw in one frozen overlay (Flameshot; its toolbar
               copies, saves or pins). Back to the two-step satty stack:
               `w-conf set --user screenshot ANNOTATOR satty`; return with
               `w-conf unset --user screenshot ANNOTATOR`.
               `full --annotate` is always satty: a Flameshot overlay is one
               window on one monitor.
  --copy       Copy the capture straight to the clipboard (wl-copy), no UI
  --save       Save the capture to $SCREENSHOT_DIR and notify

Exit codes:
  0  Success or user-cancelled selection
  1  Runtime error
  2  Usage error

Examples:
  w-screenshot region                # drag an area and draw on it in place
  w-screenshot output --copy         # focused monitor → clipboard
  w-screenshot full --save           # every monitor → PNG file
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-screenshot help`.
