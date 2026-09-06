#!/usr/bin/env bats
# fingerprint.bats — w-fingerprint is the sole fprintd contract for people and Hub.

load helpers

BIN="rootfs/usr/bin/w-fingerprint"

setup() {
  STUBS="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS"
  export W_FPRINT_LIST="$STUBS/fprintd-list"
  export W_FPRINT_ENROLL="$STUBS/fprintd-enroll"
  export W_FPRINT_DELETE="$STUBS/fprintd-delete"
  export W_FPRINT_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  make_list 'User test has no fingers enrolled for reader.' 1
  make_enroll '' 0
  make_delete 0
}

make_list() { # <output> <exit>
  local output="$1" rc="$2"
  cat > "$W_FPRINT_LIST" <<EOF
#!/usr/bin/env bash
printf '%s\\n' $(printf '%q' "$output")
exit $rc
EOF
  chmod +x "$W_FPRINT_LIST"
}

make_enroll() { # <output> <exit>
  local output="$1" rc="$2"
  cat > "$W_FPRINT_ENROLL" <<EOF
#!/usr/bin/env bash
printf '%s\\n' $(printf '%q' "$output")
exit $rc
EOF
  chmod +x "$W_FPRINT_ENROLL"
}

make_delete() { # <exit>
  local rc="$1"
  export W_FPRINT_DELETE_ARGS="$BATS_TEST_TMPDIR/delete-args"
  cat > "$W_FPRINT_DELETE" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\${W_FPRINT_DELETE_ARGS:?}"
exit $rc
EOF
  chmod +x "$W_FPRINT_DELETE"
}

@test "status porcelain: an empty store still means the reader is available" {
  run "$REPO/$BIN" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *$'available=yes\n'* ]]
  [ "$(grep -c '^finger\..*=empty$' <<< "$output")" -eq 10 ]
}

@test "status porcelain: maps fprintd's named prints onto the ten stable slots" {
  make_list $'Fingerprints for user test on reader (press):\n - #0: left-thumb\n - #1: right-index-finger' 0
  run "$REPO/$BIN" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *"finger.left-thumb=enrolled"* ]]
  [[ "$output" == *"finger.right-index-finger=enrolled"* ]]
  [[ "$output" == *"finger.left-index-finger=empty"* ]]
}

@test "status porcelain: a missing reader is safe and hides every slot" {
  make_list 'Impossible to get devices: No devices available' 1
  run "$REPO/$BIN" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *"available=no"* ]]
  [ "$(grep -c '^finger\..*=empty$' <<< "$output")" -eq 10 ]
}

@test "enroll: normalizes fprintd progress, retry and completion" {
  make_enroll $'Enrolling right-index-finger finger.\nEnroll result: enroll-stage-passed\nEnroll result: enroll-retry-remove-finger\nEnroll result: enroll-completed' 0
  run "$REPO/$BIN" enroll right-index-finger
  [ "$status" -eq 0 ]
  [[ "$output" == *"event=ready"* ]]
  [[ "$output" == *"event=stage"* ]]
  [[ "$output" == *$'event=retry\nreason=enroll-retry-remove-finger'* ]]
  [[ "$output" == *"event=complete"* ]]
  [[ "$output" == *"event=done"* ]]
}

@test "enroll: rejects a non-fprintd finger name before opening the reader" {
  run "$REPO/$BIN" enroll third-hand
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid finger: third-hand"* ]]
}

@test "enroll: SIGTERM ends the real child and reports cancellation" {
  cat > "$W_FPRINT_ENROLL" <<'EOF'
#!/usr/bin/env bash
trap 'exit 143' TERM
echo 'Enrolling left-thumb finger.'
while :; do sleep 1; done
EOF
  chmod +x "$W_FPRINT_ENROLL"

  local out="$BATS_TEST_TMPDIR/enroll.out"
  "$REPO/$BIN" enroll left-thumb > "$out" &
  local pid=$!
  for _ in 1 2 3 4 5; do grep -q 'event=ready' "$out" && break; sleep 0.1; done
  kill -TERM "$pid"
  wait "$pid" || rc=$?
  [ "${rc:-0}" -eq 130 ]
  grep -qx 'event=cancelled' "$out"
}

@test "delete: delegates only a validated named finger for the invoking user" {
  run "$REPO/$BIN" delete left-middle-finger
  [ "$status" -eq 0 ]
  mapfile -t args < "$W_FPRINT_DELETE_ARGS"
  [ "${args[1]}" = "-f" ]
  [ "${args[2]}" = "left-middle-finger" ]
}

@test "delete: validates before invoking fprintd" {
  run "$REPO/$BIN" delete all
  [ "$status" -eq 2 ]
  [ ! -e "$W_FPRINT_DELETE_ARGS" ]
}

