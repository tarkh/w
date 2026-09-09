---
title: Power and battery
section: guide
order: 8
summary: Power profiles, the idle cascade of lock, screen-off and suspend, lid and power-button actions, and the battery charge limit.
sources:
  - path: .claude/library/w-power.md
    sha256: 038c7df8ac878dabf993b1798fd6251f9d490658ffcae039a3644d61c9571c4a
  - path: .claude/library/w-kbdlight.md
    sha256: c119c45ae51cfa7e33b66c1754a362ddd33d7c2851b7bae80654f877bbabb068
---

**Hub → Power** is one panel over everything that decides how much energy the
machine uses and what it does when you leave it alone.

## Laptop or desktop

**Machine → Type** is the switch that reseeds every other setting on this page
at once. *Laptop* gives you separate behaviour on wall power and on battery, a
lid action, and the battery controls. *Desktop* gives one gentle set of idle
timers, ignores the lid, and hides the battery section because there is nothing
to show.

It is normally detected for you, and worth changing only if the detection got
your hardware wrong. A value you set deliberately survives the switch — if
something looks stuck after changing the type, that is why: it is your choice,
not a preset. `w-reset power` clears the lot back to W's defaults.

## Power profile

**Profile** is *Performance*, *Balanced* or *Power saver*. Only the profiles the
hardware actually supports are offered — *Performance* needs a platform driver
that many desktops and virtual machines do not have, and its absence is not a
fault.

**Auto-switch (AC/battery)** hands the choice to the power source: balanced
while plugged in, power saver on battery. Turn it off if you would rather pick
by hand.

## Idle: lock, then screen off, then suspend

The three idle timers are a **chain, not three separate stopwatches**, and
reading them that way is the difference between the settings doing what you
expect and looking broken:

- **Auto-lock (idle)** counts from your last keypress or mouse move.
- **Screen off (after lock)** counts from the moment the lock fired.
- **Suspend (after screen off)** counts from the moment the screen went dark.

So 5 / 2 / 10 means: lock after five minutes, screen off two minutes later,
suspend ten minutes after that. Each row shows the resulting absolute time
underneath it, so you never have to do the arithmetic yourself. Setting a value
to zero switches that link off and the next one counts from the previous live
link instead.

On a laptop there are two independent sets — **Idle — on AC** and **Idle — on
battery** — and the battery one is deliberately more aggressive.

**Keyboard backlight off (idle)** sits in the same section but is *not* part of
the chain: it is its own timer counting from your last activity, and the light
comes back the moment you touch anything.

Two behaviours worth knowing about, both intentional:

- The machine always locks **before** it suspends, so it never resumes to an
  unlocked desktop.
- Once the screen is locked, nudging the mouse blanks the display again after
  the screen-off delay rather than leaving it lit.

<kbd>Super+L</kbd> locks immediately.

Idle timers are per-account: two people on one machine legitimately have
different ones.

## Lid and power button

On a laptop, **Lid** sets what closing the lid does, separately **On battery**
and **On AC** — suspend, lock, nothing, or power off. **Power button → When
pressed** does the same for the button: the power menu, suspend, power off, or
nothing.

If your machine suspends and then wakes a few seconds later on its own, W
already handles the usual cause — on some firmware an open lid keeps asserting
a wake signal, so W removes it for the duration of a suspend that started with
the lid open and puts it back afterwards. Closing the lid still wakes the
machine as it should.

## Battery

**Status** shows the charge and, where the firmware reports it, the battery's
**health** — its current full capacity against its original one.

**Charge limit** caps charging below 100%. A battery kept at 80% ages
noticeably more slowly than one held full, which is worth it for a laptop that
lives on a desk; set it to *Full* before a trip. The cap is re-applied after
every resume, because firmware tends to forget it. On hardware that does not
expose the setting the control does nothing, and there is no way around that
from software.

The bar shows the battery block only where there is a battery.

## Shutting down

<kbd>Super+Backspace</kbd> opens the power menu: **Lock**, **Logout**,
**Suspend**, **Reboot**, **Shutdown**.

Logout, reboot and shutdown go the polite way: W asks each window to close, so
an editor gets to show its save dialog, and if you cancel that dialog the whole
shutdown is called off rather than pushed through. That is why the power menu is
the better route than a raw `systemctl poweroff` — unsaved work cannot be lost
by accident.

From a terminal the settings on this page are `w-power`, and the keyboard
backlight itself is `w-kbdlight`.
