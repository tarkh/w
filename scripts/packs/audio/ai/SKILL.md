---
name: audio
description: >-
  The `audio` W-Pack: music production on PipeWire — Ardour 9 (DAW), qpwgraph
  (patchbay), Audacity, the plugin starter set (Surge XT, LSP, Dragonfly), the
  JACK API from PipeWire and the `realtime` group. How YOU drive a running
  Ardour over its own MCP surface (and why it is off by default), routing and
  latency (buffer size, xruns), plugin discovery and the W colour themes. Load
  this for DAW/recording/mixing work, audio routing between apps, latency or
  "no sound in Ardour" problems — when `w-pack status audio` reports installed.
---

# W-Pack: audio

Music production on W's PipeWire stack, all from the official `extra` repo.
Curated into `/usr/share/w/ai/skills/audio/` when the bundle is installed.
General sound (volume, devices, "no sound") is the base `w-audio` skill's
knowledge — this skill is the studio layer on top.

## What the bundle actually did

1. **JACK API from PipeWire**: `pipewire-jack` replaced `jack2` (pre.sh). Any
   JACK app — Ardour first — talks to the running PipeWire; there is no JACK
   server to start, and none should be (`jackd` would fight PipeWire for the
   device). `pipewire-jack` stays after the pack is removed (ffmpeg needs a
   `jack` provider).
2. **Realtime**: `realtime-privileges` (group `realtime`: rtprio 98,
   unlimited memlock); the installing account was added to it. Membership
   counts from the **next login** — `id -nG` shows it at once, `ulimit -r`
   (98) / `ulimit -l` (unlimited) only in a new session. An account that ran
   `w-pack setup audio` without root got the admin command to ask for.
3. **Apps**: `ardour` (Ardour 9), `qpwgraph`, `audacity`; plugins, one format
   each: `lsp-plugins-lv2`, `dragonfly-reverb-lv2` (LV2 — Ardour and Audacity
   load them), `surge-xt-vst3` (VST3 — Ardour only).
4. **Ardour seeds** (`~/.config/ardour9/`, only if absent): `config` — audio
   backend **JACK/Pipewire**, 48 kHz / 256 frames, plugin scan at every start
   (`discover-plugins-on-start`); `ui_config` — colour theme `w`.
5. **Themes** (w-style axes): `ardour` renders `~/.config/ardour9/themes/w-ardour.colors`
   from the W palette; `audacity` sets Audacity's light/dark theme to W's
   appearance. qpwgraph follows the Qt axis. None is live — the app reads its
   theme at start; after `w-theme set`, restart Ardour/Audacity.
6. **AI bridge**: `/usr/share/w/ai/mcp.d/ardour.conf` registers Ardour's own MCP
   server by URL (`http://127.0.0.1:4820/mcp`) for every `w-ai` host.

## Driving Ardour (MCP)

Ardour 9.8 serves MCP itself — "MCP HTTP Server (Experimental)": session and
transport, tracks/buses, sends, plugins and their parameters, markers,
regions, MIDI notes. **It is OFF by default, and must stay the user's switch:**
it listens on every interface, with no authentication and no Origin check —
while it runs, any web page open in a browser (or any host on the network the
firewall lets in) can drive the session. So:

- Tools from the `ardour` server fail to connect → Ardour is not running, or
  the surface is off. Ask the user to enable it: Ardour → Edit → Preferences →
  Control Surfaces → tick **MCP HTTP Server (Experimental)** — and to untick it
  when done. Never enable it yourself (no config edits, no scripts).
- Host notes: Claude Code / Codex / OpenCode connect at launch — if Ardour was
  started later, restart the assistant (`w-ai`). In goose the server is listed
  but disabled until you enable the extension.
- Work loop: inspect (`session_get_info`, `tracks_list`, `track_get_regions`)
  → change in small steps → re-read to verify. `session_save` (or
  `session_quick_snapshot`) before destructive edits; `session_undo` reverts
  editor operations. Plugins: `plugin_list_available` → `plugin_add_by_plugin_id`.
