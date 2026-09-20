# modules/uv.sh — uv (Python venv/tool manager)
# apply.sh context: runs on the live system as root; post-boot only.
#
# W's Python story has two halves. `python` + `python-pip` ride in
# packages/base.txt (pip stays available because it's what seeds a fresh venv
# with itself in the first place — Arch's `python` does not bundle it, and a lot
# of tooling docs still say "pip install X"). This module is the other half:
# **uv is the one sanctioned way to actually create venvs, install Python CLIs,
# or pin an interpreter version on W** — not pipx (same job, redundant), and
# never a bare system-wide `pip install` (Arch marks `python` PEP 668
# "externally-managed" on purpose, to protect pacman-owned files; W does not
# patch that marker away). Inside a venv, `pip install` is fine — that boundary
# is the whole point.
#
# Single rolling Python version, same policy already encoded in ruff.toml
# ("Arch ships current CPython; match it rather than a lowest common
# denominator") — no system multi-version story. A project that genuinely needs
# a non-current interpreter gets it via `uv python install X.Y`, which downloads
# into an isolated uv-managed location and never touches the system `python`
# package.
#
# Cache hygiene: uv's and pip's download caches are large, ephemeral and fully
# recoverable from network — the profile that does not belong inside @home
# snapshots. They ride outside via the home-subvols registry
# (/usr/share/w/defaults/home-subvols → mod_homesubvol), not here. W tracks
# updates for its OWN packages only (w-update, pacman/AUR) — dependencies
# inside a venv are that project's business (lockfiles exist for exactly this
# reason), so there is deliberately no "scan venvs for outdated deps" mechanism.

mod_uv() {
  info "Installing uv (Python venv/tool manager)..."
  w_pac -S --needed --noconfirm uv
}
