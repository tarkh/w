#!/usr/bin/env bats
# pac.bats — install/lib/pac.sh: the w_pac seam (installer.md §5, layer 2).
#
# A stalled mirror cannot be reproduced honestly until the fault-injection endpoint
# of Ф.4 exists, and a green run against live mirrors proves nothing about it. What
# CAN be pinned down here is every decision the seam makes: classification from
# canned pacman output, which mirror gets blamed, that the list is reordered rather
# than trimmed, and that the retry loop stops where it must. `pacman` and `sleep`
# are shadowed by functions; W_PAC_SYSROOT keeps the mirrorlist under the tmpdir so
# a run as root cannot touch the real one.

load helpers

setup() {
  source "$REPO/scripts/install/lib/pac.sh"

  export W_PAC_SYSROOT="$BATS_TEST_TMPDIR/target"
  LIST="$W_PAC_SYSROOT/etc/pacman.d/mirrorlist"
  mkdir -p "$(dirname "$LIST")"
  cat > "$LIST" <<'EOF'
Server = https://one.example.org/$repo/os/$arch
Server = https://two.example.org/$repo/os/$arch
Server = https://three.example.org/$repo/os/$arch
EOF

  OUT="$BATS_TEST_TMPDIR/pacman.out"
  sleep() { :; }   # backoff must not cost the suite 15 seconds
}

servers() { grep '^Server' "$LIST" | sed -E 's|.*//([^/]+)/.*|\1|' | tr '\n' ' '; }

# ── Classification ────────────────────────────────────────────────────────────

@test "class: the three transport signatures from installer.md §5 are network" {
  printf '%s\n' "error: failed retrieving file 'core.db' from one.example.org : Operation too slow. Less than 1 bytes/sec transferred the last 10 seconds" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == network ]]

  printf '%s\n' "error: failed retrieving file 'foo-1.0-1-x86_64.pkg.tar.zst' from two.example.org : The requested URL returned error: 404" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == network ]]

  printf '%s\n' "error: failed to commit transaction (failed to retrieve some files)" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == network ]]
}

@test "class: the wording pacman really prints when it runs out of servers" {
  # Measured against the Ф.4 endpoint, not quoted from memory: exhausting every
  # server for one file says "download library error", and the "(failed to retrieve
  # some files)" phrasing only ever appears as the warning line above it. Until this
  # was added the class was carried solely by the per-file "Operation too slow"
  # lines — true today, but one pacman wording change away from `unknown`.
  printf '%s\n' "error: failed to commit transaction (download library error)" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == network ]]

  printf '%s\n' "error: failed to synchronize all databases (download library error)" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == network ]]
}

@test "class: keyring / disk / package truths are defects, never retried" {
  local sig
  for sig in "error: foo: signature from \"Bob <bob@archlinux.org>\" is invalid" \
             "error: required key missing from keyring" \
             "error: failed to commit transaction (conflicting files)" \
             "error: could not commit transaction: No space left on device" \
             "error: target not found: nonexistent-pkg"; do
    printf '%s\n' "$sig" > "$OUT"
    [[ "$(_w_pac_class "$OUT")" == defect ]] || { echo "not a defect: $sig"; return 1; }
  done
}

@test "class: a defect wins over a transport line in the same transaction" {
  # A run that stalled AND reports an invalid signature is a defect: retrying it
  # would bury the real cause behind three attempts.
  printf '%s\n' \
    "error: failed retrieving file 'foo.pkg.tar.zst' from one.example.org : Operation too slow" \
    "error: foo: signature from \"Bob\" is invalid" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == defect ]]
}

@test "class: unrecognised output is unknown (an unclassified retry is not a retry)" {
  printf '%s\n' "error: something nobody has seen before" > "$OUT"
  [[ "$(_w_pac_class "$OUT")" == unknown ]]
}

# ── Who gets blamed ───────────────────────────────────────────────────────────

@test "mirrors: hosts are read out of pacman's own error lines, deduplicated" {
  printf '%s\n' \
    "error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow" \
    "error: failed retrieving file 'b.pkg.tar.zst' from one.example.org : Operation too slow" \
    "warning: too many errors from two.example.org, skipping for the remainder of this transaction" > "$OUT"
  [[ "$(_w_pac_mirrors "$OUT" | tr '\n' ' ')" == "one.example.org two.example.org " ]]
}

