#!/usr/bin/env bats
# wconf.bats — w-conf-lib.sh: layer precedence, parse semantics, writes.
#
# Runs unprivileged against a synthetic layer tree: WCONF_ETC / WCONF_VENDOR_DIR /
# WCONF_HOME are the library's test seams, so nothing here touches /etc/w.
# The complementary gate lives in check/wconf.sh, which cross-checks the REAL
# shipped configs against `source` and against the Python twin.

load helpers

setup() {
  export WCONF_ETC="$BATS_TEST_TMPDIR/etc-w"
  export WCONF_VENDOR_DIR="$BATS_TEST_TMPDIR/defaults"
  export WCONF_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$WCONF_ETC" "$WCONF_VENDOR_DIR" "$WCONF_HOME/.config/w" \
           "$WCONF_ETC/policy.d" "$WCONF_ETC/site-defaults.d"
  source "$REPO/rootfs/usr/lib/w/w-conf-lib.sh"
}

# ── Precedence ───────────────────────────────────────────────────────────────

@test "layers: user beats system beats site-default beats vendor" {
  printf 'K=vendor\nONLY_V=v\n'  > "$WCONF_VENDOR_DIR/probe.conf"
  printf 'K=site\n'              > "$WCONF_ETC/site-defaults.d/probe.conf"
  printf 'K=system\n'            > "$WCONF_ETC/probe.conf"
  printf 'K=user\n'              > "$WCONF_HOME/.config/w/probe.conf"

  [ "$(wconf_get probe K)" = "user" ]
  [ "$(wconf_origin probe K)" = "user" ]
  # A key only the vendor defines still arrives — that is the whole point of the
  # split: new vendor keys reach installed machines.
  [ "$(wconf_get probe ONLY_V)" = "v" ]
  [ "$(wconf_origin probe ONLY_V)" = "vendor" ]
}

@test "layers: site-default sits BELOW the local admin (locality is preserved)" {
  printf 'K=site\n'   > "$WCONF_ETC/site-defaults.d/probe.conf"
  printf 'K=admin\n'  > "$WCONF_ETC/probe.conf"
  [ "$(wconf_get probe K)" = "admin" ]
}

@test "layers: policy beats everything and marks the key locked" {
  printf 'K=system\n' > "$WCONF_ETC/probe.conf"
  printf 'K=user\n'   > "$WCONF_HOME/.config/w/probe.conf"
  printf 'K=fleet\n'  > "$WCONF_ETC/policy.d/probe.conf"

  [ "$(wconf_get probe K)" = "fleet" ]
  [ "$(wconf_origin probe K)" = "policy" ]
  wconf_locked probe K
}

@test "drop-ins: <file>.d/*.conf apply after the base file, in sorted order" {
  printf 'K=base\n' > "$WCONF_ETC/probe.conf"
  mkdir -p "$WCONF_ETC/probe.conf.d"
  printf 'K=ten\n'    > "$WCONF_ETC/probe.conf.d/10-a.conf"
  printf 'K=ninety\n' > "$WCONF_ETC/probe.conf.d/90-b.conf"
  [ "$(wconf_get probe K)" = "ninety" ]
}

@test "layer-scoped read ignores the layers above it" {
  printf 'K=system\n' > "$WCONF_ETC/probe.conf"
  printf 'K=user\n'   > "$WCONF_HOME/.config/w/probe.conf"
  # This is what every phase-1 subsystem uses: same semantics as reading its own
  # single file, no accidental new precedence.
  [ "$(wconf_layer_get probe system K)" = "system" ]
  [ "$(wconf_layer_get probe user K)" = "user" ]
}

# ── Scope (who may set what) ─────────────────────────────────────────────────

@test "scope: the user layer cannot override a system-scope key" {
  printf 'CHARGE_LIMIT\tsystem\nAC_LOCK\tuser\n' > "$WCONF_VENDOR_DIR/probe.schema"
  printf 'CHARGE_LIMIT=100\nAC_LOCK=600\n' > "$WCONF_VENDOR_DIR/probe.conf"
  printf 'CHARGE_LIMIT=60\nAC_LOCK=1800\n' > "$WCONF_HOME/.config/w/probe.conf"
  wconf_load probe

  # Root-domain policy stays with the vendor/admin layers…
  [ "$(wconf_get probe CHARGE_LIMIT)" = "100" ]
  [ "$(wconf_origin probe CHARGE_LIMIT)" = "vendor" ]
  # …while the key declared user-overridable behaves normally.
  [ "$(wconf_get probe AC_LOCK)" = "1800" ]
  [ "$(wconf_origin probe AC_LOCK)" = "user" ]
  # The refusal is visible, not silent.
  [[ "${WCONF_WARN[*]}" == *"CHARGE_LIMIT is system-scope"* ]]
  # And the refused value is still recorded, so `w-conf cat` can explain it.
  [ "$(wconf_layer_get probe user CHARGE_LIMIT)" = "60" ]
}

