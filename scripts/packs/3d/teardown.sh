#!/usr/bin/env bash
# 3d bundle — MACHINE teardown, the declared inverse of setup.sh and pre.sh. Run
# by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# Nothing to undo here: setup.sh only verifies; the manifest rows, the w-style
# axis, the AI skill and the mcp.d drop-in are unwound by w-pack itself. The
# Cycles GPU runtime pre.sh added is an optional dependency installed --asdeps:
# once blender is gone (`remove --packages`) it shows up in `pacman -Qdt` and
# leaves with the next orphan sweep — not removed here, because another
# consumer (ROCm/oneAPI apps) may still use it.

set -uo pipefail

echo -e "  \033[1;35m->\033[0m 3d: nothing to undo on the machine (the Cycles GPU runtime, if any, is an --asdeps optional dependency)."
exit 0
