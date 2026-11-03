---
name: w-security
description: >-
  W Linux security model and tools: kernel/sysctl hardening (w-kernel), privileges
  (sudo-rs, run0), the secrets keyring (gnome-keyring, seahorse), the SSH agent slot (w-ssh:
  switching agents, per-host key selectors, "too many authentication failures"),
  fingerprints (w-fingerprint: enrolling, listing and deleting fingers, the reader),
  firmware updates (fwupdmgr), and disk encryption / Secure Boot (w-crypt,
  w-secureboot) on encrypted installs. Load this for hardening, secrets/SSH keys,
  fingerprints, firmware, or LUKS/TPM2/Secure Boot questions.
sources:
  - path: .claude/library/security.md
    sha256: 85649ab384308d1c5a2bdf97aebd4dc077ea08025974c54bb7d939a270c2f0a5
  - path: .claude/library/w-fingerprint.md
    sha256: db6347feb144b0a35aec53c7c5cb7ee5b3386a4d2cfa904f582ec9915356bd24
  - path: .claude/library/w-ssh.md
    sha256: b1a094a3801dad4efdd25e9e56439883f0e2a3d71cde53a717ca77597bb8ca2b
  - path: .claude/library/package-limine.md
    sha256: 2acfee9e62d4c73216008833895c914e161af7a708d707a458253034aa403230
tools:
  - w_fwupd_refresh
---

# W Security

W ships a modern, minimal-but-sufficient security baseline. Wayland/Hyprland already
isolate input and screen capture; fingerprint + PAM + the lock screen + polkit handle
authentication; btrfs + Snapper + snap-pac provide rollback; Arch rolling delivers fast
CVE fixes. On top of that:

## Kernel & hardening — `w-kernel`

The default kernel is `linux-zen` (not `linux-hardened`, which would break the
unprivileged user namespaces sandboxing and rootless containers rely on, and DKMS).
sysctl and boot-cmdline hardening are applied as a profile.

- `w-kernel list [--porcelain]` — the known kernels, which are installed, which one boots
  next and which one is running. Porcelain is TSV:
  `name pkg version installed default running`.
- `w-kernel set <zen|vanilla|lts>` — install that kernel plus its paired headers (every
  DKMS module rebuilds behind them) and make it the default. It regenerates whatever this
  machine actually boots — GRUB on a plain install, Limine on an encrypted one.
- `w-kernel remove <zen|vanilla|lts>` — uninstall one. It refuses the running kernel and
  the default one; switch first.
- `w-kernel harden <on|off|status>` — the hardening profile as a whole (sysctl drop-ins
  plus boot cmdline). `status --porcelain` is TSV: `state(on|off|mixed) pending(yes|no)`.

Three things worth knowing before advising someone here:

- **Switching kernels never removes one.** Every installed kernel stays a bootable menu
  entry, so switching to one that is already installed is an instant, offline repin of
  the boot default — no download. That is the answer when a kernel upgrade breaks a
  driver (Wi-Fi included): keep `lts` installed as a rescue kernel, and switching to it
  works even with no network. `lts` is an older, long-supported series that usually still
  carries a driver a newer kernel regressed or has not gained yet.
- **A kernel switch only takes effect at the next boot.** Until then the running kernel
  and the default disagree; `w-update` reports that as a pending reboot, and the bar shows
  its reboot glyph.
- **`harden status` can say `mixed`.** The sysctl drop-ins and the boot cmdline are two
  halves that can end up toggled apart. Report it as "partially applied" — never round it
  down to "off". `pending=yes` means the configured cmdline has not reached the running
  kernel yet (reboot owed). Note that `harden off` removes the boot parameters at once but
  leaves sysctl values already applied to the running kernel in place until a reboot.
  The profile is exactly the three `90-w-*.conf` drop-ins; `/etc/sysctl.d/80-w-dns.conf`
  (TCP Fast Open off, owned by the DNS module — see the w-network skill) is plumbing, not
  hardening, and `harden off` leaves it alone on purpose.

Both surfaces are also in the Hub: the kernel under System → General, hardening under
System → Security.

