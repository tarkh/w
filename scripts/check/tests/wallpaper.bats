#!/usr/bin/env bats
# wallpaper.bats — w-wallpaper's pure resolver: width→tier bucketing and the
# bidirectional fallback (down the ladder to the nearest smaller master, then
# up to the nearest larger), webp preferred over png at every tier.

load helpers

setup() {
  # Source-guarded: definitions only, the dispatch is skipped. The script sets
  # -euo pipefail on source; drop -u and pipefail, but LEAVE -e ON — bats reports a
  # failed assertion through errexit, so a `set +e` here would make every test in
  # the file pass unconditionally, the last assertion included.
  source "$REPO/rootfs/usr/bin/w-wallpaper"
  set +u; set +o pipefail
  WP="$BATS_TEST_TMPDIR/wallpaper"
  mkdir -p "$WP"
}

@test "wallpaper_for_width: buckets widths into tiers (empty/garbage → smallest)" {
  [[ "$(wallpaper_for_width 6000)" == wallpaper-5120x2880 ]]
  [[ "$(wallpaper_for_width 5120)" == wallpaper-5120x2880 ]]
  [[ "$(wallpaper_for_width 5119)" == wallpaper-3840x2160 ]]
  [[ "$(wallpaper_for_width 3840)" == wallpaper-3840x2160 ]]
  [[ "$(wallpaper_for_width 2560)" == wallpaper-2560x1440 ]]
  [[ "$(wallpaper_for_width 1920)" == wallpaper-1920x1080 ]]
  [[ "$(wallpaper_for_width 800)"  == wallpaper-1920x1080 ]]
  [[ "$(wallpaper_for_width)"      == wallpaper-1920x1080 ]]
  [[ "$(wallpaper_for_width abc)"  == wallpaper-1920x1080 ]]
}

@test "wallpaper_try: prefers webp over png" {
  touch "$WP/wallpaper-1920x1080.png" "$WP/wallpaper-1920x1080.webp"
  [[ "$(wallpaper_try "$WP" wallpaper-1920x1080)" == "$WP/wallpaper-1920x1080.webp" ]]
}

@test "wallpaper_file: exact tier match wins" {
  touch "$WP/wallpaper-3840x2160.webp" "$WP/wallpaper-1920x1080.webp"
  [[ "$(wallpaper_file "$WP" 3840)" == "$WP/wallpaper-3840x2160.webp" ]]
}

@test "wallpaper_file: falls DOWN to the nearest smaller master" {
  touch "$WP/wallpaper-1920x1080.png"
  [[ "$(wallpaper_file "$WP" 5120)" == "$WP/wallpaper-1920x1080.png" ]]
}

@test "wallpaper_file: falls UP when nothing smaller exists (2k/4k-only theme serves HD)" {
  touch "$WP/wallpaper-3840x2160.webp"
  [[ "$(wallpaper_file "$WP" 1920)" == "$WP/wallpaper-3840x2160.webp" ]]
}

@test "wallpaper_file: empty width resolves via the smallest tier" {
  touch "$WP/wallpaper-2560x1440.webp"
  [[ "$(wallpaper_file "$WP" "")" == "$WP/wallpaper-2560x1440.webp" ]]
}

@test "wallpaper_file: theme with no wallpapers fails" {
  run wallpaper_file "$WP" 1920
  [[ "$status" -ne 0 ]]
  [[ -z "$output" ]]
}

# hyprpaper_ipc: readiness-by-retry, not by a proxy file signal (see the
# function's own comment for the stale-socket bug this replaced).

@test "hyprpaper_ipc: succeeds immediately when hyprctl is already up" {
  hyprctl() { return 0; }
  run hyprpaper_ipc 0 wallpaper "DP-1,/tmp/x.webp"
  [[ "$status" -eq 0 ]]
}

@test "hyprpaper_ipc: wait_timeout=0 fails on the first miss, no retry" {
  hyprctl() { return 1; }
  run hyprpaper_ipc 0 wallpaper "DP-1,/tmp/x.webp"
  [[ "$status" -ne 0 ]]
}

@test "hyprpaper_ipc: retries past transient failures until hyprctl succeeds" {
  # Simulates hyprpaper not yet ready for the first two calls (e.g. socket file
  # present but the daemon not accepting requests yet) — the third succeeds.
  export COUNTER_FILE="$BATS_TEST_TMPDIR/tries"
  echo 0 > "$COUNTER_FILE"
  hyprctl() {
    local n; n=$(<"$COUNTER_FILE"); n=$((n + 1)); echo "$n" > "$COUNTER_FILE"
    (( n >= 3 ))
  }
  run hyprpaper_ipc 5 wallpaper "DP-1,/tmp/x.webp"
  [[ "$status" -eq 0 ]]
  [[ "$(<"$COUNTER_FILE")" -eq 3 ]]
}

@test "hyprpaper_ipc: gives up once the deadline passes, not on a stale proxy signal" {
  # hyprctl never succeeds — must fail once wait_timeout elapses, not hang or
  # false-positive on anything filesystem-based.
  hyprctl() { return 1; }
  run hyprpaper_ipc 1 wallpaper "DP-1,/tmp/x.webp"
  [[ "$status" -ne 0 ]]
}
