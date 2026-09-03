# Changelog

Every entry here is one published release — one commit on the public branch, one
tag. `scripts/publish.sh` reads the section matching the version being released and
uses it verbatim as the release commit message and the GitHub release notes, so a
missing or empty section fails the release.

Written for the people running W, not for the people writing it: say what changed
for them and what they have to do about it, not which files moved.

## v0.4.0

- **W now refuses an update it cannot verify.** Until this release, trusting an update
  meant trusting the transport: HTTPS, plus the assumption that the address in
  `/var/lib/w/src/.git/config` still pointed at the real W. Everything `w-sync` does
  after a pull runs as root, so that assumption was worth root on your machine. Every
  release is now published as an annotated tag signed with the W release key, and
  `w-sync update` verifies that signature against the key shipped on the machine
  (`/usr/share/w/update/w-release.allowed_signers`) **before** it takes a snapshot and
  before it pulls. A tip that carries no release tag, or one not signed by a trusted
  key, stops the update dead and leaves the machine bit-for-bit as it was. `w-sync
  status` gained a `Signed:` line saying which way this is set.

  Verification is on by default, including on machines installed before this release.
  If your checkout tracks something other than the official repository — a fork, or a
  branch of your own — there are no signed release tags to find, so this update
  records `VERIFY_SIGNATURE=no` in `/etc/w/update.conf` for you. A value already in
  that file is never overwritten.

- **If `w-sync update` has been dying on what looked like a credentials problem, this
  release is the fix — and the fix has to arrive by hand once.** The install image is
  tagged `edge`, and the nightly build moves that tag. `git fetch --tags` refuses to
  move a tag it already has and fails the entire fetch, so on a machine that had once
  seen that tag the *next* `w-sync update` died before it could do anything, and
  reported it as though the repository could not be reached. The fetch now passes
  `--force --prune-tags`. Since the broken code is the code that would have to run to
  deliver its own fix, a machine already in this state needs one command first, run as
  the user who owns the checkout:

  ```
  git -C /var/lib/w/src fetch --tags --force --prune-tags origin
  w-sync update
  ```

- **The status bar is now composed by you, screen by screen.** W Hub -> Appearance ->
  Bar is a new tab listing every block the bar can show, once per connected monitor,
  with the whole bar switchable off per screen as well. The same thing from a terminal
  — or through the assistant, which knows these commands:

  ```
  w-bar status
  w-bar block HDMI-A-1 tray off
  w-bar monitor eDP-1 off
  ```

  Choices live alongside the rest of your bar settings in
  `~/.config/quickshell/w/config/bar.json`. Switching a bar off keeps them, so
  switching it back on restores the same composition. Bar position moved out of
  Appearance -> Settings into this new tab; `w-appearance bar-position` is unchanged.

  Two things follow for a machine that already exists. A new install now ships four
  blocks switched off — system monitors (CPU/RAM/temperature/disk), network,
  brightness and keyboard backlight: they are readouts rather than everyday controls,
  and each is two clicks away in the Hub. **Your own bar is left exactly as it is** —
  that file is yours and updates do not touch it. But blocks are addressed by an `id`
  that your `bar.json` predates, so the new tab and `w-bar` will list nothing on your
  machine until the file has them. Taking the new default — which replaces your bar
  customizations, after backing the current file up — is:

  ```
  w-reset quickshell config/bar.json
  ```

  Adding `"id": "<name>"` by hand to the blocks you want addressable works just as
  well; the bar reloads as you save.

- **The Hub menu was reorganised.** It had grown into a list in the order things were
  added: twenty tiles in which a settings section and a one-shot command looked alike.
  It is now an even 4x4 — ten sections (appearance -> devices -> connectivity -> power
  -> system -> extensions) followed by six quick actions. Security and Date & time
  were each a section holding two or three controls; both are now tabs of System,
  where the boot-options tab appears only on a machine that has them. Calendar and
  Screenshot are no longer tiles: they are launcher entries now, the calendar still
  opens from the clock, and the screenshot entry takes a region (the other modes
  capture instantly and would photograph the launcher closing). The Power tile is
  called Power menu, so it no longer reads as a synonym of the Power section next to
  it. Separately: a highlighted row is no longer clipped at the edge of a scrolling
  list, and a dropdown in a bottom row now opens upwards instead of drawing past the
  card — which also fixes the NumLock dropdown under Input, wrong since it shipped.

