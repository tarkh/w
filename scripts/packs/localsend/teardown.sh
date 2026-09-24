#!/usr/bin/env bash
# localsend bundle — MACHINE teardown, the declared inverse of setup.sh. Run by
# `w-pack remove`, with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES
#
# Removes the firewalld rule setup.sh added. The service definition itself
# (manifest row) is removed separately by w-pack right after this runs — order
# does not matter here, `--remove-service` on an already-gone definition is a
# harmless no-op.
#
# Idempotent; best-effort. See pack-localsend.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }

if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
  firewall-cmd --permanent --zone=home --remove-service=localsend >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  info "Closed the 'localsend' firewall service in the 'home' zone."
fi

info "localsend machine teardown complete."
exit 0
