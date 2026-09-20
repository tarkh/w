---
title: Keyboard, mouse and touchpad
section: guide
order: 6
summary: Keyboard layouts and the switch key, key repeat, mouse and touchpad behaviour, gestures, and where the fingerprint reader is set up.
sources:
  - path: .claude/library/w-keyboard.md
    sha256: ce8652939203622146af301b8f3ca9294fb723e85a8706a261d902fd41bbbf35
  - path: .claude/library/w-pointer.md
    sha256: 6305ddbe5a3269ba4a9d36d27bb1b1a2c2001ee5d387cfa9ff6ca0d525152067
  - path: .claude/library/w-locale.md
    sha256: 689971e1187491ddf127d58d89c4fb4aa632cf5bd7015df76e762f7100287707
  - path: .claude/library/w-userdirs.md
    sha256: e3aed83e00209e9f3d94b94de1e9ee6c67c85028be243b5f49b9f1e7c9a4b328
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

The list shows each language under its own name — «русский», 日本語, Deutsch —
with its locale code beside it. Searching matches either, so you can type `рус`
or `ru_RU`, whichever your current keyboard can produce.

### After you switch, some things stay English for a while

Changing the language is instant and works with no network, which means it does
not download anything. A few parts of the system need an extra package before
they can speak your language — the Firefox interface, the spell checker, the
translated manual pages. They arrive on the next system update, or immediately
with:

```
sudo w-langpack apply
```

`w-langpack status` says what is missing before you run it. Nothing is broken in
the meantime: anything without its language pack simply stays in English.

### Your folders follow the language

The standard folders in your home — Documents, Downloads, Pictures, Music,
Videos, Desktop — are created in your language at your first login, and the
programs find them by their role, not their name (a screenshot lands in the
Pictures folder whatever it is called). When you switch the language, they are
**renamed at your next login**: `~/Pictures` becomes `~/Изображения`, with
everything in it exactly where it was — a rename is all that happens, nothing is
copied, merged or deleted.

Two things are left alone on purpose. A folder you moved or renamed yourself
(`xdg-user-dirs-update --set DOWNLOAD /path` is the command; a file manager
does the same) is yours and keeps its name in every language. And if the new
name is already taken by a folder with files in it, both stay as they are —
`w-userdirs status` says so, and merging them is your call.

If you would rather keep the English names, the switch is right under the
language: **Hub → System → Language → Folder names follow the language → No**.
It is per user and needs no password. `w-userdirs sync --dry-run` previews what
the next login would rename.

### What will not translate

Some of the terminal programs W ships have no translations at all — not missing
from W, absent from the programs themselves. The file lister (`eza`), the shell
history search (`atuin`), the editors (`helix`, `micro`), the file manager
(`yazi`) and the system monitor (`btop`) are English-only whatever your language
is. Their *dates and numbers* do follow your locale; only their own words do not.
So `ls` shows you Russian month names, but if you list a directory you may not
read, the refusal comes back in English — that message belongs to the program,
not to W.

W's own `w-` commands are a different case, and worth knowing the shape of:
their **help is translated** — `w-<command> help`, the `w-info` catalog, and the
whole command reference in this documentation. What stays English is what they
print *while working*: errors, status lines, progress. An English error under a
Russian help page is expected, not a half-finished translation.

For the same reason a Japanese or Chinese web page shows real characters rather
than empty boxes: W installs full Unicode font coverage regardless of the
language you picked.