@test "scope: a key with no schema row is unconstrained (pre-split subsystems)" {
  printf 'CHARGE_LIMIT\tsystem\n' > "$WCONF_VENDOR_DIR/probe.schema"
  printf 'UNDECLARED=admin\n' > "$WCONF_ETC/probe.conf"
  printf 'UNDECLARED=user\n' > "$WCONF_HOME/.config/w/probe.conf"
  [ "$(wconf_get probe UNDECLARED)" = "user" ]
}

@test "scope: an admin (system-layer) value is never restricted by the schema" {
  printf 'CHARGE_LIMIT\tsystem\n' > "$WCONF_VENDOR_DIR/probe.schema"
  printf 'CHARGE_LIMIT=100\n' > "$WCONF_VENDOR_DIR/probe.conf"
  printf 'CHARGE_LIMIT=80\n'  > "$WCONF_ETC/probe.conf"
  [ "$(wconf_get probe CHARGE_LIMIT)" = "80" ]
  [ "$(wconf_origin probe CHARGE_LIMIT)" = "system" ]
}

# ── Parse semantics ──────────────────────────────────────────────────────────

@test "values: inline comment stripped only when whitespace precedes '#'" {
  printf 'A=menu      # power menu\nB=gpt#4\nC="has # inside"\n' > "$WCONF_ETC/probe.conf"
  [ "$(wconf_get probe A)" = "menu" ]
  [ "$(wconf_get probe B)" = "gpt#4" ]
  [ "$(wconf_get probe C)" = "has # inside" ]
}

@test "values: last assignment in a file wins; empty stays empty" {
  printf 'K=first\nK=second\nE=\n' > "$WCONF_ETC/probe.conf"
  [ "$(wconf_get probe K)" = "second" ]
  # A declared-empty key is NOT absent: the default must not fire.
  [ "$(wconf_get probe E fallback)" = "" ]
  [ "$(wconf_get probe MISSING fallback)" = "fallback" ]
}

@test "values: a shell array is kept verbatim (w-term sources that key itself)" {
  printf 'TERMINAL=ghostty\nTERMINAL_OPTS=(--title W)\n' > "$WCONF_ETC/terminal.conf"
  [ "$(wconf_get terminal TERMINAL_OPTS)" = "(--title W)" ]
}

@test "lenient: a non-KEY=value line is ignored with a warning, not fatal" {
  printf 'export BOGUS=1\nif true; then :; fi\nK=survives\n' > "$WCONF_ETC/probe.conf"
  # Load in THIS shell: warnings collected inside a $(…) subshell would die with
  # it (which is why w-conf cat loads before it prints them).
  wconf_load probe
  # One admin flourish must never blind a whole subsystem.
  [ "$(wconf_get probe K)" = "survives" ]
  [ "${#WCONF_WARN[@]}" -ge 1 ]
  [[ "${WCONF_WARN[0]}" == *"not KEY=value"* ]]
}

@test "keys: prefix filter enumerates a catalog across layers" {
  printf 'NTP_arch=a\nNTP_google=g\nSERVERS=arch\n' > "$WCONF_ETC/time.conf"
  printf 'NTP_corp=c\n' > "$WCONF_ETC/time.conf.d/50-corp.conf" 2>/dev/null || {
    mkdir -p "$WCONF_ETC/time.conf.d"; printf 'NTP_corp=c\n' > "$WCONF_ETC/time.conf.d/50-corp.conf"; }
  run wconf_keys time NTP_
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "NTP_arch" ]
  [ "${lines[1]}" = "NTP_corp" ]
  [ "${lines[2]}" = "NTP_google" ]
}

# ── Writes ───────────────────────────────────────────────────────────────────

@test "set: replaces the value in place, keeping the aligned trailing comment" {
  printf 'CHARGE_LIMIT=100             # 0..100\nMODE=desktop\n' > "$WCONF_ETC/power.conf"
  wconf_set power CHARGE_LIMIT 80
  grep -qx 'CHARGE_LIMIT=80             # 0..100' "$WCONF_ETC/power.conf"
  [ "$(wconf_get power CHARGE_LIMIT)" = "80" ]
}