- **Three launcher entries never worked, and a fourth is new.** Power menu, Volume
  control and Assistant have been in the launcher since they shipped and did nothing
  when clicked: their `Exec=` line was quoted in a way the desktop-entry specification
  does not recognise, so what reached the shell was a syntax error. Each had another
  door — a hotkey, the logo's right-click menu, a bar block — which is why it went
  unnoticed until Calendar, which now has an entry of its own and no other door. All
  four work.

## v0.3.0

- **W has moved to its permanent home — https://github.com/tarkh/w.** Every release
  up to and including v0.2.0 was published from a scratch repository used to shake the
  release machinery out, and that repository is being deleted. The address is baked
  into the install image and into `/etc/os-release`, so this release *is* the move:
  a new install points at the new repository on its own. A machine installed from an
  older image keeps pulling from the old address and stops updating the moment it
  disappears — point it at the new one once and it resumes:

  ```
  git -C /var/lib/w/src remote set-url origin https://github.com/tarkh/w
  sudo w-sync update
  ```

  The entries below this one describe releases of that earlier repository, so their
  tags and release pages no longer exist. Everything they describe is present in the
  system you are running; the changelog moved across intact on purpose.

- **Switching off your last display no longer strands the desktop.** With every
  connected output disabled, the machine came up with a session that runs, answers on
  the network and draws nothing — a black screen with no way back that does not
  involve a second computer. The Hub never offered the switch on a single-screen
  machine, but two ways around that existed, and both are now closed:

  - `w-monitor disable` run from a text console skipped the "not the last active
    output" check completely, because the check asked the running compositor and there
    is none on a console. It has been skippable that way in every release so far. The
    check now answers from the kernel's list of connected outputs when there is no
    compositor to ask, so it holds on a console too.
  - The dangerous case is not one command, it is time passing. Switching off the
    laptop panel while an external monitor is plugged in is a perfectly good thing to
    want, and the machine only breaks later, when the external one is unplugged —
    a moment at which nothing was checking anything. The display layout is now judged
    once more immediately **before** the compositor reads it, separately for your
    session and for the login screen, and if it would leave every screen off, exactly
    one is switched back on. Every other choice you made is left alone, and on a
    healthy configuration this does nothing whatsoever.

  Should you still land on a black screen, `RECOVERY.md` now has a section written for
  that symptom — Ctrl+Alt+F2, `w-monitor reset --all`, `sudo w-monitor greeter reset`,
  reboot — and it ships on the machine too, at `/usr/share/doc/w/RECOVERY.md`, which is
  where you will need it.

- **The install image is rebuilt nightly, and no longer right after each release.**
  The ISO the README links to is one rolling image built from the current tree.
  Publishing a version no longer forces a rebuild on the spot, so for a day or so
  after a release the download can still be the previous night's image. It makes no
  difference to what you end up with: an image here is a bootstrap medium, and the
  first update pulls the machine up to the current tree regardless.

## v0.2.0

- **`w-rollback` — one command that puts an older system back.** W has taken a
  filesystem snapshot before every package transaction and every `w-sync update`
  since the beginning, but nothing turned one back into the running system.
  `sudo w-rollback run` now does: it lists the snapshots, asks which one to go back
  to, and asks you to confirm before it changes anything. **The system it replaces
  is kept, not deleted**, so a rollback can itself be rolled back. It works on both
  kinds of install — encrypted (Limine) and plain (GRUB) — and both paths were
  walked on real machines rather than reasoned about. `w-rollback status` tells you
  where you stand without changing anything.
