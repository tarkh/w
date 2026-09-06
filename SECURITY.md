# Security Policy

**English** · [Русский](docs/ru/SECURITY.md)

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report it privately through GitHub's
[security advisory form](https://github.com/tarkh/w/security/advisories/new).
That opens a private thread visible only to you and the maintainer.

What to include: what an attacker can do, how to reproduce it, and which version
(`IMAGE_VERSION` in `/etc/os-release`) you saw it on.

You will get an acknowledgement within a few days. W is a one-person project, so
please read that as a best effort rather than a service-level commitment. Fixes
ship in the next release, with credit in the release notes unless you would rather
stay anonymous.

## Scope

W is a distribution: most of the code running on a W machine is upstream Arch
software, not W's own. Issues in upstream packages belong with their maintainers.

W's own attack surface, and what this policy covers:

- The installer (`scripts/install.sh` and its modules) — it runs as root, handles
  passwords and LUKS keys, and writes the initial system
- The update path — `w-sync`, `apply.sh` and the module manifests, which fetch and
  apply code as root
- Privileged helpers — the polkit actions and the authentication agent under
  `rootfs/usr/lib/w/`, and anything that decides *whether* to elevate
- The AI layer — the boundary between reading system state and changing it, and
  the polkit gate in front of every action that changes something
- Anything shipped that weakens a system relative to stock Arch: sudo, firewall,
  DNS, kernel hardening, keyring, Secure Boot

## How updates are trusted

W updates itself over the `edge` channel: `/var/lib/w/src` is a git checkout of the
public repository, and `w-sync` fast-forwards it and then runs `apply.sh` as root.
That makes the release signature, not the transport, the thing that decides whether
code runs on your machine as root.

- Every release is one commit on the public branch, tagged `vX.Y.Z`, and both the
  tag and the commit are signed with the W release key.
- Before it pulls anything, `w-sync update` requires the incoming tip to carry a
  `vX.Y.Z` tag signed by a key in `/usr/share/w/update/w-release.allowed_signers`,
  and refuses outright otherwise — before the pre-update snapshot, so a refused
  update leaves the machine untouched. `w-sync status` shows whether this is armed.
- That anchor file ships in the installation image, and is read only from the
  installed copy — never from the checkout being verified. A new anchor can
  therefore only arrive through an update that verified against the previous one,
  which is what makes key rotation a signed operation rather than a way in.
- The rolling `edge` tag, which the nightly workflow moves to the current install
  image, is never accepted as a release: CI holds no signing key, and it should not.
- The signing key is not stored in this repository, on the build machines, or in
  CI. A release is signed on the maintainer's machine, through an agent.

An update also tells you before it overwrites work of your own: `w-sync update`
compares every W-managed file it is about to replace against the revision you are
coming from, and warns about the ones you edited by hand. `w-reset check` audits the
whole machine the same way, separating files an update will overwrite from your own
customisations, which it never touches.

If you are tracking a fork rather than the official repository, there are no signed
release tags to find, and the installer records that on your machine
(`VERIFY_SIGNATURE=no` in `/etc/w/update.conf`). Updates then rest on the transport
alone — the position everyone was in before signing existed.

## Supported versions

Only the latest release. W is a rolling distribution with a single published
branch; there are no maintenance branches and no backports.

## What W does not promise yet

Stated plainly, because a beta that overstates its guarantees is worse than one
that does not:

- **Only the edge channel is signed.** Edge releases are signed and verified (see
  "How updates are trusted" above). The `stable` channel — W delivered as a pacman
  package from a W repository — is not built yet, and when it is it will need its
  own packager key. Until then, `stable` is not a channel you can be on.
- **Rollback after a bad update is manual.** An update takes a snapshot of your home
  before it applies, and `w-rollback` walks you through restoring a snapshot, but
  nothing reverts a failed apply on its own.
- **The AI layer is opt-in and off by default.** Enabling it gives a model the
  ability to request privileged actions, each one gated by polkit. That gate is the
  boundary — treat everything behind it as trusted and everything in front of it as
  not.
