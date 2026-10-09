#!/usr/bin/env bash
# audio bundle — PREPARE step. Run by `w-pack install` BEFORE pkgs.txt, always
# as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# One thing has to happen before the package layer resolves: the JACK API must
# come from PipeWire. The base system already has a `jack` provider — jack2,
# pulled in by ffmpeg/mpv/portaudio — and Ardour links libjack. Under jack2
# there is no JACK server running, so Ardour's JACK backend has nothing to talk
# to and only raw ALSA is left, which PipeWire already holds ("device busy").
# pipewire-jack is the same libjack, served by the running PipeWire.
#
# It conflicts with jack2, and a non-interactive pacman answers "Remove jack2?
# [y/N]" with N — the transaction fails. `--ask=4` (ALPM_QUESTION_CONFLICT_PKG)
# answers yes to exactly that question and nothing else. `--asdeps`: it is
# pulled in for the apps, not asked for by name — and it must NOT be in
# pkgs.txt, or `remove --packages` would take away the `jack` that ffmpeg
# itself depends on. teardown.sh leaves it in place (see there).
#
# Not run by `w-pack refresh`. Idempotent; a failure here is fatal — without
# the swap Ardour installs but cannot open an audio device.

set -uo pipefail

info() { echo -e "  \033[1;35m->\033[0m $*"; }
err()  { echo -e "  \033[1;31mERROR:\033[0m $*" >&2; }

if pacman -Q pipewire-jack >/dev/null 2>&1; then
  info "pipewire-jack already provides the JACK API."
  exit 0
fi

info "Replacing jack2 with pipewire-jack (the JACK API served by PipeWire)..."
if ! pacman -S --needed --noconfirm --asdeps --ask=4 pipewire-jack; then
  err "could not install pipewire-jack — Ardour would have no audio device."
  exit 1
fi
exit 0
