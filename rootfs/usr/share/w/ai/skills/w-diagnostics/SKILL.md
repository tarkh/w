---
name: w-diagnostics
description: >-
  How to diagnose a W Linux machine: find failed services, read session and boot
  logs from the persistent journal, and collect a full diagnostic bundle. Load
  this when troubleshooting, reading logs, investigating a crash or a service that
  won't start, or when a theme applied only partially.
sources:
  - path: .claude/library/dev-workflow.md
    sha256: c7b25636e6e15bf0cf81153f0d6594d77b291214602faf5e9215267df4390ee3
  - path: .claude/library/w-logs.md
    sha256: f1898e041ab918820d3cfe1faa6e40b079f4c7834b52ba791f0251219e214e60
  - path: .claude/library/package-sensors.md
    sha256: 014f39f988b63216e2d60e89d7ce317a5c849dadc1eaaa4e3f531386ca6d8ccf
tools:
  - w_system_status
  - w_machine_profile
  - w_service_status
  - w_logs
  - w_service_restart
  - w_service_enable
  - w_logs_status
  - w_logs_retention
  - w_logs_vacuum
---

# W Diagnostics

W enables **persistent journald** (`Storage=persistent`, journal under
`/var/log/journal`), so logs survive reboots — including the very first boot. Most
troubleshooting starts with `systemctl` and `journalctl`.

## First checks

- **Failed services:** `systemctl --failed` (system scope) and
  `systemctl --user --failed` (the user session). W runs the desktop as a systemd user
  session, so user-scope failures matter as much as system ones.
- **The session:** the Hyprland session is `wayland-wm@hyprland.service` under uwsm.
  Inspect it with `systemctl --user status wayland-wm@hyprland.service` and read its logs
  with `journalctl --user -b`.
- **This boot vs last boot:** `journalctl -b` (current boot), `journalctl -b -1`
  (previous boot) — useful when a machine crashed or rebooted unexpectedly.
- **Kernel/hardware messages:** `dmesg` or `journalctl -k`.
- **Crashes / core dumps:** `coredumpctl list` and `coredumpctl info`.
- **Boot performance:** `systemd-analyze blame` and `systemd-analyze critical-chain`.

## Targeted search vs general health check

Two different jobs need two different moves:

- **"Is everything OK?"** → the general health check (`diagnose_system` prompt):
  `w_system_status` → `w_service_status` (failed units) → `w_logs(priority='err')` for
  each.
- **"X isn't working" / a specific complaint** → point search, not a bigger tail. Use
  `investigate_symptom` (prompt), or by hand: pull the key noun out of the complaint and
  call `w_logs(grep=<pattern>, since='1 hour ago')` — a regex match over a narrow time
  window. Widen `since` (`'today'`, `'boot'`, `'-1 boot ago'`) only if that comes back
  empty; raising `lines` on an untargeted tail just adds noise. If a unit name is
  implied (NetworkManager, pipewire, ...), check its status too.

## Machine profile

`w_machine_profile` answers questions about the hardware and install-time setup —
GPU/CPU, disk encryption + bootloader, locale, keyboard layout, timezone, update
channel (edge/stable). It reads everything live on each call (nothing is cached or
remembered as a stored fact), so it stays correct across GPU swaps, keymap/locale/
timezone changes, or a channel switch — reach for it instead of guessing or
assuming last-known state.

## Fixing a failed service

Once you've found the broken unit, `w_service_restart` restarts it and
`w_service_enable` flips its enabled/disabled + running state — both privileged
(polkit prompt), curated to a full unit name only. They are on by default
(`W_AI_TOOL_MAINTAIN`); unlike `w_run` they take no free-form command.

## Log retention and disk-space housekeeping

W drives retention for **every** log node from one number — `w-logs`, source
W's layered config (vendor default in `/usr/share/w/defaults/logs.conf`, this
machine's deviation in `/etc/w/logs.conf`; a fleet may pin it in
`/etc/w/policy.d/logs.conf`, and then `w_logs_retention` explains the refusal rather
than prompting). Start with `w_logs_status`: it shows how many days are kept plus
current disk usage across the journal, `/var/log` flat files (logrotate), and
`/var/log/w/`.

- **Change the durable policy:** `w_logs_retention(days=…)` — sets the kept window
  everywhere at once (journal `MaxRetentionSec`, logrotate `maxage`/`rotate`,
  tmpfiles age). This is what you want when the machine "keeps too much / too little".
- **One-off cleanup now:** `w_logs_vacuum` trims the **journal only** to a kept span
  (e.g. '2w', '30d') or total size ('500M') immediately, without changing policy.
  Use it when disk space is tight right now; use `w_logs_retention` to prevent
  recurrence. Both are privileged (polkit) and gated by `W_AI_TOOL_MAINTAIN`.

`/var/log` flat files are rotated by `logrotate.timer` (systemd, not cron); a
failsafe catch-all bounds any daemon's orphan `*.log` to the same policy. See
w-logs.md.

## Where W writes its own logs

W keeps installation and configuration logs under `/var/log/w/` (age-cleaned to the
retention window by systemd-tmpfiles):

- `install.log` — the installer run.
- `apply.log` — each `apply.sh` configuration run (appended per session; on a mid-run
  abort it records the exact file, line, and command that failed).
- `firstboot.log` — the first-boot configuration pass.

## Theme applied only partially

If theming looks half-applied after login, the login-time render logs to
`~/.local/state/w-style-apply.log` (also journal-tagged `w-style-apply`). The **last
line** names the theming axis where the render stopped — that is the first place to look.

## Temperature reads wrong or frozen after sleep

If the bar's temp block (or `btop`) shows a value that doesn't move under load, first
check `sensors -j` directly — if it's returning a chip other than `coretemp`/`k10temp`
(e.g. `applesmc` on a MacBook), the CPU-temp hwmon driver has likely lost its binding
across a suspend/resume cycle: the module stays loaded (`lsmod`) but its
`/sys/class/hwmon/*/name` node disappears, so the reading falls back to whatever chip
is left. Confirm the CPU itself isn't actually the problem via
`/sys/class/thermal/thermal_zone*` (`type` `x86_pkg_temp` — a separate MSR-based path,
unaffected). A dedicated sleep hook (`w-sensors`) detects and reloads the affected
module automatically after resume; if it's still stuck, `sudo modprobe -r <mod> &&
sudo modprobe <mod>` (module name from `HWMON_MODULES` in `/etc/conf.d/lm_sensors`)
re-probes it by hand. See package-sensors.md.

## Full diagnostic bundle

W ships `collect-logs.sh` in its source tree. Run as root, it gathers a timestamped
bundle under `/var/log/w/diag/` (plus a `tar.gz`): the W logs above, journal
error/warn/full for the current and previous boot, `systemctl --failed` (system and
per-user), `dmesg`, core dumps, boot timing, and the pacman package/manual/foreign lists.
Use this to capture everything at once when reporting a hard-to-reproduce problem.
