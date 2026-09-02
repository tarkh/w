#!/usr/bin/env bash
# dev bundle — MACHINE layer. Run by `w-pack install` AFTER packages, config
# (manifest) and the w-style axes are in place, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# One machine-wide step: the `zed` command name. Everything that reaches a home —
# the legacy-git advisory, the mise storage subvolumes, the first theme render —
# is in setup-user.sh, so a second account can catch itself up with `w-pack setup
# dev` instead of being told the bundle is "installed" while none of it is theirs.
#
# Idempotent; best-effort — a hiccup warns rather than aborting (packages + config
# are already deployed). See pack-dev.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. `zed` → `zeditor` ─────────────────────────────────────────────────────
# Arch ships the binary as `zeditor` (the name `zed` is taken by the ZFS event
# daemon), while every upstream doc, muscle memory and $EDITOR-style invocation
# says `zed`. Provide the familiar name in /usr/local/bin (ahead of /usr/bin in
# PATH), but never shadow a real `zed` binary that something else owns.
LINK="/usr/local/bin/zed"
if [[ -x /usr/bin/zeditor ]]; then
  if [[ -L "$LINK" ]]; then
    ln -sfn /usr/bin/zeditor "$LINK"          # refresh our own symlink (idempotent)
    info "zed -> zeditor symlink refreshed."
  elif [[ -e "$LINK" ]]; then
    warn "$LINK exists and is not a symlink — leaving it alone (use 'zeditor')."
  elif command -v zed >/dev/null 2>&1; then
    warn "another 'zed' is already on PATH ($(command -v zed)) — not shadowing it."
  else
    ln -s /usr/bin/zeditor "$LINK"
    info "Created $LINK -> /usr/bin/zeditor."
  fi
else
  warn "/usr/bin/zeditor not found — did the 'zed' package install?"
fi

info "dev machine setup complete."
exit 0
