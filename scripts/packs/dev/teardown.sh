#!/usr/bin/env bash
# dev bundle — MACHINE layer teardown, the declared inverse of setup.sh. Run by
# `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# One machine-wide step to undo: the `zed` command name. setup.sh only ever
# creates /usr/local/bin/zed when it is free to do so — it refuses to shadow a
# real binary and refuses to overwrite a non-symlink — so the teardown has to be
# just as narrow: remove it ONLY if it is still OUR symlink, pointing where we
# pointed it. Anything else on that path belongs to someone else.
#
# Idempotent; best-effort. See pack-dev.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

LINK="/usr/local/bin/zed"

if [[ -L "$LINK" ]]; then
  if [[ "$(readlink "$LINK")" == "/usr/bin/zeditor" ]]; then
    rm -f "$LINK"
    info "Removed $LINK (the zed -> zeditor name this bundle provided)."
  else
    warn "$LINK points at $(readlink "$LINK") — not ours, leaving it alone."
  fi
elif [[ -e "$LINK" ]]; then
  warn "$LINK exists and is not a symlink — not ours, leaving it alone."
fi

info "dev machine teardown complete."
exit 0
