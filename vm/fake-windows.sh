#!/usr/bin/env bash
# vm/fake-windows.sh — lay a fake "Windows" onto the VM disk for the dual-boot E2E
# (vm/e2e.sh --dualboot), in place of the blank disk reset-disk.sh made.
#
# What a laptop that came with Windows looks like after the user shrank C: in Disk
# Management: GPT with a small Windows ESP (FAT32, ef00, EFI/Microsoft/Boot), the MSR,
# an NTFS volume, then free space. The installer's free mode must put W into that
# free space and leave the three partitions alone, byte for byte — so their sha256
# are recorded here, from the image as it was before S1, and compared in S3.
#
# Built as a sparse raw image entirely in userspace (no root, no loop/nbd devices):
# parted writes the table into the file, each filesystem is made in its own file and
# copied into place, then the image is converted to the qcow2 start.sh boots.
# Host tools: parted, mkfs.fat (dosfstools), mtools, mkntfs (ntfsprogs), qemu-img —
# all declared by the w-dev bundle (or the base system).
#
# No EFI/BOOT/BOOTX64.EFI on the fake ESP: OVMF must fall through to the ISO in S1.
#
# Usage: bash vm/fake-windows.sh      (writes vm/w-base.qcow2 + vm/logs/e2e-dualboot.sha256)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK="$SCRIPT_DIR/w-base.qcow2"
SUMS="$SCRIPT_DIR/logs/e2e-dualboot.sha256"

# Layout in MiB. 44 GiB total leaves ~41.7 GiB free after the Windows partitions —
# above the installer's 40 GiB floor, and roughly the size of the regular e2e disk.
DISK_GIB=44
ESP_START=1   ESP_MIB=260
MSR_START=261 MSR_MIB=16
NTFS_START=277 NTFS_MIB=2048

die() { echo "fake-windows: $*" >&2; exit 1; }
for t in parted mkfs.fat mmd mcopy mkntfs qemu-img sha256sum; do
  command -v "$t" &>/dev/null || die "missing host tool '$t' (w-pack install w-dev)"
done

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
img="$tmp/disk.raw"
truncate -s "${DISK_GIB}G" "$img"

# Names in inner quotes: parted splits its script on spaces otherwise.
parted -s "$img" -- mklabel gpt \
  mkpart '"EFI system partition"' fat32 "${ESP_START}MiB" "$((ESP_START + ESP_MIB))MiB" set 1 esp on \
  mkpart '"Microsoft reserved partition"' "${MSR_START}MiB" "$((MSR_START + MSR_MIB))MiB" set 2 msftres on \
  mkpart '"Basic data partition"' ntfs "${NTFS_START}MiB" "$((NTFS_START + NTFS_MIB))MiB" set 3 msftdata on

# Windows ESP: FAT32 with the Windows Boot Manager path (a placeholder binary — this
# scenario proves the partition is left alone, not that Windows boots).
truncate -s "${ESP_MIB}M" "$tmp/esp.img"
mkfs.fat -F32 -n SYSTEM "$tmp/esp.img" >/dev/null
mmd -i "$tmp/esp.img" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot
printf 'W e2e placeholder for bootmgfw.efi\n' > "$tmp/bootmgfw.efi"
mcopy -i "$tmp/esp.img" "$tmp/bootmgfw.efi" ::/EFI/Microsoft/Boot/bootmgfw.efi

# C: — a real (empty) NTFS volume.
truncate -s "${NTFS_MIB}M" "$tmp/ntfs.img"
mkntfs -F -Q -q -L Windows -s 512 -p $((NTFS_START * 2048)) -H 255 -S 63 "$tmp/ntfs.img" &>/dev/null \
  || die "mkntfs failed"

dd if="$tmp/esp.img"  of="$img" bs=1M seek="$ESP_START"  conv=notrunc,sparse status=none
dd if="$tmp/ntfs.img" of="$img" bs=1M seek="$NTFS_START" conv=notrunc,sparse status=none

# Reference hashes of the three partitions, by GPT number, read from the final image
# (the MSR stays zero-filled, as Windows leaves it — still hashed: it must stay so).
mkdir -p "$(dirname "$SUMS")"
{
  printf '1 %s\n' "$(dd if="$img" bs=1M skip="$ESP_START"  count="$ESP_MIB"  status=none | sha256sum | cut -d' ' -f1)"
  printf '2 %s\n' "$(dd if="$img" bs=1M skip="$MSR_START"  count="$MSR_MIB"  status=none | sha256sum | cut -d' ' -f1)"
  printf '3 %s\n' "$(dd if="$img" bs=1M skip="$NTFS_START" count="$NTFS_MIB" status=none | sha256sum | cut -d' ' -f1)"
} > "$SUMS"

qemu-img convert -f raw -O qcow2 "$img" "$DISK"
echo "fake-windows: $DISK (${DISK_GIB}G: ESP ${ESP_MIB}M + MSR ${MSR_MIB}M + NTFS ${NTFS_MIB}M + free), hashes → $SUMS"