- **The rollback W did have never worked.** The assistant's `w_snapshot_rollback`
  action — present in every release up to and including v0.1.7 — called `snapper
  rollback`, which repoints the btrfs default subvolume, while W boots an explicit
  `subvol=@`. It reported success and changed nothing, every single time. If you
  ever asked the assistant to roll back and it told you it had, it had not — and
  your system was not damaged either, because nothing happened at all. The
  assistant can now only *start* a rollback: it opens `w-rollback`, and the
  password and the confirmation are yours.
- **RECOVERY.md — what to do when the machine will not boot.** A page written by
  symptom: won't boot, boots wrong, an update made things worse. It ships on the
  machine as well, at `/usr/share/doc/w/RECOVERY.md`, which is where you will need
  it — a machine that will not boot has no browser.
- **You are now told when you are running from a snapshot.** Booting a snapshot
  from the boot menu is the recovery path, its root is read-only, and the desktop
  looked completely normal — so anything saved outside `/home` vanished at the next
  reboot without a word ever being said. A notice at login now says so, on both
  bootloaders.
- **The installer no longer asks about Secure Boot.** The checkbox was cosmetic:
  the answer was read three times and reached nothing — no keys, no signing,
  whichever way you answered it. Turning Secure Boot on for real needs the firmware
  in Setup Mode and a UEFI toggle, neither of which an installer can do for you, so
  the option is gone and the encrypted install's final screen now points at **Hub →
  Security**: it enables Secure Boot in two steps and then seals TPM2, after which
  the passphrase stops being asked at every boot. This affects new installs only;
  nothing changes on an installed system.
- The on-box assistant now knows the upgrade order for laptops with Broadcom Wi-Fi:
  the driver goes in **before** the system upgrade. The other way round, DKMS
  rebuilds the old driver against the new kernel, the build fails, and the machine
  comes back with no Wi-Fi — which on a laptop with no Ethernet port is also the
  channel you would have fixed it through.

## v0.1.7

- **The install image builds again.** Arch removed the `broadcom-wl` package from
  its repositories on 1 September, and the image's package list still asked for
  it, so every build since — including the one for v0.1.6 — failed before
  producing anything. The list now follows upstream, which dropped the same
  package the same day. If you are updating an installed system, nothing here
  changes it; this restores the download.
- **Broadcom Wi-Fi on old chips, and what changed.** That package was what let
  the *live* session drive a handful of older Broadcom chips — BCM43142,
  BCM4360, the ones in machines like the 2013–2015 MacBook Pro. Arch ships only
  a source version now, so the default image no longer covers them in the
  installer, exactly as the official Arch image no longer does. **Installed
  systems are unaffected**: the installer still detects such a chip and installs
  the driver for it. What is affected is installing on a laptop that has one of
  those chips *and* no Ethernet port — there the installer can no longer bring
  the network up. For that case you can build yourself an image that does:
  `./scripts/build-iso.sh --broadcom-wl`, see "Building your own ISO" in the
  README.
- The README now has a section on building your own image, instead of a note
  buried in the install steps.

## v0.1.6

- **Folders in the file manager are the theme's colour again.** W recolours the
  Papirus folder icons to the tone of the active theme, and that had quietly
  stopped working in v0.1.2 — the release that moved W's internals out of
  `/usr/local`. The recolouring step looked for its helper on `PATH`, where it
  no longer is, found nothing, and skipped without reporting anything, so
  nothing in the logs said so. If you installed or updated since v0.1.2 your
  folders have been stock Papirus blue; updating fixes them, and already-open
  windows pick up the new icons when you restart them.
- A new default wallpaper for the `w` theme, in all four resolutions. The colours
  of the theme are unchanged — the picture was drawn to fit the palette, not the
  other way round — so nothing else about your desktop moves. If you are using
  your own theme or your own wallpaper, this does not touch it.
- Nothing else changes on an installed system.

## v0.1.5

