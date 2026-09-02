# disk.sh — partitioning, formatting, mounting

BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"
# @home_snapshots is a top-level subvolume (parallel to @snapshots for root) that
# backs the separate `home` snapper config — see modules/snapshots.sh. It must come
# right after @home so /home is mounted before /home/.snapshots (disk_mount mounts
# in array order). genfstab picks it up automatically; no manual fstab entry needed.
BTRFS_SUBVOLS=( "@:/:" "@home:/home" "@home_snapshots:/home/.snapshots" "@snapshots:/.snapshots" "@var_log:/var/log" "@var_cache:/var/cache" )

# ── Encryption model (set by install.sh from the TUI) ────────────────────────
# CONF_ENCRYPT=true  → LUKS2 (Argon2id) wraps the root partition; btrfs lives on
#                      /dev/mapper/$LUKS_NAME. Bootloader = Limine (reads plain
#                      kernel/initramfs from the ESP; it can't open LUKS), so the
#                      ESP is enlarged to stage current + snapshot boot files.
# CONF_ENCRYPT=false → current behaviour (plain btrfs on the partition, GRUB).
CONF_ENCRYPT="${CONF_ENCRYPT:-false}"
CONF_LUKS_PASS="${CONF_LUKS_PASS:-}"
LUKS_NAME="cryptroot"

# The device that hosts btrfs: the LUKS mapper when encrypted, else the raw part.
root_device() {
  local disk="$1"
  if [[ "$CONF_ENCRYPT" == true ]]; then
    echo "/dev/mapper/$LUKS_NAME"
  else
    part "$disk" 2
  fi
}

disk_list() {
  local entries=()
  while IFS= read -r line; do
    local name size model
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    model=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
    entries+=("/dev/$name" "$size  $model")
  done < <(lsblk -dno NAME,SIZE,MODEL | grep -Ev "^loop|^sr")
  echo "${entries[@]}"
}

disk_partition() {
  local disk="$1"
  # The ESP holds the bootloader; on the encrypted/Limine path it ALSO stages the
  # kernel+initramfs of the running system and every bootable snapshot (Limine can't
  # read the LUKS root), so it must be much larger. Plain/GRUB keeps the current 512M.
  local esp_size="512M"
  [[ "$CONF_ENCRYPT" == true ]] && esp_size="2048M"
  ui_info "Partitioning $disk (ESP ${esp_size})..."
  wipefs -af "$disk" &>/dev/null
  sgdisk --zap-all "$disk" &>/dev/null
  sgdisk -n "1:0:+${esp_size}" -t 1:ef00 -c 1:"EFI"  "$disk" &>/dev/null
  sgdisk -n 2:0:0              -t 2:8300 -c 2:"root" "$disk" &>/dev/null
  partprobe "$disk" 2>/dev/null; sleep 1
}

# LUKS2 (Argon2id) wrap of the root partition. Runs after partitioning, before
# formatting. The passphrase is fed via a keyfile-stdin with NO trailing newline so
# the enrolled key material equals what the user types interactively at boot. TPM2
# auto-unlock and the recovery key are enrolled later (post-boot) by `w-crypt`.
disk_encrypt() {
  local disk="$1"
  local part2; part2="$(part "$disk" 2)"
  ui_info "Encrypting root partition (LUKS2 / Argon2id)..."
  printf '%s' "$CONF_LUKS_PASS" | cryptsetup luksFormat --type luks2 \
    --pbkdf argon2id --batch-mode --key-file - "$part2" &>/dev/null
  printf '%s' "$CONF_LUKS_PASS" | cryptsetup open --key-file - "$part2" "$LUKS_NAME" &>/dev/null
}

disk_format() {
  local disk="$1"
  ui_info "Formatting partitions..."
  mkfs.fat -F32 "$(part "$disk" 1)" &>/dev/null
  mkfs.btrfs -f -L wroot "$(root_device "$disk")" &>/dev/null
}

disk_mount() {
  local disk="$1"
  local root_part; root_part="$(root_device "$disk")"
  local efi_part;  efi_part="$(part "$disk" 1)"

  ui_info "Creating btrfs subvolumes..."
  mount "$root_part" "$MNT"
  for sv in "${BTRFS_SUBVOLS[@]}"; do
    btrfs subvolume create "$MNT/${sv%%:*}" &>/dev/null
  done
  umount "$MNT"

  ui_info "Mounting subvolumes..."
  mount -o "${BTRFS_OPTS},subvol=@" "$root_part" "$MNT"
  for sv in "${BTRFS_SUBVOLS[@]:1}"; do  # skip @ (already mounted)
    local name="${sv%%:*}" mnt="${sv##*:}"
    mkdir -p "$MNT$mnt"
    mount -o "${BTRFS_OPTS},subvol=${name}" "$root_part" "$MNT$mnt"
  done

  mkdir -p "$MNT/boot/efi"
  # Restrictive masks: the ESP holds the random-seed and (encrypted path) staged
  # kernels/initramfs — a world-readable ESP makes bootctl flag a security hole.
  # genfstab copies these mount options into the target fstab.
  mount -o fmask=0077,dmask=0077 "$efi_part" "$MNT/boot/efi"

  # virtiofs mount point for dev mode — only when installing FROM a dev VM (see
  # disk_fstab below for the detection). A real ISO boot has no /w-src share, so
  # this stays a no-op there instead of leaving a dead /mnt/w-src on every install.
  # Bare `cmd && cmd` here would be exactly the set-e/pipefail landmine documented
  # in dev-workflow.md: mountpoint returning 1 (the normal, expected case on a real
  # ISO install — no /w-src) makes the whole statement's exit status 1 and aborts
  # the script right here under `set -e`, since it isn't wrapped in an `if`.
  if mountpoint -q /w-src 2>/dev/null; then
    mkdir -p "$MNT/mnt/w-src"
  fi
}

disk_fstab() {
  ui_info "Generating fstab..."
  genfstab -U "$MNT" >> "$MNT/etc/fstab"
  # virtiofs for dev mode. /w-src (not /mnt/w-src — that's the target's own mount
  # point, /mnt is busy with the target during install) is the dev-workflow's own
  # documented live-mount convention; its presence is the signature of a dev-VM
  # install. Real hardware/ISO installs never have it, so they get no fstab entry
  # and no /mnt/w-src directory at all instead of a permanent, always-empty artifact.
  if mountpoint -q /w-src 2>/dev/null; then
    echo -e "\n# Project directory via virtiofs (dev mode)"      >> "$MNT/etc/fstab"
    echo "w-src  /mnt/w-src  virtiofs  defaults,nofail  0  0"     >> "$MNT/etc/fstab"
  fi
}
