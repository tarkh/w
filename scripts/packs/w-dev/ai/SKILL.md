---
name: w-dev
description: >-
  Developing W Linux itself on a machine that runs W, with the `w-dev` W-Pack: the
  four tiers the work is split across (host tooling, disposable containers, the
  live host as a target, the development VM) and the rules that keep the host
  clean while it is also the machine under test. Load this when the user is
  working ON W — running scripts/check.sh, building the ISO, running the e2e
  install, applying a module to this machine, or asking what is safe to try on the
  host — and `w-pack status w-dev` reports installed. Not for operating an
  installed W: that is the other skills' job.
---

# W-Pack: w-dev

The toolchain for developing **W itself** on a machine that runs W. Curated into
`/usr/share/w/ai/skills/w-dev/` when the bundle is installed. Present only if
`w-pack status w-dev` reports installed — on a user's machine this file does not
exist, and neither does the bundle in any catalogue.

## The situation this skill is for

The development box runs W from the **dev-edge channel**, so it is simultaneously
the machine W is written on and a machine W is installed on. Two git checkouts
exist and they are not the same thing:

| Checkout | Remote | What it is |
|---|---|---|
| the dev repo (e.g. `~/Dev/w-linux`) | GitLab, SSH | where W is edited; can be ahead of everything |
| `/var/lib/w/src` | GitLab, HTTPS token | **what runs this machine** — `w-sync` pulls here and applies |

Never edit `/var/lib/w/src`. It is a delivery target, not a workspace; `w-sync`
pulls it `--ff-only` and a local change there stops updates dead.

## The four tiers

Work is assigned to a tier by what it needs, not by preference. Putting a job on
the wrong tier is how the host gets cluttered or the checks go quietly hollow.

**Tier A — on the host, declared by this bundle.** `shellcheck`, `ruff`, `bats`,
`gh`. Things that must be local because an editor's LSP cannot reach into a
container and because the edit→check loop has to cost seconds.

```bash
bash scripts/check.sh          # all offline suites, seconds
bash scripts/check.sh --bash   # one suite
bash scripts/check.sh --online # adds package-existence checks (network)
```

**Tier B — a disposable container, nothing on the host.** The reference run, the
ISO build and the end-to-end install. These need root, loop devices, archiso and
QEMU; none of that belongs on a working machine.

```bash
ci/iso-build-container.sh --check-only   # scripts/check.sh --online --strict
ci/iso-build-container.sh                # ...then build the ISO
ci/e2e-container.sh --encrypted          # LUKS2 + Limine + TPM2 install test
ci/e2e-container.sh                      # plain btrfs + GRUB
```

Rootful podman (`sudo`) and `/dev/kvm` are the only host requirements. The `--strict`
run is the honest one: it turns "this tool is absent" into a failure, so no suite
can step aside unnoticed. **When asked whether the tree is green, this is the
answer** — a bare `scripts/check.sh` on a host missing a linter reports green over
work it never inspected.

**Tier C — the live host as the target.** The reason for developing on real
hardware: a GPU, a fingerprint reader, a Bluetooth radio and a real display stack
that no VM reproduces. Two roads:

- *the normal one* — commit, `git push origin main`, then `sudo w-sync update` on
  this machine. This is the path a user's machine takes, which is exactly why it
  is worth taking here.
- *the fast one* — `sudo bash scripts/apply.sh --<module>` straight from the dev
  checkout, skipping git entirely.

**The fast road has no safety net of its own**, and this matters: `w-sync update`
takes a pre-snapshot of `@home` only, and root snapshots come from `snap-pac`,
which fires on **pacman transactions**. A module that only rewrites config files
(`--rootfs`, `--style`, `--hyprland`, `--quickshell`) therefore changes the running
system with nothing to roll back to. So:

```bash
sudo snapper -c root create --description "pre-apply <module>"   # always, first
sudo W_APPLY_ON_HOST=1 bash scripts/apply.sh --<module>
```

`apply.sh` refuses to run on a machine that is not the development VM unless
`W_APPLY_ON_HOST=1` is set — the guard exists because the script was written for a
disposable guest and says so in its own header.

Modules that touch boot are a different risk class and are **VM-first, always**:
`--limine`, `--grub`, `--plymouth`, and `--packages` when it pulls a kernel. A bad
config is an ugly desktop; a bad bootloader is a machine that does not start. If
one of these has to be tried on the host, take the snapshot, know that
`/usr/share/doc/w/RECOVERY.md` is the paper trail, and that this machine boots
through Limine (encrypted install) so recovery goes through
`w-rollback` → `limine-snapper-restore`.

**Tier D — the development VM.** `vm/start.sh`, live repo share over virtiofs,
`apply.sh` inside the guest in seconds. The daily driver for UI and installer
work, and the only correct place for anything in the boot path. Needs the
`virt` bundle.

## Keeping the host clean

One rule, and it is the whole strategy: **nothing is installed on this machine by
hand.** Whatever has to be here is declared in the repository — `packages/*.txt`
for the base, `scripts/packs/<bundle>/pkgs.txt` for a bundle — and arrives through
`w-pack`. Then the machine is self-describing (`w-pack list`, `w-pack status`) and
reversible (`w-pack remove <bundle> --packages`), and no one has to remember what
they added six months ago.

To check the rule is holding, compare what is installed against what is declared:

```bash
w-pkg-audit        # explicitly-installed packages the repository does not declare
```

A non-empty list is not automatically wrong — it is a list of decisions that were
never written down, and each one should end up declared, removed, or explained.

## Gotchas

- **`w-dev` is invisible in catalogues until installed** (`AUDIENCE=maintainer`).
  It is not missing; `w-pack list --all` shows it. Once installed it lists like any
  other bundle — a machine must be able to say what is on it.
- **`pacman -Fy` goes stale.** `setup.sh` fetched it once for the `paths` suite's
  collision probe; refresh it with a system update, or that probe silently skips.
- **A green `scripts/check.sh` is not a green tree** unless the three tool-backed
  suites actually ran. Read the `skip` lines, or use Tier B.
- **`/var/lib/w/src` is not the workspace.** See the table above.
