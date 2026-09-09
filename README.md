# W Linux

![W Linux — the default wallpaper of theme `w`](banner.webp)

**English** · [Русский](docs/ru/README.md)

**W** is a personal Arch Linux distribution: a reproducible install of Arch with a
fixed configuration and a curated set of software, driven by a TUI installer.
Every install pulls fresh packages, but the configuration it lands on is always
the same one.

It is a Wayland desktop built on Hyprland and Quickshell, themed end to end from a
single palette, with its own set of `w-*` command-line tools for the things a
desktop actually needs — updates, themes, power, monitors, keyboard, network,
screenshots, backups of your own config.

> **Status: beta.** W is usable day to day and is what its author runs, but it is
> young. Expect rough edges, expect to read a log occasionally, and do not put it
> on a machine whose data you have not backed up elsewhere.

---

## What you get

**Desktop** — Hyprland (Lua configuration) under a uwsm-managed session, with a
Quickshell UI written for W: bar, launcher, notification centre and OSDs, calendar,
clipboard manager, volume and brightness control, power menu, network and Bluetooth
tray, a unified authentication dialog for polkit and gcr, and a lock screen with
fingerprint support. The graphical session remembers what you had open, including
named layouts.

**Theming that actually reaches everything.** One palette renders GTK, Qt/Kvantum,
icons, the terminal, the shell prompt, Firefox chrome, the bootloader theme and the
boot splash. `w-theme new <image>` builds a complete theme from any wallpaper —
colours extracted from the image, light and dark variants, live re-skin without a
restart.

**A real installer.** A dialog-based wizard (English and Russian) covering disk,
encryption, locale, keyboard, timezone, users, update channel and optional software
bundles — plus an unattended `--preset` mode used by the project's own end-to-end
test harness.

**Disk layout** — GPT/UEFI, btrfs with subvolumes for `/`, `/home`, `/var/log`,
`/var/cache` and snapshots, zram instead of a swap partition, snapper timelines for
both root and home, and optional full-disk LUKS encryption with Secure Boot support.

**Updates that respect your edits.** W separates what it owns from what you own.
Managed files (shell code, QML, themes, units) are overwritten on every update so
improvements reach you; your configuration is seeded once and never touched again.
`w-reset` puts any module back to the W default when you want a clean slate.

**Optional software bundles** (`w-pack`) — containers, development tooling, extra
AI components — installed at setup time or later, never forced.

**An on-box AI layer**, opt-in and off by default, with a privilege model that
distinguishes reading system state from changing it, and polkit gating everything
that changes.

---

## Requirements

- x86_64 machine with **UEFI** firmware
- A disk you are willing to erase
- A working internet connection during installation

---

## Installing