@test "set: appends an absent key, and the cache reflects it immediately" {
  printf 'MODE=desktop\n' > "$WCONF_ETC/power.conf"
  wconf_get power LID_WAKE >/dev/null      # prime the cache before the write
  wconf_set power LID_WAKE keep
  [ "$(wconf_get power LID_WAKE)" = "keep" ]
}

@test "set: user layer lands 0600 in a 0700 dir and leaves no temp file" {
  rm -rf "$WCONF_HOME/.config/w"
  wconf_set probe K v user
  [ "$(stat -c '%a' "$WCONF_HOME/.config/w")" = "700" ]
  [ "$(stat -c '%a' "$WCONF_HOME/.config/w/probe.conf")" = "600" ]
  run bash -c "ls -a '$WCONF_HOME/.config/w' | grep -c '\\.w-conf\\.'"
  [ "$output" = "0" ]
}

@test "set: an existing file keeps its own mode" {
  printf 'K=a\n' > "$WCONF_ETC/probe.conf"
  chmod 640 "$WCONF_ETC/probe.conf"
  wconf_set probe K b
  [ "$(stat -c '%a' "$WCONF_ETC/probe.conf")" = "640" ]
}

@test "set: refuses a policy-locked key instead of writing a shadowed value" {
  printf 'K=admin\n' > "$WCONF_ETC/probe.conf"
  printf 'K=fleet\n' > "$WCONF_ETC/policy.d/probe.conf"
  run wconf_set probe K mine
  [ "$status" -ne 0 ]
  [[ "$output" == *"locked by site policy"* ]]
  # The admin file must be untouched: a refused write writes nothing.
  grep -qx 'K=admin' "$WCONF_ETC/probe.conf"
}

@test "set: policy locks the USER layer too, not just the admin one" {
  # The idle cascade is user-scope (power.schema), so w-power writes it without
  # root. A fleet mandate has to reach that path as well, or "locked" would mean
  # "locked for root only" — the one caller that already needed a password.
  printf 'AC_LOCK=300\n' > "$WCONF_ETC/policy.d/power.conf"
  run wconf_set power AC_LOCK 60 user
  [ "$status" -ne 0 ]
  [[ "$output" == *"locked by site policy"* ]]
  [ ! -e "$WCONF_HOME/.config/w/power.conf" ]
}

@test "set: refuses a user-layer write to a system-scope key" {
  # The loader would drop such a value on the next read, so accepting the write
  # would report success and change nothing — the same failure mode as writing a
  # policy-locked key, just with the schema as the authority instead of the fleet.
  printf 'LID_ON_AC\tsystem\n' > "$WCONF_VENDOR_DIR/power.schema"
  run wconf_set power LID_ON_AC suspend user
  [ "$status" -ne 0 ]
  [[ "$output" == *"system-scope"* ]]
  [ ! -e "$WCONF_HOME/.config/w/power.conf" ]
  # …and the admin layer still takes it.
  wconf_set power LID_ON_AC suspend
  [ "$(wconf_get power LID_ON_AC)" = "suspend" ]
}

@test "set: user-features is writable for ai and unknown elsewhere" {
  # `w-ai features set` writes this second user file so the toggles survive
  # `w-ai profile use` rewriting ai.conf. It is a real layer of `ai` only.
  wconf_set ai W_AI_EMBED ollama user-features
  [ "$(stat -c '%a' "$WCONF_HOME/.config/w/ai-features.conf")" = "600" ]
  [ "$(wconf_get ai W_AI_EMBED)" = "ollama" ]
  [ "$(wconf_origin ai W_AI_EMBED)" = "user-features" ]
  run wconf_set probe K v user-features
  [ "$status" -ne 0 ]
}

@test "set: refuses an invalid key, a multi-line value and an unwritable layer" {
  run wconf_set probe "bad key" v;                 [ "$status" -ne 0 ]
  run wconf_set probe K "$(printf 'a\nb')";        [ "$status" -ne 0 ]
  run wconf_set probe K v vendor;                  [ "$status" -ne 0 ]
  run wconf_set probe K v policy;                  [ "$status" -ne 0 ]
  run wconf_set probe K v site-default;            [ "$status" -ne 0 ]
}

@test "unset: drops the key and the value falls back to the layer below" {
  printf 'K=vendor\n' > "$WCONF_VENDOR_DIR/probe.conf"
  printf 'K=admin\n'  > "$WCONF_ETC/probe.conf"
  wconf_unset probe K
  # This is the new w-reset semantics: "as on a fresh install", not "copy the
  # vendor file over the admin one".
  [ "$(wconf_get probe K)" = "vendor" ]
  [ "$(wconf_origin probe K)" = "vendor" ]
}

