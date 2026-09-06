# Recovery — when W will not boot, or boots wrong

**English** · [Русский](https://github.com/tarkh/w/blob/main/docs/ru/RECOVERY.md)
— on the machine itself, `/usr/share/doc/w/RECOVERY.ru.md`. The links here are
absolute because this page also ships offline, where a relative one would lead
nowhere.

W takes a filesystem snapshot before every package transaction and before every
`w-sync update`, and it keeps one permanent snapshot, `W initial state`, from the
day the machine was installed. Those snapshots are bootable. This page is how you
use them.

Read the section that matches your symptom. Everything here has been run on a real
machine — none of it is a procedure that only looks right on paper.

---

## The one command

If the machine still boots:

```sh
sudo w-rollback run
```

It shows the snapshots, asks which one to go back to, and asks you to confirm before
it changes anything. **The system it replaces is kept, not deleted** — a rollback can
itself be rolled back.

`w-rollback status` tells you where you stand without changing anything.

---

## Symptom: it boots, but something broke after an update

Roll back to the snapshot taken just before the change:

1. `w-rollback list` — the descriptions name the transaction (`pacman -Syu …`), and
   `pre` is the state *before* it.
2. `sudo w-rollback run`, pick that `pre` number, confirm.
3. Reboot.

Package updates and W's own updates are separate concerns, so check which one you
mean: `w-update` upgrades Arch packages, `w-sync` updates W itself.

If only a *config* is wrong — a theme, a module's settings — do not roll the whole
system back. `w-reset` puts a single subsystem's config back to the W default and
leaves everything else alone.

---

## Symptom: the screen stays black after login, or the login screen never appears

The machine itself is running — the fans behave normally, the disk settles down, it
answers on the network — but nothing is drawn on any screen.

If you turned a monitor off in the Hub's Displays panel and later unplugged or
removed the other one, that is almost certainly what this is: every display the
machine still has is switched off, so there is nothing left to draw on. W checks for
exactly this before the desktop starts and repairs it by itself, so you should not
be reading this section — if you are, the check did not get to run, and the repair is
one command by hand.

Get to a text console with **Ctrl+Alt+F2** and log in there (or reach the machine
over SSH from another computer — the network is up). Then:

```sh
w-monitor reset --all          # your session's display layout
sudo w-monitor greeter reset   # and the login screen's, if that is what is dark
sudo reboot
```

`reset --all` drops only the saved display rules — resolution, scale, rotation,
placement, on/off — and puts every output back to automatic. Nothing else about the
system changes, so do **not** roll a snapshot back for this: it is a settings file,
not a broken system.

`w-monitor status` prints those rules if you want to see what was wrong first;
`disabled = true` on the only display you still own is the fingerprint.

If the screen is black from the very first second — no manufacturer logo, no boot
menu — this is not your symptom. Read "it does not even reach the boot menu" below.

---

## Symptom: it does not boot

The snapshots are in the boot menu. Which menu depends on how the disk was set up
at install time; you will know which one you have from what the screen looks like.

**Encrypted install (Limine).** The menu appears for about **1.5 seconds** — start
tapping an arrow key immediately after the firmware screen, do not wait for the menu
to show up. Then:

```
W Linux  →  Snapshots  →  pick a snapshot by date
```

The disk passphrase is asked *after* the menu, not before.

**Plain install (GRUB).** Hold <kbd>Shift</kbd> or tap <kbd>Esc</kbd> during boot to
reveal the menu, then open the snapshots submenu.

Once it has booted:

```sh
sudo w-rollback run
```

Booted from a snapshot, `w-rollback` restores **that** snapshot — it does not ask
which one. Reboot afterwards and you are back on a normal system.

A notification appears shortly after login telling you the session is a recovery boot,
with a button that runs the rollback for you — it opens a terminal, asks for your
password, and walks through the same confirmation. You do not have to find the command
yourself.

### A snapshot is in the list but not in the boot menu

On the encrypted path the boot entries are generated separately from the snapshots
themselves, so a snapshot can exist without being bootable — it is in
`w-rollback list`, but the menu does not offer it. Regenerate the entries from a
system that still boots:

```sh
sudo limine-snapper-sync
```

### What a snapshot boot looks like

A snapshot is read-only, and W boots it that way on purpose. Expect this and do not
be alarmed:

* The desktop comes up normally and you can use it.
* A handful of services fail — the GnuPG socket units, `ipp-usb`. They need to write
  to `/` and cannot. This is harmless and disappears once you are back on a normal
  system.
* Anything you save inside a snapshot is lost. Copy files you want to keep to
  `/home`, which is a separate subvolume and stays writable.

---

## Symptom: it does not even reach the boot menu

Boot the W (or any Arch) install medium and do the swap by hand. This is the same
thing `w-rollback` does, minus the conveniences.

If the disk is encrypted, unlock it first:

```sh
cryptsetup open /dev/<root-partition> cryptroot
```

Mount the **top of the filesystem** — no `subvol=` option; that is the only place
where `@` and the snapshots are both visible:

```sh
mount -o subvolid=5 /dev/mapper/cryptroot /mnt   # plain install: /dev/<root-partition>
ls /mnt                                          # @  @home  @snapshots  …
```

Find the snapshot you want. The dates are in UTC:

```sh
grep -r '<date>' /mnt/@snapshots/*/info.xml
```

Swap it in, keeping the broken system rather than deleting it:

```sh
mv /mnt/@ /mnt/@.broken
btrfs subvolume snapshot /mnt/@snapshots/<number>/snapshot /mnt/@
```

Unmount and reboot. On an encrypted install, if the kernel no longer matches the
restored system, boot a snapshot from the Limine menu once and run
`sudo w-rollback run` — it restores the kernel pair from the EFI partition, which a
manual swap cannot do.

---

## Symptom: the disk passphrase is not accepted

The passphrase slot is the fallback that always exists; TPM2 unlock and the printed
recovery key are extra slots on top of it. `w-crypt` manages them:

```sh
w-crypt status          # which slots exist
sudo w-crypt help       # enrolling TPM2, adding a recovery key, wiping TPM2
```

If TPM2 unlock stopped working after a firmware or boot change, that is expected —
PCR values changed. Use the passphrase, then re-enroll TPM2.

---

## Symptom: a file in your home directory is gone

`/home` has its own timeline snapshots, taken hourly and kept separately from the
system ones, so you do not need to roll the system back to get a file:

```sh
snapper -c home list
ls /home/.snapshots/<number>/snapshot/<your-user>/
```

Copy what you need straight out of there.

---

## Undoing a rollback

**Encrypted (Limine).** The system you rolled back *from* was registered as a
snapshot with the description you typed. It is in the boot menu like any other —
boot it and run `sudo w-rollback run`.

**Plain (GRUB).** It was kept as a subvolume named `@.bak-<timestamp>`. Swap it back
from an install medium, using the procedure above in reverse:

```sh
mount -o subvolid=5 /dev/<root-partition> /mnt
mv /mnt/@ /mnt/@.discard
mv /mnt/@.bak-<timestamp> /mnt/@
```

Once you are sure you no longer need a kept system, remove it. Nothing removes it
for you, and a plain `btrfs subvolume delete` will refuse: a root subvolume has
others nested inside it (`/.snapshots`, `/var/lib/machines`, …), so the delete has
to be recursive.

```sh
btrfs subvolume delete -R /mnt/@.bak-<timestamp>
```

---

## Where the machine writes down what happened

```
/var/log/w/w-install-*.log    the installer
/var/log/w/w-apply-*.log      the setup that runs after it
journalctl -b -1              the previous boot, in full
```

`/var/log` is a separate subvolume, so these survive a rollback — the log of the
boot that broke is still there after you have recovered from it.
