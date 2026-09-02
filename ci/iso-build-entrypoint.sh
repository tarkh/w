#!/usr/bin/env bash
# ci/iso-build-entrypoint.sh — the container half of ci/iso-build-container.sh.
#
# Runs as root inside a fresh archlinux image with the repo bind-mounted at /w.
# Do not run it on a real machine: it installs packages and writes into
# /etc/sudoers.d, which is harmless in a throwaway container and rude anywhere
# else. The container script is the only intended caller.
set -euo pipefail

REPO=/w
CHECK_ONLY=0
[[ "${1:-}" == "--check-only" ]] && { CHECK_ONLY=1; shift; }

# Everything left over is build-iso.sh's (e.g. --broadcom-wl, --preset). Passing
# them through is what makes the container path a real substitute for a local
# build rather than only the nightly's own path: the person who needs an opt-in
# image is the likeliest not to be on Arch in the first place.
BUILD_ARGS=("$@")

info() { echo -e "\033[1;35m==>\033[0m $*"; }

# ── 1. Arch userland ──────────────────────────────────────────────────────────
# archlinux:latest can be days behind the mirrors, and a keyring older than the
# packages it has to verify makes every later signature check fail. Refresh the
# keyring on its own first, then the rest.
info "Refreshing pacman database and keyring..."
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Su --noconfirm

# archiso + base-devel are the build itself. The rest is what scripts/check.sh
# looks for: a missing tool does not fail a suite, it SKIPs it or — worse —
# changes its verdict, so an incomplete list here produces a run that reports
# on less than it claims. Every entry below was added because its absence
# showed up as a false result on the first live run:
#
#   python-numpy      the memory suite's vector tests assert that hybrid search
#                     RRF-ranks a vector-only hit; without numpy that path
#                     degrades to FTS5 and two bats cases fail for the
#                     environment's reason rather than the code's.
#   quickshell        qmllint resolves W's QML against the real Quickshell
#                     types. Without them a `Connections { target: root }` is
#                     reported as "cannot assign Hub to QObject" — not a defect,
#                     just a base class it could not follow.
info "Installing build and check dependencies..."
pacman -S --noconfirm --needed \
  archiso base-devel git rsync sudo \
  shellcheck ruff bats python python-numpy qt6-declarative quickshell

# The paths suite asserts no shipped /usr/bin path collides with a file owned by
# an Arch package — which needs the files database. Without it that probe SKIPs,
# and an upstream package quietly claiming one of W's names would go unseen.
info "Syncing the pacman files database..."
pacman -Fy

# ── 2. The unprivileged builder ───────────────────────────────────────────────
# Given the invoking user's uid, so everything the build writes into the
# bind-mounted repo (archiso/out, archiso/w-repo) comes back owned by them
# rather than by a stray container uid.
BUILD_UID="${W_CI_UID:-1000}"
BUILD_GID="${W_CI_GID:-1000}"
getent group builder >/dev/null || groupadd -g "$BUILD_GID" builder 2>/dev/null || groupadd builder
id builder &>/dev/null || useradd -m -u "$BUILD_UID" -g builder builder 2>/dev/null \
                       || useradd -m -g builder builder

# The scoped root grant, rendered from the template the release gate already
# ships: one grant, one file, shared by a headless build host and by CI.
info "Granting builder the two root commands build-iso.sh needs..."
sed -e "s|<user>|builder|g" -e "s|<repo>|$REPO|g" \
  "$REPO/ci/w-release-gate.sudoers" > /etc/sudoers.d/w-release-gate
chmod 0440 /etc/sudoers.d/w-release-gate
visudo -cf /etc/sudoers.d/w-release-gate >/dev/null

# One grant the template deliberately does NOT carry, and the reason it does
# not. build-iso.sh pre-builds AUR packages with makepkg, and makepkg installs
# each package's declared dependencies itself, through `sudo pacman -S`. On the
# build host the template targets, those are already present — it is a machine
# that develops W, so limine, snapper, btrfs-progs, libnotify and the JDK the
# limine pair compiles against are simply installed. A container starts from
# nothing, so here makepkg genuinely needs pacman, and without this the build
# dies at "sudo: a password is required" before it compiles anything.
#
# It stays out of the shared template on purpose: unrestricted pacman is
# unrestricted root (it can install anything, hooks included), which is a fine
# thing to hand a container that is deleted at the end of the job and a bad
# thing to leave standing in /etc/sudoers.d on a real build server.
printf 'builder ALL=(root) NOPASSWD: /usr/bin/pacman\n' > /etc/sudoers.d/w-ci-makepkg
chmod 0440 /etc/sudoers.d/w-ci-makepkg
visudo -cf /etc/sudoers.d/w-ci-makepkg >/dev/null

# git refuses to read a tree owned by another uid, and check.sh's whole file
# inventory is `git ls-files`. Without this the suites would see an empty list
# and pass vacuously — the worst failure mode a gate can have.
runuser -u builder -- git config --global --add safe.directory "$REPO"

# ── 3. Check, then build ──────────────────────────────────────────────────────
# --online is the point of running this here rather than only on a laptop. It
# asks the Arch and AUR indexes whether every name in packages/ still exists —
# a package that leaves the repositories breaks installs on user machines but
# NOT this build, because packages/pacman.txt is installed on the target, never
# baked into the image. Nothing else in the pipeline would notice. The probe
# fails only on a definitive "no such name"; a network hiccup is reported and
# tolerated, so it cannot make the nightly run flaky.
info "scripts/check.sh --online"
runuser -u builder -- bash -c "cd $REPO && bash scripts/check.sh --online"

if [[ $CHECK_ONLY -eq 1 ]]; then
  info "--check-only: stopping before the build."
  exit 0
fi

# printf applies its format once even with no arguments, so an unguarded
# `printf '%q '` on an empty array yields one EMPTY quoted argument — which
# build-iso.sh's parser rejects as an unknown option. The nightly build passes
# no arguments at all, so that is the common path, not the corner case.
BUILD_ARGV=""
((${#BUILD_ARGS[@]})) && BUILD_ARGV="$(printf '%q ' "${BUILD_ARGS[@]}")"
info "scripts/build-iso.sh $BUILD_ARGV"
runuser -u builder -- bash -c "cd $REPO && bash scripts/build-iso.sh $BUILD_ARGV"

ls -lh "$REPO/archiso/out"
