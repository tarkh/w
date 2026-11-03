#!/usr/bin/env bats
# mok-refused.bats — firmware that refuses shim's variables from a running OS (AMI
# Aptio IV, ASUS X99: mokutil → EINVAL; MokManager at boot writes fine). Phase 1 must
# finish with the "Enroll key from disk" steps instead of failing, and the installer
# must read the missing MokNew as "no code, from disk". mokutil and chroot_run are
# stubs; what the firmware then does is the hardware run.

load helpers

setup() {
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"; PATH="$bin:$PATH"
  export MOK_IMPORT_RC=0
  cat > "$bin/mokutil" <<'EOF'
#!/bin/sh
case "$1" in
  --generate-hash=*) echo '$6$salt$hash' ;;
  --timeout) exit "$MOK_IMPORT_RC" ;;
  --import) exit "$MOK_IMPORT_RC" ;;
esac
EOF
  chmod +x "$bin/mokutil"
}

lift_mok_queue() {
  eval "$(sed -n -e '/^err() /p' -e '/^mok_disk_hint() {/,/^}/p' -e '/^mok_queue() {/,/^}/p' \
    "$REPO/rootfs/usr/bin/w-secureboot")"
}

@test "w-secureboot: the import goes through → the code and Enroll MOK steps" {
  lift_mok_queue
  run mok_queue /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enroll MOK"* ]]
  [[ "$output" != *"Enroll key from disk"* ]]
}

@test "w-secureboot: the firmware refuses the import → phase 1 goes on, from-disk steps" {
  lift_mok_queue
  MOK_IMPORT_RC=255 run mok_queue /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"refused"* ]]
  [[ "$output" == *"Enroll key from disk → W_EFI"* ]]
  [[ "$output" != *"Enroll MOK →"* ]]
}

setup_installer() {
  MNT="$BATS_TEST_TMPDIR/mnt"; mkdir -p "$MNT/var/tmp" "$MNT/root"
  wrepo="$BATS_TEST_TMPDIR/w-repo"; mkdir -p "$wrepo"
  touch "$wrepo/shim-signed-16.1-1-any.pkg.tar.zst"
  export W_EFIVARS="$BATS_TEST_TMPDIR/efivars"; mkdir -p "$W_EFIVARS"
  W_UNATTENDED="" W_TRACE_FD=""
  source "$REPO/scripts/install/modules/limine.sh"
  ui_info() { :; }
  die() { echo "DIE: $*"; return 1; }
  chroot_run() { :; }
  DROPPED=""; limine_mok_drop_medium() { DROPPED=1; }
  eval "$(declare -f limine_secureboot | sed "s#/root/w-repo#$wrepo#g")"
}

@test "installer: MokNew queued → code shown, the medium's hash queued for deletion" {
  setup_installer
  touch "$W_EFIVARS/MokNew-605dab50-e046-4300-abb6-3dd810dd8b23"
  limine_secureboot
  [[ "$MOK_CODE" =~ ^[0-9]{8}$ ]]
  [ -z "$MOK_FROM_DISK" ]
  [ "$DROPPED" = 1 ]
}

@test "installer: no MokNew after phase 1 → from disk, no code, the medium's hash left" {
  setup_installer
  limine_secureboot
  [ -z "$MOK_CODE" ]
  [ "$MOK_FROM_DISK" = 1 ]
  [ -z "$DROPPED" ]
}

@test "installer: unattended → neither code nor from-disk screen (nobody reads it)" {
  setup_installer
  W_UNATTENDED=1
  limine_secureboot
  [ -z "$MOK_CODE" ]
  [ -z "$MOK_FROM_DISK" ]
}