## Privileges — sudo-rs and run0

- `sudo` on W is **sudo-rs** (memory-safe), used transparently via a shadow symlink; it
  reads the normal `/etc/sudoers`.
- `run0` (from systemd, no extra package) is available as an interactive alternative:
  no setuid, a clean environment, and authorization through polkit → the fingerprint/
  password prompt in a GUI terminal.

## Secrets & SSH keys

Two decoupled layers:

- **Secrets:** `gnome-keyring` provides the Secret Service, auto-unlocked by your login
  password. GUI manager: **seahorse** ("Passwords and Keys"). Any password manager the
  user installs stores its own unlock key here too, via libsecret.
- **SSH agent:** a **slot**, not a fixture — see the next section.
- **Caveat:** logging in with fingerprint only does **not** auto-unlock the keyring (a PAM
  limitation) — the login password does. W's greeter has no fingerprint step, so in
  practice the keyring is unlocked; this matters only if that ever changes.

## Fingerprints — `w-fingerprint`

The reader is what the password dialog and the lock screen offer instead of typing.
Enrolling is the user's own business — no root, no polkit prompt: fprintd lets an active
user manage **their own** prints. GUI: **Hub → Input → Fingerprint**. Never call
`fprintd-enroll` / `fprintd-list` directly — `w-fingerprint` is the one interface, and it
is what the Hub uses too.

- `w-fingerprint status` — the reader plus all ten named slots. `--porcelain` adds
  `available=yes|no` and, when unavailable, `reason=no-device|unauthorized`.
- `w-fingerprint enroll <finger>` — enrol one finger; it prints a live `event=` stream
  (`ready`, `stage`, `retry`, `complete`, `error`, `cancelled`) and ends in exactly one
  verdict. Ctrl-C cancels cleanly and releases the reader.
- `w-fingerprint delete <finger>` · `w-fingerprint fingers` (the ten accepted names:
  `left-thumb`, `left-index-finger`, … `right-little-finger`).
- `w-fingerprint lock-sensor mode <native|wake>` — who verifies under the lock screen.
  `native` (default): hyprlock itself, sensor lit for the whole lock. `wake`: W's auth
  daemon verifies only for `lock-sensor window <10..300>` seconds after the lock, a
  wake-up from sleep or any activity while locked, then the sensor sleeps — the mode for
  readers that overheat under a continuous scan (see the `w-power` skill). Both are
  user-scope keys of the `fingerprint` config (`~/.config/w/fingerprint.conf`); a
  change applies from the next lock. `lock-sensor status` shows the mode, the window
  and the daemon's live state. GUI: Hub → Input → Fingerprint → Lock screen.

Three things worth knowing before you diagnose anything:

- **`available=no` does not mean the device is missing.** fprintd answers only an
  **active session**, so a fingerprint command run over SSH or from another VT reports
  `reason=unauthorized` while the reader is sitting right there. Tell the user to run it
  from their desktop session; `reason=no-device` is the one that means "check the hardware".
- **The reader takes a single claim.** While an enrolment is running, authentication by
  finger is unavailable — and vice versa, an enrolment started while the password dialog
  is asking for a finger fails with `busy`. That is not a bug; wait and retry.
- **"The finger stopped working after a resume, everywhere"** — the lock screen *and*
  every polkit prompt, while `w-fingerprint status` still lists the enrolled fingers.
  That is fprintd holding a device it could not close: look for `Error closing device
  after disconnect: The device is still busy` in `journalctl -u fprintd` just before
  the suspend. It happens when a verification is killed at the moment the machine
  freezes, so the daemon never gets to finish the close, and the bus resets the reader
  on resume. `systemctl restart fprintd` clears it. W avoids creating this on its own
  sleep path (`w-power sleep` tells the lock sensor to stand down before locking), so
  a bare `systemctl suspend` with the reader lit is the likely trigger — as is `native`
  mode, where hyprlock holds the reader for the whole lock and so still holds it when
  the machine freezes. Suggest `wake` mode to a user this keeps happening to.
- **The first enrolled finger turns the fingerprint mode on**, and deleting the last one
  turns it off: the password dialog offers the reader only when there is something to
  match. So "why does it ask for my finger now?" and "why did it stop?" are usually this.