- The unencrypted install path is now tested as well. Every published image was
  already installed onto an encrypted disk and checked before this; now the
  plain btrfs + GRUB layout — what you get by answering "no" to encryption — is
  installed and checked alongside it, on the same image. The two use different
  boot loaders, so passing one said nothing about the other.
- Your assistant now answers update questions correctly. It knows that this
  repository publishes one commit per release (so "one behind" means one
  version, not one commit), that pinning `REF` in `/etc/w/update.conf` holds a
  machine in place, and that `w-update` and `w-sync` are two different updates —
  packages from Arch, and W's own configuration.
- Nothing else changes on an installed system.

## v0.1.4

- Every published image is now installed, not just built. After each build a
  runner boots the very file on the download page, installs it unattended onto
  an encrypted LUKS2 + Limine + TPM2 disk — the stack a default install
  produces — reboots into the result and checks it: no failed services, no
  crashes, the login manager up, the boot loader correctly staged. If an image
  would not install, that is now known the same day instead of on your machine.
- Nothing on an installed system changes in this release; updating one only
  restamps its version.

## v0.1.3

- The install image on the releases page is now rebuilt every night from this
  repository, instead of whenever one happened to be built by hand. W is a thin
  layer over a distribution that moves daily, so an image that sits still only
  gets further from Arch — and an upstream package that stops building now turns
  into a failed build the same night, rather than into a failed install on your
  machine weeks later. Same page, same link, still exactly one image.
- Nothing else changes. No tool, no default and no configuration is different in
  this release; updating an installed system only restamps its version.

## v0.1.2

- W's own commands now live in `/usr/bin` and its internal helpers in
  `/usr/lib/w/`, instead of `/usr/local`. `/usr/local` is yours: nothing W
  installs will appear there any more, so what you put in it is once again the
  only thing in it.
- **If you are upgrading an existing install, remove the old copies by hand and
  reboot** — `w-sync` does not delete files, and `/usr/local/bin` comes before
  `/usr/bin` in `PATH`, so anything left behind keeps shadowing the updated
  tool, `w-sync` itself included:

  ```
  sudo rm -f  /usr/local/bin/w-* /usr/local/bin/papirus-folders
  sudo rm -rf /usr/local/lib/w
  sudo rm -f  /usr/local/src/w-windowblind.c
  sudo reboot
  ```

  Leave `/usr/local/bin/sudo` alone — that is W's `sudo-rs` shim and it works by
  being found first. A fresh install needs none of this.

## v0.1.1

- The README now says where the first-boot logs live, so a failed install is one
  `ls /var/log/w/` away from an explanation instead of a guess.
  Thanks to @tarkh (#1).

## v0.1.0

First public release.

- Beta of the W desktop: Hyprland under uwsm with the Quickshell UI (bar, launcher,
  notification centre, calendar, clipboard, volume and brightness, power menu,
  network and Bluetooth tray, lock screen with fingerprint support), a session that
  remembers open windows and named layouts, and a unified authentication dialog.
- Theming across GTK, Qt/Kvantum, icons, terminal, shell prompt, Firefox chrome,
  bootloader and boot splash from one palette. `w-theme new <image>` builds a full
  theme from any wallpaper.
- TUI installer in English and Russian — disk, LUKS encryption with Secure Boot,
  locale, keyboard, timezone, users, update channel, optional software bundles —
  plus an unattended `--preset` mode.
- btrfs layout with snapper timelines for root and home, zram in place of swap.
- Updates over the `edge` channel: `w-sync` takes a home snapshot, pulls, and
  applies only the modules a change actually touches. `w-reset` restores any module
  to its W default.
- The `w-*` tool set: updates, themes, wallpaper, power, monitors, keyboard,
  pointer, night light, keyboard backlight, DNS, firewall, logs, time, screenshots,
  package bundles. `w-info` lists them all.
- An on-box AI layer, opt-in and off by default, with every state-changing action
  behind polkit.
