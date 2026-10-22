#!/usr/bin/env bats
# snapshots.bats — home snapper retention and the one-anchor-per-update contract.
#
# apply.sh and w-sync cannot be sourced (both dispatch at the bottom), so the
# functions are lifted out with sed and run against a `snapper` stub that records
# its arguments — what passes here is the code that ships. The real snapper side
# (ranges + FREE_LIMIT without btrfs quota) is a VM check, see snapshots.md.

load helpers

APPLY="$REPO/scripts/apply.sh"
WSYNC="$REPO/rootfs/usr/bin/w-sync"

setup() {
  LOG="$BATS_TEST_TMPDIR/snapper.log"; : > "$LOG"
  export LOG
  info() { :; }; warn() { :; }
  run_priv() { "$@"; }
  remount_flatten_snapshots_dir() { echo "remount $*" >> "$LOG"; }
  # Default stub: the home config exists and every call succeeds.
  snapper() { echo "$*" >> "$LOG"; }
}

lift() { eval "$(sed -n "/^$1()/,/^}/p" "$2")"; }

# ── apply.sh ──────────────────────────────────────────────────────────────────

@test "pre_apply_home_snapshot: anchors when nobody else did" {
  lift pre_apply_home_snapshot "$APPLY"
  unset W_HOME_SNAPSHOT_TAKEN
  pre_apply_home_snapshot
  grep -q 'home create --description pre-apply --cleanup-algorithm number' "$LOG"
}

@test "pre_apply_home_snapshot: skips when w-sync already anchored" {
  lift pre_apply_home_snapshot "$APPLY"
  W_HOME_SNAPSHOT_TAKEN=1 pre_apply_home_snapshot
  run grep -c create "$LOG"
  [ "$output" -eq 0 ]
}

@test "configure_home_snapper: an existing config still gets the retention" {
  lift configure_home_snapper "$APPLY"
  configure_home_snapper
  run grep -c create-config "$LOG"
  [ "$output" -eq 0 ]
  grep -q '^remount /home/.snapshots$' "$LOG"
  grep -q 'home set-config .*NUMBER_CLEANUP=yes NUMBER_LIMIT=2-10 .*NUMBER_MIN_AGE=1800' "$LOG"
  grep -q 'home set-config .*FREE_LIMIT=0.2' "$LOG"
  grep -q 'home set-config .*TIMELINE_LIMIT_WEEKLY=2' "$LOG"
}

@test "configure_home_snapper: no @home_snapshots → nothing is configured" {
  lift configure_home_snapper "$APPLY"
  snapper() { echo "$*" >> "$LOG"; [[ "$*" != "-c home list" ]]; }
  mountpoint() { return 1; }
  configure_home_snapper
  run grep -c 'set-config\|create-config' "$LOG"
  [ "$output" -eq 0 ]
}

# ── w-sync ────────────────────────────────────────────────────────────────────

@test "w-sync pre_snapshot: success is reported, so apply can skip its own" {
  lift pre_snapshot "$WSYNC"
  pre_snapshot
  grep -q 'home create --description pre-sync --cleanup-algorithm number' "$LOG"
}

@test "w-sync pre_snapshot: a failed or impossible snapshot is not reported as taken" {
  lift pre_snapshot "$WSYNC"
  snapper() { [[ "$1 $2 $3" == "-c home list" ]]; }
  run pre_snapshot
  [ "$status" -ne 0 ]
  snapper() { return 1; }
  run pre_snapshot
  [ "$status" -ne 0 ]
}

@test "w-sync packs_changed: bundle tree and its deploy machinery only" {
  lift packs_changed "$WSYNC"
  packs_changed $'docs/x.md\nscripts/packs/dev/setup.sh'
  packs_changed 'scripts/install/lib/deploy.sh'
  ! packs_changed $'.claude/library/x.md\nrootfs/usr/bin/w-sync'
}

# The anchor is taken after the pull (which touches only the checkout), only when
# something will run, and the apply it guards is told about it.
@test "w-sync update: pull → gated pre-snapshot → apply with the flag" {
  local p g s a
  p="$(grep -n 'pull --ff-only origin' "$WSYNC" | cut -d: -f1)"
  g="$(grep -n 'if \[\[ -n "\$flags" \]\] || packs_changed "\$changed"; then' "$WSYNC" | cut -d: -f1)"
  s="$(grep -n 'if pre_snapshot; then snap=(env W_HOME_SNAPSHOT_TAKEN=1); fi' "$WSYNC" | cut -d: -f1)"
  a="$(grep -n 'run_priv "\${snap\[@\]}" "\$APPLY" \$flags' "$WSYNC" | cut -d: -f1)"
  [ -n "$p" ] && [ -n "$g" ] && [ -n "$s" ] && [ -n "$a" ]
  [ "$p" -lt "$g" ] && [ "$g" -lt "$s" ] && [ "$s" -lt "$a" ]
}

# A `snapper list | grep -q` under pipefail reads as "absent" once grep closes the
# pipe before snapper is done writing (SIGPIPE → 141): the anchor was re-created on
# every full apply of a machine with a long snapshot list.
@test "initial_snapshot: an existing anchor is found in a long list" {
  lift initial_snapshot "$APPLY"
  snapper() {
    echo "$*" >> "$LOG"
    if [[ "$*" == "-c root list" ]]; then
      echo " 1 | single | W initial state | important=yes"
      for ((i = 2; i < 20000; i++)); do echo " $i | pre | pacman -Syu |"; done
    fi
  }
  set -o pipefail
  initial_snapshot
  run grep -c create "$LOG"
  [ "$output" -eq 0 ]
}

@test "initial_snapshot: created when absent" {
  lift initial_snapshot "$APPLY"
  initial_snapshot
  grep -q 'root create --description W initial state --userdata important=yes' "$LOG"
}
