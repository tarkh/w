#!/usr/bin/env bash
# ci/iso-build-container.sh — build the W ISO inside a privileged Arch container.
#
# One command for both consumers, and that is the point: the edge-iso workflow
# runs exactly this, and so does a developer on a machine that is not Arch (or
# that would rather not install archiso on it). The workflow contains no build
# logic of its own — everything that turns the tree into an image lives here and
# in ci/iso-build-entrypoint.sh next to it, where check.sh can lint it.
#
#   ci/iso-build-container.sh                 # check, then build the ISO
#   ci/iso-build-container.sh --check-only    # just run scripts/check.sh in it
#
# Why a container, and why privileged: mkarchiso pacstraps a root filesystem and
# assembles a squashfs image, so it needs real root, loop devices and mounts.
# The awkward part is build-iso.sh's own rule, which is not negotiable — yay and
# the pre-built AUR packages MUST be built by an unprivileged user (makepkg
# refuses to run as root), while mkarchiso MUST be root. The entrypoint
# therefore builds as `builder` and grants it exactly the two root commands
# build-iso.sh shells out to, through the same scoped sudoers template a
# headless build host uses (ci/w-release-gate.sudoers).
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

# Rootful only. A rootless container maps the invoking user to container root
# through a user namespace, which breaks both halves of the seam above: the loop
# devices mkarchiso needs are not delegated into it, and files the build writes
# into the bind-mounted repo come back owned by a shifted uid. CI already runs
# as root inside its VM; locally that means sudo.
SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

info "engine: $ENGINE · image: $IMAGE · repo: $REPO_DIR"
exec "${SUDO[@]}" "$ENGINE" run --rm --privileged \
  -v "$REPO_DIR:/w" \
  -e "W_CI_UID=$(id -u)" -e "W_CI_GID=$(id -g)" \
  -w /w "$IMAGE" bash /w/ci/iso-build-entrypoint.sh "$@"
