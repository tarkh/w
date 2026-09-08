---
title: w-notify
section: reference
order: 0
summary: Control desktop notifications — Do Not Disturb, history, per-app mute.
---

`w-notify` — Control desktop notifications — Do Not Disturb, history, per-app mute..

## Usage

```
Usage: w-notify <command> [args]

Info: Control desktop notifications — Do Not Disturb, history, per-app mute.

Commands:
  status [--porcelain]          Show DND, timeouts, muted apps, history size
  dnd on|off|toggle             Turn Do Not Disturb on / off / flip it
  dnd for <30m|1h|90s>          Turn DND on until a relative deadline
  dnd until <HH:MM>             Turn DND on until the next occurrence of a time
  dnd critical on|off           Let critical alerts through DND (default on)
  dnd fullscreen on|off         Silence by itself while a window is fullscreen
  history [--porcelain] [-n N]  Show recent notifications (newest first)
  history clear                 Forget the recorded history
  mute [--list] | mute <app>    List muted apps, or mute one by app name
  unmute <app>                  Unmute an app
  timeout low|normal|critical|osd <ms>   Set an auto-dismiss timeout (0 = never)
  max <n>                       Max notifications visible at once
  osd on|off                    Volume/brightness OSD popups
  send [-u urgency] [-a app] <summary> [body]   Send a notification
  help                          Show this help

Config: $CONF
State:  $STATE

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-notify dnd for 1h
  w-notify dnd until 08:00
  w-notify history -n 20
  w-notify mute Telegram
  w-notify timeout normal 8000
  w-notify send -u critical "Reboot required" "The kernel was upgraded."
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-notify help`.
