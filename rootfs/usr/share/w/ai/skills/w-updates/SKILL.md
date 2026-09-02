---
name: w-updates
description: >-
  How to keep a W Linux machine up to date. Covers the w-update tool (interactive
  full upgrade, check, status, news, interval, enable/disable), how the reboot-
  pending indicator works, the updates block in the Quickshell bar, and package
  mirror upkeep (w-mirrors) for when an update fails to download. Load this for
  anything about upgrading, checking for updates, Arch news, the updater, or
  pacman mirrors.
sources:
  - path: .claude/library/w-update.md
    sha256: 003ff0b751fb62384aed2c71ff5430a9988c61493e480aa868f88550c0c1bd0a
  - path: .claude/library/w-mirrors.md
    sha256: 14ad9894e2c6f65dfa71e6e77d8113285c226ea9955bee465e804e938517f115
tools:
  - w_updates_check
  - w_system_update
---

# W Updates

W has one native update path built on `pacman` + `yay`. There are **no** third-party
update managers (no pamac, topgrade, informant, needrestart). Rollback is handled by
the already-present snap-pac + grub-btrfs (every upgrade transaction is snapshotted
automatically). The single entry point is the `w-update` command.

## `w-update` commands

- `w-update` (or `w-update upgrade`) — interactive full upgrade: `yay -Syu --sudoloop`,
  **repo + AUR in one pass**. Never split repo/AUR (partial upgrades break Arch). Runs
  **without** `--noconfirm` on purpose — the user should review the package list,
  `.pacnew` files, and AUR PKGBUILD diffs. When the kernel changed it offers a reboot at
  the end — and that reboot is the graceful one: every window is asked to close first, so
  unsaved work still prompts and cancelling a save dialog calls the reboot off. This is a
  privileged operation (it goes through the normal sudo/polkit prompt).
- `w-update check` — **no root needed.** Counts repo updates via `checkupdates` and AUR
  updates via `yay -Qua`, detects reboot-pending, and atomically writes
  `~/.local/state/w/updates.json`. **Never run bare `pacman -Sy`** to check — it causes
  partial-upgrade breakage; `checkupdates` uses a private temporary database.
- `w-update status` — print the last recorded status plus the checker's state.
- `w-update news` — the latest Arch Linux news items (from the official RSS feed). Read
  this **before a large upgrade** — it surfaces manual-intervention announcements.
- `w-update enable` / `w-update disable` — per-user toggle of the background checker
  (`disable` masks the user timer; `enable` unmasks and starts it).
- `w-update interval [minutes]` — show or set the checker's period (per-user, no root).
- `w-update plan [--porcelain]` — read-only preflight (no root): what a repo upgrade
  would touch, pending AUR, kernel change → reboot, free disk. Backs the AI-driven
  update below; humans can run it too to preview an upgrade.

## AI-driven update (`w_system_update`) — you can update the system on request

When the user asks you to update the system, you **can** do it — the repo upgrade is a
default-on Tier-2 action. Do it as **plan → apply**, never a blind auto-apply:

1. **`w_system_update` with `action="plan"`** (read-only, no prompt). Read the result:
   repo/AUR counts, package list, `kernelChange`, free disk. If it looks big or risky,
   also check `w-update news` for manual-intervention announcements.
2. **Triage.** If it's clean, proceed. If something needs a decision — a kernel change
   (means a reboot after), low disk, an unusual set, or news requiring intervention —
   **tell the user, recommend how to proceed, and wait** for their go-ahead.
3. **`w_system_update` with `action="apply"`** — runs `pacman -Syu` non-interactively
   behind the polkit prompt (fingerprint/password). snap-pac snapshots it, so it is
   rollback-protected. Relay the result. **Never reboot for the user** — if a reboot is
   needed, say so and let them do it.
4. **If the upgrade left a reboot owed, also send a desktop notification** —
   `w_notify(summary=…, body=…, urgency="critical")`. This is the textbook critical
   alert: the user must act, and until they do, the running kernel and the installed
   one disagree. `critical` is what makes it red, keeps it on screen instead of
   auto-dismissing, and lets it through Do Not Disturb. An update that finished with
   nothing owed is `normal` at most — usually just say so in chat and send nothing.
   Reboot detection is described under "Reboot-pending detection" below.

- **If apply fails** on a package conflict, it returns the error — relay it and advise
  resolving it in a terminal (`w-update`), don't try to force it.
