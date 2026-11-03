#!/usr/bin/env bats
# progress.bats — progress_pacman moves the gauge through the download and the
# install, not only at their ends. Piped pacman flushes its per-file lines in 4 KiB
# bursts (largest downloads first) and prints "installing <pkg>..." with no counter,
# so the bar sat at 0% through the download and jumped at the end (found on a real
# install). The fake transaction here prints only what arrives on time — the two
# totals — and does the work in the target root, which the ticks must turn into
# intermediate percentages. dialog is a stub that keeps the gauge stream.

load helpers

setup() {
  source "$REPO/scripts/install/lib/progress.sh"
  DIALOG_COMMON=()
  t() { echo "$1"; }
  dialog() { cat > "$BATS_TEST_TMPDIR/gauge"; }
  sleep() { command sleep 0.1; }   # the ticker's 1 s period, sped up
  exec {W_TTY}>/dev/null
  W_LOG="$BATS_TEST_TMPDIR/install.log"; : > "$W_LOG"
  R="$BATS_TEST_TMPDIR/root"
  mkdir -p "$R/var/cache/pacman/pkg" "$R/var/lib/pacman/local"
}

fake_pacstrap() {
  printf '%s\n' "Packages (4) a-1 b-1 c-1 d-1" "" "Total Download Size:   4.00 MiB" \
    ":: Retrieving packages..."
  local i
  for i in 1 2 3 4; do
    head -c 1048576 /dev/zero > "$R/var/cache/pacman/pkg/p$i.pkg.tar.zst"; command sleep 0.4
  done
  for i in 1 2 3 4; do mkdir "$R/var/lib/pacman/local/p$i-1"; command sleep 0.4; done
  printf '%s\n' ":: Running post-transaction hooks..." "(1/2) one" "(2/2) two"
  return 3
}

# The percentages of the gauge stream, one per line.
pcts() { awk 'prev == "XXX" && /^[0-9]+$/ { print } { prev = $0 }' "$BATS_TEST_TMPDIR/gauge"; }

@test "download and install both move the bar; it never goes back; rc survives" {
  W_PAC_CACHE_ROOT="$R"
  run progress_pacman title fake_pacstrap
  [ "$status" -eq 3 ]
  run pcts
  printf '%s\n' "$output" | grep -qE '^([1-9]|[1-3][0-9]|4[0-4])$'   # mid-download
  printf '%s\n' "$output" | grep -qE '^(4[6-9]|[5-8][0-9])$'          # mid-install
  [ "${lines[-1]}" = 100 ]
  [ "$(printf '%s\n' "$output" | sort -n -c 2>&1)" = "" ]
  [ "$(grep -c WTICK "$W_LOG")" = 0 ]
  grep -qE '^[0-9] / 4 u_mib$' "$BATS_TEST_TMPDIR/gauge"
}

@test "no target root → no ticks, the counter-less lines are counted instead" {
  W_PAC_CACHE_ROOT=""
  lines_only() {
    printf '%s\n' "Packages (2) a-1 b-1" " a-1-any downloading..." " b-1-any downloading..." \
      "installing a..." "installing b..."
  }
  run progress_pacman title lines_only
  [ "$status" -eq 0 ]
  run pcts
  [ "$output" = $'22\n45\n67\n90\n100' ]
}
