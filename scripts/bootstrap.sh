#!/usr/bin/env bash
# bootstrap.sh — set up W Linux dev environment on a new machine.
# Run once after cloning the repository.
# Usage: bash scripts/bootstrap.sh [--skip-download] [--skip-vm]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/vm/arch-iso.conf"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn()  { echo -e "${YELLOW}==> WARN:${RESET} $*"; }
die()   { echo -e "${RED}==> ERROR:${RESET} $*" >&2; exit 1; }

# ── flags ─────────────────────────────────────────────────────────────────────
SKIP_DOWNLOAD=false
SKIP_VM=false
for arg in "$@"; do
  case "$arg" in
    --skip-download) SKIP_DOWNLOAD=true ;;
    --skip-vm)       SKIP_VM=true ;;
  esac
done

# ── step 1: check host dependencies ──────────────────────────────────────────
info "Checking host dependencies..."

REQUIRED=(qemu-system-x86_64 qemu-img curl sha256sum)
MISSING=()
for cmd in "${REQUIRED[@]}"; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done

# virtiofsd lives outside PATH on Arch
[[ -x /usr/lib/virtiofsd ]] || MISSING+=("virtiofsd (/usr/lib/virtiofsd)")

# OVMF firmware
[[ -f "$OVMF_CODE" ]] || MISSING+=("ovmf (OVMF_CODE.fd not found at $OVMF_CODE)")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  die "Missing dependencies:\n$(printf '  - %s\n' "${MISSING[@]}")\n\nInstall with: sudo pacman -S qemu-full ovmf virtiofsd curl"
fi

echo "  All dependencies present."

# ── step 2: download Arch Linux ISO ──────────────────────────────────────────
ISO_PATH="$REPO_ROOT/vm/$ARCH_ISO_FILE"

if $SKIP_DOWNLOAD; then
  info "Skipping ISO download (--skip-download)."
  [[ -f "$ISO_PATH" ]] || die "ISO not found at $ISO_PATH"
else
  if [[ -f "$ISO_PATH" ]]; then
    info "ISO already present: $ISO_PATH"
  else
    info "Downloading Arch Linux $ARCH_ISO_VERSION..."
    curl -fL --progress-bar -o "$ISO_PATH" "$ARCH_ISO_URL" \
      || { rm -f "$ISO_PATH"; die "Download failed (HTTP error or network issue). Check ARCH_ISO_URL in vm/arch-iso.conf."; }
  fi

  info "Verifying ISO checksum..."
  EXPECTED=$(curl -sL "$ARCH_ISO_SHA256" | grep "$ARCH_ISO_FILE" | awk '{print $1}')
  if [[ -z "$EXPECTED" ]]; then
    die "Could not fetch expected sha256 from ${ARCH_ISO_SHA256}"
  fi
  ACTUAL=$(sha256sum "$ISO_PATH" | awk '{print $1}')
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    rm -f "$ISO_PATH"
    die "SHA256 mismatch!\n  expected: $EXPECTED\n  actual:   $ACTUAL\nISO removed. Re-run bootstrap."
  fi
  echo "  Checksum OK: $EXPECTED"
fi

# ── step 3: create VM disk ────────────────────────────────────────────────────
DISK_PATH="$REPO_ROOT/$VM_DISK"

if [[ -f "$DISK_PATH" ]]; then
  info "VM disk already exists: $DISK_PATH"
else
  info "Creating VM disk ($VM_DISK_SIZE thin-provisioned qcow2)..."
  qemu-img create -f qcow2 "$DISK_PATH" "$VM_DISK_SIZE"
  echo "  Created: $DISK_PATH"
fi

# ── step 4: copy OVMF VARS (writable per-VM copy) ────────────────────────────
OVMF_VARS_VM="$REPO_ROOT/vm/OVMF_VARS.fd"
if [[ ! -f "$OVMF_VARS_VM" ]]; then
  info "Copying OVMF VARS for VM..."
  cp "$OVMF_VARS" "$OVMF_VARS_VM"
fi

# ── step 5: launch VM with ISO ───────────────────────────────────────────────
if $SKIP_VM; then
  info "Skipping VM launch (--skip-vm)."
  exit 0
fi

info "Launching VM with Arch Linux ISO..."
echo ""
echo -e "${BOLD}  Install Arch Linux following the W Linux disk layout:${RESET}"
echo ""
echo "  Partitioning (GPT + UEFI):"
echo "    /dev/vda1   512M    FAT32    EFI  →  /boot/efi"
echo "    /dev/vda2   rest    btrfs    root"
echo ""
echo "  Btrfs subvolumes:"
echo "    @                →  /"
echo "    @home            →  /home"
echo "    @home_snapshots  →  /home/.snapshots"
echo "    @snapshots       →  /.snapshots"
echo "    @var_log         →  /var/log"
echo "    @var_cache       →  /var/cache"
echo ""
echo "  Base packages to install:"
echo "    base base-devel linux linux-firmware"
echo "    grub efibootmgr grub-btrfs btrfs-progs"
echo "    zram-generator snapper snap-pac"
echo "    networkmanager openssh"
echo ""
echo "  After install — before first boot:"
echo "    1. Add virtiofs to /etc/fstab (see dev-workflow.md)"
echo "    2. Enable: NetworkManager sshd"
echo ""
echo "  After first boot on host, take a snapshot:"
echo "    qemu-img snapshot -c base vm/w-base.qcow2"
echo ""
read -rp "  Press Enter to launch VM..."

qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp "$VM_CPUS" \
  -m "$VM_RAM" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS_VM" \
  -drive file="$DISK_PATH",format=qcow2,if=virtio \
  -cdrom "$ISO_PATH" \
  -boot order=dc \
  -device virtio-gpu \
  -display spice-app \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -device virtio-rng-pci

info "VM session ended."
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Take base snapshot:  qemu-img snapshot -c base vm/w-base.qcow2"
echo "  2. Start normal dev VM: bash vm/start.sh"
