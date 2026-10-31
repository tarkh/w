#!/usr/bin/env bats
# disk.bats — install/lib/disk.sh: the free-space (dual-boot) plan. disk_plan must
# pick the largest free block and the lowest free GPT slots, and refuse a disk it
# cannot install next to; the whole-disk plan must stay p1/p2. sgdisk/lsblk/
# blockdev are shadowed by functions fed from per-test variables — no real disk.

load helpers

setup() {
  source "$REPO/scripts/install/lib/utils.sh"
  source "$REPO/scripts/install/lib/disk.sh"
  die() { echo "die: $*" >&2; exit 1; }

  PTTYPE=gpt SS=512
  FIRST=2048 LAST=$(( 2048 + 50 * 2097152 - 1 ))   # a 50 GiB block
  TABLE=$'Number  Start (sector)    End (sector)  Size       Code  Name\n   1            2048          534527   260.0 MiB   EF00  EFI system partition\n   2          534528          567295   16.0 MiB    0C01  Microsoft reserved\n   4          567296         4761599   2.0 GiB     0700  Basic data partition'
  lsblk()    { echo "$PTTYPE"; }
  blockdev() { echo "$SS"; }
  sgdisk() {
    case "$1" in
      -F) echo "$FIRST" ;;
      -E) echo "$LAST" ;;
      -p) printf 'Disk %s: …\n%s\n' "$2" "$TABLE" ;;
    esac
  }
  CONF_DISK=/dev/nvme0n1 CONF_ENCRYPT=true
  t() { case "$1" in u_gib) echo GiB ;; u_mib) echo MiB ;; *) echo "$1" ;; esac; }
}

@test "disk_plan wipe: p1/p2 of the fresh table" {
  CONF_DISK_MODE=wipe
  disk_plan
  [[ "$CONF_ESP_PART" == /dev/nvme0n1p1 && "$CONF_ROOT_PART" == /dev/nvme0n1p2 ]]
}

@test "disk_plan free: lowest free GPT slots, region from sgdisk" {
  CONF_DISK_MODE=free
  disk_plan
  [[ "$ESP_NUM" == 3 && "$ROOT_NUM" == 5 ]]
  [[ "$CONF_ESP_PART" == /dev/nvme0n1p3 && "$CONF_ROOT_PART" == /dev/nvme0n1p5 ]]
  [[ "$FREE_FIRST" == "$FIRST" && "$FREE_LAST" == "$LAST" && "$FREE_SS" == 512 ]]
}

@test "disk_free_gib / disk_free_ok: 40 GiB threshold, 4K sectors" {
  [[ "$(disk_free_gib /dev/x)" == 50 ]]
  disk_free_ok /dev/x
  SS=4096 FIRST=256 LAST=$(( 256 + 39 * 262144 - 1 ))   # 39 GiB in 4K sectors
  [[ "$(disk_free_gib /dev/x)" == 39 ]]
  ! disk_free_ok /dev/x
}

@test "disk_plan free: refuses a non-GPT disk and a too-small block" {
  CONF_DISK_MODE=free
  PTTYPE=dos
  run disk_plan
  [[ "$status" -ne 0 && "$output" == *"No usable free space"* ]]
  PTTYPE=gpt LAST=$(( FIRST + 30 * 2097152 - 1 ))
  run disk_plan
  [[ "$status" -ne 0 && "$output" == *"smaller than 40 GiB"* ]]
  FIRST=0 LAST=0
  run disk_plan
  [[ "$status" -ne 0 ]]
}

@test "disk_esp_mib: 2048 encrypted, 512 plain" {
  [[ "$(disk_esp_mib)" == 2048 ]]
  CONF_ENCRYPT=false
  [[ "$(disk_esp_mib)" == 512 ]]
}

@test "disk_size_fmt: binary units, one decimal from exact bytes, MiB below 1 GiB" {
  [[ "$(disk_size_fmt 47244640256)" == "44.0 GiB" ]]
  [[ "$(disk_size_fmt $(( 42731 * 1048576 )))" == "41.7 GiB" ]]
  [[ "$(disk_size_fmt $(( 260 * 1048576 )))" == "260 MiB" ]]
  [[ "$(disk_size_fmt 1073741824)" == "1.0 GiB" ]]
}

@test "disk_kept_parts: an empty column does not shift the rest" {
  lsblk() {
    printf '%s\n' 'TYPE="disk" NAME="/dev/vda" SIZE="47244640256" FSTYPE="" LABEL=""' \
      'TYPE="part" NAME="/dev/vda2" SIZE="16777216" FSTYPE="" LABEL=""' \
      'TYPE="part" NAME="/dev/vda3" SIZE="2147483648" FSTYPE="ntfs" LABEL="Windows"'
  }
  local rows=() node bytes fs label
  while IFS=$'\x1f' read -r node bytes fs label; do rows+=("$node|$bytes|$fs|$label"); done < <(disk_kept_parts /dev/vda)
  [[ "${#rows[@]}" == 2 ]]
  [[ "${rows[0]}" == "/dev/vda2|16777216||" ]]
  [[ "${rows[1]}" == "/dev/vda3|2147483648|ntfs|Windows" ]]
}
