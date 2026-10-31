#!/usr/bin/env bats
# bootmenu.bats — Windows next to W in the boot menus: the detector (w-boot-otheros)
# over efibootmgr output, and both consumers — GRUB's 35_w-other-os and Limine's
# post.d/60-w-other-os. efibootmgr/lsblk are PATH stubs fed from fixtures; the
# consumers' absolute helper paths are rewritten to the checkout. What a real
# firmware does with the entries is the dual-boot e2e (vm/e2e.sh --dualboot).

load helpers

DETECT="$REPO/rootfs/usr/lib/w/w-boot-otheros"
WIN=5a9896b2-d432-4c67-b4c6-23e0cd597c8e
W_ESP=33719f7c-54b8-4d6b-9276-26b66a7a3468

setup() {
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  export EFI_OUT="$BATS_TEST_TMPDIR/efi.out" PARTS="$BATS_TEST_TMPDIR/parts"
  printf '#!/bin/sh\ncat "$EFI_OUT"\n' > "$bin/efibootmgr"
  printf '#!/bin/sh\ncat "$PARTS"\n' > "$bin/lsblk"
  chmod +x "$bin"/*
  PATH="$bin:$PATH"
  # efibootmgr 18 as printed on a real dual-boot laptop (optional data glued on).
  printf '%s\n' 'BootCurrent: 0005' 'BootOrder: 0005,0000,0006' \
    "Boot0000* Windows Boot Manager	HD(1,GPT,$WIN,0x800,0x32000)/\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI57494e444f5753000100" \
    "Boot0005* W (Limine)	HD(1,GPT,$W_ESP,0x800,0x400000)/\\EFI\\limine\\limine_x64.efi" \
    "Boot0006* UEFI OS	HD(1,GPT,$W_ESP,0x800,0x400000)/\\EFI\\BOOT\\BOOTX64.EFI0000424f" > "$EFI_OUT"
  printf '%s\n' "$WIN" '' "$W_ESP" > "$PARTS"
}

# A copy of the consumer with its absolute paths pointed into the test.
localize() {
  sed -e "s#/usr/lib/w/w-boot-otheros#$DETECT#g" \
      -e "s#/etc/default/limine#$BATS_TEST_TMPDIR/default-limine#g" "$1" > "$2"
  chmod +x "$2"
}

limine_hook() {
  source "$REPO/scripts/install/modules/limine.sh"
  limine_write_other_os_hook "$BATS_TEST_TMPDIR/hook.orig"
  localize "$BATS_TEST_TMPDIR/hook.orig" "$BATS_TEST_TMPDIR/hook"
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  echo "ESP_PATH=\"$BATS_TEST_TMPDIR/esp\"" > "$BATS_TEST_TMPDIR/default-limine"
  CONF="$BATS_TEST_TMPDIR/esp/limine.conf"
  printf '%s\n' '# Managed by W.' 'timeout: 1.5' 'quiet: yes' 'default_entry: 1' '' \
    'backdrop: 000000' '' '/+W Linux' '  comment: machine-id=x' '  //linux-zen' \
    '    protocol: linux' '  //Snapshots' '    ///1' > "$CONF"
}

# ── detector ──────────────────────────────────────────────────────────────────

@test "detector: Windows on a present partition, W's own entries ignored" {
  run "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = $'0000\tWindows Boot Manager' ]
}

@test "detector: the older File(...) device-path form" {
  printf '%s\n' "Boot0003* Windows Boot Manager	HD(1,GPT,${WIN^^},0x800,0x32000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)RC" > "$EFI_OUT"
  run "$DETECT"
  [ "$output" = $'0003\tWindows Boot Manager' ]
}

@test "detector: an entry left behind by a wiped Windows is skipped" {
  printf '%s\n' "$W_ESP" > "$PARTS"
  run "$DETECT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detector: two entries for one Windows → one line" {
  sed -n '3p' "$EFI_OUT" | sed 's/Boot0000/Boot0007/' >> "$EFI_OUT"
  run "$DETECT"
  [ "$output" = $'0000\tWindows Boot Manager' ]
}

@test "detector: no EFI variables → nothing, exit 0" {
  printf '#!/bin/sh\nexit 2\n' > "$BATS_TEST_TMPDIR/bin/efibootmgr"
  run "$DETECT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── GRUB: 35_w-other-os ───────────────────────────────────────────────────────

grub_script() {
  [[ -f /usr/share/grub/grub-mkconfig_lib ]] || skip "grub not installed"
  localize "$REPO/rootfs/etc/grub.d/35_w-other-os" "$BATS_TEST_TMPDIR/35"
  pkgdatadir=/usr/share/grub run sh "$BATS_TEST_TMPDIR/35"
}

@test "grub: a BootNext entry per Windows and a visible menu" {
  grub_script
  [ "$status" -eq 0 ]
  grep -qF "menuentry 'Windows Boot Manager'" <<< "$output"
  grep -qF 'if bootnext 0000; then' <<< "$output"
  grep -qx 'set timeout_style=menu' <<< "$output"
  grep -qx 'set timeout=5' <<< "$output"
  ! grep -q chainloader <<< "$output"
}

@test "grub: no Windows → no grub.cfg lines at all" {
  printf '%s\n' "$W_ESP" > "$PARTS"
  grub_script
  [ "$status" -eq 0 ]
  [ -z "$(grep -v '^Found' <<< "$output")" ]
}

# ── Limine: post.d/60-w-other-os ──────────────────────────────────────────────

@test "limine: no Windows → limine.conf untouched, byte for byte" {
  limine_hook
  printf '%s\n' "$W_ESP" > "$PARTS"
  cp "$CONF" "$BATS_TEST_TMPDIR/before"
  touch -d '2000-01-01' "$CONF"
  run "$BATS_TEST_TMPDIR/hook"
  [ "$status" -eq 0 ]
  cmp "$CONF" "$BATS_TEST_TMPDIR/before"
  [ "$(stat -c %Y "$CONF")" -eq "$(date -d 2000-01-01 +%s)" ]
}

@test "limine: Windows → efi_boot_entry at the end, menu shown; idempotent" {
  limine_hook
  "$BATS_TEST_TMPDIR/hook"
  grep -qx 'timeout: 5' "$CONF"
  grep -qx 'quiet: no' "$CONF"
  [ "$(tail -4 "$CONF")" = "/Windows Boot Manager
    comment: Restarts into Windows through the firmware (W)
    protocol: efi_boot_entry
    entry: Windows Boot Manager" ]
  grep -qx '    ///1' "$CONF"
  cp "$CONF" "$BATS_TEST_TMPDIR/once"
  "$BATS_TEST_TMPDIR/hook"
  cmp "$CONF" "$BATS_TEST_TMPDIR/once"
}

@test "limine: the entry is moved back to the end after a regeneration" {
  limine_hook
  "$BATS_TEST_TMPDIR/hook"
  cp "$CONF" "$BATS_TEST_TMPDIR/once"
  # limine-entry-tool appending its OS branch after our entry
  printf '\n%s\n' '/+Other' '  //x' >> "$CONF"
  "$BATS_TEST_TMPDIR/hook"
  [ "$(tail -1 "$CONF")" = '    entry: Windows Boot Manager' ]
  [ "$(grep -c '^/Windows Boot Manager$' "$CONF")" -eq 1 ]
  grep -qx '/+Other' "$CONF"
}

@test "limine: Windows gone → entry removed, install-time menu restored" {
  limine_hook
  cp "$CONF" "$BATS_TEST_TMPDIR/before"
  "$BATS_TEST_TMPDIR/hook"
  printf '%s\n' "$W_ESP" > "$PARTS"
  "$BATS_TEST_TMPDIR/hook"
  cmp "$CONF" "$BATS_TEST_TMPDIR/before"
}

@test "limine: the install-time seed keeps W as entry 1" {
  limine_hook
  printf '%s\n' 'timeout: 1.5' 'quiet: yes' 'default_entry: 1' '' '/W Linux' \
    '    protocol: linux' > "$CONF"
  "$BATS_TEST_TMPDIR/hook"
  [ "$(grep -m1 '^/' "$CONF")" = '/W Linux' ]
}
