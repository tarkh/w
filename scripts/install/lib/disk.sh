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

# ── Target partitions ────────────────────────────────────────────────────────
# CONF_ESP_PART / CONF_ROOT_PART are the single source of truth for every later
# phase (format, LUKS, mount, cmdline UUID, TPM enroll, NVRAM entry). Resolved once
# by disk_plan before the summary — the confirm screen must already name them —
# and checked to exist right after partitioning. One branch per disk mode:
#   wipe — p1/p2 of the fresh table disk_partition writes;
#   free — W's own ESP + root carved out of the largest free block of an existing
#          GPT (disk_partition_free); every partition already there is left as is,
#          a foreign ESP included (it is neither reused nor mounted).
CONF_DISK_MODE="${CONF_DISK_MODE:-wipe}"
CONF_ESP_PART="${CONF_ESP_PART:-}"
CONF_ROOT_PART="${CONF_ROOT_PART:-}"

# Smallest contiguous free block the free mode accepts: the ESP (up to 2 GiB) plus a
# root with room for the system, its snapshots and a home.
FREE_MIN_GIB=40
# Free mode plan, filled by disk_plan: the block's first/last sector, the logical
# sector size, and the GPT slots the two new partitions are created in.
FREE_FIRST="" FREE_LAST="" FREE_SS="" ESP_NUM="" ROOT_NUM=""

