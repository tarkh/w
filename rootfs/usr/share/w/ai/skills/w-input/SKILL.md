---
name: w-input
description: >-
  Input configuration on W Linux: keyboard shortcuts (the w-hotkeys CLI, profiles
  and the Hub Hotkeys section), keyboard layouts and typing behaviour (w-keyboard —
  the layout ring, toggle key, key auto-repeat, NumLock), mouse and touchpad
  settings (w-pointer — speed, acceleration, scrolling, tap-to-click, click method,
  disable-while-typing, drag modes, swipe gestures), and the system language /
  locale (w-locale, LANG). Load this for anything about keybindings, remapping keys,
  keyboard layouts, mouse or touchpad behaviour, the input language, or the system
  locale.
sources:
  - path: .claude/library/w-hotkeys.md
    sha256: cedb796f65ff1c859ff32b9f37987cfa9d2980fb1d5f7469a56c959d942e4e8e
  - path: .claude/library/w-keyboard.md
    sha256: 13b38a7476f4b3928d2c11bdbe3c0a906b1f0d65b2ec8b84c67adb41c90f85dc
  - path: .claude/library/w-locale.md
    sha256: f7115aa77613a12c20ac382e5a3e74662b4278a8a811d4755e7da4fc90a8b232
  - path: .claude/library/w-pointer.md
    sha256: d8344be0c6e6e9e74217ae93f6bb1279480eb2350564b6e00b0f0a60b7c0fe5f
tools:
  - w_keyboard_status
  - w_hotkeys_status
  - w_pointer_status
---

# W Input

Everything about *input* on W: **key bindings**, **keyboard layouts and typing**,
**mouse and touchpad**, and the **system locale**. All of them are user-space,
first-party `w-*` CLIs with matching UI in the W Hub (the Hotkeys section and the
Input / System panels). Only the locale change is privileged.

> For the desktop keybindings *at a glance* and the compositor itself, see the
> `w-desktop` skill; this skill is the home for *configuring* input.

## Key bindings — `w-hotkeys`

Bindings are **data, not hand-edited config**. A catalog maps action tokens to
Hyprland dispatchers (`~/.config/hypr/hotkeys-catalog.lua`); **profiles** select
which chord runs which token; the active fragment `hotkeys.lua` is what the
compositor loads. Changes apply live via `hyprctl reload`.

- Built-in profiles: **`default`** (81 tokens across 8 categories — apps, window,
  focus, move, workspace, dwindle, system, menu) and **`i3-vim`** (an i3/vim-style diff).
  User profiles are named `^[a-z0-9-]+$`. Run `w-hotkeys catalog` for the live list
  rather than quoting a count from memory. The `menu` category (menu_up/down/left/
  right/confirm/back/delete) is Quickshell-local — roving-focus keys shared by the
  W Hub and almost every other Quickshell popup (Volume, Brightness, the Auth
  prompt, calendar, infobox — see the `w-desktop` skill for the full picture; the
  Power Menu and the tray context menu are the two exceptions), not a Hyprland
  dispatcher; still rebindable via the same CLI, but only a bare key (no modifiers)
  is a valid chord for these tokens. Where a popup has a TEXT FIELD holding focus —
  the launcher, the clipboard viewer, the assistant, the layouts panel, the Hub's
  timezone/locale/keyboard pickers and the password prompt — those chords are read
  **with Ctrl**, because a bare letter would be typed into the field instead of
  moving. So tell a user on `i3-vim` to press Ctrl+J/Ctrl+K there, not J/K; bare
  arrows, Enter and Esc work in every panel regardless of profile. Deleting an entry
  in such a panel is `Shift+Del` (or `Shift+Backspace`, or Ctrl + whatever
  `menu_delete` is — `Ctrl+X` on `i3-vim`). The Hub's Hotkeys section shows both
  chords side by side under "Menu control", so point a user there rather than
  reciting the rule. Ctrl is fixed by design and is not configurable.
