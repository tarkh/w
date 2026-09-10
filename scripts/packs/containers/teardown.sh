#!/usr/bin/env bash
# containers bundle — MACHINE layer teardown, the declared inverse of setup.sh.
# Run by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# Deliberately almost empty, and it mirrors a setup.sh that is almost empty for
# the same reason: rootless containers are per-account end to end, so everything
# with a state to undo lives in teardown-user.sh. setup.sh only READS one kernel
# knob (user.max_user_namespaces) to warn about it — it never sets it, W's harden
# module owns it, and other software needs it. Reading nothing is the correct
# inverse of reading something.
#
# The system config this bundle owns (/etc/containers/containers.conf.d/10-w.conf,
# /etc/w/env.d/containers.sh) is declared in the manifest, so w-pack removes and
# backs it up itself — a bundle never duplicates its own manifest here.
#
# This file exists rather than being absent because check.sh requires a teardown
# half for every setup half: "there is nothing to undo" is an answer a bundle
# should have to state, not one a reader should have to infer from a missing file.
#
# See pack-containers.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }

info "Nothing machine-wide to undo (the kernel knob is harden.sh's, not this bundle's)."
info "containers machine teardown complete."
exit 0
