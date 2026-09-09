---
title: Keyboard, mouse and touchpad
section: guide
order: 6
summary: Keyboard layouts and the switch key, key repeat, mouse and touchpad behaviour, gestures, and where the fingerprint reader is set up.
sources:
  - path: .claude/library/w-keyboard.md
    sha256: 13b38a7476f4b3928d2c11bdbe3c0a906b1f0d65b2ec8b84c67adb41c90f85dc
  - path: .claude/library/w-pointer.md
    sha256: d8344be0c6e6e9e74217ae93f6bb1279480eb2350564b6e00b0f0a60b7c0fe5f
  - path: .claude/library/w-locale.md
    sha256: f7115aa77613a12c20ac382e5a3e74662b4278a8a811d4755e7da4fc90a8b232
---

**Hub → Input** is where the hardware you type and point with is configured. It
opens on **Keyboard** and grows tabs to match the machine: **Touchpad** appears
only where there is one, **Fingerprint** only where there is a reader.

Two neighbours are deliberately elsewhere. Which key does what is **Hub →
Hotkeys**, not this panel — see [the desktop guide](desktop.md#windows-and-workspaces).
The language of the interface itself is **Hub → System → Language**, described
at the end of this page.

## Keyboard layouts and the switch key

**Layouts** is an ordered ring. **Add language** appends to it, the ring's first
entry is the one you get at the login screen, and the **Switch key** cycles
through them.

The switch key is not an ordinary shortcut — it is a combination of modifiers
alone, which the compositor cannot express as a binding, so it is set here
rather than in Hotkeys. The offered choices are Alt+Shift (the default),
Ctrl+Shift, Right Alt, Both Shifts, Ctrl+Space and Super+Space. The last three
carry a warning, and it is worth reading: Right Alt is AltGr on many layouts and
would swallow special-character input, Ctrl+Space is autocompletion in most
editors and terminals, and Super+Space already opens the Hub.

## Typing

- **Key repeat rate** — how many repeats per second a held key produces.
- **Repeat delay** — how long you must hold it before repeating starts.
- **NumLock at login** — applied when a keyboard is initialised, so it takes
  effect at your next login rather than right now.

From a terminal these are `w-keyboard`; `w-keyboard status` prints the current
ring, `w-keyboard list` the ~99 layouts available.

## Mouse

- **Speed** and **Acceleration** — *Adaptive* speeds up with the movement,
  *Flat* keeps the ratio constant. Flat is what you want for anything where the
  distance you move should always mean the same thing on screen.
- **Natural scrolling** and **Scroll speed**.
- **Left-handed (swap buttons)**.

## Touchpad

The touchpad tab carries the settings that make a pad feel like yours:

- **Touchpad enabled**, **Speed**, **Acceleration**, **Natural scrolling** and
  **Scroll speed** — as on the mouse.
- **Disable while typing** — stops the heel of your hand from moving the cursor
  mid-sentence.
- **Tap to click**, and **Two- / three-finger tap**, which chooses whether two
  fingers mean right-click and three mean middle, or the other way round.
- **Physical click** — *By area* treats the bottom corners of the pad as
  buttons; *By finger count* decides from how many fingers rest on the pad,
  which is the behaviour most laptops ship with today.
- **Middle-click emulation** — pressing both buttons at once.
- **Drag by tapping** and **Drag lock**, which keeps a drag alive when you lift
  a finger briefly — *with timeout* releases it on its own, *sticky* waits for
  another tap.
- **Multi-finger drag** — drag with three or four fingers instead of pressing.

If the tab shows the pad but **Speed**, **Acceleration** and the on/off switch
do nothing, the session has not identified the device yet: run `w-pointer
detect` once from a terminal inside the session. Those three are per-device
settings and need the pad's name; the rest are not.

## Gestures

- **Swipe to switch workspaces** — off, or with three or four fingers.
- **Natural swipe direction** — which way the workspaces move under your
  fingers.
- **Swiping past the last one creates a workspace**.

## Cursor timeouts

Two numbers, both in seconds, that hide the pointer when it is not being used —
`0` means never:

- **Hide when idle — system** applies to the session as a whole.
- **Hide when idle — menus** applies only while the launcher, the Hub or the
  clipboard is open, so the pointer gets out of the way of keyboard navigation.
  While it is hidden the menu stops highlighting whatever it happens to rest
  on, which is the point: one selection instead of two. Any mouse movement
  brings both back.

From a terminal all of this is `w-pointer`: `w-pointer status` prints
everything, `w-pointer keys` lists every setting with its accepted values, and
`w-pointer reset --all` returns to the W defaults.

## Fingerprint

Where the machine has a reader, the **Fingerprint** tab enrols one. Press
**Add**, choose a finger, and swipe until the card says it is done. With at
least one fingerprint enrolled, W's password dialog offers the reader as an
alternative; deleting the last one turns that off again. The password always
keeps working — see [the security guide](security.md#fingerprint-login).

## The interface language

The language W itself speaks is a system setting rather than a keyboard one, so
it lives in **Hub → System → Language** and asks for your password. It applies
to sessions started afterwards, so log out and back in to see it. Adding a
*layout* to type in that language is the Keyboard tab above; the two are
independent.
