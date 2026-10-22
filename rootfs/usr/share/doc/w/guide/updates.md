---
title: Keeping W up to date
section: guide
category: system
order: 1
summary: The single update path, the badge in the bar, Arch news, and what to do when an upgrade goes wrong.
sources:
  - path: .claude/library/w-update.md
    sha256: 1e3f24eee99045a99f89424410154d7fa70594ff133172334fa4a4d6ba8e7521
  - path: .claude/library/w-mirrors.md
    sha256: 713856f43f54c44fc52642f8968824cdca2f0c967b7bcca2c6943e9a0f6f147c
  - path: .claude/library/snapshots.md
    sha256: 0df039c2078953d0797a6911bde6f1e346d719cabab0d116bb2c8ce5d47852c1
---

W has one native update path built on `pacman` and `yay`. There are no
third-party update managers. Every upgrade transaction is snapshotted
automatically (snap-pac), so an update is always reversible — see
[the FAQ](../faq.md) and
[RECOVERY.md](../RECOVERY.md).

## The `w-update` command

- `w-update` (or `w-update upgrade`) — interactive full upgrade: repository and
  AUR packages in one pass. It runs without `--noconfirm` on purpose — you
  review the package list and AUR build diffs before anything is applied. When
  the kernel changed it offers a reboot at the end, and that reboot closes your
  windows gracefully first, so unsaved work still asks for confirmation.
- `w-update check` — checks for repository and AUR updates **without root** and
  remembers the result. Never run a bare `pacman -Sy`; W's checker uses a
  private temporary database instead.
- `w-update status` — the last recorded status.
- `w-update news` — the latest [Arch Linux news](https://archlinux.org/news/)
  items. Read this **before a large upgrade**; it surfaces the rare
  manual-intervention announcements.
- `w-update enable` / `disable` / `interval [minutes]` — per-user control of
  the background checker that keeps the badge in the bar current.
- `w-update plan` — a read-only preflight: what a repo upgrade would touch,
  pending AUR builds, whether a kernel change means a reboot, free disk space.

## Where you see updates

- **The bar** shows an updates block with a count once updates are available.
- **The Hub → System** shows the same counter and, after an upgrade that
  requires it, a "reboot pending" hint.
- Clicking the bar block (or the Updates tile in the Hub) opens `w-update` in
  a terminal.
- New releases of pack engines (comfyui, invokeai) are **not** in that count and
  are never installed by `w-update` — they show in **Hub → Packs**, in
  `w-update status`, and as a note at the end of `w-update`. See
  [the packs guide](packs.md).

W-specific `/etc` files get their `.pacnew` reconciled automatically by a
pacman hook; third-party `.pacnew` files stay manual, and `w-update` points
them out.

## If an update goes wrong

- A failed download is most often mirror trouble: `w-mirrors status` and
  `w-mirrors sync` re-rank and refresh the mirrorlist; then retry.
- If the system misbehaves after an upgrade, reboot into the pre-upgrade
  snapshot: the boot menu (GRUB or Limine, depending on the install) lists
  snapshots, and [RECOVERY.md](../RECOVERY.md) walks the restore step by step. W
  also ships a copy of that page on disk, so it is readable even when the
  system does not boot.

## Snapshots and disk space

Snapshots cost almost nothing while data stays put: a snapshot only holds on to
what was deleted or overwritten after it was taken. W bounds them so they never
grow on their own.

- **System (root)** — snap-pac snapshots every package transaction; the last 20
  (about 10 upgrades) are kept, plus the permanent `W initial state`.
- **Your home** — two streams. An hourly snapshot, of which the last 6 hours, 7
  days and 2 weeks are kept. And one snapshot before every W update that
  changes something (an update that only brings documentation takes none): the
  last 10 are kept. When the disk has less than 20% free space, W keeps only
  the last 2 of those, so infrequent updates on a full disk cannot hold on to
  months of deleted files.
- **Package cache** — `paccache` runs weekly and keeps the installed version of
  each package plus one previous version; packages that are no longer installed
  are removed from the cache.

`snapper -c home list` shows your home snapshots; `snapper -c home undochange`
restores files from one. The system journal of `snapper-cleanup` reports
"quota not working (qgroup not set)" on every run — that is expected, W does
not use btrfs quotas.

## The update channel of W itself

`w-update` upgrades *packages*; the distribution's own configuration travels
the `w-sync` channel (edge) — see `w-sync check` and the update chapter of the
FAQ.