- **`.pacnew` files:** W owns many `/etc` files, so an upgrade writes a `.pacnew` for
  them — but these are handled automatically. An alpm hook (`96-w-pacnew-reconcile`)
  drops the `.pacnew` for W-managed files (W's version is authoritative) and logs it,
  leaving only genuinely foreign `.pacnew`. So if the report still lists `.pacnew`,
  those are non-W files worth a `pacdiff` — never hand-merge a W-owned config
  (e.g. `/etc/pam.d/greetd`, `/etc/greetd/config.toml`); use `w-reset` to restore it.
- **AUR is not applied this way** — `yay` must build as the user and PKGBUILD diffs want
  review. If the plan lists AUR updates, tell the user to run `w-update` in a terminal
  for those.
- Gated by `W_AI_TOOL_UPDATE` in `ai.conf` (on by default). If disabled, tell the user
  which switch to flip — do not seek a workaround.

## Reboot-pending detection

W decides a reboot is needed by testing whether the running kernel's module directory
still exists: `[[ ! -d /usr/lib/modules/$(uname -r) ]]`. An in-place kernel upgrade
removes the running kernel's modules, so their absence means you are on a stale kernel
and should reboot. This needs no root and has zero false positives.

## A kernel upgrade can break an out-of-tree driver — and take the network with it

Upgrading the kernel rebuilds every DKMS module against it. If a module has no patch for
that kernel series yet, the rebuild fails, no module is produced for the new kernel, and
whatever it drove stops working **after the reboot**. That is merely annoying for a
filesystem module and serious for a wireless one: the connection you would use to fix it
is the thing that broke.

The live case is `broadcom-wl-dkms`, the driver for the old Broadcom Wi-Fi chips that no
in-kernel driver binds (BCM43142, BCM4360 — machines like the 2013–2015 MacBook Pro). Its
source needs a fresh patch for each kernel series, and Arch publishes the kernel before
the rebuilt driver leaves the testing repository. Inside that window, upgrading the kernel
costs you Wi-Fi.

If you are on such a machine and an upgrade is waiting, install the patched driver
**first**, then upgrade:

```sh
# fetch the newest broadcom-wl-dkms from the testing repository by hand, then:
sudo pacman -U ./broadcom-wl-dkms-*.pkg.tar.zst    # BEFORE upgrading
w-update                                            # then the full upgrade
# reboot
```

The order is the whole point. Installing the patched driver first gives DKMS a version
that will build when the upgrade brings the new kernel. The other way round, DKMS rebuilds
the *old* version against the *new* kernel, fails, and the machine comes back without
Wi-Fi. There is no need to enable the testing repository for this — it is one file.

If Wi-Fi is already gone after a reboot for this reason, the machine needs a wired
connection (or a phone tethered over USB) to fetch the driver at all; `dkms status` will
show the module missing for the running kernel.

## The `updates` bar block

The Quickshell bar has an `updates` block. It is **read-only** — it does not poll pacman
itself; it watches the `updates.json` status file that `w-update check` writes.

- Shows the update count (repo, plus AUR if configured).
- Auto-hides when there are zero updates, **but stays visible if a reboot is pending**
  (so the reboot indicator is never silently hidden), using an alternate color.
- Left-click opens `w-update` in the terminal (start an upgrade); right-click shows news.

## Background checker

A per-user systemd timer runs `w-update check` periodically and is enabled by default for
all users. The check is cheap and needs no root, and the bar block auto-hides at zero, so
there is no noise. A user can opt out with `w-update disable`.

Refresh is also **event-driven**, not just polled: a pacman `PostTransaction` alpm hook
re-runs `w-update check` after *any* pacman/yay transaction, so the indicator stays
accurate even when packages change outside the bar (e.g. a manual `pacman`/`yay`). So the
count can update immediately after an upgrade rather than waiting for the next timer tick.

## Package mirrors — when an update fails to download

An upgrade that dies with "failed retrieving file", "failed to commit transaction
(failed to retrieve some files)" or "failed to synchronize all databases" is almost never
a broken package — it is a mirror that stopped serving data. W has a tool for exactly
this, and you should use it before advising the user to "try again later".

- **`w-mirrors check`** — read-only, no root, a few seconds. It probes the head of
  `/etc/pacman.d/mirrorlist` and reports whether anything is actually serving data.
  Non-zero exit means the top mirrors are dead. Run this first when the user reports a
  failed install or upgrade.
- **`sudo w-mirrors rank`** — rebuilds the mirrorlist (reflector). This is the fix, but it
  is **not free**: it takes minutes and downloads a database from every candidate mirror
  (up to ~260 MB). Recommend it, explain the cost, and let the user run it — do not
  present it as a routine action.
- **`w-mirrors status [--porcelain]`** — the policy, the list depth, how long ago it was
  ranked, and whether a re-rank is due. Useful when diagnosing "downloads are slow".

The interactive `w-update` already does this check for you: when the upgrade fails, it
probes the mirrors itself and either says the failure is not a delivery problem or offers
the re-rank. So if the user ran `w-update` and it told them the mirrors look healthy,
believe it and read the actual error instead of blaming the network.

A machine also re-ranks on its own: `w-mirrors.timer` ticks daily and re-ranks when the
list is older than `INTERVAL_DAYS` (30 by default), skipping metered connections. Policy
lives in `/etc/w/mirrors.conf` over `/usr/share/w/defaults/mirrors.conf` — read the merged
result with `w-conf cat mirrors`, change one key with `sudo w-mirrors set <KEY> <value>`.

Two things not to do: never suggest editing `/etc/pacman.d/mirrorlist` by hand (the next
ranking overwrites it, and hand-trimming it to one "good" mirror removes the fallback
depth pacman relies on), and never suggest `pacman -Sy` on its own to "refresh" — that
causes partial upgrades.

## Related

- **Rollback:** handled automatically by snap-pac (snapshots each `yay -Syu`) + grub-btrfs
  (boot into a snapshot). No separate action is needed.
- **Firmware and Flatpak** update through their own channels (`fwupdmgr`, the Bazaar
  store), deliberately outside `w-update`.
- **Package delivery** (mirror selection, retries, the `w-mirrors` upkeep tool) is its own
  layer under all of this — see the section above.
