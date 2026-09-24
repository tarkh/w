#!/usr/bin/env bash
# localsend bundle — MACHINE layer. Run by `w-pack install`/`refresh`, with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Everything here is host-wide: the firewalld service definition is already on
# disk (manifest, deployed before this script runs — see packs.md's install
# order), this just turns it on for the `home` zone. Not `public`: LocalSend
# stays unreachable on someone else's Wi-Fi, exactly like the rest of W's LAN
# services (mDNS, Samba).
#
# Idempotent; best-effort. See pack-localsend.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

if ! command -v firewall-cmd &>/dev/null || ! firewall-cmd --state &>/dev/null; then
  warn "firewalld not available — LocalSend will not be reachable until you open 53317/tcp+udp yourself."
  exit 0
fi

if firewall-cmd --reload >/dev/null && firewall-cmd --permanent --zone=home --add-service=localsend >/dev/null \
   && firewall-cmd --reload >/dev/null; then
  info "Opened the 'localsend' service (53317/tcp+udp) in the 'home' firewall zone."
else
  warn "could not add the localsend service to the 'home' zone — run manually:"
  warn "  firewall-cmd --permanent --zone=home --add-service=localsend && firewall-cmd --reload"
fi

info "localsend machine setup complete."
exit 0
