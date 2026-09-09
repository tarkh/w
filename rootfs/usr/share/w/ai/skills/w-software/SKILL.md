---
name: w-software
description: >-
  How to install and manage software on W Linux: native packages via pacman/yay
  (repo + AUR), Python tools/venvs via uv, and where sandboxed third-party GUI apps
  fit (the optional `flatpak` W-Pack). Load this when the user wants to install,
  remove, or find an application, or set up a Python environment.
sources:
  - path: .claude/library/package-python.md
    sha256: 239b463324c3f42931b26b09ac082e0d525c2ff706857045c3bd7f37e33fac17
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

`~/.cache/uv` and `~/.cache/pip` are pre-created as nested btrfs subvolumes (`apply.sh
--uv`), so they don't bloat `@home` snapshots — nothing to do here, just don't be
surprised they're not plain directories.