@test "mirrors: nothing named when pacman names nobody" {
  printf '%s\n' "error: failed to commit transaction (failed to retrieve some files)" > "$OUT"
  [[ -z "$(_w_pac_mirrors "$OUT")" ]]
}

@test "mirrors: the port is part of the name pacman prints, so it is kept" {
  # Verbatim from a real pacman against a stalled endpoint (Ф.4). Stopping the
  # capture at the colon yielded a bare host that matches no Server line, so the
  # demotion below silently degraded into a rotate. A mirrorlist entry with an
  # explicit port is legal, so this was a live gap, not a harness artefact.
  printf '%s\n' \
    "error: failed retrieving file 'core.db' from 10.0.2.2:18083 : Operation too slow. Less than 1 bytes/sec transferred the last 10 seconds" \
    "warning: too many errors from 10.0.2.2:18080, skipping for the remainder of this transaction" > "$OUT"
  [[ "$(_w_pac_mirrors "$OUT" | tr '\n' ' ')" == "10.0.2.2:18083 10.0.2.2:18080 " ]]
}

@test "mirrors: a message that merely contains 'from' is not a host name" {
  # "required key missing from keyring" used to be one comma away from being read
  # as the mirror to blame; the patterns are keyed on pacman's two real shapes now.
  printf '%s\n' \
    "error: required key missing from keyring" \
    "error: failed to commit transaction (download library error)" > "$OUT"
  [[ -z "$(_w_pac_mirrors "$OUT")" ]]
}

# ── Reordering the list ───────────────────────────────────────────────────────

@test "demote: the blamed mirror goes last and the list keeps its depth" {
  _w_pac_demote "$LIST" one.example.org
  [[ "$(servers)" == "two.example.org three.example.org one.example.org " ]]
  [[ "$(grep -c '^Server' "$LIST")" == 3 ]]
}

@test "demote: several blamed mirrors, order among the survivors preserved" {
  _w_pac_demote "$LIST" one.example.org three.example.org
  [[ "$(servers)" == "two.example.org one.example.org three.example.org " ]]
}

@test "demote: a mirror named with its port matches the entry that carries it" {
  cat > "$LIST" <<'EOF'
Server = http://10.0.2.2:18080/one.example.org/$repo/os/$arch
Server = http://10.0.2.2:18081/two.example.org/$repo/os/$arch
Server = https://three.example.org/$repo/os/$arch
EOF
  _w_pac_demote "$LIST" 10.0.2.2:18080
  [[ "$(servers)" == "10.0.2.2:18081 three.example.org 10.0.2.2:18080 " ]]
  [[ "$(grep -c '^Server' "$LIST")" == 3 ]]
}

@test "demote: a bare host still matches an entry that carries a port" {
  printf 'Server = http://mirror.example.org:8080/$repo/os/$arch\nServer = https://other.example.org/$repo/os/$arch\n' > "$LIST"
  _w_pac_demote "$LIST" mirror.example.org
  [[ "$(servers)" == "other.example.org mirror.example.org:8080 " ]]
}

@test "demote: a host that is not in the list changes nothing and reports it" {
  run _w_pac_demote "$LIST" other.example.org
  [[ "$status" -ne 0 ]]
  [[ "$(servers)" == "one.example.org two.example.org three.example.org " ]]
}

@test "rotate: head to the bottom when pacman named nobody" {
  _w_pac_rotate "$LIST"
  [[ "$(servers)" == "two.example.org three.example.org one.example.org " ]]
}

@test "rotate: a single-entry list cannot be rotated and says so" {
  printf 'Server = https://only.example.org/$repo/os/$arch\n' > "$LIST"
  run _w_pac_rotate "$LIST"
  [[ "$status" -ne 0 ]]
}

# ── The loop ──────────────────────────────────────────────────────────────────