1. **Get an ISO** — [**download the install image**](https://github.com/tarkh/w/releases/tag/edge).

   There is one image, and it is rebuilt every night from this repository. W is a
   rolling distribution, so freezing a download per version would only hand you
   older packages to update on first boot. The file names itself
   `w-<release>-<build date>-x86_64.iso`, and the installed system records the
   same two facts in `/etc/os-release` as `IMAGE_VERSION` and `W_BUILD_DATE`:
   which version of W's own configuration it is, and which day its packages came
   from Arch.

   The release page carries the image's SHA-256; the file is replaced by every
   nightly build, so check it against the download you actually have:

   ```sh
   sha256sum w-*-x86_64.iso
   ```

   Or [build your own](#building-your-own-iso) — the same build that produces
   the published image, and the way to get an image for hardware the default one
   does not cover.

2. **Boot it.** The installer starts by itself on the first console. If you leave
   it, bring it back with `bash /root/w/scripts/install.sh`.

3. **Answer the wizard.** It confirms once before touching the disk, and everything
   after that point is destructive — read that screen.

4. **Reboot.** The first boot finishes setup (packages, AUR builds, user
   environment) and logs the whole thing to `/var/log/w/`.

---

## Building your own ISO

The published image is not special — it is what this repository builds, and you
can build the same thing:

```sh
git clone https://github.com/tarkh/w
cd w
./scripts/build-iso.sh           # writes to archiso/out/
```

Run it as your normal user, **not** with `sudo`: it elevates only for `mkarchiso`
itself, and the AUR packages it bakes in must not be built as root. It needs
`archiso` and `base-devel` installed. On a machine that is not Arch — or if you
would rather not install those — `ci/iso-build-container.sh` runs the identical
build inside a container; that script is literally what produces the nightly
image, so its output is the published one.

The build takes roughly 10–20 minutes and writes `w-<release>-<date>-x86_64.iso`.

### Broadcom Wi-Fi: vintage MacBook Pro and friends

A handful of older Broadcom chips — BCM43142 `[14e4:4365]`, BCM4360 `[14e4:43a0]`,
the ones in machines like the 2013–2015 MacBook Pro — are in no in-kernel driver's
table. Linux shows them with no driver bound at all, and they need Broadcom's own
`wl` module.

The **installed** system handles this by itself: the installer detects such a chip
and installs the driver for it. What it cannot help with is the **live session**,
and that matters on a laptop with no Ethernet port: if the installer cannot bring
the network up, it cannot install anything. Until September 2026 the image covered
this because Arch shipped a prebuilt driver package; that package is gone from the
official repositories, and upstream archiso dropped it rather than replacing it.
Only a source (DKMS) package remains, so covering the live session again means
carrying a compiler and the kernel headers in the image — **about 570 MB before
compression, a measured 139 MB on the finished ISO** (1583 → 1722 MB), to build a
2 MB driver.

That is a bad trade for everyone who does not have such a chip, so it is off by
default. If you do have one, build yourself an image with it:

```sh
./scripts/build-iso.sh --broadcom-wl
```

Or, equivalently, set `BROADCOM_WL=on` near the top of `scripts/build-iso.sh` —
the option is a single line there, with the reasoning next to it.

You do not have to pick a driver version. The Broadcom source needs a fresh patch
for each new kernel series, and Arch lands the kernel before the rebuilt driver
leaves the testing repository — so during that window the ordinary package does
not compile against the kernel the ISO ships. The build resolves the newest
driver across all repositories and, if that one is still in testing, pulls in that
**single** package while everything else in the image continues to come from the
normal repositories.

The honest limit: if Arch ships a kernel series before the driver has a patch for
it at all, no version compiles and the build stops with a compiler error. There is
nothing to do about that but wait for the patch — or build with the option off.

---

## Updating

W tracks this repository directly. Updates are pulled with `w-sync`:

```sh
w-sync check     # is anything waiting?
w-sync log       # what exactly would arrive
w-sync update    # snapshot, pull, apply only the modules that changed
w-sync status    # channel, ref, last known state
```

A snapshot of `/home` is taken before every update, so a bad one is recoverable.
Package updates from Arch itself are a separate concern, handled by `w-update`.
Either way, `sudo w-rollback run` puts an older system back — see
[RECOVERY.md](RECOVERY.md).

The channel is configured in `/etc/w/update.conf`. `REF=main` follows every
release; pinning `REF=v0.1.0` holds a machine on one version.

> During the beta, `edge` — this git repository — is the only channel. A `stable`
> channel delivering W as a signed pacman package is designed and partly built, but
> its server side does not exist yet, so the installer does not offer it.

---

## Finding your way around

`w-info` lists every user-facing tool with a one-line description — start there.
Every `w-*` tool answers `--help`, and most have a `--porcelain` output for
scripting.

The full documentation ships with the system and is published here in the same
tree — [`rootfs/usr/share/doc/w/`](rootfs/usr/share/doc/w/index.md):

- [Guides](rootfs/usr/share/doc/w/index.md#guides) — updates, theming, security,
  the desktop itself, displays, input, network, power, the AI assistant and packs.
- [FAQ](rootfs/usr/share/doc/w/faq.md) — short answers to the common questions.
- [Command reference](rootfs/usr/share/doc/w/index.md#command-reference) — a page
  per `w-*` command, generated from the command's own help text.

On a W machine the same pages open in the desktop: <kbd>Super+F1</kbd>, or the
**?** button in the corner of a Hub panel.

If something goes wrong on first boot, `/var/log/w/` already has the whole story:
`w-install-*.log` for the installer, `w-apply-*.log` for the setup that follows.

If the machine will not boot at all, or an update left it worse than it was,
[RECOVERY.md](RECOVERY.md) is the page you want: every snapshot W takes is bootable
from the boot menu, and `w-rollback` is the single command that makes an older one
the system again. It ships on the machine too, at `/usr/share/doc/w/RECOVERY.md` —
which is where you will need it, since a machine that will not boot has no browser.

Configuration lives in `/etc/w/` (system, admin-owned) and `~/.config/w/` (yours).
Logs are under `/var/log/w/`.

---

## Contributing

Bug reports and patches are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for
how this repository works, which is slightly unusual: it is published as a series
of release snapshots, so pull requests are landed by hand rather than merged with
the button. Security issues: [SECURITY.md](SECURITY.md).

## License

GPL-3.0-or-later — see [LICENSE](LICENSE). Third-party code and artwork, with
their own terms and provenance, are recorded in
[COPYING.assets](COPYING.assets).
