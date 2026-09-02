#!/usr/bin/env bash
# ci/e2e-container.sh — run the unattended end-to-end install test in a container.
#
# vm/e2e.sh boots a real VM three times and asserts against the system it ends up
# with. It is the only check W has that exercises the thing users actually do, and
# it is written for an Arch host: OVMF under /usr/share/ovmf, virtiofsd at
# /usr/lib/virtiofsd, swtpm for the encrypted scenario's TPM. A GitHub runner is
# Ubuntu. Rather than teach the harness a second host's paths — a host nobody
# develops W on, and a second set of paths to keep true — this puts an Arch
# userland around it, exactly as ci/iso-build-container.sh does for the build.
#
#   ci/e2e-container.sh --encrypted    # LUKS2 + Limine + TPM2 (the default install)
#   ci/e2e-container.sh                # plain btrfs + GRUB
#
# Arguments are passed straight through to vm/e2e.sh.
#
# Why privileged: the guest needs hardware virtualisation, so the container needs
# the host's /dev/kvm — and --privileged is what hands the host's /dev over whole.
# Nested virtualisation on a GitHub standard runner is widely said to be absent;
# it is not (measured 2026-08-27), which is the only reason this file can exist.
# Everything inside runs as root, which is why there is none of the unprivileged
# builder machinery the ISO build needs: no makepkg here, and virtiofsd wants root
# anyway.
#
# The ISO under test is NOT built here. It is whatever sits in archiso/out/ — in
# CI, the published edge image downloaded from the releases page, which is the
# file a user boots. Testing the artefact rather than a private rebuild of it is
# the point; vm/e2e.sh picks the newest ISO there on its own.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE="${W_CI_IMAGE:-archlinux:latest}"
ENGINE="${W_CI_ENGINE:-}"

die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;35m==>\033[0m $*"; }

if [[ -z "$ENGINE" ]]; then
  for e in podman docker; do
    command -v "$e" &>/dev/null && { ENGINE="$e"; break; }
  done
fi
[[ -n "$ENGINE" ]] || die "neither podman nor docker found (set W_CI_ENGINE)"

[[ -e /dev/kvm ]] || die "/dev/kvm is not present on this host — the guest would fall back to emulation and never finish in time."

SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

info "engine: $ENGINE · image: $IMAGE · repo: $REPO_DIR"
exec "${SUDO[@]}" "$ENGINE" run --rm --privileged \
  -v "$REPO_DIR:/w" \
  -w /w "$IMAGE" bash /w/ci/e2e-entrypoint.sh "$@"
