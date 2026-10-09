---
title: The desktop
section: guide
category: desktop
order: 4
summary: Windows, workspaces, popups, notifications, screenshots and session restore.
sources:
  - path: .claude/library/package-hyprland.md
    sha256: 5dfed699e45460460d3b1f3e5408dadd0a1bb9f4db3fccab3cc51a37dae9d61d
  - path: .claude/library/quickshell.md
    sha256: da1b14d9d934188dd9b49ece41af8b58ab8d5abe06c6172e198e1c5ade171759
  - path: .claude/library/w-screenshot.md
    sha256: cab923bc52e33ecc3604a6f4786103d095312a01a25b1b2a5ee893a41c67c3ae
  - path: .claude/library/w-record.md
    sha256: c7ff443860ecebfc73ec01be9a90b845d1a1110e79f9bdabfde1c5dcd7b0f625
  - path: .claude/library/package-files.md
    sha256: 85da1d2fccfd07be804443763a7fdde37727878e1b6c85d3288413f72c23b504
---

W desktop = the Hyprland compositor with the Quickshell UI on top. Both are
configured by W's theme; the tools you touch day to day are the ones below.

## Windows and workspaces

Hyprland is a tiling compositor: windows tile automatically, and dragging a
window's titlebar into another turns them into a resizable split. The basics:

- Move focus with <kbd>Super+Arrow</kbd>, move windows with
  <kbd>Super+Shift+Arrow</kbd>, switch or move windows between the first ten
  workspaces with <kbd>Super+(Shift+)1..0</kbd>.
- **Window groups**: <kbd>Super+G</kbd> groups two windows into a tabbed group
  (W styles the group's tab bar); <kbd>Super+Tab</kbd> cycles inside one.
- <kbd>Super+F</kbd> / <kbd>Super+Shift+F</kbd> fullscreen (real and
  fake-fullscreen), <kbd>Super+M</kbd> maximize, <kbd>Super+Shift+Space</kbd>
  float/untile, <kbd>Super+Shift+C</kbd> center a floating window,
  <kbd>Super+P</kbd> pin it above everything.
- <kbd>Super+R</kbd> resize mode, <kbd>Super+S</kbd> the scratchpad (a parked
  window you summon back on the current workspace).
- **Per-app window rules** (always float this app, open it centred at a fixed
  size…) are drop-in files: W's own live in `/usr/share/w/hypr/rules.d/`, yours go
  in `~/.config/hypr/rules.d/<app>.lua` and win over W's for the same app —
  a file that calls `hl.window_rule({ match = { class = "^(app)$" }, float = true })`,
  then `hyprctl reload`.
- **Open / Save dialogs** float and open at one size (1000x640). Resize one once
  and GTK apps keep that size everywhere. If every app's dialog suddenly opens
  full-height, reset the saved size: `gsettings reset
  org.gtk.Settings.FileChooser window-size`.
- The full, rebindable list lives in **Hub → Hotkeys**.

## The shell surfaces

- **The bar** at the top: workspaces, active window, tray, clock, and status
  blocks (updates, network, audio). Which blocks it shows — and on which
  monitor — is set in **Hub → Appearance → Bar**.
- **The launcher** (<kbd>Super+D</kbd>) starts apps and carries W actions
  (lock, screenshot, screen recording, calendar).
- **The Hub** (<kbd>Super+Space</kbd>) is the control center — see the other
  guides.
- **Clipboard history** (<kbd>Super+V</kbd>) searches what you copied; entries
  persist across reboots.
- **Notifications** appear in the top-right. A left click opens the source —
  it switches to the app's workspace, focuses its window (restoring it from the
  tray) and lets the app show the chat or tab; a right click dismisses one card,
  a middle click dismisses them all. **Hub → Notifications** (and the `w-notify`
  command) manage do-not-disturb and per-app muting.
- **Volume and brightness** popups open from their keys; they show levels
  live like any desktop's OSD.

## Sessions that come back

When W's session memory is on (default for new installs), logging out — or
locking for longer than the configured interval — parks your windows and
brings back the same layout at the next login, including files open in the
terminal. **Hub → System → Session** chooses: always restore, always start
fresh, or off. **Super+O** saves or applies a named, reusable layout.

Do-not-reopen apps (e.g. a password manager you want empty after every login)
are excluded in the session settings; see `w-session` for the details.

