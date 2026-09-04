---
name: bitwarden
description: >-
  Working with the `bitwarden` W-Pack on W Linux: the Bitwarden desktop app as the
  user's password manager and SSH agent — how biometric unlock reaches W's auth
  card through polkit, why the vault needs the login keyring, how `w-ssh` hands the
  SSH agent over and back, and why per-host key selectors (`w-ssh sync`) are needed
  at all. Load this when the user asks about Bitwarden, their password manager,
  vault unlock, biometric/fingerprint unlock of a password manager, SSH keys stored
  in a vault, "too many authentication failures" on ssh or git push, or the browser
  extension's connection to the desktop app, and `w-pack status bitwarden` reports
  installed.
---

# W-Pack: bitwarden

Bitwarden desktop (`bitwarden` from `extra`) wired into the slots W already
provides. W ships **no** password manager and takes no position on which one to
use — this bundle is only the wiring, and every slot it plugs into is
vendor-neutral (see the `w-security` skill and `w-ssh`).

## What the bundle actually did

1. Installed the `bitwarden` package.
2. Pinned the app's agent socket: `BITWARDEN_SSH_AUTH_SOCK=$HOME/.bitwarden-ssh-agent.sock`
   (`/etc/w/env.d/bitwarden.sh`, sourced at graphical-session-pre).
3. Switched the account's SSH agent: `w-ssh use bitwarden` — which masks
   `gcr-ssh-agent.socket` for that user and re-points W's stable
   `SSH_AUTH_SOCK` symlink.
4. Enabled `bitwarden.service` (user unit) so the app starts hidden in the tray
   with the graphical session.

Steps the user must take inside the app (encrypted vault state, not settable from
outside): log in, turn on **Unlock with system authentication**, turn on **Enable
SSH Agent**.

## Biometric unlock goes through polkit — so it is W's own card

Bitwarden implements Linux biometrics as a polkit check on the action
`com.bitwarden.Bitwarden.unlock` (`auth_self`), NOT as its own fingerprint code.
On W that check is answered by **`w-authd`**, so the prompt the user sees is the
W auth card, and the PAM stack behind it is `/etc/pam.d/polkit-1`:
`pam_fprintd.so sufficient`, then `system-auth`. Consequences worth knowing:

- With a finger enrolled (`fprintd-enroll`), the card opens in **fingerprint
  mode** — glyph, no input. After pam_fprintd gives up it converts in place into
  the ordinary password card. That is the "finger failed a few times → asks for
  the Linux password" behaviour, and it is W's card doing it, not Bitwarden's.
- No polkit setup step is needed. The Arch package ships the action file, so the
  app's own `needsSetup()` is false. Do **not** run its auto-setup: it chains a
  `chcon` and would fail on a distro without SELinux.
- The unlock key itself is stored via libsecret in the **login keyring**
  (gnome-keyring). W unlocks that with the login password at greetd, and W's
  greeter has no fingerprint step, so the keyring is always open by the time the
  app starts. If the keyring were ever locked, unlock would fail with a confusing
  error — check `w-security`'s keyring section before blaming Bitwarden.

## SSH: why `w-ssh sync` exists

The agent offers **every** key in the vault, in its own order. `sshd` gives up
after `MaxAuthTries` (6 by default), so with more than six keys the right one is
never reached: `Too many authentication failures`. This is inherent to the agent
protocol — not a W or Bitwarden bug — and the only fix is to tell ssh which key to
offer per host.

`w-ssh sync` builds that from the agent itself: each key's **name in the vault** is
read as the list of hosts it belongs to. Naming an item `GitLab git.example.com`
generates

```
Host GitLab git.example.com
    IdentityFile ~/.ssh/agent-keys/gitlab_git.example.com.pub
    IdentitiesOnly yes
```

into `~/.ssh/config.d/50-w-agent.conf`. The public key on disk is a **selector**,
not a duplicated secret — the private half never leaves the vault.

So the user's workflow is: add a key to Bitwarden, put the host(s) in its name,
run `w-ssh sync`. If `~/.ssh/config` has no `Include config.d/*.conf` yet,
`w-ssh include` adds it at the top (it must be above the first `Host` line, or it
belongs to that block and applies to one host only).

Key listing works while the vault is **locked**, so `w-ssh sync` does not require
an unlock. Signing does — the app prompts to unlock, then to approve.

## Diagnosing

- `w-ssh status` — active agent, whether the socket is live, key count, whether
  the selectors and the Include are in place. Start here for anything SSH.
- `ssh -G <host> | grep -i identit` — what ssh will actually offer for that host.
- Agent dead / "Error connecting to agent": the app is not running. It holds the
  agent, so `systemctl --user status bitwarden.service`.
- To hand SSH back to W's own agent: `w-ssh use gcr` (reversible, no relogin).

## Adjacent, already handled — do not re-solve

- **Clipboard**: copied passwords never enter the clipboard history. `w-cliphist-store`
  drops anything carrying the `x-kde-passwordManagerHint` MIME hint, which the
  Bitwarden desktop sets. See the clipboard section of the `w-apps` skill.
- **Wayland**: the app is Electron and runs natively (`ELECTRON_OZONE_PLATFORM_HINT=wayland`
  session-wide), so no per-app flags.
- **Browser extension**: connects to the desktop app over native messaging, which
  the app sets up itself when browser integration is enabled in its settings.
  Nothing on W's side to configure.
