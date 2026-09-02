#!/usr/bin/env bash
# scripts/build-iso.sh — build the W Linux install ISO.
#
# Two things happen before mkarchiso runs:
#   1. yay is pre-built into an unsigned local repo ("w-repo"), staged onto the
#      ISO. It exists purely to break the AUR chicken-and-egg on firstboot (no
#      yay -> nothing can build yay from AUR); the rest of aur.txt is compiled by
#      that yay on the target itself, over the network. See installer.md.
#   2. scripts/+packages/+rootfs and the Plymouth theme are staged into
#      airootfs/root — the same payload mod_firstboot later copies onto the
#      installed target, baked into the ISO itself this time since there is no
#      virtiofs share on real hardware.
# Run as your normal user (yay must NOT be built as root); mkarchiso itself is
# invoked with sudo only for its own step.
#
# --preset FILE: bake an unattended answers file into the ISO as
# /root/w/preset.conf — .zlogin then runs install.sh --preset with it on boot
# (fleet deployment, audit P2). The resulting ISO INSTALLS WITHOUT ASKING and
# carries the preset's passwords in plaintext — build it per fleet rollout,
# never publish it as a general download.
#
# --broadcom-wl: build an image whose LIVE session can drive Broadcom STA Wi-Fi
# (see BROADCOM_WL below). Off by default, and deliberately so — it is the one
# switch here that changes the published image's size.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Build options ─────────────────────────────────────────────────────────────
# BROADCOM_WL — Broadcom STA (`wl`) Wi-Fi in the LIVE session. `off` | `on`.
#
# Some old Broadcom chips are in no in-kernel driver's table: BCM43142 [14e4:4365]
# and BCM4360 [14e4:43a0] show no "Kernel driver in use" at all under brcmsmac /
# brcmfmac (see scripts/install/modules/wifi.sh, which installs the driver on the
# TARGET for exactly those). Until 2026-09-01 the live ISO covered them because
# Arch shipped a prebuilt `broadcom-wl`; that package is gone from the official
# repositories, and upstream archiso dropped the line rather than replacing it
# (archiso 63dd047b). Only the DKMS source package remains, so covering the live
# session now means carrying a compiler into the image:
#
#   +571 MiB in airootfs (linux-headers 284 + gcc 221) to build a 7.6 MiB driver
#
# That is why this is off. Turn it on to build yourself an image for such a
# machine — a laptop with no Ethernet port and one of those chips cannot be
# installed from the default image at all, because nothing brings its network up.
BROADCOM_WL="${W_ISO_BROADCOM_WL:-off}"

# linux-headers is the part DKMS cannot do without and nothing else pulls in;
# `dkms` itself arrives as broadcom-wl-dkms's own dependency.
BROADCOM_WL_PKGS=(broadcom-wl-dkms linux-headers)

PRESET_FILE=""
ISO_EXTRA_PKGS=()
while (($#)); do
  case "$1" in
    --preset) PRESET_FILE="${2:-}"; [[ -n "$PRESET_FILE" ]] || { echo "ERROR: --preset needs a file" >&2; exit 1; }; shift ;;
    --broadcom-wl) BROADCOM_WL=on ;;
    *) echo "ERROR: unknown option: $1 (usage: build-iso.sh [--preset FILE] [--broadcom-wl])" >&2; exit 1 ;;
  esac
  shift
done
[[ "$BROADCOM_WL" == off || "$BROADCOM_WL" == on ]] \
  || { echo "ERROR: BROADCOM_WL must be 'off' or 'on', got: $BROADCOM_WL" >&2; exit 1; }

PROFILE="$PROJECT_DIR/archiso/profile"
AIROOTFS="$PROFILE/airootfs"
WORK="$PROJECT_DIR/archiso/work"
OUT="$PROJECT_DIR/archiso/out"
W_REPO_SRC="$PROJECT_DIR/archiso/w-repo"

