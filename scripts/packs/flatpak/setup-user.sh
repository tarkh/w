#!/usr/bin/env bash
# flatpak bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup flatpak` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Two things a Flatpak sandbox can only get out of ONE account's home:
#   1. the Papirus icon mirror — /usr/share/icons is blacklisted by flatpak and
#      Flathub has no Papirus Icontheme extension, so the icons must sit in
#      ~/.local/share/icons, which the global override binds as xdg-data/icons:ro.
#   2. the Gtk3theme extensions the sandbox mounts for GTK3 apps — built by the
#      w-style `gtk` axis in USER scope (sync_flatpak_gtk3). env-hyprland renders
#      the user bundle at every login, so this render is only about NOW: without it
#      the first sandboxed GTK3 app before the next login would be unthemed.
#
# A second account gets neither until it runs `w-pack setup flatpak` — deliberate:
# both cost that account's disk, and neither is a choice anyone else can make for
# them (packs.md, "two layers"). Idempotent; best-effort. See pack-flatpak.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"
USER_UID="$(id -u "$USER_NAME")"
RUNDIR="/run/user/$USER_UID"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root over sudo/ssh, or a
# service dir at firstboot) the target user cannot chdir there. Move to their home.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Run a command as the target user. XDG_RUNTIME_DIR is passed explicitly because
# runuser otherwise leaves ROOT's value in the environment.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$RUNDIR" "$@"
  else "$@"; fi
}

# ── 1. Papirus mirror into the account's home (the bindable path) ────────────
# Papirus-Dark is mostly symlinks into the Papirus base, so BOTH dirs are copied.
# Source and homes share the btrfs volume, so cp --reflink=auto is copy-on-write —
# instant and ~zero extra space (verified: btrfs fi du Exclusive 0.00B). W icons are
# static across themes (name + folder hue are constants) and the system theme is
# already retinted by the icons axis when we get here (packs install after
# apply --all), so the copy carries the current W folder hue. The axis re-retints
# this mirror on every `w-style apply icons`, keeping host and sandbox in sync.
info "Mirroring Papirus icons into $USER_HOME for the sandbox..."
icondir="$USER_HOME/.local/share/icons"
if [[ "$AS_ROOT" == 1 ]]; then install -d -o "$USER_NAME" -g "$USER_NAME" "$icondir"
else install -d "$icondir"; fi
for d in Papirus Papirus-Dark; do
  [[ -d "/usr/share/icons/$d" ]] || continue
  rm -rf "${icondir:?}/$d"
  if cp -a --reflink=auto "/usr/share/icons/$d" "$icondir/$d"; then
    [[ "$AS_ROOT" == 1 ]] && chown -R "$USER_NAME:$USER_NAME" "$icondir/$d"
  else
    warn "could not mirror /usr/share/icons/$d — sandboxed apps fall back to stock icons"
  fi
done

# ── 2. Build the sandbox's GTK3 theme extensions now ─────────────────────────
# User scope only (sync_flatpak_gtk3 returns early for root), hence as_user even
# when we are root. A failure here costs nothing permanent: the next login renders
# the same axis.
info "Rendering the gtk axis for $USER_NAME (builds the sandbox Gtk3theme extensions)..."
as_user w-style apply gtk || warn "w-style apply gtk failed — the extensions build at next login"

info "flatpak user setup complete for $USER_NAME."
exit 0
