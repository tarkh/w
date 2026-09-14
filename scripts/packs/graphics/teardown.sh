#!/usr/bin/env bash
# graphics bundle — MACHINE teardown, the declared inverse of setup.sh. Run by
# `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# Nothing to undo: setup.sh only verifies. The packages are pacman's subject
# (w-pack prints / runs the -Rns line itself), the MCP drop-ins and the
# per-account plug-in and uv tool are unwound by w-pack and teardown-user.sh.
# Written out so the symmetry gate (setup ⇒ teardown) records the decision
# rather than a reader inferring it from a missing file.

set -uo pipefail

echo -e "  \033[1;35m->\033[0m graphics: nothing to undo on the machine (setup.sh only verifies)."
exit 0
