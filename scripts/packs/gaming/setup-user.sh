#!/usr/bin/env bash
# gaming bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup gaming` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Three things, all account-scoped: keep the game library out of @home
# snapshots (it can run to hundreds of GiB and is fully recoverable from
# Steam/Lutris/Heroic themselves), the `gamemode` group membership that
# `renice`/`ioprio` in gamemode.ini need (see pack machine layer, meta.conf),
# and Heroic's theme selection — the one launcher of the three whose skinning
# channel is a file W can own, so its first launch is already in W's palette.
#
# Idempotent; best-effort. See pack-gaming.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root over sudo/ssh, or
# a service dir at firstboot) the target user cannot chdir there. Move to a cwd
# they can read.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Game library out of @home snapshots ────────────────────────────────
# Steam's library (games, Proton prefixes under compatdata/, shader cache) and
# the Lutris/Heroic install trees are large, ephemeral (reinstallable from the
# storefront) and exactly the profile that should not ride inside snapper's
# @home timeline. Nested btrfs subvolumes: snapshots are non-recursive, so a
# nested subvolume is excluded natively. Same pattern as mise's toolchains
# (pack-dev, home-hygiene.md "base ↔ pack" boundary) — the pack carves its own
# paths here because this layer runs on `w-pack setup`, not `apply`.
#
# Only acts while the path is ABSENT — a populated directory cannot be
# converted in place. `~/.steam` (symlinks) and `~/.config/heroic` (small
# config) are deliberately not here.
own_dir() {   # create <dir> owned by the account, whichever privilege we hold
  if [[ "$AS_ROOT" == 1 ]]; then install -d -o "$USER_NAME" -g "$USER_NAME" "$1"
  else install -d "$1"; fi
}

exclude_from_snapshots() {
  local dir="$1"
  if [[ -e "$dir" ]]; then
    if btrfs subvolume show "$dir" >/dev/null 2>&1; then
      info "$dir already a subvolume — nothing to do."
    else
      warn "$dir already exists as a regular dir — leaving as-is (rides in @home snapshots)."
    fi
    return 0
  fi
  # Subvolume creation is permitted for whoever may write the parent directory, so
  # this works for an account catching itself up, not only for root.
  if as_user btrfs subvolume create "$dir" >/dev/null 2>&1; then
    [[ "$AS_ROOT" == 1 ]] && chown "$USER_NAME:$USER_NAME" "$dir"
    info "Created nested subvolume $dir (excluded from @home snapshots)."
  else
    own_dir "$dir"
    warn "$dir not on btrfs (or subvolume create failed) — plain dir, no snapshot exclusion."
  fi
}

if [[ -d "$USER_HOME" ]]; then
  info "Keeping the game library out of @home snapshots for $USER_NAME..."
  own_dir "$USER_HOME/.local/share"
  exclude_from_snapshots "$USER_HOME/.local/share/Steam"
  exclude_from_snapshots "$USER_HOME/Games"
  exclude_from_snapshots "$USER_HOME/.local/share/lutris"
fi

# ── 2. Group `gamemode` membership ─────────────────────────────────────────
# gamemode.ini's [general] renice/ioprio (machine layer, gamemode.ini) only
# take effect for members of this group — gamemoded checks it itself before
# raising priority. `usermod -aG` adds the group; the effect is at the NEXT
# login (a new group list is read at session start, not mid-session).
info "Adding $USER_NAME to group 'gamemode' (renice/ioprio while a game runs)..."
if [[ "$AS_ROOT" == 1 ]]; then
  if usermod -aG gamemode "$USER_NAME" >/dev/null 2>&1; then
    info "$USER_NAME added to group 'gamemode'."
  else
    warn "usermod -aG gamemode failed — the account may already be a member, or usermod errored."
  fi
else
  # Adding a user to a group is root's call (it edits /etc/group). An account
  # catching itself up without root gets the exact command to ask for — a silent
  # skip would leave it without renice/ioprio with no clue why.
  if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx gamemode; then
    info "$USER_NAME is already in group 'gamemode' — nothing to do."
  else
    warn "$USER_NAME is not in group 'gamemode'. Only an administrator can add it:"
    warn "    sudo usermod -aG gamemode $USER_NAME"
    warn "  then log out and back in (group membership applies at login), and re-run:"
    warn "    w-pack setup gaming"
  fi
fi

if getent group gamemode >/dev/null 2>&1; then
  : # group present
else
  warn "group 'gamemode' not found — the gamemode package's sysusers did not create it?"
  warn "  The package may not be installed yet; re-run after 'sudo w-pack install gaming'."
fi

# ── 3. Heroic in W's colours ───────────────────────────────────────────────
# Two halves, and both are needed before Heroic's first launch for the window to
# come up in W's palette (pack-gaming.md "Ось темы — Heroic"):
#   a) render the bundle's `heroic` axis into THIS account. w-pack already ran
#      it as root, which writes /etc/skel (future accounts only) — this is the
#      catch-up pass for an account that exists now.
#   b) point Heroic at the rendered file: `customThemesPath` in config.json and
#      `theme` in store/config.json. Neither has an external apply channel, but
#      both files are plain JSON merged over Heroic's defaults, so they can be
#      written before the app ever runs (heroic-seed.py explains the one
#      upstream trap that dictates what a from-scratch seed must contain).
# A running Heroic is skipped: it rewrites config.json on any settings change
# and would race us. The process is `heroic` (/opt/Heroic/heroic, symlinked to
# /usr/bin/heroic), not the package name.
heroic_conf="$USER_HOME/.config/heroic"
heroic_css="$heroic_conf/themes/w.css"
heroic_themed=0

if [[ -d "$USER_HOME" ]] && command -v w-style >/dev/null; then
  info "Rendering the Heroic palette for $USER_NAME..."
  as_user w-style apply heroic \
    || warn "w-style apply heroic failed (renders at next login instead)."
else
  info "w-style not available yet — the heroic axis renders at next login."
fi

if [[ ! -s "$heroic_css" ]]; then
  warn "No rendered stylesheet at $heroic_css — not selecting it (renders at next login)."
elif pgrep -u "$USER_NAME" -x heroic >/dev/null 2>&1; then
  warn "Heroic is running — not touching its config (quit it and run 'w-pack setup gaming')."
else
  as_user python3 "$BUNDLE_DIR/heroic-seed.py" \
    --config-dir "$heroic_conf" --theme "$heroic_css"
  case $? in
    0) heroic_themed=1; info "Heroic is set to W's theme (visible at its next launch)." ;;
    3) heroic_themed=1; info "Heroic already points at W's theme — nothing to do." ;;
    4) info "W's palette is listed in Heroic as 'w.css'; select it under"
       info "  Settings → General → Select Theme when you want it." ;;
    *) warn "Could not select W's theme in Heroic — pick 'w.css' by hand in"
       warn "  Settings → General → Select Theme (after setting Custom Themes Path"
       warn "  to $heroic_conf/themes)." ;;
  esac
fi

info "gaming user setup complete for $USER_NAME."
info "  Snapshot exclusions apply immediately; group membership at the NEXT login."
if [[ $heroic_themed == 1 ]]; then
  info "  Heroic's colours come from the active W theme; 'w-theme set' recolours it"
  info "  at its next launch (Heroic reads the stylesheet only when it starts)."
fi
exit 0