# ── Scope declaration read back out ──────────────────────────────────────────

@test "scope: a glob row declares a whole catalog family" {
  # DNS_*/NTP_* entries are data the admin extends, so they are declared once by
  # pattern. Without this the entries ship UNCONSTRAINED and a user file could
  # redefine the addresses behind the admin's chosen provider name.
  printf 'NTP_google=a.example\n'          > "$WCONF_VENDOR_DIR/probe.conf"
  printf 'NTP_*\tsystem\nSERVERS\tsystem\n' > "$WCONF_VENDOR_DIR/probe.schema"
  printf 'NTP_google=hijack.example\n'      > "$WCONF_HOME/.config/w/probe.conf"

  [ "$(wconf_scope probe NTP_google)" = "system" ]
  [ "$(wconf_get probe NTP_google)" = "a.example" ]
  [ -z "$(wconf_scope probe UNDECLARED)" ]
}

@test "scope: porcelain carries the scope as a fifth field, after locked" {
  printf 'MODE\tsystem\nAC_LOCK\tuser\n' > "$WCONF_VENDOR_DIR/power.schema"
  printf 'MODE=desktop\nAC_LOCK=300\n'   > "$WCONF_ETC/power.conf"
  local line; line="$(wconf_list_porcelain power | grep '^MODE')"
  [ "$(cut -f3 <<<"$line")" = "system" ]     # layer, field 3 — unchanged
  [ -z "$(cut -f4 <<<"$line")" ]             # locked, field 4 — unchanged
  [ "$(cut -f5 <<<"$line")" = "system" ]     # scope, appended
}

# ── Cross-implementation contract ────────────────────────────────────────────

@test "python twin agrees with the bash reader over a full layer tree" {
  command -v python3 >/dev/null || skip "python3 not installed"
  printf 'K=vendor\nONLY_V=v\nQ="a # b"\nLOCKED_K=vendor\n' > "$WCONF_VENDOR_DIR/probe.conf"
  # Include a schema so the twin's scope enforcement is compared too, not just
  # its precedence: a divergence there would only surface once a subsystem ships
  # a schema, i.e. long after the code that caused it.
  # A glob row is part of the contract too: fnmatch on the python side must agree
  # with bash's [[ == pattern ]], or a catalog entry would be constrained by one
  # reader and free in the other.
  printf 'LOCKED_K\tsystem\nK\tboth\nNTP_*\tsystem\n' > "$WCONF_VENDOR_DIR/probe.schema"
  printf 'K=site\n'                        > "$WCONF_ETC/site-defaults.d/probe.conf"
  printf 'K=system\nH=gpt#4\nbad line\n'    > "$WCONF_ETC/probe.conf"
  mkdir -p "$WCONF_ETC/probe.conf.d"
  printf 'D=dropin   # note\n'             > "$WCONF_ETC/probe.conf.d/10-x.conf"
  printf 'NTP_x=vendor\n'                 >> "$WCONF_VENDOR_DIR/probe.conf"
  printf 'K=user\nLOCKED_K=sneaky\nNTP_x=sneaky\n' > "$WCONF_HOME/.config/w/probe.conf"

  bash_out="$(wconf_list_porcelain probe | cut -f1-3)"
  py_out="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import core
for k, (v, layer) in sorted(core.conf_read("probe").items()):
    print("\t".join((k, v, layer)))
' "$REPO/rootfs/usr/lib/w/w-mcp")"
  [ "$bash_out" = "$py_out" ]
}

# ── Environment robustness ───────────────────────────────────────────────────

# Regression, release gate 2026-08-06: `_wconf_user_dir` dereferenced a bare $HOME.
# systemd exports HOME only for units with User=, so w-firstboot (a root system
# unit) has none — and every consumer of this library runs `set -u`. Result: the
# first `apply --dns` of a FRESH install died with "HOME: unbound variable", i.e.
# no new W machine could finish firstboot. Reproduced here the way the consumers
# actually run (own shell, set -euo pipefail), because bats itself does not set -u
# and would report a pass on the broken code.
@test "user layer resolves without HOME (systemd system-unit context)" {
  run env -u HOME -u XDG_CONFIG_HOME -u WCONF_HOME \
      bash -c "set -euo pipefail; source '$REPO/rootfs/usr/lib/w/w-conf-lib.sh'; _wconf_user_dir"
  [ "$status" -eq 0 ]
  # Resolved from passwd on purpose: root running a tool from a unit must read the
  # same user layer as root running it from a shell.
  [ "$output" = "$(getent passwd "$(id -u)" | cut -d: -f6)/.config/w" ]
}

