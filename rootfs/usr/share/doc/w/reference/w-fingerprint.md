---
title: w-fingerprint
section: reference
order: 0
summary: Enrol, list and delete the fingerprints of the current user.
---

`w-fingerprint` — Enrol, list and delete the fingerprints of the current user.

## Usage

```
Usage: w-fingerprint <command> [args]

Info: Enrol, list and delete the fingerprints of the current user.

Commands:
  status [--porcelain]              Show reader availability and all ten finger slots
  enroll <finger>                   Enroll one finger; emits event=<name> lines while running
  delete <finger>                   Delete one enrolled finger
  lock-sensor mode <native|wake>    Who verifies under the lock screen (see below)
  lock-sensor window <seconds>      How long the sensor stays lit in wake mode (10..300)
  lock-sensor status [--porcelain]  Mode, window and the live sensor state
  fingers                           List accepted finger names
  help                              Show this help

Lock sensor:
  native  hyprlock verifies itself, sensor lit for the whole lock (default)
  wake    w-authd verifies for <window> s after lock, wake-up or any activity,
          then the sensor sleeps; readers that overheat under a long lock
          (verify-disconnected after ~4 min) keep working this way
  A mode switch takes effect at the next lock. Both keys are user-scope
  (~/.config/w/fingerprint.conf); a hyprlock started by hand, outside the
  w-lock scope, gets no sensor in wake mode.

Exit codes: 0 success · 1 runtime error · 2 usage
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-fingerprint help`.
