---
title: w-record
section: reference
order: 0
summary: Record the screen — region/window/monitor, one key to start and stop.
---

`w-record` — Record the screen — region/window/monitor, one key to start and stop.

## Usage

```
Usage: w-record <mode> [action] | stop | status [--porcelain] | get [KEY] | set KEY VALUE

Info: Record the screen — region/window/monitor, one key to start and stop.

Modes:
  region    Select a rectangular region
  window    Record the focused window (Hyprland geometry)
  output    Record the focused monitor

Actions (default: toggle):
  --toggle  Start recording, or stop the one already running. This is what the
            keybinds do: the same chord begins and ends the take.
  --start   Start only; fail if a recording is already running

Commands:
  stop      Stop the running recording and finish the file
  status    Report whether a recording is running, of what, and for how long
  get       Print every setting as KEY=value (+ BACKENDS), or one value
  set       Change one setting for your account

Settings (in effect from the next recording):
  RECORDER  wf (wf-recorder; gsr arrives with an optional W-Pack)
  ENCODER   auto | cpu | vaapi — where the encoding happens
  AUDIO     system | mic | none — what lands on the audio track
  FORMAT    mp4 | mkv | webm; webm always encodes on the CPU
  FRAMERATE constant frame rate, 1-240; 30 by default
  WINDOW_MASK yes | no — paint the corners of a `window` recording black instead
            of the wallpaper behind them; yes always encodes on the CPU

Exit codes:
  0  Success, or the user cancelled the selection
  1  Runtime error
  2  Usage error

Examples:
  w-record output                    # focused monitor; press again to stop
  w-record region --start            # drag an area, start, fail if busy
  w-record stop                      # finish the file and notify
  w-record status --porcelain        # machine-readable state
  w-record set AUDIO mic             # narrate instead of the desktop's sound
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-record help`.
