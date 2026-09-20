---
name: w-power
description: >-
  Power management on W Linux: power profiles (performance/balanced/power-saver),
  the AC↔battery auto-switch, idle timers (screen-off / auto-lock / auto-suspend),
  lid-close and power-button actions, the battery charge threshold, laptop/desktop
  mode, the battery indicator, suspend/reboot/shutdown, and the keyboard backlight
  (level, the media keys, light at the disk-password prompt, going dark on idle).
  Load this for anything about battery, charging, power profiles, idle timeouts,
  screen blanking, the lid, suspend/sleep, logout/reboot/shutdown, or a keyboard
  that is not lit.
sources:
  - path: .claude/library/w-power.md
    sha256: 6ebee081798bf911e01e3677de0d6eba65052d329682ae63eb095bd0fdc6b59b
  - path: .claude/library/w-kbdlight.md
    sha256: d17c2a2a0ecf20c3a464a254d778e0873def9ebb8833b4362e08eb9869dec506
  - path: .claude/library/quickshell-powermenu.md
    sha256: 8d9f9fb42f9cc89eac3b17ba1c5d379da87d8071eabcfe8aa976d9599ef3b518
  - path: .claude/library/quickshell-bar.md
    sha256: 76dc9b56a2cdf3a879e737a653ea5bc330722c1eb346e64f917765823a1abf5c
  - path: .claude/library/package-hyprlock.md
    sha256: b22971fe5d7f69876a20eb7082c4e3f0895c47c23caf1024b44a856da7893755
tools:
  - w_power_status
  - w_power_profile
  - w_power_charge_limit
  - w_power_lid
  - w_power_mode
---

# W Power

W has one power subsystem, driven by the **`w-power`** CLI. It is a thin front over
four standard backends, each owning one concern:

- **power-profiles-daemon (PPD)** — the power profile (performance / balanced /
  power-saver). This is the standard freedesktop daemon; W does **not** use TLP (only
  one power tool may run).
- **hypridle** — idle timers: screen-off (DPMS), auto-lock, and auto-suspend. Its
  config is *generated* by `w-power`, so edit timers through `w-power`, not by hand.
- **systemd-logind** — hardware events: the lid-close action and the power button.
- **sysfs** — the battery charge threshold.

Start every power question with **`w_power_status`** — it prints the whole live state
(mode, profile, idle timers, lid/power-key, charge limit, and the battery summary).

## Laptop vs desktop mode

`w-power` has a global **mode** that reseeds sensible presets across every knob:

- **laptop** — aggressive, AC≠battery idle timers; AC/battery profile auto-switch on;
  lid-close suspends on battery / locks on AC; battery + charge controls shown.
- **desktop** — one gentle idle set; no auto-switch; lid ignored; battery controls
  auto-hidden (no `BAT*` present).

Set it with `w_power_mode` ('laptop' | 'desktop' | 'auto' — auto detects from the
chassis type and battery presence). It switches the whole preset table at once, so
use it deliberately.

**What a mode switch does and does not touch.** W's power config is layered: W's own
defaults live in a generated vendor layer, `/etc/w/power.conf` holds only the machine's
**deviations** from them, and `~/.config/w/power.conf` holds the user's idle overrides.
A mode switch rewrites the vendor layer only — so every knob that was left at its
default follows the new mode, while a value someone deliberately set (say a 80% charge
limit) is a deviation and **survives** the switch. If a setting looks "stuck" after
switching modes, that is why: it is an explicit deviation, not a preset. Run
`w-conf cat power` — it prints every effective value with the layer it came from — and
clear a deviation with the matching `w-power` command (or `w-reset power` for all of
them at once).

**Who may set what is declared, not guessed.** The idle timers are user-scope (a user
may override them without root); the profile, lid, power-key, charge-limit and mode
knobs are system-scope, and a value for one of those in a *user* file is ignored on
purpose — `w-conf cat power` names the ignored line, and `w-conf scope power [KEY]`
prints the declaration. Do not advise a user to put `CHARGE_LIMIT` or `LID_ON_AC` in
`~/.config/w/power.conf`; the setter refuses to write it there and the reader would
ignore it anyway.

**A fleet may pin a power knob.** If `/etc/w/policy.d/power.conf` sets a key, that is
site policy: `w-power` refuses to change it (naming the file), the Hub shows a padlock,
and the `w_power_*` tools say so instead of raising a pointless auth prompt. Report it
as a deliberate fleet decision — there is no local workaround, and inventing one would
be wrong.

## Power profiles

Up to three profiles via PPD: **performance**, **balanced**, **power-saver**. Switching
is a plain user action (no privilege) — `w_power_profile`. **`performance` is not always
there:** it needs a platform driver (intel_pstate / amd-pstate / ACPI platform_profile),
so a VM and many desktops offer only balanced + power-saver. `w_power_status` lists what
this machine actually has — read it before promising a profile, and if the user asks for
a missing one, say it is unavailable on this hardware rather than reporting a failure. In laptop mode an **auto-switch**
can drive the profile from the power source (e.g. balanced on AC, power-saver on
battery); toggling that auto-switch is a system setting left to the Hub Power panel /
`w-power profile auto`.