die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;35m==>\033[0m $*"; }

# The AUR build seam (clone-with-retry, makepkg, pinned-Gradle rescue) is shared
# with the target-side fallback in modules/limine.sh — see the header there.
# shellcheck source=install/lib/aurbuild.sh
source "$SCRIPT_DIR/install/lib/aurbuild.sh"

[[ $EUID -ne 0 ]] || die "Run as a regular user — yay can't be built as root (mkarchiso itself is sudo'd internally)."
[[ -d "$PROFILE" ]] || die "archiso profile not found at $PROFILE"
command -v mkarchiso &>/dev/null || die "mkarchiso not found — pacman -S --needed archiso"
command -v makepkg   &>/dev/null || die "makepkg not found — pacman -S --needed base-devel"

# ── 1. Pre-build AUR packages into w-repo ─────────────────────────────────────
# This is NOT a general AUR cache — do NOT wire it up to packages/aur.txt (that
# list is for the target, post-boot, once yay already exists; see the x-plan
# discussion in installer.md). Only two classes of package belong here:
#
#   yay
#     One-shot bootstrap dependency: without it nothing can build AUR at all.
#
#   limine-mkinitcpio-hook, limine-snapper-sync   (encrypted/Limine path only)
#     Both compile a native binary via GraalVM `native-image` (gradle
#     nativeCompile) — by far the heaviest, most RAM-hungry build in the whole
#     install, and each also downloads the GraalVM JDK. Pre-building them removes
#     that cost from the target entirely (mod_limine installs them with `pacman -U`
#     from w-repo, falling back to a live yay build when the files aren't present —
#     e.g. the dev-VM apply path without an ISO). The native-image binaries are
#     self-contained and built `-march=compatibility` + linked only against glibc
#     (backward-compatible), so a binary built here runs identically on any target
#     with same-or-newer glibc — safe for the end-of-install `initial` snapshot.
#     NOTE: do NOT add limine-entry-tool — limine-mkinitcpio-hook already bundles
#     it (provides+conflicts=limine-entry-tool); installing both would conflict.
#     Cost: the two `!strip` binaries add ~60-120 MB to the ISO.
PREBUILD_AUR_PKGS=(yay limine-mkinitcpio-hook limine-snapper-sync)

rm -rf "$W_REPO_SRC"
mkdir -p "$W_REPO_SRC"

w_aur_build "$W_REPO_SRC" "${PREBUILD_AUR_PKGS[@]}" \
  || die "Pre-building the w-repo packages failed — see the makepkg output above."

# ── 1b. Broadcom STA driver for the live session (opt-in) ────────────────────
# The driver is DKMS-only now, and its source needs a per-kernel-major patch:
# -46 added one for linux 6.17, -48 for 7.1, -49 for 7.2. Arch lands the kernel
# in `core` BEFORE the matching driver rebuild leaves `extra`, so during that
# window the `extra` build simply does not compile against the kernel this ISO
# ships — the failure is a compiler error deep inside a DKMS log, and nothing
# about it says "wrong repository".
#
# So the source is not a knob: the build picks the newest broadcom-wl-dkms of
# ALL repositories, and when that one lives in a *-testing repo it stages that
# single package into w-repo and lets pacman find it there. ONE name is
# redirected; the rest of the image still comes from core+extra as before —
# which is why [extra-testing] is not simply enabled instead.
BROADCOM_WL_FROM_TESTING=0
stage_broadcom_wl() {
  local rows best_ver="" best_repo="" best_file="" repo ver file
  info "Resolving the newest broadcom-wl-dkms across the repositories..."
  rows="$(curl -fsS --max-time 30 \
      'https://archlinux.org/packages/search/json/?name=broadcom-wl-dkms&arch=x86_64' \
    | python3 -c 'import json,sys
for x in json.load(sys.stdin)["results"]:
    print("\t".join([x["repo"], "%s-%s" % (x["pkgver"], x["pkgrel"]), x["filename"]]))')" \
    || die "Could not ask archlinux.org for broadcom-wl-dkms (network?)."
  [[ -n "$rows" ]] || die "broadcom-wl-dkms is in no repository any more — see COPYING/README."

  while IFS=$'\t' read -r repo ver file; do
    [[ -n "$repo" ]] || continue
    if [[ -z "$best_ver" ]] || (( $(vercmp "$ver" "$best_ver") > 0 )); then
      best_ver="$ver"; best_repo="$repo"; best_file="$file"
    fi
  done <<< "$rows"

  case "$best_repo" in
    core|extra|multilib)
      info "  newest is $best_ver in [$best_repo] — pacman will take it from there." ;;
    *)
      info "  newest is $best_ver in [$best_repo] — staging that one package into w-repo."
      curl -fsS --max-time 120 -o "$W_REPO_SRC/$best_file" \
        "https://geo.mirror.pkgbuild.com/$best_repo/os/x86_64/$best_file" \
        || die "Downloading $best_file from [$best_repo] failed."
      BROADCOM_WL_FROM_TESTING=1 ;;
  esac
  ISO_EXTRA_PKGS+=("${BROADCOM_WL_PKGS[@]}")
}

if [[ "$BROADCOM_WL" == on ]]; then
  command -v vercmp &>/dev/null || die "vercmp not found — it ships with pacman."
  stage_broadcom_wl
fi

