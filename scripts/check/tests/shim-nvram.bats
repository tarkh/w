#!/usr/bin/env bats
# shim-nvram.bats — w-secureboot's firmware entry "W" against the entries an earlier
# install can leave behind. An entry on a partition that is gone must not stop the new
# one (AMI hides it as a VenHw placeholder at boot — found live, ASUS X99); one on a
# partition that still exists may be another W's and stays. efibootmgr, blkid and
# findmnt are stubs; /dev/disk/by-partuuid is rewritten into the test.

load helpers

ESP=82d49b8f-5046-42e2-ba97-7eb2ba5aa96f
OLD=43a9e483-e567-42a6-a345-55f9fe7e0b72
OTHER=0d1b0b4e-2f5c-4c55-9a8e-7d3e1c2a9b10

setup() {
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"; PATH="$bin:$PATH"
  export EFI_LIST="$BATS_TEST_TMPDIR/efi" EFI_LOG="$BATS_TEST_TMPDIR/log" ESP_UUID="$ESP"
  : > "$EFI_LOG"
  cat > "$bin/efibootmgr" <<'EOF'
#!/bin/sh
[ $# -eq 0 ] && { cat "$EFI_LIST"; exit 0; }
echo "$*" >> "$EFI_LOG"
EOF
  printf '#!/bin/sh\necho "$ESP_UUID"\n' > "$bin/blkid"
  printf '#!/bin/sh\necho /dev/nvme0n1p1\n' > "$bin/findmnt"
  chmod +x "$bin"/*
  byuuid="$BATS_TEST_TMPDIR/by-partuuid"; mkdir -p "$byuuid"; touch "$byuuid/$ESP"
  eval "$(sed -n -e '/^err() /p' -e '/^shim_nvram_list() {/,/^}/p' -e '/^esp_partuuid() /p' \
    -e '/^shim_nvram_entry() {/,/^}/p' -e '/^shim_nvram_first() {/,/^}/p' \
    "$REPO/rootfs/usr/bin/w-secureboot" | sed "s#/dev/disk/by-partuuid#$byuuid#g")"
  esp_location() { echo "/dev/nvme0n1 1"; }
  esp_path() { echo /boot/efi; }
}

entry() { printf 'Boot%s* W\tHD(1,GPT,%s,0x800,0x400000)/\\EFI\\W\\shimx64.efi\n' "$1" "$2"; }

@test "no W entry → one is created" {
  printf 'BootOrder: 0000\nBoot0000* Windows Boot Manager\tHD(1,GPT,bd1e1b88-5cb7-4f51-8d95-2729c0279e73)/\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI\n' > "$EFI_LIST"
  shim_nvram_entry
  grep -q -- '--create --disk /dev/nvme0n1 --part 1' "$EFI_LOG"
}

@test "an entry on this ESP → kept, nothing created" {
  entry 0003 "$ESP" > "$EFI_LIST"
  shim_nvram_entry
  [ ! -s "$EFI_LOG" ]
}

@test "an entry from an earlier install on a partition that is gone → removed, a new one created" {
  entry 0001 "$OLD" > "$EFI_LIST"
  shim_nvram_entry
  grep -qx -- '-b 0001 -B' "$EFI_LOG"
  grep -q -- '--create' "$EFI_LOG"
}

@test "another W's entry on a partition that exists → kept, ours created beside it" {
  touch "$byuuid/$OTHER"
  entry 0004 "$OTHER" > "$EFI_LIST"
  shim_nvram_entry
  ! grep -q -- '-B' "$EFI_LOG"
  grep -q -- '--create' "$EFI_LOG"
}

@test "ESP unreadable → an existing entry is taken as ours (no duplicate)" {
  touch "$byuuid/$OTHER"; ESP_UUID=""
  entry 0004 "$OTHER" > "$EFI_LIST"
  shim_nvram_entry
  [ ! -s "$EFI_LOG" ]
}

@test "first in BootOrder: our ESP's entry, not another W's listed before it" {
  { echo 'BootOrder: 0000,0004,0003'; entry 0004 "$OTHER"; entry 0003 "$ESP"; } > "$EFI_LIST"
  shim_nvram_first
  grep -qx -- '-o 0003,0000,0004' "$EFI_LOG"
  grep -qx -- '-n 0003' "$EFI_LOG"
}
