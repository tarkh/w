---
title: Displays and night light
section: guide
order: 5
summary: Monitor layout, scaling and placement, the separate login-screen layout, the blue-light filter, and what to do about a black screen.
sources:
  - path: .claude/library/w-monitor.md
    sha256: 79e44dc01381170142d38d80021c3c2f1ef3533031d6e7d96f1a79c377eb932f
  - path: .claude/library/w-nightlight.md
    sha256: 50cce4d1f5c5d33b58b73a91f5fe3f5c73a5ad035d63805753852ed5b4e7984d
---

**Hub → Displays** holds two things that answer the same question — what the
screen physically looks like. The first two tabs are the monitor layout, one for
your session and one for the login screen; the third is the night light.

## The monitor layout

The **Session** tab lists every connected output with the controls you would
expect:

- **Resolution** and **Refresh rate** — the modes the monitor actually reports.
- **Scale** — how large everything is drawn. **Auto** picks a sensible value for
  the panel's size and density. The list holds only scales the compositor
  accepts for this resolution, in roughly quarter steps — a panel that cannot
  divide by 1.5 offers 1.6 instead. Hyprland rejects anything else and quietly
  substitutes its own pick, so W never offers it; `w-monitor scales <output>`
  prints the full set.
- **Rotation** — for a monitor standing on its side.
- **Position** — where this output sits relative to the ones already placed:
  *Left*, *Right*, *Above*, *Below*. There is no pixel arithmetic to do; W
  chains the outputs for you.
- **Primary** — a W concept rather than a Wayland one. The primary output is the
  one that carries the status bar, and the one the login card and the lock
  screen are drawn on.
- **Enabled** — turn an output off without unplugging it.

Your layout lives in a settings file, not in the compositor's memory, so it
survives a reboot and a re-plug. From a terminal the same layout is `w-monitor`
— `w-monitor status` prints what you have, and `w-monitor help` lists the rest.
No administrator rights are involved: the session is yours.

Changing **Scale** or **Primary** also moves the lock screen, which reads its
size at the moment it locks — so the change lands the next time the screen
locks, not immediately.

## The login screen has its own layout

The greeter is a separate program that runs before you log in, so it does not
see your session's settings. The **Login screen** tab configures it separately,
and because that file belongs to the machine rather than to you, saving it asks
for your password.

That tab behaves a little differently from the first one on purpose:

- **Copy from session** takes the layout you just built for yourself as a
  starting point.
- Changes are staged and only land when you press **Apply** — you are editing a
  screen you are not currently looking at, so nothing happens behind your back.
  **Discard** throws the staged edits away.
- The hint *"Changes apply on the next login screen"* is literal: to see the
  result, log out.

## Night light

The **Night light** tab warms the screen in the evening to cut blue light. It
shifts the compositor's colour transform rather than painting over the screen,
which has two pleasant consequences: it costs nothing while you work, and it
does **not** show up in screenshots or screen recordings.

- **Mode** — *off*, *schedule* (warm only inside the night window), or *always*.
- **Temperature** — the night value in kelvin; lower is warmer. 4300 is the
  default, 3000 is clearly amber, 2000 is candlelight.
- **Day temperature** — what the screen returns to when the window closes. The
  default 6600 leaves the screen alone; any other value is a real tint that
  stays on all day, which is exactly what someone who wants a permanently warmer
  screen is after. It is not an off switch — *off* means an untouched screen
  whatever this says.
- **The night window** — a start and an end time. Crossing midnight (21:00 →
  07:00) is normal. W uses clock times rather than sunset and sunrise: it ships
  no geolocation.
- **Transition** — how long the scheduled change takes, in minutes. It paces
  only the scheduled change; a switch you flip yourself eases across in about
  two seconds, so you never wait.

<kbd>Super+Shift+N</kbd> toggles the filter between *off* and *schedule*.

Two things surprise people, and neither is a fault. Setting the mode to
*schedule* in the afternoon changes nothing visible until the window opens. And
the login screen stays neutral — the night light lives in your session, and the
greeter is a different program.

From a terminal the same settings are `w-nightlight`.

## A black screen after a display change

This is a settings file, not a broken system, and it does not call for a
rollback.

W already refuses the two changes that would obviously blind you: you cannot
disable the primary output, and you cannot disable the last one still drawing.
What it cannot prevent is a legitimate change that goes wrong later — turning
off the laptop panel while an external monitor is attached is reasonable until
the external monitor is unplugged.

If you end up looking at nothing, switch to a text console with
<kbd>Ctrl+Alt+F2</kbd>, log in, and run:

```
w-monitor reset --all
sudo w-monitor greeter reset
```

The first line restores your session's layout to automatic, the second does the
same for the login screen. [RECOVERY.md](../RECOVERY.md) covers this and the
other "I cannot get back in" situations.
