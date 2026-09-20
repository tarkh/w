#!/usr/bin/env bats
# deploy.bats — install/lib/deploy.sh: seed-if-absent semantics + manifest parser.
#
# Runs unprivileged: `install` is shadowed by a bash function that drops the
# -o/-g ownership flags (chown needs root; ownership itself isn't under test),
# and W_HOME_BASE points the home root at a tmpdir (the deploy.sh test seam).

load helpers

setup() {
  source "$REPO/scripts/install/lib/deploy.sh"

  # ui.sh stubs (deploy.sh normally runs inside apply.sh which provides them).
  info() { :; }
  die()  { echo "die: $*" >&2; exit 1; }

  # install(1) minus ownership: -d → mkdir, -Dm644 src dst → mkdir parent + cp.
  install() {
    local mkdir=0 args=()
    while (($#)); do
      case "$1" in
        -d) mkdir=1 ;;
        -D*|-m*) ;;
        -o|-g) shift ;;
        *) args+=("$1") ;;
      esac
      shift
    done
    if ((mkdir)); then mkdir -p "${args[@]}"
    else mkdir -p "$(dirname "${args[1]}")" && cp "${args[0]}" "${args[1]}"
    fi
  }

  export W_HOME_BASE="$BATS_TEST_TMPDIR/homes"
  USER_HOME="$W_HOME_BASE/alice"
  mkdir -p "$USER_HOME"
}

@test "seed_user_file: seeds an absent file, creating the parent chain" {
  echo "payload" > "$BATS_TEST_TMPDIR/src.conf"
  seed_user_file "$BATS_TEST_TMPDIR/src.conf" "$USER_HOME/.config/w/a/b.conf" alice
  [[ -f "$USER_HOME/.config/w/a/b.conf" ]]
  [[ "$(cat "$USER_HOME/.config/w/a/b.conf")" == "payload" ]]
}

@test "seed_user_file: leaves an existing destination untouched" {
  echo "new" > "$BATS_TEST_TMPDIR/src.conf"
  mkdir -p "$USER_HOME/.config"
  echo "user edit" > "$USER_HOME/.config/x.conf"
  seed_user_file "$BATS_TEST_TMPDIR/src.conf" "$USER_HOME/.config/x.conf" alice
  [[ "$(cat "$USER_HOME/.config/x.conf")" == "user edit" ]]
}

@test "seed_user_file: missing source warns and succeeds" {
  run seed_user_file "$BATS_TEST_TMPDIR/nope.conf" "$USER_HOME/.config/x.conf" alice
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"WARN: skel source missing"* ]]
  [[ ! -e "$USER_HOME/.config/x.conf" ]]
}

@test "deploy_user_manifest: seeds only user-class paths; comments/blank lines ignored; last line without newline read" {
  SRC="$BATS_TEST_TMPDIR/repo"
  local skel="$SRC/rootfs/etc/skel"
  mkdir -p "$SRC/rootfs/usr/share/w/update" "$skel/.config"
  echo "A" > "$skel/.config/a.conf"
  echo "B" > "$skel/.config/b.conf"
  echo "D" > "$skel/.config/d.conf"
  # NB: final entry deliberately lacks a trailing newline (the `|| [[ -n $path ]]`
  # read-loop guard under test).
  printf '# comment line\n\n.config/a.conf\tuser\n.config/b.conf\tmanaged\n.config/c.conf\toverride\n.config/d.conf\tuser' \
    > "$SRC/rootfs/usr/share/w/update/mod.manifest"

  deploy_user_manifest mod alice
  [[ "$(cat "$USER_HOME/.config/a.conf")" == "A" ]]
  [[ "$(cat "$USER_HOME/.config/d.conf")" == "D" ]]
  [[ ! -e "$USER_HOME/.config/b.conf" ]]   # managed — not seeded here
  [[ ! -e "$USER_HOME/.config/c.conf" ]]   # override — not seeded here
}

@test "deploy_user_manifest: absent manifest dies" {
  SRC="$BATS_TEST_TMPDIR/norepo"
  run deploy_user_manifest ghost alice
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"manifest not found"* ]]
}

# ── w_home_users: who counts as a W user ──────────────────────────────────────
# The passwd source is the W_PASSWD seam; `_home_owned_by` is shadowed because a
# test tmpdir belongs to whoever runs bats, never to "alice" (same reasoning as
# the `install` shadow above — privileged externals are not under test here).

