#!/usr/bin/env bats
# mirrors.bats — w-mirrors: layer 3 of the package-delivery plan (installer.md §5).
#
# What is worth testing here is exactly one promise, and it is the promise that
# cannot be verified by a live run: **no outcome of the ranker may shorten or empty
# /etc/pacman.d/mirrorlist.** A ranking run against healthy mirrors proves the
# mechanism works; it proves nothing at all about the branches that matter — a
# ranker that returns three mirrors, or none, or is killed by its own timeout
# halfway through. Those are the branches that run unattended, from a timer, on a
# machine nobody is watching, and each of them ends with the machine either able or
# unable to install software. So they are driven here, deterministically, with a
# fake `reflector` on PATH.
#
# The scheduling guards get the same treatment: "did not re-rank because the list
# is fresh" and "did not re-rank because the link is metered" are silent successes
# by design, and a silent success is only trustworthy if something asserts it.

load helpers

MIRRORS_BIN="rootfs/usr/bin/w-mirrors"

setup() {
  # Layered-config seams (the same ones wconf.bats uses) — nothing here reads or
  # writes the real /etc/w. The vendor layer is the REAL shipped file, so these
  # tests also fail if the shipped defaults stop parsing or stop validating.
  export WCONF_ETC="$BATS_TEST_TMPDIR/etc-w"
  export WCONF_VENDOR_DIR="$BATS_TEST_TMPDIR/defaults"
  export WCONF_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$WCONF_ETC" "$WCONF_VENDOR_DIR" "$WCONF_HOME/.config/w"
  cp "$REPO/rootfs/usr/share/w/defaults/mirrors.conf" "$WCONF_VENDOR_DIR/mirrors.conf"

  export W_MIRRORS_LIST="$BATS_TEST_TMPDIR/mirrorlist"
  export W_MIRRORS_STATE="$BATS_TEST_TMPDIR/state/mirrors.state"

  # A believable existing list: 12 servers, which is what a machine installed by
  # W actually inherits from the ISO.
  : > "$W_MIRRORS_LIST"
  local i
  for i in $(seq 1 12); do
    echo "Server = https://old$i.example.org/\$repo/os/\$arch" >> "$W_MIRRORS_LIST"
  done

  # Fake reflector: BIN/reflector reads BIN/reflector.mode to decide what to do.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"

  source "$REPO/$MIRRORS_BIN"
  # -u and pipefail off, -e deliberately ON: bats reports a failed assertion through
  # errexit, so `set +e` here would make every test in the file pass regardless.
  set +u; set +o pipefail
  # The tests are unprivileged; the root gate is not what they are about.
  need_root() { :; }
}

