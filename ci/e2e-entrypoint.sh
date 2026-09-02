#!/usr/bin/env bash
# ci/e2e-entrypoint.sh — the container half of ci/e2e-container.sh.
#
# Runs as root inside a fresh archlinux image with the repo bind-mounted at /w.
# Do not run it on a real machine: it installs packages and drives QEMU against
# the repository's VM disk, both of which are fine in a throwaway container and
# rude anywhere else. The container script is the only intended caller.
set -euo pipefail

REPO=/w
info() { echo -e "\033[1;35m==>\033[0m $*"; }
die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }

# ── 1. Is this machine actually able to run a guest? ──────────────────────────
# Asked first and answered loudly. Without KVM, QEMU silently falls back to
# software emulation, which does not fail — it just takes so long that the run
# dies on a phase timeout hours later, having reported nothing about why.
[[ -e /dev/kvm ]] || die "/dev/kvm is not in the container — is it --privileged?"
[[ -w /dev/kvm ]] || die "/dev/kvm is present but not writable by this user."
info "host: $(nproc) cpu · $(free -g | awk '/^Mem:/{print $2}') GiB RAM · $(df -h --output=avail /w | tail -1 | tr -d ' ') free on /w · kvm ok"

# ── 2. Arch userland ──────────────────────────────────────────────────────────
# Same keyring-first order as ci/iso-build-entrypoint.sh: archlinux:latest can be
# days behind the mirrors, and a keyring older than the packages it verifies makes
# every later signature check fail.
info "Refreshing pacman database and keyring..."
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Su --noconfirm

# What vm/start.sh and vm/e2e.sh reach for, and nothing else:
#
#   qemu-base   the emulator itself, headless — the harness passes -display none
#               and -audiodev none, so the desktop/GUI variants add only weight.
#   qemu-hw-display-virtio-vga + qemu-hw-display-virtio-gpu
#               Arch ships QEMU's display devices as separate packages and
#               qemu-base pulls none of them, but headless still needs a GPU:
#               start.sh asks for virtio-vga even with -display none, because the
#               guest wants a framebuffer whether or not anyone is watching it.
#               BOTH packages, and the second one is the interesting half.
#               qemu-hw-display-virtio-vga contains only hw-display-virtio-vga.so
#               — the VGA-compatibility wrapper — and declares a dependency on
#               qemu-common alone; the device it wraps lives in
#               qemu-hw-display-virtio-gpu, which nothing pulls in. With just the
#               wrapper installed QEMU starts happily and runs for forty-five
#               seconds, until the guest kernel binds its virtio-gpu driver, and
#               then segfaults. Proven by an A/B on one runner, one variable: the
#               module absent, SIGSEGV at 45s; the module present, a clean boot.
#               Both invisible on a developer's machine, which has qemu-full.
#   edk2-ovmf   the UEFI firmware. vm/arch-iso.conf names /usr/share/ovmf/x64,
#               which is this package's compatibility path into /usr/share/edk2.
#   virtiofsd   the repository share the guest mounts as /w-src — how the preset
#               reaches the installer and how logs and the firstboot status
#               marker come back out. start.sh expects it at /usr/lib/virtiofsd.
#   swtpm       the emulated TPM 2.0. Not optional for --encrypted: the install
#               enrols LUKS2 into TPM2 so the later headless boots unlock without
#               a passphrase prompt nobody is there to answer.
#   openssh     ssh-keygen for the harness key, ssh for the stage-3 assertions.
info "Installing the VM harness dependencies..."
pacman -S --noconfirm --needed \
  qemu-base qemu-hw-display-virtio-vga qemu-hw-display-virtio-gpu \
  edk2-ovmf virtiofsd swtpm openssh git

# check.sh is not run here — ci/iso-build-container.sh already did, on this same
# tree, before the image under test was published. Repeating it would only make
# the slowest workflow slower.
git config --global --add safe.directory "$REPO"

# ── 3. The test ───────────────────────────────────────────────────────────────
# No knobs, no CI-specific timeouts: this is the same command a developer runs,
# with the same phase ceilings. The expectation going in was that a guest under
# nested virtualisation would need looser ones — measured, it does not. The first
# green run here did the whole encrypted pipeline in eleven minutes (install
# 4m21s, firstboot 5m32s, assertions 51s) against vm/e2e.sh's ceilings of 45, 90
# and 10 minutes. A runner is not slower than the development VM; it is faster.
info "vm/e2e.sh $*"
cd "$REPO"
exec bash vm/e2e.sh "$@"
