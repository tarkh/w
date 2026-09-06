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
    sha256: f406324ae9e0c67ff4c0e72a0439ad46f79368a92ae7ad58b928e69db0f3f486
  - path: .claude/library/w-fingerprint.md
    sha256: b90c064967fe921e5caa2992fbf049f310fc1820cba8eec937e25306171a8f69
  - path: .claude/library/w-ssh.md
    sha256: 34bbf5becbefc07d81b82f475b37fa1e32b8ed0e969f0d88ab07ec9e6208ab79
  - path: .claude/library/package-limine.md
    sha256: 5951a5fff90962e7eb7045b4c8967a84a94b228fab59c6e4548921b32297889a
tools:
  - w_fwupd_refresh
---

# W Security

W ships a modern, minimal-but-sufficient security baseline. Wayland/Hyprland already
isolate input and screen capture; fingerprint + PAM + the lock screen + polkit handle
authentication; btrfs + Snapper + snap-pac provide rollback; Arch rolling delivers fast
CVE fixes. On top of that:

## Kernel & hardening — `w-kernel`

The default kernel is `linux-zen` (not `linux-hardened`, which would break Flatpak's user
namespaces and DKMS). sysctl and boot-cmdline hardening are applied as a profile.

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

Three things worth knowing before you diagnose anything:

- **`available=no` does not mean the device is missing.** fprintd answers only an
  **active session**, so a fingerprint command run over SSH or from another VT reports
  `reason=unauthorized` while the reader is sitting right there. Tell the user to run it
  from their desktop session; `reason=no-device` is the one that means "check the hardware".
- **The reader takes a single claim.** While an enrolment is running, authentication by
  finger is unavailable — and vice versa, an enrolment started while the password dialog
  is asking for a finger fails with `busy`. That is not a bug; wait and retry.
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

## Disk encryption & Secure Boot (encrypted installs only)

On an encrypted install, W uses LUKS2 (Argon2id) + TPM2 auto-unlock + a passphrase
fallback, with **Limine** as the bootloader and snapshot-boot support. Two tools manage it
(run with `sudo`):

- `w-crypt status | enroll-tpm | reenroll-tpm | recovery-add | wipe-tpm` — TPM2 auto-unlock
  enrollment and a printable recovery key.
- `w-secureboot status[--porcelain] | enable | disable | setup | sign | reenroll` — Secure
  Boot via sbctl. **`enable`/`disable` are the entry points** (also what the Hub's Security
  control runs — the System panel's **Security** tab, which is present only on the
  encrypted+Limine install path, since a plain GRUB system ships no sbctl at all). TPM2 auto-unlock is sealed to PCR7, which measures the Secure Boot policy, so
  toggling SB always breaks it — but PCR7 is only measured by the firmware/bootloader at
  boot time, not live, so `enable` **cannot** enroll the sbctl keys and re-seal TPM2 in one
  shot: doing both in the same session seals against the still-old PCR7 and the disk would
  keep asking for its passphrase forever. `enable` is therefore two calls with a reboot in
  between: the first enrolls the keys and asks for a reboot (no TPM prompt yet); after
  rebooting, run `enable` again to actually re-seal TPM2 (one disk-passphrase prompt), which
  only proceeds if a reboot genuinely happened since enrollment (tracked by boot ID) — this
  protects against silently reproducing the same broken seal. `status --porcelain`'s 4th
  field, `tpm_pending` (`no`/`reboot_needed`/`ready`), tells you which phase you're in; the
  Hub surfaces this as a "Finish enabling" row under the toggle rather than lying that it's
  simply "On". `disable` is a single call: it removes TPM2 first (the passphrase prompt
  returns immediately) *then* resets the sbctl keys back to Setup Mode — no PCR timing
  issue there since nothing needs to match a future boot. `enable`'s first call still
  requires the firmware to already be in Setup Mode (a manual UEFI step); the older
  `setup`/`sign`/`reenroll` remain for manual/advanced use and are what `enable` calls
  under the hood.
- **The installer never turns Secure Boot on, and does not ask about it.** Enrolling keys
  needs the firmware in Setup Mode and switching SB on needs a UEFI toggle plus a reboot —
  none of which an installer can do. A fresh encrypted install therefore boots with SB off
  and asks for the LUKS passphrase every time; both are expected. The order that works is
  Secure Boot first, TPM2 auto-unlock second (that is what `enable` does): sealing TPM2
  while SB is off is close to pointless, because PCR7 then reads the same for any medium
  someone boots, so the TPM would hand the key to a USB stick just as readily.

These tools are only present on encrypted/Limine installs; on a standard install the
bootloader is GRUB and neither applies.

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
