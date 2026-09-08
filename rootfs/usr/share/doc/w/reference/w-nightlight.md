---
title: w-nightlight
section: reference
order: 0
summary: Night light — warm the screen on a schedule to cut blue light in the evening.
---

`w-nightlight` — Night light — warm the screen on a schedule to cut blue light in the evening..

## Usage

```
Usage: w-nightlight <command> [value]

Info: Night light — warm the screen on a schedule to cut blue light in the evening.

Commands:
  status [--porcelain]   Show mode, temperatures, window and whether it is on now
  mode <off|schedule|always>
                         off      never filter
                         schedule warm between the start and end times
                         always   warm around the clock
  temp <K>               Night colour temperature, ${TEMP_MIN}-${TEMP_MAX} (lower is warmer)
  day <K>                Daytime colour temperature — the other end of the ramp.
                         ${IDENTITY_K} (the default) means an untouched screen.
  schedule <HH:MM> <HH:MM>
                         Start and end of the night window (crossing midnight is fine)
  transition <minutes>   How long the change from day to night takes (0 = instant)
  toggle                 Flip between off and schedule
  preview <K|off|reset>  Live, NOT saved: try a temperature, drop to neutral, or
                         (reset) go straight back to what the schedule says
  apply                  Re-compute and ease to what should be on screen right now
  help                   Show this help

Options:
  --user <name>          Act for that account instead of the invoker (root).
                         apply.sh --nightlight uses it to render every account,
                         not just the first one.

Config: ~/.config/w/nightlight.conf   (defaults: /usr/share/w/defaults/nightlight.conf)
Renders: ~/.config/hypr/hyprsunset.conf  — generated, do not edit by hand
GUI: W Hub -> Displays -> Night light

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-nightlight mode schedule
  w-nightlight temp 3400
  w-nightlight day 6500
  w-nightlight schedule 22:30 06:45
  w-nightlight transition 30
  w-nightlight preview 2700
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-nightlight help`.
