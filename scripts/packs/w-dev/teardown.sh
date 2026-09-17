#!/usr/bin/env bash
# w-dev bundle — MACHINE layer teardown, the declared inverse of setup.sh.
# Run by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# setup.sh did one thing: it fetched pacman's files database. The correct inverse
# is to leave it alone. The bundle populated that database but never owned it —
# it is pacman's, it is shared (the "command not found" handler reads it, so does
# anyone running `pacman -F`), and deleting it would take a facility away from a
# machine that did not ask this bundle to manage it. Removing a pack undoes what
# W wired, not what W merely warmed up.
#
# The packages are w-pack's own business: `remove --packages` takes them, minus
# whatever another installed bundle still lists. Nothing for this file to add.
#
# It exists rather than being absent because check.sh requires a teardown half for
# every setup half: "there is nothing to undo" is an answer a bundle should have
# to state, not one a reader should have to infer from a missing file.
#
# See pack-w-dev.md.
set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }

info "Leaving the pacman files database in place (it is pacman's, not this bundle's)."
info "w-dev machine teardown complete."
exit 0