- There is **no tool to import an audio file** — the surface edits what the
  session already holds (regions, MIDI notes from JSON). New audio comes in
  through the user (Session → Import, Ctrl+I) or `ardour9-lua`.
- Without the surface: `ardour9-lua` runs Lua against a session headless
  (batch import/export, renaming, analysis); `ardour9-export` renders a
  session from the command line.

## Routing and latency

- **qpwgraph** — the patchbay: every PipeWire node (apps, Ardour's JACK ports,
  devices, MIDI) and its wires; save a wiring as a patchbay file and turn on
  "activate" to have it re-applied. CLI equivalents: `pw-link -o`/`-i` (list
  ports), `pw-link <out> <in>` / `-d` (connect/disconnect), `pw-jack <app>`
  forces any app onto PipeWire's JACK library.
- **Buffer size = latency.** Ardour asks for 256 frames at 48 kHz (~5.3 ms);
  PipeWire honours it for the graph — except in a virtual machine, where
  PipeWire's own VM rule raises the minimum to 1024 (~21 ms, by design). Xruns (clicks, Ardour's xrun counter) →
  raise to 512/1024 in Window → Audio/MIDI Setup; force for the whole graph:
  `pw-metadata -n settings 0 clock.force-quantum 512` (`0` = back to auto).
  Check the live values: `pw-top` (QUANT/RATE per node, ERR = xruns).
- Xruns with small buffers and the account not in `realtime` (or not
  re-logged in) → that is the cause; fix the group, log out and in.
- **All sound stops the moment Ardour starts** (and Audacity hangs at start
  while Ardour runs): Ardour is duplex, so the input device joins its graph
  and, ranking higher, becomes the graph's clock — a capture device that
  delivers nothing (dead/virtual mic, a VM's sound card) freezes everything.
  Check: `timeout 5 pw-record - | head -c 100000 | wc -c` gives 0. Fix: card
  profile without input — `wpctl status` (card id) → `wpctl set-profile <id>
  <output-only index>` (`pw-cli enum-params <id> EnumProfile` lists them).
- "Device busy" / no backend → `pacman -Q pipewire-jack` (jack2 back means a
  manual change — `w-pack install audio` swaps it again); never pick the raw
  ALSA backend in Ardour — PipeWire holds the device.

## Plugins

Ardour finds LV2 at every start; VST3 (Surge XT) through the start-up scan the
seed turns on — a plugin installed later appears at the next Ardour start, or
at once via Window → Plugin Manager → Discover. Paths: LV2 `/usr/lib/lv2`,
VST3 `/usr/lib/vst3` (and `~/.vst3` for the user's own). Audacity loads LV2
(LSP, Dragonfly) — not Surge XT (VST3, an instrument). Plugin windows are
normal floating windows. Windows-only VSTs (yabridge + Wine) are **not**
supported by W yet.

## Theming

- Ardour: theme **W** (`color-file` = `w`), plus `~/.config/ardour9/clearlooks.rc`
  — the installed widget rc with greyed-out labels made readable on dark
  palettes. A colour the user edits in
  Preferences → Appearance → Colors is saved as `my-w-ardour.colors` and wins
  over W's file — to return to W's palette, delete that file. Picking another
  theme there is the user's choice; W does not switch it back.
- Audacity: W flips only light ↔ dark; a user-chosen high-contrast/classic/
  custom theme is kept. Audacity rewrites its config on exit, so change it
  while Audacity is closed.

## Music generation (ComfyUI)

Not wired yet. The intended path: generate a stem with YuE on the local
ComfyUI service (`comfyui` W-Pack, :8188 API) and bring the WAV into the Ardour
session. Ardour's MCP surface cannot import files, so today: render in ComfyUI,
the user imports it (Session → Import, Ctrl+I), then you arrange, process and
mix it over MCP.
