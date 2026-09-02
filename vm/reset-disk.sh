#!/usr/bin/env bash
# Reset VM disk to a clean state for installer testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/arch-iso.conf"

DISK="$SCRIPT_DIR/w-base.qcow2"
VARS="$SCRIPT_DIR/OVMF_VARS.fd"
VARS_SECBOOT="$SCRIPT_DIR/OVMF_VARS.secboot.fd"

echo "Removing old disk and NVRAM..."
rm -f "$DISK" "$VARS" "$VARS_SECBOOT"
# Wipe the emulated TPM state too, so a fresh install can re-enroll cleanly.
rm -rf "${SWTPM_DIR:-/tmp/w-swtpm}"

echo "Creating fresh disk (${VM_DISK_SIZE})..."
qemu-img create -f qcow2 "$DISK" "$VM_DISK_SIZE"

echo "Copying fresh OVMF_VARS..."
cp "$OVMF_VARS" "$VARS"

echo "Done."
echo "  Plain install:        bash vm/start.sh --install"
echo "  Encrypted + SB + TPM: bash vm/start.sh --install --secureboot --tpm"
