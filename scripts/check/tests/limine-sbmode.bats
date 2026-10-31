#!/usr/bin/env bats
# limine-sbmode.bats — limine_migrate_secureboot_mode over the states a live machine
# can carry into mod_limine: config-hash enrollment with and without sbctl's keys, and
# a mode file with and without them. sbctl is a PATH stub; the function's absolute
# paths are rewritten into the test. What the firmware then boots is the e2e.

load helpers

setup() {
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  export SBCTL_STATE="$BATS_TEST_TMPDIR/sbctl-state"
  printf '#!/bin/sh\ncat "$SBCTL_STATE" 2>/dev/null\n' > "$bin/sbctl"
  chmod +x "$bin/sbctl"
  PATH="$bin:$PATH"
  MODE="$BATS_TEST_TMPDIR/secureboot-mode" DEFAULT="$BATS_TEST_TMPDIR/default-limine"
  source "$REPO/scripts/install/modules/limine.sh"
  ui_info() { :; }
  eval "$(declare -f limine_migrate_secureboot_mode \
    | sed -e "s#/var/lib/w/secureboot-mode#$MODE#g" -e "s#/etc/default/limine#$DEFAULT#g")"
}

keys() { printf '{\n  "installed": true,\n  "landlock": true\n}\n' > "$SBCTL_STATE"; }

@test "enrollment + sbctl keys, no mode file → own" {
  keys; echo 'ENABLE_ENROLL_LIMINE_CONFIG=yes' > "$DEFAULT"
  limine_migrate_secureboot_mode
  [ "$(cat "$MODE")" = own ]
}

@test "enrollment without sbctl keys (the old installer's leftover) → no mode" {
  echo 'ENABLE_ENROLL_LIMINE_CONFIG=yes' > "$DEFAULT"
  limine_migrate_secureboot_mode
  [ ! -e "$MODE" ]
}

@test "mode own without sbctl keys → dropped" {
  echo own > "$MODE"
  limine_migrate_secureboot_mode
  [ ! -e "$MODE" ]
}

@test "mode own with keys, and mode shim → kept as is" {
  keys; echo own > "$MODE"
  limine_migrate_secureboot_mode
  [ "$(cat "$MODE")" = own ]
  rm -f "$SBCTL_STATE"; echo shim > "$MODE"
  limine_migrate_secureboot_mode
  [ "$(cat "$MODE")" = shim ]
}