@test "status porcelain: a full store reports all ten slots enrolled" {
  local body='Fingerprints for user test on reader (press):' f i=0
  while read -r f; do body+=$'\n - #'"$i: $f"; i=$((i + 1)); done < <("$REPO/$BIN" fingers)
  make_list "$body" 0
  run "$REPO/$BIN" status --porcelain
  [ "$status" -eq 0 ]
  [ "$(grep -c '^finger\..*=enrolled$' <<< "$output")" -eq 10 ]
  [ "$(grep -c '=empty$' <<< "$output")" -eq 0 ]
}

@test "status: the human view names every slot and its state" {
  make_list $'Fingerprints for user test on reader (press):\n - #0: left-thumb' 0
  run "$REPO/$BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fingerprint reader: available"* ]]
  [[ "$output" =~ left-thumb[[:space:]]+enrolled ]]
  [ "$(grep -c 'empty$' <<< "$output")" -eq 9 ]
}

@test "status: no reader says so, and passes fprintd's own words through" {
  make_list 'Impossible to get devices: No devices available' 1
  run "$REPO/$BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fingerprint reader: unavailable"* ]]
  [[ "$output" == *"No devices available"* ]]
}

# A reader that is physically there but gated by polkit's allow_active is correctly
# unavailable — enrolling would be denied too — but "no device" would send whoever
# is debugging it to the USB cable instead of to the session.
@test "status: a polkit refusal is unavailable for a different, named reason" {
  make_list 'ListEnrolledFingers failed: GDBus.Error:net.reactivated.Fprint.Error.PermissionDenied: Not Authorized: net.reactivated.fprint.device.verify' 0
  run "$REPO/$BIN" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *"available=no"* ]]
  [[ "$output" == *"reason=unauthorized"* ]]

  run "$REPO/$BIN" status
  [[ "$output" == *"not authorized"* ]]
}

@test "status: a genuinely absent reader names the device, not the session" {
  make_list 'Impossible to get devices: No devices available' 1
  run "$REPO/$BIN" status --porcelain
  [[ "$output" == *"reason=no-device"* ]]

  run "$REPO/$BIN" status
  [[ "$output" == *"(no device)"* ]]
}

@test "status: an available reader states no reason at all" {
  run "$REPO/$BIN" status --porcelain
  [[ "$output" == *"available=yes"* ]]
  [[ "$output" != *"reason="* ]]
}

@test "status: a bogus flag is a usage error, not a silently plain listing" {
  run "$REPO/$BIN" status --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected --porcelain"* ]]
}

# The reader is a single-claim device: while the auth dialog holds it for a polkit
# prompt, an enrol cannot start. The Hub must be able to say so without parsing
# GDBus error text of its own.
@test "enroll: a reader held by another client is a normalized busy" {
  make_enroll 'Impossible to enroll: GDBus.Error:net.reactivated.Fprint.Error.AlreadyInUse: Device already in use by another client' 1
  run "$REPO/$BIN" enroll left-thumb
  [ "$status" -ne 0 ]
  [[ "$output" == *$'event=error\nreason=busy'* ]]
  [ "$(grep -c '^event=error$' <<< "$output")" -eq 1 ]
}

@test "enroll: a vanished reader is a normalized unavailable" {
  make_enroll 'Impossible to enroll: No devices available' 1
  run "$REPO/$BIN" enroll left-thumb
  [ "$status" -ne 0 ]
  [[ "$output" == *$'event=error\nreason=unavailable'* ]]
  [ "$(grep -c '^event=error$' <<< "$output")" -eq 1 ]
}

# fprintd's verdict names are the most precise reason available, so they ride
# through as the reason rather than being flattened into a generic failure.
@test "enroll: an fprintd verdict rides through as the reason, once" {
  make_enroll $'Enrolling left-thumb finger.\nEnroll result: enroll-duplicate' 1
  run "$REPO/$BIN" enroll left-thumb
  [ "$status" -ne 0 ]
  [[ "$output" == *$'event=error\nreason=enroll-duplicate'* ]]
  [ "$(grep -c '^event=error$' <<< "$output")" -eq 1 ]
  [[ "$output" != *"reason=failed"* ]]
}

# Without this the Hub would sit on "enrolling…" forever: the stream must always
# reach a terminal verdict, even when the failure never named itself on stdout.
@test "enroll: a failure that says nothing recognisable still terminates the stream" {
  make_enroll 'Enrolling left-thumb finger.' 1
  run "$REPO/$BIN" enroll left-thumb
  [ "$status" -ne 0 ]
  [[ "$output" == *"event=ready"* ]]
  [[ "$output" == *$'event=error\nreason=failed'* ]]
  [ "$(grep -c '^event=error$' <<< "$output")" -eq 1 ]
}

@test "fingers: names exactly the ten slots status reports" {
  run "$REPO/$BIN" fingers
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 10 ]
  [[ "$output" == *"left-thumb"* ]]
  [[ "$output" == *"right-little-finger"* ]]
}

@test "an unknown or missing command is a usage error, not a silent no-op" {
  run "$REPO/$BIN" wipe
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: wipe"* ]]

  run "$REPO/$BIN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: w-fingerprint"* ]]
}
