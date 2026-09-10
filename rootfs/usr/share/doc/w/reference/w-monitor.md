---
title: w-monitor
section: reference
order: 0
summary: Configure monitors (resolution, scale, rotation, layout).
---

`w-monitor` — Configure monitors (resolution, scale, rotation, layout).

## Usage

```
Usage: w-monitor <command> [args]

Info: Configure monitors (resolution, scale, rotation, layout).

Commands:
  list [--porcelain]              Show live outputs (name, mode, scale, layout...)
  modes <output> [--porcelain]    List available modes for a live output
  status [--porcelain]            Show saved rules from the fragment + primary
  mode <output> <WxH@Hz|preferred>    Set resolution / refresh rate
  scale <output> <float|auto>         Set scale factor
  transform <output> <0|90|180|270>   Set rotation
  place <output> <right|left|above|below|auto>   Set layout position
  enable <output>                 Re-enable a disabled output
  disable <output>                Disable an output (blocked on primary or the last enabled one)
  primary <output>                Set the primary monitor (auto-enables it; where the main bar lives)
  sanity                          Re-enable one output if EVERY connected one is disabled
                                   (run before the compositor starts; no-op otherwise)
  reset <output>|--all            Drop saved rule(s), fall back to auto
  greeter status [--porcelain]        Show the greeter's effective config (no root needed)
  greeter sync                        Copy the session layout to the greeter (root)
  greeter primary <output>            Set the greeter's primary monitor (root, auto-enables it)
  greeter apply <spec>...             Set the whole greeter layout in one shot (root); spec =
                                       <output>:<mode>:<scale>:<transform>:<position>:<on|off|primary>
                                       (at most one spec may say "primary" — implies on, and
                                       is written as the greeter's primary monitor)
  greeter reset                       Drop the greeter override, fall back to auto (root)
  greeter sanity                      Same rescue as "sanity", for the login screen (root)
  help                            Show this help

Rules persisted to: $FRAG   State mirror: $STATE
Greeter rules: $GREETER_FRAG   Greeter state: $GREETER_STATE

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-monitor mode eDP-1 1920x1080@60
  w-monitor scale eDP-1 1.5
  w-monitor place HDMI-A-1 right
  w-monitor primary eDP-1
  w-monitor reset HDMI-A-1
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-monitor help`.