# passwd_fixture <line>... — write $W_PASSWD, creating every home dir mentioned.
passwd_fixture() {
  export W_PASSWD="$BATS_TEST_TMPDIR/passwd"
  : > "$W_PASSWD"
  local line home
  for line in "$@"; do
    echo "$line" >> "$W_PASSWD"
    home="$(echo "$line" | cut -d: -f6)"
    [[ "$home" == "$W_HOME_BASE"/* ]] && mkdir -p "$home"
  done
  # Homes are "owned" by the account whose passwd line names them.
  _home_owned_by() {
    local want; want="$(awk -F: -v h="$1" '$6 == h {print $1; exit}' "$W_PASSWD")"
    [[ "$want" == "$2" ]]
  }
}

@test "w_home_users: lists human accounts, skips system uids and nobody" {
  passwd_fixture \
    "root:x:0:0::/root:/usr/bin/zsh" \
    "http:x:33:33::/srv/http:/usr/bin/nologin" \
    "alice:x:1000:1000::$W_HOME_BASE/alice:/usr/bin/zsh" \
    "bob:x:1001:1001::$W_HOME_BASE/bob:/bin/bash" \
    "nobody:x:65534:65534::/:/usr/bin/nologin"
  run w_home_users
  [[ "$status" -eq 0 ]]
  [[ "$output" == "alice	$W_HOME_BASE/alice
bob	$W_HOME_BASE/bob" ]]
}

@test "w_home_users: skips service accounts that sit in the human uid range" {
  passwd_fixture \
    "alice:x:1000:1000::$W_HOME_BASE/alice:/usr/bin/zsh" \
    "svc:x:1002:1002::$W_HOME_BASE/svc:/usr/bin/nologin" \
    "svc2:x:1003:1003::$W_HOME_BASE/svc2:/bin/false" \
    "svc3:x:1004:1004::$W_HOME_BASE/svc3:"
  mkdir -p "$W_HOME_BASE"/{svc,svc2,svc3}
  run w_home_users
  [[ "$output" == "alice	$W_HOME_BASE/alice" ]]
}

@test "w_home_users: skips a missing home, '/' and a home owned by someone else" {
  passwd_fixture \
    "alice:x:1000:1000::$W_HOME_BASE/alice:/usr/bin/zsh" \
    "ghost:x:1005:1005::$W_HOME_BASE/ghost:/usr/bin/zsh" \
    "rooty:x:1006:1006::/:/usr/bin/zsh"
  rmdir "$W_HOME_BASE/ghost"                     # passwd says it exists, disk says no
  # squatter's home is alice's — the guard that stops `install -d -o` giving it away
  echo "squat:x:1007:1007::$W_HOME_BASE/alice:/usr/bin/zsh" >> "$W_PASSWD"
  run w_home_users
  [[ "$output" == "alice	$W_HOME_BASE/alice" ]]
}

@test "w_home_users: an account-less machine yields an empty list, not an error" {
  passwd_fixture "root:x:0:0::/root:/usr/bin/zsh"
  run w_home_users
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

# ── w_render_user_theme: the render finalizer ─────────────────────────────────
# W_STYLE_BIN points at a stub that records HOME + argv + the session vars, so the
# test asserts the CONTRACT (render as the account, with that account's session or
# with none) without needing root, a real w-style or a live session. `runuser` and
# `id` are shadowed for the same reason the `install` shadow exists above.

# render_stub — install the w-style stub + the runuser/id shadows. Sets RENDER_LOG.
render_stub() {
  RENDER_LOG="$BATS_TEST_TMPDIR/render.log"
  export W_STYLE_BIN="$BATS_TEST_TMPDIR/w-style-stub"
  cat > "$W_STYLE_BIN" <<EOF
#!/usr/bin/env bash
{
  echo "args: \$*"
  echo "HOME: \$HOME"
  echo "XDG_RUNTIME_DIR: \${XDG_RUNTIME_DIR-<unset>}"
  echo "DBUS: \${DBUS_SESSION_BUS_ADDRESS-<unset>}"
  echo "HIS: \${HYPRLAND_INSTANCE_SIGNATURE-<unset>}"
} >> "$RENDER_LOG"
exit \${STUB_RC:-0}
EOF
  chmod +x "$W_STYLE_BIN"
  # `runuser -u <user> -- <cmd...>`: drop the switch, run the command in place.
  runuser() { shift 2; [[ "$1" == "--" ]] && shift; "$@"; }
  id() { echo 4242; }
}

@test "w_render_user_theme: renders as the account, with no session vars when there is no session" {
  render_stub
  # A root-SSH apply leaks root's session vars into runuser — they must not survive.
  export XDG_RUNTIME_DIR=/run/user/0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
  w_render_user_theme alice "$USER_HOME"
  [[ "$(grep '^args:' "$RENDER_LOG")" == "args: apply user" ]]
  [[ "$(grep '^HOME:' "$RENDER_LOG")" == "HOME: $USER_HOME" ]]
  [[ "$(grep '^XDG_RUNTIME_DIR:' "$RENDER_LOG")" == "XDG_RUNTIME_DIR: <unset>" ]]
  [[ "$(grep '^DBUS:' "$RENDER_LOG")" == "DBUS: <unset>" ]]
}

@test "w_render_user_theme: hands the account its own session bus + Hyprland instance" {
  render_stub
  export W_RUNTIME_BASE="$BATS_TEST_TMPDIR/run"
  mkdir -p "$W_RUNTIME_BASE/4242/hypr/sig_newest"
  w_render_user_theme alice "$USER_HOME"
  [[ "$(grep '^XDG_RUNTIME_DIR:' "$RENDER_LOG")" == "XDG_RUNTIME_DIR: $W_RUNTIME_BASE/4242" ]]
  [[ "$(grep '^DBUS:' "$RENDER_LOG")" == "DBUS: unix:path=$W_RUNTIME_BASE/4242/bus" ]]
  [[ "$(grep '^HIS:' "$RENDER_LOG")" == "HIS: sig_newest" ]]
}

@test "w_render_user_theme: a live session without Hyprland passes no instance signature" {
  render_stub
  export W_RUNTIME_BASE="$BATS_TEST_TMPDIR/run"
  mkdir -p "$W_RUNTIME_BASE/4242"
  w_render_user_theme alice "$USER_HOME"
  [[ "$(grep '^HIS:' "$RENDER_LOG")" == "HIS: <unset>" ]]
}

@test "w_render_user_theme: a failing render warns instead of failing the apply" {
  render_stub
  export STUB_RC=1
  run w_render_user_theme alice "$USER_HOME"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"WARN: w-style apply user failed for alice"* ]]
}

@test "w_render_user_theme: no w-style on the machine is a silent no-op" {
  render_stub
  export W_STYLE_BIN="$BATS_TEST_TMPDIR/absent-w-style"
  run w_render_user_theme alice "$USER_HOME"
  [[ "$status" -eq 0 ]]
  [[ ! -e "$RENDER_LOG" ]]
}

@test "w_render_user_themes: renders every human account, none on an account-less machine" {
  render_stub
  passwd_fixture \
    "alice:x:1000:1000::$W_HOME_BASE/alice:/usr/bin/zsh" \
    "bob:x:1001:1001::$W_HOME_BASE/bob:/bin/bash"
  w_render_user_themes
  [[ "$(grep -c '^HOME:' "$RENDER_LOG")" -eq 2 ]]
  grep -qx "HOME: $W_HOME_BASE/alice" "$RENDER_LOG"
  grep -qx "HOME: $W_HOME_BASE/bob" "$RENDER_LOG"

  : > "$RENDER_LOG"
  passwd_fixture "root:x:0:0::/root:/usr/bin/zsh"
  w_render_user_themes
  [[ ! -s "$RENDER_LOG" ]]
}

@test "w_home_subvols_read: paths only — comments (whole-line and trailing), blanks and trailing space dropped" {
  printf '# header\n\n.cache/uv       # uv: cache\n  \n.cache/go\t# go\n.local/share/x   \n' > "$BATS_TEST_TMPDIR/reg"
  run w_home_subvols_read "$BATS_TEST_TMPDIR/reg"
  [ "$status" -eq 0 ]
  [ "$output" = $'.cache/uv\n.cache/go\n.local/share/x' ]
}

@test "w_home_subvols_read: the shipped registry parses to home-relative paths" {
  run w_home_subvols_read "$REPO/rootfs/usr/share/w/defaults/home-subvols"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while read -r p; do
    [[ "$p" != /* && "$p" != *' '* ]]
  done <<< "$output"
}