## The SSH agent slot — `w-ssh`

The session always exports one stable path, `SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/w/ssh-agent.sock`,
and a **symlink** behind it points at whichever agent is active. So switching agents is one
command, takes effect for anything started afterwards, and needs no dotfile and no relogin.

- `w-ssh status` — **start here for any SSH problem**: active agent, whether its socket is
  live, how many keys it offers, whether the generated selectors and the `~/.ssh/config`
  Include are in place. It also flags the common confusion where the calling shell was
  started before the last switch and still carries the old socket.
- `w-ssh list` / `w-ssh use <name>` — the catalog is `gcr` (W's default, from gcr-4),
  `bitwarden`, `onepassword`, `openssh`, and `none`. `use` masks `gcr-ssh-agent.socket`
  for that user when another agent takes over, and unmasks it on the way back — the
  handoff is explicit and reversible.
- Adding an agent W does not know about is one `SOCKET_<name>=` line in
  `/etc/w/ssh.conf` or `~/.config/w/ssh.conf`; `%t` = `$XDG_RUNTIME_DIR`, `%h` = home.

### `w-ssh sync` — per-host key selectors (why "Too many authentication failures" happens)

An agent holding a whole password vault offers **every** key it has, and `sshd` gives up
after `MaxAuthTries` (6 by default). With more than six keys the right one is never
reached and the connection dies as `Too many authentication failures`. This is inherent to
the agent protocol — not a bug in W or in the password manager — and the only fix is to
tell ssh which key to offer per host.

`w-ssh sync` generates exactly that from the agent, reading each key's **name in the
vault** as the list of hosts it belongs to: an item named `GitLab git.example.com` yields
a `Host GitLab git.example.com` block with `IdentityFile` + `IdentitiesOnly yes`. Output
goes to `~/.ssh/config.d/50-w-agent.conf` and `~/.ssh/agent-keys/`; `~/.ssh/config` is
never rewritten. The public key on disk is a **selector**, not a copied secret.

So the user's workflow is: add a key to the vault → put the host(s) in its name → run
`w-ssh sync`. Key listing works while the vault is locked, so this needs no unlock.

- `w-ssh include` adds `Include config.d/*.conf` **at the top** of `~/.ssh/config`. It has
  to be above the first `Host`/`Match` line: a `Host` block runs to the next one and a
  blank line does not close it, so an Include below one applies to that single host —
  silently. If `w-ssh status` reports the Include is "inside a Host block", that is the
  bug, and moving the line is the fix.

**Passphrases with the default agent (gcr-ssh-agent):** to store one persistently, just
`ssh user@server` — on first use the prompt (W's auth card) offers an "automatically
unlock" checkbox and saves it to the keyring. `ssh-add` does **not** persist to the
keyring, and `ssh-add -l` is not a reliable unlocked-state indicator.

## Firmware — fwupd

Firmware updates use **fwupd** with LVFS; metadata refreshes on a timer. There is no
GNOME Software/Discover — use the CLI:

- `fwupdmgr get-devices`, `fwupdmgr refresh`, `fwupdmgr get-updates`, `fwupdmgr update`.

## Application sandboxing — the optional `flatpak` bundle

W keeps the slots sandboxing needs in the base — the desktop portals and the kernel's
unprivileged user namespaces (which is why the default kernel is not `linux-hardened`).
The channel itself is opt-in: `sudo w-pack install flatpak` adds Flatpak with Flathub,
the Bazaar store, Flatseal for per-app permissions, and W's theme inside the sandbox.
Check with `w-pack status flatpak`; once installed, the bundle curates its own
`flatpak` skill with the operational detail.

## Disk encryption & Secure Boot (encrypted installs only)

On an encrypted install, W uses LUKS2 (Argon2id) + TPM2 auto-unlock + a passphrase
fallback, with **Limine** as the bootloader and snapshot-boot support. Two tools manage it
(run with `sudo`):

- `w-crypt status [--porcelain] | enroll-tpm [--pin] [--no-secureboot] | reenroll-tpm |
  recovery-add [--replace] | wipe-tpm` — automatic unlock and a printable recovery key; the
  Hub's System → **Security** tab has a row for each (Automatic unlock: Off / TPM / TPM + PIN /
  Re-seal; Recovery key: Create / Replace). `enroll-tpm` **refuses while Secure Boot is not on
  in W and enforced by the firmware** (PCR7 is then the same for any USB stick) —
  `--no-secureboot` is only for an admin who sealed to other PCRs in `/etc/w/crypt.conf`;
  never suggest it as a workaround. On a laptop recommend `--pin` (TPM2 + PIN: the boot asks
  for a short PIN, a keypad glyph under the field; three wrong PINs — or a changed boot chain —
  bring up the lock-glyph prompt, which takes the passphrase or the recovery key; the
  passphrase typed at the PIN prompt counts as a wrong PIN). Status
  porcelain (root): `luks tpm_device tpm2(none|tpm|pin) pcrs recovery
  reseal(no|pending|stale|unknown)`; `stale` = the sealed PCR policy no longer matches this
  boot (firmware/shim/dbx update) → `sudo w-crypt reenroll-tpm`, which keeps a PIN seal a PIN
  seal (asks for a new PIN; needs a terminal).
- `w-secureboot status[--porcelain] | enable [--mode own|shim] | disable | setup | sign |
  reenroll [--if-stale]` — Secure Boot. **`enable`/`disable` are the entry points** (what the Hub's
  System → **Security** tab's Secure Boot row runs; its rows exist only on the encrypted+Limine
  path). The Hub row is a walk-through: it shows W's state and the firmware's, names the next
  step (prepare W → reboot / MokManager → turn SB on in the firmware → finish) and can reboot
  straight into the firmware setup (`w-session-exit firmware`). Limine
  is signed with sbctl's db key, generated on this machine; the **mode** says who trusts it
  and `enable` picks it from the firmware (`status` shows the mode, porcelain field 5):
  - `shim` — firmware keeps its factory keys (the usual laptop). Microsoft-signed shim
    (Fedora's, package `shim-signed`) boots Limine, and W's key goes into shim's MokList:
    after the first `enable` the user reboots, the blue *Shim UEFI key management* menu
    opens by itself → Enroll MOK → Continue → Yes → the one-time code `enable` printed (not
    echoed) → Reboot, all within 5 minutes (the firmware watchdog then reboots and the
    request is lost; `enable` re-queues it). Never **Reset MOK** — it erases all keys.
    The first `enable` makes the `W` firmware entry first and the next boot; if Windows
    starts anyway, pick W in the firmware's boot menu (F11/F12/Esc) and put W first there.
    Windows' BitLocker is not affected. Refused when the firmware lacks the Microsoft
    3rd-party UEFI CA (Secured-core default) — tell the user to enable "Allow Microsoft
    3rd-party UEFI CA". `disable` here needs Secure Boot turned off in the firmware first.
  - `own` — firmware in Setup Mode (user cleared its keys): sbctl's keys are enrolled
    (Microsoft's kept); changes PCR7 of every OS, so BitLocker asks for its recovery key once.
  TPM2 auto-unlock is sealed to PCR7, measured only at boot, so `enable` is **two calls with
  a reboot in between**: the first changes keys / queues the MokManager step, the second
  (after the reboot, tracked by boot ID) re-seals an **existing** TPM2 seal. It never creates
  one — automatic unlock is a separate `w-crypt enroll-tpm` step, so a laptop turning Secure
  Boot on stays on its passphrase. Porcelain field 4 `tpm_pending` (`no`/`reboot_needed`/
  `ready`) says which phase; field 7 `mok` (`yes`/`no`/`unknown`/`na`) whether W's key reached
  MokList (`no` after a lost MokManager request → `enable` again re-queues it).
  `disable` removes the TPM2 seal too (the passphrase is asked again). Loaders for the mode are laid out by
  `/usr/lib/w/w-secureboot-stage` after every Limine regeneration; `setup`/`sign`/`reenroll`
  are the advanced pieces `enable` uses.
- **Once Secure Boot is on in W, `/boot/efi/limine.conf` is fingerprinted** into the boot
  loader. A stale fingerprint halts Limine with `CHECKSUM MISMATCH FOR CONFIG FILE` —
  **even with Secure Boot switched off in the firmware**, and snapshots do not cover the
  ESP. A guard keeps it current: `w-secureboot reenroll --if-stale` (re-enrolls only on a
  mismatch) runs after every Limine regeneration, before every poweroff/reboot
  (`w-secureboot-guard.service`) and before hibernation, so an edit past limine-entry-tool
  survives a clean shutdown. Porcelain field 6 `config_hash` is `ok`/`stale`/`unknown`
  (`unknown` without root — the ESP is root-only); on `stale`, run `sudo w-secureboot
  reenroll` right away and check what it reports. What the guard cannot catch — power loss
  or a hard reset right after a change, an ESP changed while W was not running — still
  needs the way back: live medium → chroot → `w-secureboot reenroll`; point the user to
  `/usr/share/doc/w/RECOVERY.md` §"CHECKSUM MISMATCH FOR CONFIG FILE".
- **The install medium boots with Secure Boot on.** Once per downloaded image shim refuses
  it (`Verification failed`) and opens MokManager: any key within 10 s → Enroll hash from
  disk → the medium → `EFI/BOOT/grubx64.efi` → Continue → Yes → Reboot (no password).
  `Access Denied` = a Secured-core firmware: allow the 3rd-party UEFI CA or switch Secure
  Boot off. The stick must be a byte-for-byte copy of the ISO: `dd` (Linux/macOS), Rufus
  (forces DD mode for this image by itself) or balenaEtcher; Ventoy or copying the files
  onto a FAT stick is not supported.
- **Installed with Secure Boot enforcing, W sets it up itself** (shim mode): only the
  encrypted stack is offered; the installer's last screen shows a one-time code, and on the
  next boot MokManager wants **Enroll MOK** (and **Delete MOK** — the medium's hash, same
  code; it drops the public image's trust, which the installed W does not need) → Reboot;
  request lost → after `Verification failed` any key within 10 s → Enroll key from disk →
  volume `W_EFI` → `EFI/W/W-MOK.cer`. Some firmware (older AMI, e.g. ASUS X99) refuses to
  create shim's variables from the OS (`mokutil` → `Failed to enroll new keys`): then
  there is no code at all — the installer's last screen and `w-secureboot enable` give
  only those from-disk steps, and the medium's hash stays in MokList. Firstboot finishes
  phase 2. TPM2 auto-unlock comes with it on a desktop; a laptop keeps the passphrase (a
  stolen laptop with TPM-only boots to the login screen) — Hub → Security → Automatic unlock
  (`sudo w-crypt enroll-tpm --pin`) adds it.
- **With Secure Boot off at install, the installer does not turn it on.** Enrolling keys
  needs the firmware in Setup Mode and switching SB on needs a UEFI toggle plus a reboot —
  none of which an installer can do. Such an encrypted install boots with SB off
  and asks for the LUKS passphrase every time; both are expected. The order that works is
  Secure Boot first, TPM2 auto-unlock second (`enable`, then `w-crypt enroll-tpm`): sealing TPM2
  while SB is off is close to pointless, because PCR7 then reads the same for any medium
  someone boots, so the TPM would hand the key to a USB stick just as readily. The
  installer offers the encrypted stack first (the recommended default; plain GRUB is the
  compatibility choice) and leaves TPM2 to the user — except unattended preset installs
  (nobody is there to type) and desktops installed under Secure Boot; both are sealed to
  PCR 7 on the first boot. When the user asks why the passphrase
  is asked at every boot, explain this and point to the docs guide `security.md`
  §"Disk encryption and Secure Boot"; whether to enable auto-unlock is their call.

These tools are only present on encrypted/Limine installs; on a plain GRUB install the
bootloader is GRUB and neither applies.

### Windows next to W (dual boot) and BitLocker

When the firmware has a Windows boot entry, both boot menus (GRUB and Limine) show for
5 s with a Windows entry; without one the menu stays hidden. That entry does not
chainload Windows — it restarts into the firmware's own "Windows Boot Manager" entry
(BootNext), so BitLocker sees a normal Windows boot and does not ask for its recovery
key. No Windows entry in the menu → the firmware lost it (e.g. after a firmware reset):
start Windows once from the firmware's boot menu (F12/F8/Esc) and it restores the entry;
the menu picks it up at the next kernel update. What still triggers a BitLocker key
prompt is turning Secure Boot off (or allowing the 3rd-party CA on a Secured-core machine) and `w-secureboot` in `own`
mode (both change PCR7) — the `shim` mode does not; have the user keep the recovery key at hand.
The other way round: Windows installs Microsoft's Secure Boot updates (dbx, 2023
certificates) only while Secure Boot is on, so its first boots after W turned it on change
PCR7 for W — the disk asks for the passphrase once, then `sudo w-crypt reenroll-tpm` (Hub →
Security → Re-seal). Best: let Windows finish its updates, then re-seal.

### ESP space on an encrypted install

The ESP is 2 GiB there because Limine cannot read the LUKS root: kernels, initramfs and
the snapshot boot entries are all copied onto it. It is not a scarce resource, and a
second or third kernel is not what threatens it:

- Snapshot boot entries are content-addressed (`vmlinuz_sha256_…`), so many snapshots
  sharing one kernel cost one copy. What grows the ESP is the number of *distinct*
  kernel/initramfs builds still referenced — kernel upgrades and initramfs rebuilds.
- Measured: one kernel ≈ 92 MB used of 2048; adding `linux-lts` cost +37 MB.
- It is self-limiting. `limine-snapper-sync` evicts the oldest snapshot boot entries once
  the ESP passes 85% usage, so it degrades instead of filling up, and it never touches the
  current kernels or the btrfs snapshots themselves.

So do not advise trimming the snapshot policy or repartitioning to make room for a kernel;
neither is the constraint.

### If the ESP stops receiving kernel updates

Two AUR packages keep the ESP in sync with `/boot`: `limine-mkinitcpio-hook` (the boot
path — it builds each initramfs straight into the ESP and updates the Limine entries) and
`limine-snapper-sync` (snapshot boot entries). A machine installed while their upstream
build was broken (Arch's gradle 9.7.0, 2026-08) can be missing both. Neither absence
announces itself, so recognise the symptoms:

- **A kernel update appears to do nothing** — `uname -r` after a reboot still reports the
  old kernel. `mkinitcpio` rebuilds into `/boot`, but Limine boots from the ESP at
  `/boot/efi`, and the piece that copies one to the other is the missing hook.
- **Snapshot boot entries are not generated** (that is `limine-snapper-sync`).

Confirm rather than guess — `pacman -Q limine-mkinitcpio-hook limine-snapper-sync`, and
compare what Limine actually loads against the installed kernel:

```
grep -E '^\s*(path|module_path): boot\(\):' /boot/efi/limine.conf
cmp /boot/efi/<machine-id>/linux-zen/vmlinuz /boot/vmlinuz-linux-zen
```

**The repair is one command** (privileged, and it rebuilds the packages from source, so it
takes a few minutes and needs network):

```
sudo bash /var/lib/w/src/scripts/apply.sh --limine
```

It reinstalls the pair, restages the ESP, and re-pins the default boot entry. Never
improvise instead of running it: hand-copying files into the ESP leaves the entries'
BLAKE2B hashes stale, which halts Limine outright once Secure Boot is on.

## Rules of engagement

All of the above that changes system state (kernel, firewall, disk, firmware, packages) is
**privileged** and goes through W's polkit + fingerprint/password prompt, which is
audited. Never attempt to bypass that prompt — the OS enforces authorization.

**The prompt names the account it is asking for** ("Password for user `x`"), and on a
**non-administrator's** session — where polkit accepts any of the machine's admins — it
also offers the list, so the administrator who is actually present can authenticate
without switching users. If a user reports that their own password is rejected at that
prompt, the first thing to check is which name it shows: an admin-level action does not
accept a non-admin's password, no matter who is typing.
