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

  # Layered-config seams (as wconf.bats): the vendor layer is the REAL shipped
  # file, the user layer a scratch home — which is also where hyprlock-auth.conf
  # renders, so HOME and WCONF_HOME point at the same place.
  export W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh"
  export WCONF_ETC="$BATS_TEST_TMPDIR/etc-w"
  export WCONF_VENDOR_DIR="$BATS_TEST_TMPDIR/defaults"
  export WCONF_HOME="$BATS_TEST_TMPDIR/home"
  export HOME="$WCONF_HOME"
  mkdir -p "$WCONF_ETC" "$WCONF_VENDOR_DIR" "$WCONF_HOME/.config/w"
  cp "$REPO/rootfs/usr/share/w/defaults/fingerprint".{conf,schema} "$WCONF_VENDOR_DIR/"
  # w-authd's D-Bus surface and w-power's re-render, both recorded, never run.
  export W_BUSCTL="$STUBS/busctl"
  export BUSCTL_LOG="$BATS_TEST_TMPDIR/busctl.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${BUSCTL_LOG:?}"\necho \x27s "state=idle locked=no mode=native attempts=0"\x27\n' > "$W_BUSCTL"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${BATS_TEST_TMPDIR:?}/w-power.log"\n' > "$STUBS/w-power"
  chmod +x "$W_BUSCTL" "$STUBS/w-power"
  PATH="$STUBS:$PATH"
}

AUTH_CONF="$WCONF_HOME/.config/hypr/hyprlock-auth.conf"

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

# ── lock-sensor ─────────────────────────────────────────────────────────────────

@test "lock-sensor: the shipped default is native, and status says so in both voices" {
  run "$REPO/$BIN" lock-sensor status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *$'lock.sensor=native\n'* ]]
  [[ "$output" == *$'lock.window=30\n'* ]]
  [[ "$output" == *$'lock.locked=no\n'* ]]
  [[ "$output" == *"lock.live=state=idle"* ]]
  run "$REPO/$BIN" lock-sensor status
  [[ "$output" == *"Lock sensor: native (window 30s)"* ]]
}

@test "lock-sensor mode wake: user layer, hyprlock override, hypridle re-render" {
  run "$REPO/$BIN" lock-sensor mode wake
  [ "$status" -eq 0 ]
  grep -q '^LOCK_SENSOR=wake' "$WCONF_HOME/.config/w/fingerprint.conf"
  grep -q '^auth:fingerprint:enabled = false$' "$BATS_TEST_TMPDIR/home/.config/hypr/hyprlock-auth.conf"
  grep -q '^_render-user$' "$BATS_TEST_TMPDIR/w-power.log"
  [ ! -e "$BUSCTL_LOG" ]                       # nothing to disarm on the way IN
  run "$REPO/$BIN" status --porcelain
  [[ "$output" == *$'lock.sensor=wake\n'* ]]
}

@test "lock-sensor mode native: the override says nothing, and the daemon is disarmed" {
  "$REPO/$BIN" lock-sensor mode wake >/dev/null
  run "$REPO/$BIN" lock-sensor mode native
  [ "$status" -eq 0 ]
  ! grep -q 'fingerprint:enabled' "$BATS_TEST_TMPDIR/home/.config/hypr/hyprlock-auth.conf"
  grep -q 'lock-sensor mode: native' "$BATS_TEST_TMPDIR/home/.config/hypr/hyprlock-auth.conf"
  grep -q 'com.w.authd.LockSensor Disarm' "$BUSCTL_LOG"
}

@test "lock-sensor mode: anything but native|wake is a usage error that writes nothing" {
  run "$REPO/$BIN" lock-sensor mode always
  [ "$status" -eq 2 ]
  [ ! -e "$WCONF_HOME/.config/w/fingerprint.conf" ]
}

@test "lock-sensor window: 10..300 lands in the user layer and drives _arm; the rest is refused" {
  run "$REPO/$BIN" lock-sensor window 120
  [ "$status" -eq 0 ]
  grep -q '^LOCK_SENSOR_ARM=120' "$WCONF_HOME/.config/w/fingerprint.conf"
  run "$REPO/$BIN" lock-sensor _arm
  grep -q 'com.w.authd.LockSensor Arm u 120' "$BUSCTL_LOG"
  for bad in 9 301 abc ""; do
    run "$REPO/$BIN" lock-sensor window "$bad"
    [ "$status" -eq 2 ]
  done
  grep -q '^LOCK_SENSOR_ARM=120' "$WCONF_HOME/.config/w/fingerprint.conf"
}

@test "lock-sensor: a policy-pinned mode is reported locked and refused" {
  mkdir -p "$WCONF_ETC/policy.d"
  printf 'LOCK_SENSOR=native\n' > "$WCONF_ETC/policy.d/fingerprint.conf"
  run "$REPO/$BIN" status --porcelain
  [[ "$output" == *$'\nlock.locked=yes'* ]]
  run "$REPO/$BIN" lock-sensor mode wake
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/home/.config/hypr/hyprlock-auth.conf" ]
}

@test "lock-sensor: a missing or unknown subcommand is a usage error" {
  run "$REPO/$BIN" lock-sensor
  [ "$status" -eq 2 ]
  run "$REPO/$BIN" lock-sensor arm
  [ "$status" -eq 2 ]
}