# make_reflector <n> — a reflector that saves n ranked servers and exits 0.
make_reflector() {
  cat > "$BIN/reflector" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$BIN/argv"
out=""
while (( \$# )); do [[ "\$1" == --save ]] && { out="\$2"; }; shift; done
: > "\$out"
for i in \$(seq 1 $1); do echo "Server = https://new\$i.example.org/\\\$repo/os/\\\$arch" >> "\$out"; done
exit 0
EOF
  chmod +x "$BIN/reflector"
}

# A reflector that dies before writing anything — the `timeout 200` case Ф.1 hit,
# where the ranker never reached --save.
make_reflector_dead() {
  printf '#!/usr/bin/env bash\nexit 143\n' > "$BIN/reflector"
  chmod +x "$BIN/reflector"
}

depth() { grep -c '^Server' "$W_MIRRORS_LIST"; }

# ── The fail-soft contract ────────────────────────────────────────────────────

@test "rank: a full ranking replaces the list" {
  make_reflector 20
  run cmd_rank
  [ "$status" -eq 0 ]
  [[ "$output" == *"mirrorlist replaced"* ]]
  [ "$(depth)" -eq 20 ]
  grep -q 'new1.example.org' "$W_MIRRORS_LIST"
  ! grep -q 'old1.example.org' "$W_MIRRORS_LIST"
}

@test "rank: a too-shallow ranking is merged, never substituted (depth is the fallback)" {
  make_reflector 3
  run cmd_rank
  [ "$status" -eq 0 ]
  [[ "$output" == *"ranked only 3"* ]]
  # The 3 ranked mirrors lead; all 12 previous ones survive below them.
  [ "$(depth)" -eq 15 ]
  [ "$(head -n1 "$W_MIRRORS_LIST")" = "Server = https://new1.example.org/\$repo/os/\$arch" ]
  grep -q 'old12.example.org' "$W_MIRRORS_LIST"
}

@test "rank: the merge does not duplicate a mirror that was already in the list" {
  # Reflector returns 2 servers; make one of them identical to an existing entry.
  make_reflector 2
  echo 'Server = https://new1.example.org/$repo/os/$arch' >> "$W_MIRRORS_LIST"
  run cmd_rank
  [ "$status" -eq 0 ]
  [ "$(grep -c 'new1\.example\.org' "$W_MIRRORS_LIST")" -eq 1 ]
}

@test "rank: an empty ranking leaves the list untouched" {
  make_reflector 0
  run cmd_rank
  [ "$status" -eq 0 ]
  [[ "$output" == *"keeping the current mirrorlist"* ]]
  [ "$(depth)" -eq 12 ]
  grep -q 'old1.example.org' "$W_MIRRORS_LIST"
}

@test "rank: a ranker killed before --save leaves the list untouched" {
  make_reflector_dead
  run cmd_rank
  [ "$status" -eq 0 ]
  [ "$(depth)" -eq 12 ]
}

@test "rank: without reflector nothing is written and the failure is explicit" {
  # Removing the stub is not enough to make reflector absent: a dev machine has the
  # real one in /usr/bin, so the guard never fired and this test passed only in the
  # CI container, by luck. Narrow PATH to the stub dir for the probe — the guard is
  # the first thing cmd_rank does, so nothing else needs to be on it.
  rm -f "$BIN/reflector"
  local saved_path="$PATH"
  PATH="$BIN"
  run cmd_rank
  PATH="$saved_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reflector is not installed"* ]]
  [ "$(depth)" -eq 12 ]
}

# ── Scheduling guards (the silent successes) ──────────────────────────────────

@test "rank --scheduled: does nothing while the list is younger than INTERVAL_DAYS" {
  make_reflector 20
  mkdir -p "$(dirname "$W_MIRRORS_STATE")"
  printf 'LAST_RUN=%s\n' "$(date +%s)" > "$W_MIRRORS_STATE"
  run cmd_rank --scheduled
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [ "$(depth)" -eq 12 ]
}

@test "rank --scheduled: runs once the list is older than INTERVAL_DAYS" {
  make_reflector 20
  mkdir -p "$(dirname "$W_MIRRORS_STATE")"
  printf 'LAST_RUN=%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$W_MIRRORS_STATE"
  run cmd_rank --scheduled
  [ "$status" -eq 0 ]
  [ "$(depth)" -eq 20 ]
}

@test "rank --scheduled: a fresh install is not re-ranked by the first timer tick" {
  # No state file at all: the age falls back to the mirrorlist's own mtime, which
  # on a fresh machine is the list pacstrap copied minutes ago. Without this,
  # OnCalendar=daily + Persistent would fire a ~260 MB catch-up run right after
  # the installer already ranked.
  [[ "$(uname)" == Darwin ]] && skip "GNU stat -c (runs on Arch/CI)"
  make_reflector 20
  rm -f "$W_MIRRORS_STATE"
  run cmd_rank --scheduled
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [ "$(depth)" -eq 12 ]
}

@test "rank --scheduled: skips a metered link, and says so in the state" {
  make_reflector 20
  printf '#!/usr/bin/env bash\necho "GENERAL.METERED:yes (guessed)"\n' > "$BIN/nmcli"
  chmod +x "$BIN/nmcli"
  mkdir -p "$(dirname "$W_MIRRORS_STATE")"
  printf 'LAST_RUN=%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$W_MIRRORS_STATE"
  run cmd_rank --scheduled
  [ "$status" -eq 0 ]
  [[ "$output" == *"metered"* ]]
  [ "$(depth)" -eq 12 ]
  grep -q 'LAST_RESULT=skipped-metered' "$W_MIRRORS_STATE"
}

