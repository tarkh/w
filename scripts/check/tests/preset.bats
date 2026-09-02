#!/usr/bin/env bats
# preset.bats — install/lib/tui.sh: preset (unattended install) parsing +
# validation. answers_serialize → answers_load must round-trip losslessly, and
# preset_validate must replay the wizard's per-step rules offline.
#
# tui.sh is sourced standalone: die/dialog helpers are stubbed, steps.conf is
# the real one (so the tests track the live step map). Arch-only validators
# (v_keymap → loadkeys) and host-specific ones (v_blockdev) are shadowed.

load helpers

setup() {
  # tui.sh reads steps.conf relative to its own dir — the real file.
  source "$REPO/scripts/install/lib/tui.sh"
  die() { echo "die: $*" >&2; exit 1; }

  load_steps

  # Host-agnostic shadows for environment-bound validators. The functions are
  # still *called* by preset_validate — only their probe is replaced.
  v_keymap()   { [[ "$1" =~ ^[a-z0-9-]+$ ]]; }
  v_blockdev() { [[ "$1" == /dev/* ]]; }
  # v_edge_repo (install.sh, not sourced here) does a real network git clone —
  # stub it host-agnostic/offline, like the shadows above; presence of a value
  # is already enforced by preset_validate's own required-field check.
  v_edge_repo() { [[ -n "$1" ]]; }
  # steps.conf conditions reference live-ISO helpers; provide deterministic
  # stubs (no Wi-Fi step, packs step visible so its bundle check is exercised).
  net_has_wifi()    { return 1; }
  packs_available() { return 0; }
  SRC="$REPO"

  PRESET="$BATS_TEST_TMPDIR/preset.conf"
}

# Minimal complete answers for the plain (unencrypted) path.
fill_valid_answers() {
  ANSWERS[keymap]=us
  ANSWERS[locale]=en_US.UTF-8
  ANSWERS[mode]=stable
  ANSWERS[disk]=/dev/vda
  ANSWERS[encrypt]=no
  ANSWERS[hostname]=w-e2e
  ANSWERS[timezone]=Europe/Moscow
  ANSWERS[root_pass]=secret
  ANSWERS[user]=w
  ANSWERS[user_pass]=secret
}

@test "answers_serialize → answers_load round-trips tricky values" {
  fill_valid_answers
  ANSWERS[root_pass]='p a$s "q" '\''w'\''`x`;&|'
  ANSWERS[hostname]='host with spaces'
  LANG_CODE=ru
  answers_serialize "$PRESET"

  local want_pass="${ANSWERS[root_pass]}" want_host="${ANSWERS[hostname]}"
  ANSWERS=()
  answers_load "$PRESET"
  [[ "${ANSWERS[root_pass]}" == "$want_pass" ]]
  [[ "${ANSWERS[hostname]}" == "$want_host" ]]
  [[ "${ANSWERS[disk]}" == /dev/vda ]]
  [[ "$lang" == ru ]]
}

@test "answers_load: unknown key aborts with file:line" {
  printf 'disk=/dev/vda\ndiks=/dev/vdb\n' > "$PRESET"
  run answers_load "$PRESET"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown key 'diks'"* ]]
  [[ "$output" == *":2"* ]]
}

@test "answers_load: non-assignment line aborts" {
  printf 'disk=/dev/vda\nrm -rf /\n' > "$PRESET"
  run answers_load "$PRESET"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not a key=value line"* ]]
}

@test "answers_load: missing file aborts" {
  run answers_load "$BATS_TEST_TMPDIR/nope.conf"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Preset not found"* ]]
}

@test "answers_load: comments and blank lines are ignored" {
  printf '# a comment\n\ndisk=/dev/vda\n' > "$PRESET"
  answers_load "$PRESET"
  [[ "${ANSWERS[disk]}" == /dev/vda ]]
}

@test "preset_validate: complete plain-path preset passes" {
  fill_valid_answers
  run preset_validate
  [[ "$status" -eq 0 ]]
}

@test "preset_validate: missing required fields are all reported" {
  fill_valid_answers
  unset 'ANSWERS[root_pass]' 'ANSWERS[user]'
  run preset_validate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"root_pass: missing"* ]]
  [[ "$output" == *"user: missing"* ]]
}

@test "preset_validate: encrypt=yes requires luks_pass (conditional step)" {
  fill_valid_answers
  ANSWERS[encrypt]=yes
  run preset_validate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"luks_pass: missing"* ]]

  ANSWERS[luks_pass]=lockpick
  run preset_validate
  [[ "$status" -eq 0 ]]
}

@test "preset_validate: encrypt=no leaves luks_pass invisible" {
  fill_valid_answers
  run preset_validate
  [[ "$status" -eq 0 ]]
  [[ "$output" != *luks_pass* ]]
}

@test "preset_validate: bad enum values are rejected" {
  fill_valid_answers
  ANSWERS[mode]=edgy
  ANSWERS[encrypt]=maybe
  ANSWERS[disk]=vda
  ANSWERS[timezone]=Nowhere/None
  run preset_validate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"mode: 'edgy'"* ]]
  [[ "$output" == *"encrypt: 'maybe'"* ]]
  [[ "$output" == *"disk: 'vda'"* ]]
  [[ "$output" == *"timezone"* ]]
}

@test "preset_validate: unknown packs bundle is rejected, real one passes" {
  fill_valid_answers
  ANSWERS[packs]="containers no-such-bundle"
  run preset_validate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown bundle 'no-such-bundle'"* ]]
  [[ "$output" != *"'containers'"* ]]
}

# The shipped samples must always load + validate — this pins them to the live
# steps.conf (a new required step without a sample default breaks here first).
@test "preset_validate: shipped plain sample passes" {
  answers_load "$REPO/vm/e2e/preset-plain.sample.conf"
  run preset_validate
  [[ "$status" -eq 0 ]]
}

@test "preset_validate: shipped encrypted sample passes" {
  answers_load "$REPO/vm/e2e/preset-encrypted.sample.conf"
  run preset_validate
  [[ "$status" -eq 0 ]]
  [[ "${ANSWERS[encrypt]}" == yes ]]
}

@test "answers_serialize: unattended flag persists only in preset mode" {
  fill_valid_answers
  answers_serialize "$PRESET"
  ! grep -q '^unattended=' "$PRESET"

  W_UNATTENDED=1 answers_serialize "$PRESET"
  grep -q '^unattended=1$' "$PRESET"
}
