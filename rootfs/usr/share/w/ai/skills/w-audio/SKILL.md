---
name: w-audio
description: >-
  How audio works on W Linux: the PipeWire + WirePlumber stack, the wpctl/pactl
  CLIs, the Volume Control popup and the wiremix mixer, and — most importantly —
  how to diagnose "no sound". Load this for anything about audio, sound devices,
  volume/mute, microphones, or a silent machine.
sources:
  - path: .claude/library/package-audio.md
    sha256: c5b39c470bb5215b27120d9dc128c5a8f11f9ad41da6e6b8f49f886b2142d967
  - path: .claude/library/quickshell-volumecontrol.md
    sha256: 05dc4dfdd3d9e9c8881cf30ef55f727883b51c36b965d836d61db2f7bbb53edd
tools:
  - w_audio_status
---

# W Audio

Sound on W is **PipeWire** with the **WirePlumber** session manager. There is no
separate PulseAudio or JACK daemon — PipeWire implements the protocols itself
through shims (`pipewire-pulse`, `pipewire-alsa`; the JACK one, `pipewire-jack`,
comes with the `audio` pack along with DAWs and realtime scheduling).

## The stack

- **`pipewire`** — the media server (the node graph). On its own it creates *no*
  sink/source nodes.
- **`wireplumber`** — the session manager. It creates the actual sink/source nodes,
  handles routing and device policy. **This is mandatory**: bare `pipewire` without
  WirePlumber means no nodes, i.e. silence and an empty Volume Control popup.
- **`pipewire-pulse`** — the PulseAudio replacement; `pactl` and PulseAudio apps
  talk to this.
- **`pipewire-alsa`** — the ALSA → PipeWire bridge for legacy ALSA clients.

These run as **user** services (not system), socket-activated inside the session:
`pipewire`, `pipewire-pulse`, `wireplumber`. Check them with
`systemctl --user status pipewire wireplumber pipewire-pulse`. A soft graph reset
is `systemctl --user restart wireplumber` (it re-creates the nodes).

## CLI — `wpctl` (WirePlumber)

`wpctl` is the primary tool. `@DEFAULT_AUDIO_SINK@` / `@DEFAULT_AUDIO_SOURCE@` are
handy aliases for the current default output / input.

- `wpctl status` — the whole graph: default sink/source (marked `*`), volume, mute,
  every device and stream.
- `wpctl get-volume @DEFAULT_AUDIO_SINK@` — volume + a `[MUTED]` flag if muted.
- `wpctl set-mute @DEFAULT_AUDIO_SINK@ 0` — unmute (`1` mute, `toggle`).
- `wpctl set-volume @DEFAULT_AUDIO_SINK@ 50%` — set the volume.
- `wpctl set-default <id>` — make a device the default (the `id` comes from
  `wpctl status`).

`pactl` (via `pipewire-pulse`) also works — e.g. `pactl list short sinks`,
`pactl set-default-sink <name>` — for anyone used to the PulseAudio path.

## Diagnosing "no sound"

Work top-down; `w_audio_status` gathers most of this in one call:

1. **Is WirePlumber running?** If not, there are no nodes → silence. Restart it:
   `systemctl --user restart wireplumber`.
2. **Is there a default sink** (marked `*` in `wpctl status`)? If there is *no* sink
   at all, the problem is the hardware/ALSA driver (`aplay -l`), not PipeWire.
3. **Not muted?** `wpctl get-volume @DEFAULT_AUDIO_SINK@` → if `[MUTED]`, unmute.
4. **Volume not 0?** Bump it with `wpctl set-volume`.
5. **The right sink selected?** The classic case: audio is being sent to HDMI or the
   wrong device. Pick the intended one with `wpctl set-default <id>` (or the Output
   selector in the Volume Control popup).
6. **Per-app routing** (system has sound but one app doesn't) — open `wiremix`: the
   app's stream may be stuck on a different or disconnected device.
7. **Bluetooth audio** — check the device and its profile (A2DP vs HFP) in
   `wpctl status` / `wiremix`; pairing itself is handled by the Bluetooth applet.

## Volume UI and the mixer

- **Volume Control** (`Super+A`) — a Quickshell popup with a volume slider, output
  and input device selectors, and mute buttons. It talks to PipeWire natively (no
  subprocess). Its theme comes from `w-style`; behavior (like the mixer command)
  lives in `~/.config/quickshell/w/config/volume.json`.
- **wiremix** — a PipeWire-native **TUI** mixer (volume, routing, profiles/ports),
  opened from the popup's "Open Mixer" button (`w-term -e wiremix`). It is the
  advanced/per-app tool. Themed by the `w-style` `wiremix` axis (applies on its next
  launch, not live).

Media keys (play/next/prev, volume up/down/mute) are keybindings that drive
`playerctl` and `wpctl` — see the `w-input` skill for those bindings.

## Tool (via `w-mcp`)

- **`w_audio_status`** *(read)* — the live audio state: WirePlumber's status, the
  full `wpctl status` graph, and the default sink/source volume + mute flag. Call it
  first for any "no sound" / audio-device question so the diagnosis is grounded in
  the real graph instead of assumptions. It is read-only (no privilege). To *change*
  anything, guide the user through the `wpctl` commands above (or run them via the
  host shell) — there is no privileged audio actuation tool.