@test "rank: an explicit run ignores both guards" {
  make_reflector 20
  printf '#!/usr/bin/env bash\necho "GENERAL.METERED:yes"\n' > "$BIN/nmcli"
  chmod +x "$BIN/nmcli"
  mkdir -p "$(dirname "$W_MIRRORS_STATE")"
  printf 'LAST_RUN=%s\n' "$(date +%s)" > "$W_MIRRORS_STATE"
  run cmd_rank
  [ "$status" -eq 0 ]
  [ "$(depth)" -eq 20 ]
}

@test "is_metered: NetworkManager's 'no (guessed)' is not metered" {
  printf '#!/usr/bin/env bash\necho "GENERAL.METERED:no (guessed)"\n' > "$BIN/nmcli"
  chmod +x "$BIN/nmcli"
  run is_metered
  [ "$status" -ne 0 ]
}

# ── Policy → reflector argv ───────────────────────────────────────────────────

@test "rank: the shipped vendor policy becomes the reflector argv (country omitted when empty)" {
  make_reflector 20
  run cmd_rank
  [ "$status" -eq 0 ]
  argv="$(tr '\n' ' ' < "$BIN/argv")"
  [[ "$argv" == *"--protocol https"* ]]
  [[ "$argv" == *"--age 12"* ]]
  [[ "$argv" == *"--score 30"* ]]
  [[ "$argv" == *"--sort rate"* ]]
  [[ "$argv" == *"--number 20"* ]]
  [[ "$argv" == *"--threads 4"* ]]
  [[ "$argv" == *"--connection-timeout 3"* ]]
  [[ "$argv" == *"--download-timeout 12"* ]]
  [[ "$argv" != *"--country"* ]]
}

@test "rank: an admin-layer country reaches reflector" {
  make_reflector 20
  printf 'COUNTRY=Germany\n' > "$WCONF_ETC/mirrors.conf"
  wconf_reload mirrors
  run cmd_rank
  [ "$status" -eq 0 ]
  grep -qx -- '--country' "$BIN/argv"
  grep -qx -- 'Germany' "$BIN/argv"
}

@test "rank: a malformed policy value refuses to run rather than passing it on" {
  make_reflector 20
  printf 'SCORE=lots\n' > "$WCONF_ETC/mirrors.conf"
  wconf_reload mirrors
  run cmd_rank
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid SCORE"* ]]
  [ "$(depth)" -eq 12 ]
}

@test "valid_key: accepts the documented values and rejects the rest" {
  valid_key PROTOCOL https
  ! valid_key PROTOCOL ftp
  valid_key AGE 12
  ! valid_key AGE 0
  ! valid_key AGE twelve
  valid_key COUNTRY ""
  valid_key COUNTRY "Germany"
  valid_key COUNTRY "Germany, France"
  ! valid_key COUNTRY '$(id)'
  valid_key SKIP_METERED no
  ! valid_key SKIP_METERED maybe
  ! valid_key NOT_A_KEY 1
}

# ── State ─────────────────────────────────────────────────────────────────────

@test "rank: records what it did, so status does not have to guess" {
  make_reflector 17
  run cmd_rank
  [ "$status" -eq 0 ]
  grep -q 'LAST_COUNT=17' "$W_MIRRORS_STATE"
  grep -q 'LAST_RESULT=replaced' "$W_MIRRORS_STATE"
  grep -qE 'LAST_RUN=[0-9]+' "$W_MIRRORS_STATE"
}

@test "status --porcelain: machine-readable, and honest about being due" {
  mkdir -p "$(dirname "$W_MIRRORS_STATE")"
  printf 'LAST_RUN=%s\nLAST_COUNT=20\nLAST_RESULT=replaced\n' \
    "$(( $(date +%s) - 40 * 86400 ))" > "$W_MIRRORS_STATE"
  run cmd_status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *"depth=12"* ]]
  [[ "$output" == *"interval_days=30"* ]]
  [[ "$output" == *"due=yes"* ]]
  [[ "$output" == *"last_result=replaced"* ]]
}