# Fake pacman: fails the first $FAIL_TIMES attempts with $FAIL_OUT, then succeeds.
# The attempt counter lives in a file — w_pac runs it in a pipeline (subshell).
fake_pacman() {
  pacman() {
    local n; n=$(( $(cat "$BATS_TEST_TMPDIR/n" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$BATS_TEST_TMPDIR/n"
    (( n > FAIL_TIMES )) && { echo "installing things"; return 0; }
    printf '%s\n' "$FAIL_OUT"
    return 1
  }
}
attempts() { cat "$BATS_TEST_TMPDIR/n"; }

@test "w_pac: a network failure is retried against a different mirror and survives" {
  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_pacman

  run w_pac -S --needed --noconfirm foo
  [[ "$status" -eq 0 ]]
  [[ "$(attempts)" == 2 ]]
  # The retry changed something: the blamed host is no longer the one pacman would
  # reach first. Without this the "retry" is just a sleep.
  [[ "$(servers)" == "two.example.org three.example.org one.example.org " ]]
  [[ "$output" == *"PAC: attempt 1/3 failed on one.example.org (class=network)"* ]]
  [[ "$output" == *"mirror demoted to the bottom"* ]]
  [[ "$output" == *"PAC: transaction succeeded on attempt 2"* ]]
  [[ "$output" != *CRITICAL* ]]   # a survived flake must not trip vm/e2e.sh's gate
}

@test "w_pac: no mirror named — the head is rotated instead" {
  FAIL_TIMES=1
  FAIL_OUT="error: failed to commit transaction (failed to retrieve some files)"
  fake_pacman

  run w_pac -S foo
  [[ "$status" -eq 0 ]]
  [[ "$(servers)" == "two.example.org three.example.org one.example.org " ]]
  [[ "$output" == *"mirrorlist head rotated"* ]]
}

@test "w_pac: named mirrors that are absent from THIS list say so, not 'nobody named'" {
  # The rotate branch is reached both when pacman named nobody and when it named
  # hosts this list does not contain — the latter meaning the wrong mirrorlist is
  # being reordered. Cost a live debugging session precisely because the message
  # claimed "no mirror named" while the parser had in fact found twenty.
  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from stranger.example.org : Operation too slow"
  fake_pacman

  run w_pac -S foo
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1 mirror(s) named, none of them in"* ]]
  [[ "$output" == *"head rotated"* ]]
  [[ "$output" != *"no mirror named"* ]]
}

@test "w_pac: a stubborn network failure stops after W_PAC_TRIES and is tagged" {
  FAIL_TIMES=99
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_pacman

  run w_pac -S foo
  [[ "$status" -ne 0 ]]
  [[ "$(attempts)" == 3 ]]
  [[ "$output" == *"CRITICAL"* ]]
  [[ "$output" == *"failed after 3 attempts (class=network, last mirror=one.example.org)"* ]]
}

@test "w_pac: a defect is not retried at all" {
  FAIL_TIMES=99
  FAIL_OUT="error: foo: signature from \"Bob\" is invalid"
  fake_pacman

  run w_pac -S foo
  [[ "$status" -ne 0 ]]
  [[ "$(attempts)" == 1 ]]
  [[ "$output" == *"not retried (class=defect"* ]]
  [[ "$(servers)" == "one.example.org two.example.org three.example.org " ]]
}

@test "w_pac: an unrecognised failure is not retried either" {
  FAIL_TIMES=99
  FAIL_OUT="error: something nobody has seen before"
  fake_pacman

  run w_pac -S foo
  [[ "$status" -ne 0 ]]
  [[ "$(attempts)" == 1 ]]
  [[ "$output" == *"not retried (class=unknown"* ]]
}

@test "w_pac: pacman's output still flows to stdout (progress bars parse it)" {
  FAIL_TIMES=0; FAIL_OUT=""
  fake_pacman
  run w_pac -S foo
  [[ "$output" == *"installing things"* ]]
  [[ "$output" != *PAC:* ]]   # a healthy run leaves no PAC: line at all
}

@test "w_pac: returns the status to the caller instead of killing the phase" {
  # Modules live under `set -e`: the seam must hand control back, not exit. The
  # test runs in a separate shell WITH set -e, because bats itself does not set it
  # and a naive in-process check would pass on broken code (checks.md rule 9).
  FAIL_TIMES=99
  run bash -c "
    set -euo pipefail
    export W_PAC_SYSROOT='$W_PAC_SYSROOT'
    source '$REPO/scripts/install/lib/pac.sh'
    sleep() { :; }
    pacman() { echo 'error: foo: signature from \"Bob\" is invalid'; return 1; }
    rc=0; w_pac -S foo || rc=\$?
    echo \"handed back rc=\$rc\"
  "
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"handed back rc=1"* ]]
}

@test "w_pac: the installer path goes through arch-chroot into \$MNT" {
  MNT="$BATS_TEST_TMPDIR/mnt"
  arch-chroot() { echo "chroot:$*"; }
  run w_pac -S --needed --noconfirm foo
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"chroot:$MNT pacman -S --needed --noconfirm foo"* ]]
}

