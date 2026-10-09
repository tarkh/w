#!/usr/bin/env bash
# audio bundle — MACHINE teardown, the declared inverse of setup.sh and pre.sh.
# Run by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# Nothing to undo here: setup.sh only verifies; the manifest rows, the w-style
# axes, the AI skill and the mcp.d drop-in are unwound by w-pack itself, group
# membership by teardown-user.sh. pipewire-jack (pre.sh) stays on purpose, even
# with --packages: it is now the system's `jack` provider, which ffmpeg, mpv and
# portaudio depend on — swapping jack2 back would be a change nobody asked for,
# and pacman would refuse to leave `jack` unprovided anyway.

set -uo pipefail

echo -e "  \033[1;35m->\033[0m audio: nothing to undo on the machine (pipewire-jack stays the system's JACK provider)."
exit 0
