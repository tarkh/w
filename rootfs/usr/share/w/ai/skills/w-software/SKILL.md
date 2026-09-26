---
name: w-software
description: >-
  How to install and manage software on W Linux: native packages via pacman/yay
  (repo + AUR), Python tools/venvs via uv, where sandboxed third-party GUI apps
  fit (the optional `flatpak` W-Pack), and where toolchains keep their caches
  (why there is no `~/go`). Load this when the user wants to install, remove, or
  find an application, set up a Python environment, or asks about Go/toolchain
  cache paths and home snapshots.
sources:
  - path: .claude/library/package-python.md
    sha256: 0dfe554db6f96ca5b1d267e67c877b14cb3cfdc86988a265d234a378d2c8d790
  - path: .claude/library/home-hygiene.md
    sha256: f71b45a02e308c86fbe243901137b960901f4f59f76dfbf4b3db991dc87d1cfd
tools:
  - w_pacman_install
  - w_pacman_remove
---

# W Software

W has three complementary software channels. Choose by trust and origin:

- **Native packages (`pacman` / `yay`)** — for the base system, W's own components, CLI
  tools, and generally trusted software. Repo packages via `pacman`; AUR packages via
  `yay` (the AUR helper, already installed).
- **Flatpak** — for untrusted or third-party GUI applications, run sandboxed
  (bubblewrap + xdg-desktop-portals). **Optional:** it ships as the `flatpak` W-Pack,
  not in the base system.
- **uv** — for Python CLIs and per-project virtual environments (not a pacman job).

Snap and AppImage are deliberately not used.

## Native packages

- Install: `sudo pacman -S <pkg>` (repo) or `yay -S <pkg>` (repo + AUR).
- Search: `pacman -Ss <term>` (repo), `yay -Ss <term>` (repo + AUR).
- Remove: `sudo pacman -Rns <pkg>`.
- Info / ownership: `pacman -Qi <pkg>`, `pacman -Qo <file>`.
- **Upgrading is done with `w-update`, not ad-hoc `pacman -Syu`** — see the `w-updates`
  skill. Never run bare `pacman -Sy` (partial upgrades break Arch).

Installing packages is a privileged action: it goes through W's normal sudo/polkit prompt.
`w_pacman_install`/`w_pacman_remove` are the curated MCP equivalents (repo-only, one
package-name-per-token, snap-pac snapshots the transaction — on by default).

## Flatpak (sandboxed GUI apps) — optional bundle

Flatpak is **not part of the base system**. It ships as a W-Pack, together with the
Flathub remote, the **Bazaar** store, **Flatseal** (per-app permissions) and W's theme
wiring for the sandbox:

- Is it here? `w-pack status flatpak`. If not: `sudo w-pack install flatpak`.
- Once installed, the bundle curates its own `flatpak` skill (its CLI, theming
  behaviour and gotchas live there) — read that instead of duplicating it here.

If the machine has no Flatpak and the user wants a third-party GUI app, the two honest
options are: install the bundle, or take the app from the repos/AUR.

## Python packages/tools (uv)

`python` + `python-pip` are base packages (one rolling version, tracking whatever Arch
currently ships — no pyenv-style multi-version setup). **`uv` is the only sanctioned way
to actually use Python beyond that** — never suggest a bare system-wide `pip install`
(even `--user`): Arch's `python` is marked PEP 668 externally-managed on purpose, and it
correctly refuses.

- New project venv: `uv venv` (or `uv init` for a new project), then `uv add <pkg>`.
- Run something once without a venv: `uv run <script.py>` / `uv run --with <pkg> ...`.
- Install an isolated global CLI (the pipx job): `uv tool install <pkg>`.
- Need a specific interpreter version: `uv python install 3.11` — downloads into uv's own
  isolated location, does not touch or replace the system `python` package.
- Inside an activated venv, plain `pip install` works as normal — the externally-managed
  guard only applies to the system environment.

`~/.cache/uv` and `~/.cache/pip` are pre-created as nested btrfs subvolumes, so they
don't bloat `@home` snapshots — nothing to do here, just don't be surprised they're not
plain directories. See the next section for the mechanism.

## Where toolchains keep their state (caches, `~/go`)

W steers per-user toolchain state to XDG locations and keeps the big, recoverable
parts out of `@home` snapshots. Two pieces, both W-managed (don't edit them):

- `/etc/profile.d/w-<tool>.sh` — login-shell env; reaches TTY/SSH shells and the
  graphical session alike. Takes effect at the next login. A personal override goes
  in the user's own shell profile — W's file keeps a value that is already set.
- `/usr/share/w/defaults/home-subvols` — the list of home paths carved as nested
  btrfs subvolumes (i.e. excluded from `@home` snapshots) for every account by
  `apply.sh --homesubvol`. Only ever created while the path is absent — an existing
  directory is left alone (and rides in snapshots).

**Go** is the first case: there is deliberately **no `~/go`** on W. `GOMODCACHE` and
`GOCACHE` live in `~/.cache/go/{mod,build}` (one subvolume), `GOPATH` is
`~/.local/share/go` (nearly empty), and `go install` puts binaries in `~/.local/bin`,
which is already on PATH. This matters even without the `dev` bundle: `w-update`
rebuilds `yay` from the AUR as the user, and that build would otherwise create `~/go`.
A `~/go` or `~/.cache/go-build` from before this change is simply stale — safe to
delete, never touched by W. Go itself is not a base package: it arrives as a build
dependency (`pacman -Qdtq` lists it as an orphan afterwards — harmless), or via
`mise` in the `dev` bundle for per-project versions.