- CLI: `w-hotkeys profiles` (list), `w-hotkeys use <profile>` (switch),
  `w-hotkeys catalog` (list bindable action tokens), `w-hotkeys set <token> <chord>`
  (rebind), `w-hotkeys reset <token>`, `w-hotkeys custom-add <chord> <command>` /
  `custom-rm` (arbitrary chord → command), `w-hotkeys profile-new` / `profile-rm`.
- GUI: the **Hotkeys** section of the W Hub — a profile selector, per-category
  binding view, click-to-rebind (with capture), conflict highlighting, and custom
  actions. This is the easy path for a user; the CLI is the scriptable one.

Media keys (play/next/prev, volume, mute) are fixed binds in the catalog that drive
`playerctl` and `wpctl` (see the `w-audio` skill for the audio side).

> Changing the layout-switch key is *not* a keybinding — it is an XKB-level option
> (see below), because a pure modifier combo like Alt+Shift cannot be expressed as a
> Hyprland bind.

## Keyboard layouts — `w-keyboard`

`w-keyboard` manages the session's **layout ring** (user-space, no root): an ordered
`kb_layout` list (`"us,ru"`) with a parallel `kb_variant` list and `kb_options`
(which carries the `grp:*_toggle` switch key). The first layout in the ring is the
login default; the toggle key cycles through them. Each change is applied live
(`hyprctl keyword input:kb_layout|...`) and persisted to the fragment
`~/.config/hypr/keyboard.lua` (the single source of truth — read even headless).

- `w-keyboard status` — the current ring (layouts / variants / options).
- `w-keyboard list` — available layouts (~99, from xkeyboard-config's `evdev.lst`).
- `w-keyboard variants <code>` — variants for a layout.
- `w-keyboard add <code[:variant]>` / `w-keyboard remove <code>` — add/drop a layout
  (keeps at least one).
- `w-keyboard set-toggle <grp:...>` — set the switch key (default `alt_shift_toggle`);
  replaces just the `grp:` option, keeping others.
- `w-keyboard set-default <code>` — move a layout to the front of the ring (the login
  default).
- `w-keyboard set-repeat <rate> <delay>` — key auto-repeat: repeats per second
  (1–100, default 25) and the delay in ms before repeating starts (100–2000, default
  600).
- `w-keyboard set-numlock <on|off>` — NumLock at login. It is applied when a keyboard
  is initialised, so tell the user it takes effect at the next login.

GUI: the **Keyboard** segment of the W Hub's Input panel (layout picker, toggle-key
selector, default badge, auto-repeat sliders, NumLock), backed by this CLI.

## Mouse and touchpad — `w-pointer`

`w-pointer` manages the session's pointer settings (user-space, no root). Same shape
as `w-keyboard`: the fragment `~/.config/hypr/pointer.lua` is the source of truth
(read even headless), and every change is applied live with `hyprctl reload` — which
re-runs the whole config, so a setting that is *removed* (a disabled gesture) really
disappears.

- `w-pointer status` — every setting, plus whether a touchpad is present and which
  devices were detected. **Call this before answering** — a machine may have no
  touchpad at all, and half of these keys then do nothing.
- `w-pointer keys` — every settable key with its accepted values and default. Use it
  instead of guessing key names.
- `w-pointer set <key> <value>` — one validated setting. Keys are namespaced:
  - `mouse.*` — `sensitivity` (−1..1), `accel_profile` (adaptive|flat),
    `natural_scroll`, `scroll_factor`, `left_handed`.
  - `touchpad.*` — `enabled`, `sensitivity`, `accel_profile`, `natural_scroll`,
    `scroll_factor`, `disable_while_typing`, `tap_to_click`, `tap_button_map`
    (`lrm` = 2 fingers right-click / 3 middle, `lmr` = swapped),
    `clickfinger_behavior` (click by finger count instead of bottom areas),
    `middle_button_emulation`, `tap_and_drag`, `drag_lock` (0|1|2), `drag_3fg`
    (0 = off, 1 = three-finger drag, 2 = four-finger).
  - `gestures.*` — `workspace_fingers` (0 = off, 3, 4 — swipe to switch workspaces),
    `swipe_distance`, `swipe_invert` (natural direction), `swipe_create_new`.
  - `cursor.*` — idle-hide timeouts in **seconds** (`cursor.inactive_timeout`):
    `system_timeout` (session-wide, 0 = never) and `menu_timeout` (default 0.1,
    applied while a modal Quickshell popup — launcher/hub/clipboard/power menu/
    assistant/infobox/layouts — is open, so the pointer gets out of the way of
    keyboard nav; any mouse movement brings it back). Both floats, `10` stored
    as `10.0`.