disk_plan() {
  if [[ "$CONF_DISK_MODE" != free ]]; then
    CONF_ESP_PART="$(part "$CONF_DISK" 1)"
    CONF_ROOT_PART="$(part "$CONF_DISK" 2)"
    return
  fi
  local region; region="$(disk_free_region "$CONF_DISK")" \
    || die "No usable free space on $CONF_DISK (GPT with a free block of ${FREE_MIN_GIB} GiB or more)."
  read -r FREE_FIRST FREE_LAST FREE_SS <<<"$region"
  (( (FREE_LAST - FREE_FIRST + 1) * FREE_SS >> 30 >= FREE_MIN_GIB )) \
    || die "The largest free block on $CONF_DISK is smaller than ${FREE_MIN_GIB} GiB."
  # The numbers are assigned, not discovered after the fact: the two lowest free GPT
  # slots, passed to sgdisk explicitly — so the summary can name the partitions
  # before anything is written, and disk_partition_free can prove sgdisk honoured it.
  local used n nums=()
  used=" $(disk_part_numbers "$CONF_DISK" | tr '\n' ' ') "
  for (( n = 1; n <= 128 && ${#nums[@]} < 2; n++ )); do
    [[ "$used" == *" $n "* ]] || nums+=("$n")
  done
  (( ${#nums[@]} == 2 )) || die "No free GPT slots left on $CONF_DISK."
  ESP_NUM="${nums[0]}"; ROOT_NUM="${nums[1]}"
  CONF_ESP_PART="$(part "$CONF_DISK" "$ESP_NUM")"
  CONF_ROOT_PART="$(part "$CONF_DISK" "$ROOT_NUM")"
}

# ESP size in MiB. On the encrypted/Limine path the ESP ALSO stages the kernel +
# initramfs of the running system and every bootable snapshot (Limine can't read
# the LUKS root), so it must be much larger; plain/GRUB keeps 512M.
disk_esp_mib() { if [[ "$CONF_ENCRYPT" == true ]]; then echo 2048; else echo 512; fi; }

# disk_free_region <disk> → "<first> <last> <sector bytes>" of the largest free
# block, sectors as sgdisk reports them (-F is aligned). GPT only: on an MBR disk
# sgdisk would convert the table on write — that is not "leaving it untouched".
disk_free_region() {
  local disk="$1" first last
  [[ "$(lsblk -ndo PTTYPE "$disk" 2>/dev/null)" == gpt ]] || return 1
  first="$(sgdisk -F "$disk" 2>/dev/null | tail -n1)"
  last="$(sgdisk -E "$disk" 2>/dev/null | tail -n1)"
  [[ "$first" =~ ^[0-9]+$ && "$last" =~ ^[0-9]+$ ]] || return 1
  (( first > 0 && last > first )) || return 1
  echo "$first $last $(blockdev --getss "$disk")"
}

# disk_free_bytes <disk> → size of the largest free block (non-zero: none).
disk_free_bytes() {
  local first last ss
  read -r first last ss < <(disk_free_region "$1") || return 1
  echo $(( (last - first + 1) * ss ))
}

# disk_free_gib <disk> → whole GiB of the largest free block (the threshold check).
disk_free_gib() {
  local b; b="$(disk_free_bytes "$1")" || return 1
  echo $(( b >> 30 ))
}

# disk_size_fmt <bytes> → "41.7 GiB" / "260 MiB". Binary units on purpose: they are
# what Windows itself counts in (Disk Management's Shrink dialog takes MB = MiB), so
# the number a dual-boot user freed there reads back unchanged here — under its
# honest IEC name. One decimal, from exact bytes; unit labels are localized.
disk_size_fmt() {
  awk -v b="$1" -v g="$(t u_gib)" -v m="$(t u_mib)" \
    'BEGIN { if (b >= 1073741824) printf "%.1f %s", b / 1073741824, g
             else printf "%d %s", b / 1048576, m }'
}

# Whole-disk size in bytes.
disk_bytes() { lsblk -dbno SIZE "$1" 2>/dev/null; }

# disk_free_ok <disk> — the free mode is possible on this disk.
disk_free_ok() {
  local gib; gib="$(disk_free_gib "$1")" || return 1
  (( gib >= FREE_MIN_GIB ))
}

# GPT numbers of the partitions already on <disk>, one per line.
disk_part_numbers() {
  sgdisk -p "$1" 2>/dev/null | awk 'f && $1 ~ /^[0-9]+$/ {print $1} /^Number/ {f=1}'
}

# "<node>␟<bytes>␟<fstype>␟<label>" (␟ = \x1f) for every partition already on <disk> — what
# the free mode promises to leave alone (install summary, disk list). Read as
# --pairs and joined by \x1f, not a tab: an empty column (the MSR has no
# filesystem) must not shift the rest, and `read` collapses runs of tabs.
disk_kept_parts() {
  lsblk -nbpPo TYPE,NAME,SIZE,FSTYPE,LABEL "$1" 2>/dev/null \
    | awk -F'"' '$2 == "part" { printf "%s\037%s\037%s\037%s\n", $4, $6, $8, $10 }'
}

# "<parent disk> <partition number>" of a partition node, read from the kernel
# (sysfs), never parsed from the name — what efibootmgr --disk/--part need.
part_location() {
  local name; name="$(basename "$(readlink -f "$1")")"
  local pk; pk="$(lsblk -ndo PKNAME "/dev/$name")"
  [[ -n "$pk" && -r "/sys/class/block/$name/partition" ]] || return 1
  echo "/dev/$pk $(<"/sys/class/block/$name/partition")"
}

# The device that hosts btrfs: the LUKS mapper when encrypted, else the raw part.
root_device() {
  if [[ "$CONF_ENCRYPT" == true ]]; then
    echo "/dev/mapper/$LUKS_NAME"
  else
    echo "$CONF_ROOT_PART"
  fi
}

# The disk the live medium is on — by the iso9660 UUID/label archiso puts on the
# kernel cmdline (archisosearchuuid= / archisolabel=), resolved with blkid and
# walked down to the whole disk. Not by mount: with copytoram (Ventoy's default)
# the medium is unmounted after boot, so /run/archiso/bootmnt is empty. Works
# through a Ventoy dm-mapper or a dd-written stick alike; prints nothing when the
# installer runs outside the live ISO (no archiso params → no filter).
_live_disk() {
  local tag dev
  tag="$(sed -n -E 's/.*archiso(searchuuid|label)=([^ ]+).*/\1=\2/p' /proc/cmdline)"
  [[ -n "$tag" ]] || return 0
  tag="${tag/searchuuid=/UUID=}"; tag="${tag/label=/LABEL=}"
  for dev in $(blkid -o device -t "$tag" 2>/dev/null); do
    lsblk -snlo NAME,TYPE "$dev" 2>/dev/null | awk '$2 == "disk" {print $1}'
  done | sort -u
}

# One "/dev/<name><TAB><description>" row per installable disk (the menu step's
# tag/desc contract): size, then what is already on it — partition count and the
# largest free block, so the disk with Windows on it and its room are visible
# before the install mode is chosen — then the model last (a long one is what the
# menu width cuts). Skipped: loop/cdrom/zram (RAM-backed swap, never a target),
# empty card readers (size 0 — selectable, but wipefs would fail mid-install),
# and the medium the ISO booted from.
disk_list() {
  local live name bytes model n fb desc
  live=" $(_live_disk | tr '\n' ' ') "
  while read -r name bytes model; do
    [[ "$bytes" == 0 || "$live" == *" $name "* ]] && continue
    desc="$(disk_size_fmt "$bytes")"
    n="$(disk_kept_parts "/dev/$name" | wc -l)"
    if (( n )); then
      desc+=" · $(t disk_parts) $n"
      if fb="$(disk_free_bytes "/dev/$name")"; then desc+=" · $(t disk_free) $(disk_size_fmt "$fb")"; fi
    else
      desc+=" · $(t disk_empty)"
    fi
    if [[ -n "$model" ]]; then desc+=" · $model"; fi
    printf '/dev/%s\t%s\n' "$name" "$desc"
  done < <(lsblk -dbno NAME,SIZE,MODEL | grep -Ev "^loop|^sr|^zram")
}

disk_partition() {
  local disk="$1"
  local esp_size; esp_size="$(disk_esp_mib)M"
  ui_info "Partitioning $disk (ESP ${esp_size})..."
  wipefs -af "$disk" &>/dev/null
  sgdisk --zap-all "$disk" &>/dev/null
  sgdisk -n "1:0:+${esp_size}" -t 1:ef00 -c 1:"EFI"  "$disk" &>/dev/null
  sgdisk -n 2:0:0              -t 2:8300 -c 2:"root" "$disk" &>/dev/null
  _disk_settle "$disk"
}

# Free mode: ESP at the head of the planned block, root on the rest of it, both in
# the GPT slots disk_plan assigned. Nothing else on the disk is written: no wipefs
# or zap of the disk, the existing entries stay byte for byte.
disk_partition_free() {
  local disk="$1" esp_mib; esp_mib="$(disk_esp_mib)"
  local esp_last=$(( FREE_FIRST + esp_mib * 1048576 / FREE_SS - 1 ))
  ui_info "Partitioning free space on $disk (ESP ${esp_mib}M, existing partitions kept)..."
  sgdisk -n "$ESP_NUM:$FREE_FIRST:$esp_last" -t "$ESP_NUM:ef00" -c "$ESP_NUM:W EFI" \
         -n "$ROOT_NUM:$((esp_last + 1)):$FREE_LAST" -t "$ROOT_NUM:8300" -c "$ROOT_NUM:W root" \
         "$disk" &>/dev/null || die "sgdisk could not create the W partitions on $disk"
  [[ "$(sgdisk -i "$ESP_NUM" "$disk" 2>/dev/null | sed -n 's/^First sector: \([0-9]*\).*/\1/p')" == "$FREE_FIRST" ]] \
    || die "Partition $ESP_NUM on $disk is not where it was planned (sector $FREE_FIRST)"
  _disk_settle "$disk"
  # The block was free in the table, not necessarily blank on disk: a leftover
  # LUKS/btrfs/FAT signature there would confuse blkid/udev. Only OUR nodes.
  local p
  for p in "$CONF_ESP_PART" "$CONF_ROOT_PART"; do wipefs -af "$p" &>/dev/null || true; done
}

# Re-read the table and require both planned nodes before anything is formatted.
_disk_settle() {
  partprobe "$1" 2>/dev/null; sleep 1
  udevadm settle 2>/dev/null || true
  local p
  for p in "$CONF_ESP_PART" "$CONF_ROOT_PART"; do
    [[ -b "$p" ]] || die "Partition $p did not appear after partitioning $1"
  done
}

# LUKS2 (Argon2id) wrap of the root partition. Runs after partitioning, before
# formatting. The passphrase is fed via a keyfile-stdin with NO trailing newline so
# the enrolled key material equals what the user types interactively at boot. TPM2
# auto-unlock and the recovery key are enrolled later (post-boot) by `w-crypt`.
disk_encrypt() {
  ui_info "Encrypting root partition (LUKS2 / Argon2id)..."
  printf '%s' "$CONF_LUKS_PASS" | cryptsetup luksFormat --type luks2 \
    --pbkdf argon2id --batch-mode --key-file - "$CONF_ROOT_PART" &>/dev/null
  printf '%s' "$CONF_LUKS_PASS" | cryptsetup open --key-file - "$CONF_ROOT_PART" "$LUKS_NAME" &>/dev/null
}

disk_format() {
  ui_info "Formatting partitions..."
  mkfs.fat -F32 -n W_EFI "$CONF_ESP_PART" &>/dev/null   # MokManager lists volumes by label
  mkfs.btrfs -f -L wroot "$(root_device)" &>/dev/null
}

disk_mount() {
  local root_part; root_part="$(root_device)"
  local efi_part="$CONF_ESP_PART"

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
