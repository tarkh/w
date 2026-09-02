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
# recoverable from network — exactly the profile that does not belong inside
# @home snapshots. Both get carved into nested btrfs subvolumes, which snapper's
# non-recursive snapshots naturally exclude (same reasoning/pattern as the
# containers pack's rootless storage, see pack-containers.md). W tracks updates
# for its OWN packages only (w-update, pacman/AUR) — dependencies inside a venv
# are that project's business (lockfiles exist for exactly this reason), so
# there is deliberately no "scan venvs for outdated deps" mechanism here.

mod_uv() {
  info "Installing uv (Python venv/tool manager)..."
  w_pac -S --needed --noconfirm uv

  # Per human account: every user builds their own venvs, so every user's caches
  # need the same snapshot exclusion (see lib/deploy.sh w_home_users).
  local -a wusers=(); local entry wuser home_dir d
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || echo "  WARN: no W user account found (uid 1000-65533), skipping cache subvolume setup."
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Excluding uv/pip caches from @home snapshots for $wuser..."
    install -d -o "$wuser" -g "$wuser" "$home_dir/.cache"
    for d in uv pip; do
      _uv_exclude_cache_dir "$home_dir/.cache/$d" "$wuser"
    done
  done
}

# Create $1 as a nested btrfs subvolume (owned by $2) if it doesn't exist yet, so
# it rides outside @home snapshots (snapshots are non-recursive — a nested
# subvolume is naturally excluded). An existing populated dir cannot be converted
# in place, so this only acts while the path is absent — same constraint as the
# containers pack's rootless storage setup.
_uv_exclude_cache_dir() {
  local dir="$1" owner="$2"
  if [[ ! -e "$dir" ]]; then
    if btrfs subvolume create "$dir" >/dev/null 2>&1; then
      chown "$owner:$owner" "$dir"
      info "Created nested subvolume $dir (excluded from @home snapshots)."
    else
      install -d -o "$owner" -g "$owner" "$dir"
      echo "  WARN: $dir not on btrfs (or subvolume create failed) — plain dir, no snapshot exclusion."
    fi
  elif btrfs subvolume show "$dir" >/dev/null 2>&1; then
    info "$dir already a subvolume — nothing to do."
  else
    echo "  WARN: $dir already exists as a regular dir — leaving as-is (will ride in @home snapshots)."
  fi
}