- `w-pointer list` — live pointer devices (mouse vs touchpad).
- `w-pointer detect` — re-scan touchpads and record their Hyprland device names.
- `w-pointer reset [mouse|touchpad|gestures|cursor|--all]` — back to W defaults.

⚠️ **The menu cursor-hide is driven compositor-side**, not by `w-pointer` alone:
`hyprland.lua` swaps `inactive_timeout` on `layer.opened/closed` of the shared
`quickshell:overlay-scrim` surface (mapped exactly while a modal popup is shown),
so it self-restores even if the shell dies mid-popup. `w-pointer` only stores the
two numbers. Disable by setting `menu_timeout` to 0.

While the pointer is hidden it also stops highlighting whatever it happens to rest
on, so a keyboard-driven menu shows one selection instead of two; the first mouse
movement brings both the pointer and its highlight back. Hiding is only visual at
the compositor level, so this half is the shell's own — the same `menu_timeout`
drives it, and 0 turns off both.

⚠️ **Touchpad speed, acceleration and the on/off switch are per-DEVICE settings** —
Hyprland has no `input:touchpad:sensitivity`, so they are emitted as `hl.device()`
rules and need the touchpad's device name. If `status` shows a touchpad present but
no devices, run `w-pointer detect` from inside the session first; setting those three
keys without a known device name silently affects nothing.

GUI: the **Mouse** and **Touchpad** segments of the Hub's Input panel (the Touchpad
segment only exists on a machine that has one).

## System locale — `w-locale`

`w-locale` reads and switches the system interface language (`/etc/locale.conf`
`LANG=`), generating the chosen locale on demand. Reading is unprivileged; **setting
is root** (it edits `/etc/locale.gen`, runs `locale-gen`, writes `LANG`).

- `w-locale status` — current `LANG`.
- `w-locale list` — selectable UTF-8 locales (~327, from glibc's `SUPPORTED`).
- `w-locale set <locale>` — **privileged**; the change takes effect only for sessions
  started *after* it (tell the user to re-login).

In the W Hub this lives in the **System** panel's "Language" section (it is a
system, relogin-scoped setting, closer to About/Updates than to the layout ring),
actuated through polkit.

## Tools (via `w-mcp`)

Three **read** tools ground input answers (all read-only, no privilege) — use them so
you report the machine's real state instead of assuming:

- **`w_keyboard_status`** *(read)* — the current layout ring (layouts, variants, and
  the `grp:*_toggle` switch key).
- **`w_hotkeys_status`** *(read)* — the active keybinding profile and its effective
  bindings (token → chord → source). Call it for "what is bound to X" / "what does
  Super+… do" instead of guessing from the defaults table.

- **`w_pointer_status`** *(read)* — mouse and touchpad settings, and whether a
  touchpad exists at all. Call it before answering anything about pointer behaviour
  ("why doesn't tapping click", "the scrolling is inverted") rather than assuming the
  machine is a laptop.

**Changing** layouts, keybindings or pointer settings is *not* a tool: `w-keyboard`,
`w-hotkeys` and `w-pointer` are user-space (rootless), so drive their CLIs through
the host shell (or the W Hub) — `w-keyboard add/remove/set-toggle/set-default/
set-repeat/set-numlock`, `w-hotkeys use/set/reset/custom-add`, `w-pointer set/detect/
reset`.

- **`w_locale_set`** — the one privileged input action: change the system locale. It
  is a **shared** Tier-2 tool (owned by the system domain, gated by a polkit prompt),
  a tool precisely *because* it needs root — it reruns `locale-gen` and rewrites
  `LANG`. Reversible; always tell the user it only applies to sessions started
  afterwards.
