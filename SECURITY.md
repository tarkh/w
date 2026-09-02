# Security Policy

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

## Supported versions

Only the latest release. W is a rolling distribution with a single published
branch; there are no maintenance branches and no backports.

## What W does not promise yet

Stated plainly, because a beta that overstates its guarantees is worse than one
that does not:

- **Releases are not signed yet.** Tags and packages carry no cryptographic
  signature at present, so the integrity of an update rests on HTTPS and on GitHub.
  Signed releases are planned (see the update-system roadmap, phase 7) and are a
  prerequisite for calling W production-ready.
- **There is no drift detection.** If something on your machine modifies a
  W-managed file, the next update overwrites it without telling you.
- **The AI layer is opt-in and off by default.** Enabling it gives a model the
  ability to request privileged actions, each one gated by polkit. That gate is the
  boundary — treat everything behind it as trusted and everything in front of it as
  not.