## Idle timers, DPMS and lock-before-sleep — hypridle

`hypridle` is the idle daemon, run as its packaged **systemd user unit**
(`hypridle.service`, global-enabled by `mod_power`) — not an autostart exec. `w-power`
renders its config from the active preset, with **separate AC and battery timers**:

- **Auto-lock**, **screen-off (DPMS)**, and **auto-suspend** form a *cascade*, not
  three independent absolute timeouts: auto-lock counts from the last activity;
  screen-off counts from the lock firing (or from last activity if lock=0); auto-suspend
  counts from screen-off firing (or from whichever earlier link is on). Each configured
  value is relative to the previous link (0 = that link is off). `w_power_status` prints
  both the configured relative values and the computed absolute firing points. On
  battery the whole cascade is more aggressive than on AC. The Hub Power panel lists the
  three timers in this same lock → display → suspend order, each with a secondary label
  showing the effective absolute firing time (or "off").
- **Re-blank on an already-locked screen** — while hyprlock is up, *any* activity
  (a nudged mouse, a glance) blanks the display again after the plain screen-off value
  (not the cascaded point) — a separate gated listener, active only when both auto-lock
  and screen-off are on. This is intentional, not a bug report: it replaces an older
  hardcoded 30 s rule.
- **Lock-before-sleep** — `before_sleep_cmd = loginctl lock-session` runs *before*
  suspend, so the machine always resumes to the lock screen; `after_sleep_cmd` turns
  DPMS back on and re-asserts the night light (see the `w-desktop` skill).
- The lock screen is **hyprlock** (a GPU locker: blurred background, PAM password +
  optional fingerprint). Manual lock is `Super+L` (a w-hotkeys default bind).
- **"The fingerprint stops working after a few minutes on the lock screen"** — not a
  broken enrolment: in the default mode hyprlock keeps the reader scanning for the whole
  lock, and libfprint's overheat guard (any reader without hardware finger detection,
  e.g. DigitalPersona U.are.U) disables it after ~4 minutes with `Device disabled to
  prevent overheating` in `journalctl -u fprintd`. The fix is the lock-sensor mode
  `w-fingerprint lock-sensor mode wake` (Hub → Input → Fingerprint → Lock screen →
  Sensor → On activity): the reader then lights up only for a window after the lock, a
  wake-up or any activity while locked — see the `w-security` skill. Do not restart
  fprintd or re-enrol as a "fix".

