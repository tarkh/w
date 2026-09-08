---
title: w-power
section: reference
order: 0
summary: Power profiles, idle policy (lock/display/suspend), lid/power key, charge limit.
---

`w-power` — Power profiles, idle policy (lock/display/suspend), lid/power key, charge limit..

## Usage

```
Usage: w-power <command> [args]

Info: Power profiles, idle policy (lock/display/suspend), lid/power key, charge limit.

Commands:
  status                     Show mode, profile, battery, idle timers, hypridle state
  profile <name>             Switch power profile live (performance|balanced|power-saver)
  profile auto on|off        Auto-switch profile on AC<->battery (root)
  idle <ac|bat> <lock|display|suspend> <seconds>
                             Set a cascade link (0 = off), RELATIVE to the previous
  idle <ac|bat> kbdlight <seconds>
                             Keyboard backlight off after N s idle (0 = never);
                             independent of the cascade, counts from last activity
                             link: lock counts from last activity, display from the
                             lock firing, suspend from the display firing; re-renders
                             hypridle (user). display < 5 is accepted but warns
                             (hyprlock needs the screen on to grab its background)
  charge-limit <0..100>      Battery charge ceiling, e.g. 80 (root; laptop firmware)
  lid <ac|bat|docked> <lock|suspend|ignore>
                             Lid-close action per power state (root)
  lid-wake <auto|keep>       Whether the lid may wake the machine (root). auto (default)
                             drops it from the ACPI wake sources while suspending with
                             the lid ALREADY OPEN — where it can serve no purpose and on
                             some firmware wakes the machine within seconds — and
                             restores it on resume, so lid-close/lid-open still wakes.
                             keep never touches the wake sources.
  power-key <poweroff|suspend|menu|ignore>
                             Power-button action (root; menu = open the W power menu)
  mode <laptop|desktop|auto> Apply a machine-mode preset to every knob (root)
  apply                      Re-render every node from $CONF (root)
  help                       Show this help

Options:
  --user <name>              Act for that account instead of the invoker (root).
                             apply.sh --power uses it to render every account's
                             idle policy, not just the first one.

System policy: $CONF   User idle overrides: ~/.config/w/power.conf

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-power status
  w-power profile performance
  w-power idle bat suspend 600
  sudo w-power charge-limit 80
  sudo w-power lid ac ignore
  sudo w-power lid-wake keep
  sudo w-power mode laptop
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-power help`.