Window groups (tabbed windows) come back as groups, tabs in order. What is
*inside* a window is each program's own memory: browser tabs return only if
the browser restores them itself — in Firefox, **Settings → Home and startup → "Open
previous windows and tabs"**; W does not switch that on for you.

## Screenshots

Three keys, all of which land you in the same place — a frozen copy of the
screen you can draw on straight away, with the toolbar next to your selection.
Nothing else opens: copy, save or pin the result from that toolbar and it is
gone again.

| Key | Captures |
| --- | --- |
| <kbd>Super+I</kbd> | the monitor you are on, already selected |
| <kbd>Super+Shift+I</kbd> | nothing yet — drag the area you want |
| <kbd>Super+Ctrl+I</kbd> | the focused window, already selected |

The editor's Save button asks where and under what name, opening on the
`Screenshots` folder inside your pictures folder. Two more keys skip the editor
entirely and write the file straight there, no questions asked:

| Key | Saves |
| --- | --- |
| <kbd>Super+Alt+I</kbd> | the focused monitor |
| <kbd>Super+Ctrl+Alt+I</kbd> | the focused window |

Files are named `W-<date>_<time>.png`. The annotation colours and font follow
your theme, and every key here is rebindable in **Hub → Hotkeys** — including
unbinding the two you do not want.

The editor is Flameshot. W also ships the older one, Satty, for the case where
Flameshot misbehaves on your hardware — pick it under **Hub → Displays → Screen
capture → Editor** (or `w-screenshot set ANNOTATOR satty`), and it opens from the
next capture on. Satty shows the shot at its real size, and a selected region opens
right over the spot you selected, with the toolbars around it. Whichever is set, `w-screenshot` carries the full set of modes for scripts and the CLI,
including the ones with no editor at all (`--copy`, `--save`).

A **window** shot taken without an editor (`--copy`, `--save`) or opened in Satty comes
out with transparent rounded corners, and — **Hub → Displays → Screen capture → Add
window shadow**, *Yes* by default — a soft shadow like on macOS
(`w-screenshot set WINDOW_SHADOW no` turns the shadow off). Flameshot saves its own
frame, so it gets neither; for the finished look use the instant window keybind or
pick Satty. A translucent window still shows what is behind it: what is captured is
the finished picture of the monitor, not the window's own surface.

## Screen recording

Three more keys, on <kbd>R</kbd> for record. Each one is a switch rather than a
button: press it to start, press it again to finish.

| Key | Records |
| --- | --- |
| <kbd>Super+Ctrl+R</kbd> | the monitor you are on |
| <kbd>Super+Alt+R</kbd> | an area you drag |
| <kbd>Super+Ctrl+Alt+R</kbd> | the focused window |

Files land in the `Screencasts` folder inside your videos folder, named
`W-<date>_<time>.mp4`. A notification confirms the start, and the one at the end
carries the finished path — click it to play the video. You can also stop a take from a terminal with
`w-record stop`, and ask what is going on with `w-record status`.

While a take is running, the bar shows a pulsing red dot and the time recorded so
far, just left of the Do Not Disturb bell. Click it to stop; right-click it to
open the recording settings. It disappears the moment the recording ends, so no
dot means nothing is being recorded.

**Sound is recorded by default** — everything you can hear, the same mix that
comes out of your speakers. Your microphone is *not* in it. One track holds one
source, so the desktop and the microphone cannot both be on it.

Everything about the next take is set in **Hub → Displays → Screen capture**:

| Setting | Choices |
| --- | --- |
| Encoding | Auto (the graphics card when it can, else the processor), Processor, Graphics card |
| Sound | Desktop sound, Microphone, No sound |
| Format | MP4 (plays everywhere), MKV (survives a crash mid-take), WebM (for the web) |
| Frame rate | 15, 24, 30, 60 or 120 frames per second |

WebM is always encoded on the processor, so it and *Graphics card* exclude each
other — the Hub offers only the combinations that work. A change applies from the
next recording; one already running keeps what it started with. The same settings
from a terminal:

```sh
w-record get                  # every setting and its current value
w-record set AUDIO mic        # narrate instead of the desktop's sound
w-record set FRAMERATE 60
w-record set WINDOW_MASK yes  # window recordings: black rounded corners, CPU encode
```

Two things worth knowing before a long take. Recording a **window** records the
rectangle it occupies at the moment you start, so a window you then move or
resize will not be followed — record the monitor if the layout is going to
change. And there is no all-monitors mode: Wayland hands over one screen at a
time, so a single file spanning every monitor is not something that can be made.