Diagnose with `pgrep -a hypridle` (if it is not running, idle-lock and lock-before-
sleep will not fire) — `w_power_status` reports this. Idle timeouts are a user setting
(rendered into the user's hypridle config), adjusted through the Hub Power panel or
`w-power idle`.

**Idle policy is per-account.** Every human account has its own overrides and its own
rendered hypridle config; `apply.sh --power` renders for all of them. Two accounts on
one machine legitimately have different timers — that is not drift to be "fixed", and
never edit another user's file to align them.

**"The lock screen died" / "I locked the screen and now there is only a message about
another TTY".** The lock screen runs in its own systemd scope, so restarting hypridle
cannot kill it, and W refuses to restart hypridle at all while a lock is up. If a user
hits the message anyway (a session that has not been through an update since 2026-08-07
still has its old lock screen inside hypridle's cgroup), the recovery is the command
Hyprland prints: `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` from
another TTY. Say plainly that a *new* lock will not have the problem.

## Keyboard backlight — `w-kbdlight`

A separate subsystem with a clean split of duties, and knowing the split is how you
answer these questions correctly:

- **`w-kbdlight` owns the device** — which LED is the backlight, its level, the media
  keys, and the light at the disk-password prompt.
- **`w-power` owns when it goes dark on idle** — because the idle config file has
  exactly one writer, and it is `w-power`.

Check it with **`w-kbdlight status`**: device, level, key step, boot level and the
idle-off timers, all in one place. `w-kbdlight status` is honest on machines with no
backlight ("not present on this machine", exit 0) — most laptops have none, so rule
that out before debugging anything else.

Everyday commands (no root, no special group — an ordinary user in an *active*
graphical session is enough): `w-kbdlight up`, `down`, `set 40%`, `toggle`, `get`.
The media keys `XF86KbdBrightnessUp` / `Down` / `XF86KbdLightOnOff` are already bound
to exactly these.

**Never reach for `brightnessctl -c leds`** to control the keyboard light. It picks
the *first* led-class device, which is normally an indicator (numlock), not the
backlight — the real one matches `*kbd_backlight*` and is vendor-named (`smc::` on
Apple, `tpacpi::` on ThinkPads, `dell::`, `asus::`). `w-kbdlight` is the one place
that resolves this; use it and everything stays consistent.

**Light at the LUKS/boot prompt.** The level lives *inside the initramfs* (that prompt
has no other filesystem), so it is not a plain config edit: run
`sudo w-kbdlight boot <N|off>`, which writes the config **and** rebuilds the image.
Editing `/etc/w/kbdlight.conf` by hand changes nothing until a rebuild.

If someone reports "the keyboard lights up during the password prompt and goes dark
right after unlocking", that is not a bug: `systemd-backlight` restores the level the
machine was shut down with. The boot level covers the boot window only.

**Going dark on idle** is set through `w-power`: `w-power idle ac kbdlight <seconds>`
(and `bat`, 0 = never; defaults 120 s on AC, 60 s on battery). It is *not* a link of
the lock → screen-off → suspend cascade — it is an independent timer counting from
last activity, so it does not shift any of the cascade points. The listener calls
`w-kbdlight off` (which remembers the current level) and `restore` on activity.

## Lid and power button — systemd-logind

The **lid-close** action is set per power source, handled by logind independently:
'battery', 'ac' (wall power), and 'docked' (external display attached). Actions are
suspend / lock / ignore / poweroff / hibernate. Set it with `w_power_lid`.

The **power button** action (menu / poweroff / suspend / ignore) and the **critical
battery** action are rarer settings left to the Hub Power panel / `w-power power-key`.

### "It suspends, then wakes up again after a few seconds"

Diagnose this before blaming suspend itself. The lid is a separate thing from the
lid-close *action*: it is also an ACPI **wake source** (`/proc/acpi/wakeup`), and on
some firmware that wake source is asserted by the lid merely *being open* — so the
machine wakes seconds after reaching S3, every time, when the user suspended from the
menu with the lid up. Closing the lid instead makes the same machine sleep fine; that
asymmetry is the fingerprint.

W handles it: `LID_WAKE=auto` (the default) drops the lid from the wake sources for the
duration of a suspend that starts with the lid **open**, and restores it on resume — so
close-the-lid-then-open-it still wakes the machine. `w-power status` reports the mode as
`lid-wake`; `sudo w-power lid-wake keep` opts out. There is no Hub control and no tool
for this — it is correctness, not a preference.

If a machine still wakes on its own, the lid is not the culprit. Check what else is
wake-enabled (`/proc/acpi/wakeup`, `/sys/bus/{pci,usb}/devices/*/power/wakeup`), read
`/sys/power/pm_wakeup_irq` (`ENODATA` means no device IRQ caused it — look at ACPI GPEs
in `/sys/firmware/acpi/interrupts/` instead), and compare suspend/resume pairs with
`journalctl -k -g 'PM: suspend (entry|exit)'` to see how long it actually slept.

## Battery and charge threshold

The bar shows a **battery** block reading **upower** natively (percentage, level glyph,
charging bolt). It **auto-hides** on a desktop with no battery — its absence there is
expected, not a bug. From a shell, `upower -i /org/freedesktop/UPower/devices/DisplayDevice`
gives the aggregate; `w_power_status` includes it.

On laptops whose firmware supports it, a **charge threshold** caps charging (typically
**80%** to reduce wear, or **100%** for full capacity) — set with `w_power_charge_limit`.
It is a no-op where the firmware exposes no `charge_control_end_threshold` sysfs, and it
is re-applied after resume (firmware resets it).

## Suspend / reboot / shutdown — the power menu

`Super+Backspace` opens the **power menu** (a Quickshell popup): **Lock**, **Logout**,
**Suspend**, **Reboot**, **Shutdown** (hotkeys `L`, `E`, `S`, `R`, `Ctrl+S`).

| Action | Command |
|---|---|
| Lock | `loginctl lock-session` |
| Suspend | `systemctl suspend` (hypridle locks first via `before_sleep_cmd`) |
| Logout / Reboot / Shutdown | `w-session-exit <logout\|reboot\|shutdown>` |

**`w-session-exit`** is a graceful exit: it closes each window (editors show their save
dialogs), waits for them to close, then does `uwsm stop` / `systemctl reboot|poweroff`.
If a window stays open (a cancelled save), it **aborts** rather than force-killing — so
logout/reboot/shutdown never lose unsaved work. For a shutdown or reboot, prefer telling
the user to use the power menu so this graceful path runs.

## Tools (via `w-mcp`)

- **`w_power_status`** *(read)* — the full live state: mode, profiles + active/auto,
  idle timers (AC vs battery), lid/power-key, charge limit, battery summary, and whether
  hypridle runs. Call it first to ground any answer.
- **`w_power_profile`** *(Tier 1, no privilege)* — switch the PPD profile
  (performance | balanced | power-saver). Immediate, reversible.
- **`w_power_charge_limit`** *(Tier 2, polkit)* — set the battery charge threshold
  (0–100; typically 80 or 100). Laptop firmware only. Gated by `W_AI_TOOL_POWER`.
- **`w_power_lid`** *(Tier 2, polkit)* — set the lid-close action (suspend | lock |
  ignore | poweroff | hibernate) for a source (battery | ac | docked). Gated by
  `W_AI_TOOL_POWER`.
- **`w_power_mode`** *(Tier 2, polkit)* — set laptop | desktop | auto (switches the
  whole preset table; explicit deviations survive — see above). Gated by `W_AI_TOOL_POWER`.

Suspend/reboot/shutdown stay user actions through the power menu (or `systemctl suspend`
/ `w-session-exit` in a shell) — there is no privileged suspend/shutdown tool.