# ── w_run_retry: the pacstrap seam ────────────────────────────────────────────
#
# pacstrap cannot go through w_pac (it takes none of pacman's arguments and is
# wrapped in progress_pacman), so it gets the generic runner, which classifies the
# slice of $W_LOG its own command appended. `step` below imitates that exactly:
# write to $W_LOG, return nonzero — which is what progress_pacman's `tee -a
# "$W_LOG"` and install.sh's `exec >>"$W_LOG"` both produce.
fake_step() {
  W_LOG="$BATS_TEST_TMPDIR/install.log"
  : > "$W_LOG"
  step() {
    local n; n=$(( $(cat "$BATS_TEST_TMPDIR/n" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$BATS_TEST_TMPDIR/n"
    if (( n > FAIL_TIMES )); then echo "installed things" >> "$W_LOG"; return 0; fi
    printf '%s\n' "$FAIL_OUT" >> "$W_LOG"
    return 1
  }
}

@test "w_run_retry: a network failure is classified from the log and retried" {
  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_step

  run w_run_retry pacstrap step
  [[ "$status" -eq 0 ]]
  [[ "$(attempts)" == 2 ]]
  [[ "$(servers)" == "two.example.org three.example.org one.example.org " ]]
  [[ "$output" == *"PAC: pacstrap attempt 1/3 failed on one.example.org (class=network)"* ]]
  [[ "$output" == *"PAC: pacstrap succeeded on attempt 2"* ]]
  [[ "$output" != *CRITICAL* ]]
}

@test "w_run_retry: only the slice this command appended is classified" {
  # The install log is one file for the whole run, so an earlier step's text is
  # sitting in it. Here that text is a DEFECT signature and this step's own failure
  # is transport: classifying the whole file would let the stale line win (fatal is
  # tested first, by design) and refuse a retry that should happen. Reading only the
  # bytes this command appended is what keeps the two apart.
  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_step
  printf '%s\n' "error: foo: signature from \"Bob\" is invalid" >> "$W_LOG"

  run w_run_retry pacstrap step
  [[ "$status" -eq 0 ]]
  [[ "$(attempts)" == 2 ]]
  [[ "$output" == *"class=network"* ]]
  [[ "$output" != *"class=defect"* ]]
}

@test "w_run_retry: the host mirrorlist is demoted even though \$MNT is set" {
  # The open question this answers: during pacstrap $MNT exists, but the transaction
  # reads the HOST's list — pacstrap only copies it into the target after the
  # packages land. Reordering the target's copy would change nothing at all.
  MNT="$BATS_TEST_TMPDIR/mnt"
  mkdir -p "$MNT/etc/pacman.d"
  cp "$LIST" "$MNT/etc/pacman.d/mirrorlist"

  local host="$BATS_TEST_TMPDIR/host"
  mkdir -p "$host/etc/pacman.d"
  cp "$LIST" "$host/etc/pacman.d/mirrorlist"

  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_step

  W_PAC_SYSROOT="$host" run w_run_retry pacstrap step
  [[ "$status" -eq 0 ]]
  local reordered untouched
  reordered=$(grep '^Server' "$host/etc/pacman.d/mirrorlist" | sed -E 's|.*//([^/]+)/.*|\1|' | tr '\n' ' ')
  untouched=$(grep '^Server' "$MNT/etc/pacman.d/mirrorlist" | sed -E 's|.*//([^/]+)/.*|\1|' | tr '\n' ' ')
  [[ "$reordered" == "two.example.org three.example.org one.example.org " ]]
  [[ "$untouched" == "one.example.org two.example.org three.example.org " ]]
}

@test "w_run_retry: the pre-retry hook runs, and only between attempts" {
  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_step
  reset_hook() { echo "hook ran" >> "$BATS_TEST_TMPDIR/hook"; }

  W_PAC_PRERETRY=reset_hook run w_run_retry pacstrap step
  [[ "$status" -eq 0 ]]
  [[ "$(grep -c 'hook ran' "$BATS_TEST_TMPDIR/hook")" == 1 ]]
}

@test "w_run_retry: partial downloads are cleared from the cache root, not the list root" {
  local cacheroot="$BATS_TEST_TMPDIR/mnt"
  mkdir -p "$cacheroot/var/cache/pacman/pkg"
  touch "$cacheroot/var/cache/pacman/pkg/half.pkg.tar.zst.part"
  mkdir -p "$W_PAC_SYSROOT/var/cache/pacman/pkg"
  touch "$W_PAC_SYSROOT/var/cache/pacman/pkg/keep.pkg.tar.zst.part"

  FAIL_TIMES=1
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_step

  W_PAC_CACHE_ROOT="$cacheroot" run w_run_retry pacstrap step
  [[ "$status" -eq 0 ]]
  [[ ! -e "$cacheroot/var/cache/pacman/pkg/half.pkg.tar.zst.part" ]]
  [[ -e "$W_PAC_SYSROOT/var/cache/pacman/pkg/keep.pkg.tar.zst.part" ]]
}

@test "w_run_retry: without \$W_LOG there is nothing to classify, so no retry" {
  # An unconditional retry is precisely the variant §5 rejects — so the honest
  # answer to "no output to read" is one attempt and a line saying why.
  FAIL_TIMES=99
  FAIL_OUT="error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow"
  fake_step
  W_LOG=""

  run w_run_retry pacstrap step
  [[ "$status" -ne 0 ]]
  [[ "$(attempts)" == 1 ]]
  [[ "$output" == *"no \$W_LOG to classify against — not retried"* ]]
}

@test "w_run_retry: a callee's errexit is not leaked back to the caller" {
  # Not hypothetical: progress_pacman — the wrapper the installer passes in — ends
  # with an unconditional `set -e`. A runner that only ever RE-ENABLES errexit
  # would hand it back on to a caller that never had it (w-pack and the other
  # runtime tools run without it), so the next harmless nonzero status in that
  # script would exit it silently. The caller here therefore deliberately runs
  # WITHOUT -e, and the assertion is that it still does afterwards.
  cat > "$BATS_TEST_TMPDIR/errexit.sh" <<EOS
set -uo pipefail
export W_PAC_SYSROOT='$W_PAC_SYSROOT'
source '$REPO/scripts/install/lib/pac.sh'
sleep() { :; }
W_LOG='$BATS_TEST_TMPDIR/ee.log'; : > "\$W_LOG"
n=0
step() {
  n=\$((n + 1))
  set +e
  if (( n > 1 )); then set -e; return 0; fi
  echo "error: failed retrieving file 'a.pkg.tar.zst' from one.example.org : Operation too slow" >> "\$W_LOG"
  set -e          # exactly what progress_pacman does before returning
  return 1
}
rc=0; w_run_retry pacstrap step || rc=\$?
case \$- in *e*) ee=on ;; *) ee=off ;; esac
echo "rc=\$rc attempts=\$n errexit=\$ee"
EOS
  run bash "$BATS_TEST_TMPDIR/errexit.sh"
  [[ "$status" -eq 0 ]]
  # errexit=off — the setting the caller started with, despite the callee's set -e.
  [[ "$output" == *"rc=0 attempts=2 errexit=off"* ]]
}

@test "w_run_retry: a defect is not retried, and the list is left alone" {
  FAIL_TIMES=99
  FAIL_OUT="error: required key missing from keyring"
  fake_step

  run w_run_retry pacstrap step
  [[ "$status" -ne 0 ]]
  [[ "$(attempts)" == 1 ]]
  [[ "$output" == *"not retried (class=defect"* ]]
  [[ "$(servers)" == "one.example.org two.example.org three.example.org " ]]
}

@test "w_run_retry: returns the status to the caller instead of killing the phase" {
  # Same reasoning as the w_pac twin: mod_base runs under set -e, and the runner
  # must hand control back. Separate shell WITH set -euo pipefail, because bats does
  # not set it and an in-process check would pass on broken code (checks.md rule 9).
  run bash -c "
    set -euo pipefail
    export W_PAC_SYSROOT='$W_PAC_SYSROOT'
    source '$REPO/scripts/install/lib/pac.sh'
    sleep() { :; }
    W_LOG='$BATS_TEST_TMPDIR/rc.log'; : > \"\$W_LOG\"
    step() { echo 'error: target not found: nope' >> \"\$W_LOG\"; return 1; }
    rc=0; w_run_retry pacstrap step || rc=\$?
    echo \"handed back rc=\$rc\"
  "
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"handed back rc=1"* ]]
}