# ── Target resolution: whose user layer are we acting on? ────────────────────
#
# The rule three subsystems used to answer alone (w-power, w-nightlight,
# w-monitor, plus w-conf), each with its own copy of `awk '$3>=1000 … exit'`.
# Two bugs came out of that and both are pinned below: a render that reached only
# the first account, and a pkexec caller (the Hub) writing into the FIRST user's
# ~/.config/w instead of their own.
#
# W_EUID fakes root (bash makes EUID readonly) and `getent` is shadowed to read
# the passwd fixture, so the whole matrix runs unprivileged.

_seed_passwd() {
  export W_PASSWD="$BATS_TEST_TMPDIR/passwd"
  cat > "$W_PASSWD" <<EOF
root:x:0:0::/root:/usr/bin/bash
bin:x:1:1::/:/usr/bin/nologin
gitlab:x:1002:1002::/var/lib/gitlab:/usr/bin/nologin
alice:x:1000:1000::/home/alice:/usr/bin/zsh
bob:x:1001:1001::/srv/bob:/usr/bin/zsh
nobody:x:65534:65534::/:/usr/bin/nologin
EOF
  getent() { # getent passwd <name|uid>
    awk -F: -v k="$2" '$1 == k || $3 == k { print; found = 1 } END { exit !found }' "$W_PASSWD"
  }
}

@test "target: root falls back to the first human account (firstboot)" {
  _seed_passwd
  W_EUID=0 SUDO_USER= PKEXEC_UID= wconf_resolve_target
  [ "$WCONF_TARGET_USER" = "alice" ]
  [ "$WCONF_TARGET_HOME" = "/home/alice" ]
  [ "$WCONF_HOME" = "/home/alice" ]
}

@test "target: the fallback skips system uids, service shells and nobody" {
  _seed_passwd
  # gitlab sits in the human uid range but has a nologin shell — a service
  # account is not a W user, and rendering a desktop config into /var/lib is how
  # you find that out the hard way.
  sed -i '/^alice/d;/^bob/d' "$W_PASSWD"
  run env W_EUID=0 SUDO_USER= PKEXEC_UID= W_PASSWD="$W_PASSWD" \
      bash -c "set -euo pipefail; source '$REPO/rootfs/usr/lib/w/w-conf-lib.sh'; wconf_resolve_target; echo \$WCONF_TARGET_USER"
  # Nothing to resolve: exit 1, silent — the caller decides what that means.
  [ "$status" -eq 1 ]
}

@test "target: sudo invoker beats the first account" {
  _seed_passwd
  W_EUID=0 SUDO_USER=bob PKEXEC_UID= wconf_resolve_target
  [ "$WCONF_TARGET_USER" = "bob" ]
}

@test "target: pkexec invoker beats the first account (the Hub's path)" {
  _seed_passwd
  # pkexec sets no SUDO_USER — which is exactly how the Hub's second user ended
  # up writing their idle timers into the first user's ~/.config/w/power.conf.
  W_EUID=0 SUDO_USER= PKEXEC_UID=1001 wconf_resolve_target
  [ "$WCONF_TARGET_USER" = "bob" ]
}

@test "target: an explicit name beats every invoker (the module loop)" {
  _seed_passwd
  W_EUID=0 SUDO_USER=alice PKEXEC_UID=1000 wconf_resolve_target bob
  [ "$WCONF_TARGET_USER" = "bob" ]
}

@test "target: home comes from passwd, never from /home/<user>" {
  _seed_passwd
  W_EUID=0 SUDO_USER= PKEXEC_UID= wconf_resolve_target bob
  # /home/bob would be a phantom path: the first `install -d` would create it and
  # leave the real home untouched, silently.
  [ "$WCONF_TARGET_HOME" = "/srv/bob" ]
}

@test "target: a non-root caller may not act for someone else" {
  _seed_passwd
  run wconf_resolve_target alice
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires root"* ]]
}

@test "target: an unknown user is refused, not guessed" {
  _seed_passwd
  run env W_EUID=0 W_PASSWD="$W_PASSWD" \
      bash -c "set -euo pipefail; source '$REPO/rootfs/usr/lib/w/w-conf-lib.sh'; wconf_resolve_target ghost"
  [ "$status" -eq 2 ]
}