info "Building w-repo database (unsigned — SigLevel=Never, see installer.md)..."
repo-add "$W_REPO_SRC/w-repo.db.tar.gz" "$W_REPO_SRC"/*.pkg.tar.*

# ── 2. Stage the install-time payload into airootfs ───────────────────────────
info "Staging scripts/packages/rootfs into airootfs..."
rm -rf "$AIROOTFS/root/w"
mkdir -p "$AIROOTFS/root/w"
rsync -a --chown=root:root --exclude='__pycache__/' --exclude='*.pyc' \
  "$PROJECT_DIR/scripts" "$PROJECT_DIR/packages" "$PROJECT_DIR/rootfs" \
  "$AIROOTFS/root/w/"

# Stamp this ISO's build date into the payload's /etc/os-release (W_BUILD_DATE).
# Two orthogonal facts live there and must not be conflated: IMAGE_VERSION is the
# RELEASE (a git tag, written by scripts/publish.sh — never touched here), while
# W_BUILD_DATE is the day THIS image was assembled. On a rolling distro both
# matter: the same release built two months apart carries different packages.
# The repo ships W_BUILD_DATE empty, meaning "not built from a stamped ISO".
# Same one-line rewrite as the dev helper devtools/usr/local/bin/w-os-release-stamp.
sed -i "s/^W_BUILD_DATE=.*/W_BUILD_DATE=$(date -u +%Y.%m.%d)/" \
  "$AIROOTFS/root/w/rootfs/etc/os-release"

# Fleet preset (see the header). The rm above already wiped any stale copy from
# a previous --preset build, so a plain build never inherits one.
if [[ -n "$PRESET_FILE" ]]; then
  [[ -f "$PRESET_FILE" ]] || die "Preset not found: $PRESET_FILE"
  info "Baking unattended preset into the ISO (installs without asking!)..."
  install -m600 "$PRESET_FILE" "$AIROOTFS/root/w/preset.conf"
fi

# NOTE: mkarchiso copies profile/airootfs/ with `cp -af --no-preserve=ownership,mode`
# (see _make_custom_airootfs in /usr/bin/mkarchiso) — it discards every mode bit on
# the way into the image no matter what's chmod'd here on the host beforehand. The
# +x bits this staged tree needs are declared in profiledef.sh's file_permissions
# array instead (the only thing mkarchiso actually re-applies after that copy).

info "Staging w-repo into airootfs..."
rm -rf "$AIROOTFS/root/w-repo"
cp -a "$W_REPO_SRC" "$AIROOTFS/root/w-repo"

info "Staging Plymouth theme into airootfs (branded boot splash)..."
rm -rf "$AIROOTFS/usr/share/plymouth/themes/w"
mkdir -p "$AIROOTFS/usr/share/plymouth/themes"
cp -a "$PROJECT_DIR/rootfs/usr/share/plymouth/themes/w" "$AIROOTFS/usr/share/plymouth/themes/w"
install -Dm644 "$PROJECT_DIR/rootfs/etc/w/themes/w/logo/W-logo-256x256.png" \
  "$AIROOTFS/usr/share/plymouth/themes/w/logo.png"

# ── 3. Build the ISO ──────────────────────────────────────────────────────────
# mkarchiso stamps completed stages inside $WORK and skips them on a rerun unless
# it's wiped — a profile/airootfs edit (like the one that just landed above) would
# otherwise silently NOT make it into the next ISO. Rebuilding is already rare
# (dev-workflow.md: ~10-20 min), so always start from a clean work dir instead of
# trying to reason about which stage's cache is safe to keep. $WORK is root-owned
# (mkarchiso itself runs under sudo below and pacstraps into it) — clean it as
# root too, a plain `rm -rf` from this non-root script would just hit EACCES.
sudo rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

# An opt-in package list is built from a COPY of the profile, never by editing
# the tracked one: a build must not leave the working tree dirty (publish.sh
# gates on that), and a half-finished run must not leave a profile that quietly
# builds a different image next time. With no extras the copy never happens and
# the path is byte-for-byte what it always was.
BUILD_PROFILE="$PROFILE"
if ((${#ISO_EXTRA_PKGS[@]})); then
  BUILD_PROFILE="$PROJECT_DIR/archiso/profile-build"
  info "Adding ${#ISO_EXTRA_PKGS[@]} opt-in package(s): ${ISO_EXTRA_PKGS[*]}"
  rm -rf "$BUILD_PROFILE"
  cp -a "$PROFILE" "$BUILD_PROFILE"
  printf '%s\n' "${ISO_EXTRA_PKGS[@]}" >> "$BUILD_PROFILE/packages.x86_64"

  # w-repo has to precede [core]/[extra] to win the name — pacman takes a package
  # from the first repository that carries it, not from the one with the highest
  # version. Nothing else in w-repo (yay, the limine pair) is in packages.x86_64,
  # so exactly one name can be affected.
  if ((BROADCOM_WL_FROM_TESTING)); then
    W_REPO_SRC="$W_REPO_SRC" python3 - "$BUILD_PROFILE/pacman.conf" <<'PY'
import os, sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
block = "[w-repo]\nSigLevel = Never\nServer = file://%s\n\n" % os.environ["W_REPO_SRC"]
assert "[core]\n" in s, "no [core] section in the profile's pacman.conf"
p.write_text(s.replace("[core]\n", block + "[core]\n", 1))
PY
  fi
fi

info "Building W Linux ISO..."
sudo mkarchiso -v -w "$WORK" -o "$OUT" "$BUILD_PROFILE"
info "ISO ready in $OUT"
