---
name: w-software
description: >-
  How to install and manage software on W Linux: native packages via pacman/yay
  (repo + AUR), sandboxed third-party GUI apps via Flatpak (Flathub, the Bazaar
  store, Flatseal for permissions), and Python tools/venvs via uv. Load this when
  the user wants to install, remove, or find an application, or set up a Python
  environment.
sources:
  - path: .claude/library/package-flatpak.md
    sha256: 9f6e18651f17cb4be183e7859d9ab5b80a85d1a0379ac5f5f0e443382bd0cc88
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
  (bubblewrap + xdg-desktop-portals).
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

## Flatpak (sandboxed GUI apps)

- **GUI store: Bazaar** — W's native software store (GTK4), the primary way to browse and
  install Flatpak apps. Flathub is configured system-wide.
- **CLI:** `flatpak install flathub <app-id>`, `flatpak list`, `flatpak update`,
  `flatpak uninstall <app-id>`, `flatpak run <app-id>`.
- **Permissions: Flatseal** — the GUI to inspect and adjust each app's sandbox permissions
  (filesystem access, devices, etc.).

W applies its theme inside the Flatpak sandbox automatically (colors and icons for
GTK3/GTK4/Qt apps). After switching the system theme, sandboxed apps pick up the new colors
on their next restart (Flatpak cannot live-reload theme extensions).

**Note on per-app overrides:** a per-app override set via `flatpak override --user` (or
Flatseal) shadows W's system-wide theming override. If a Flatpak app's theme/icons/font
look wrong, check `flatpak override --user --show <app>` and reset with
`flatpak override --user --reset <app>` if a stray environment override is the cause.

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
