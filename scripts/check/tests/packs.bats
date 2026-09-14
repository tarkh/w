#!/usr/bin/env bats
# packs.bats — w-pack's remove pipeline (packs.md phase 7).
#
# What is worth asserting here is what a live run cannot show you cheaply: remove
# is destructive, multi-account, and most of its promises are about what it does
# NOT touch. "It removed the bundle" is visible on a VM in ten seconds; "it left
# the user's own settings.json alone, backed up the managed file it did delete,
# reached the second account that had the layer and no one else, and refused to
# strand a dependent bundle" is four states you would have to build by hand every
# time. So they are built here, deterministically, against a fake bundle tree.
#
# Everything runs unprivileged: the root gates and ownership are not the subject
# (EUID-0 branches are the ones the VM run exercises), the state roots are the
# env seams w-pack declares, and w_home_users is stubbed to a two-account machine.

load helpers

PACK_BIN="rootfs/usr/bin/w-pack"

setup() {
  export W_PACKS_DIR="$BATS_TEST_TMPDIR/packs"
  export W_PACKS_STATE="$BATS_TEST_TMPDIR/var/packs.json"
  export W_PACKS_WSTYLE_DROPIN="$BATS_TEST_TMPDIR/wstyle/modules.d"
  export W_PACKS_AI_SKILLS="$BATS_TEST_TMPDIR/ai/skills"
  export W_PACKS_MCP_DROPIN="$BATS_TEST_TMPDIR/ai/mcp.d"
  export W_PACKS_DEPLOY_SDK="$BATS_TEST_TMPDIR/deploy.sh"
  export W_PRIV_LIB="$REPO/rootfs/usr/lib/w/w-priv-lib.sh"
  export W_PAC_LIB="$REPO/rootfs/usr/lib/w/w-pac-lib.sh"
  export W_BACKUP_LIB="$REPO/rootfs/usr/lib/w/w-backup-lib.sh"

  # Backups land in the account's own home / a tmp system root, never the real ones.
  export W_BACKUP_SYS_ROOT="$BATS_TEST_TMPDIR/var/backups"

  HOMES="$BATS_TEST_TMPDIR/homes"
  ALICE="$HOMES/alice"; BOB="$HOMES/bob"
  mkdir -p "$ALICE" "$BOB" "$(dirname "$W_PACKS_STATE")"

  # A minimal deploy SDK: w-pack sources it for w_home_users (who counts as a human
  # account) and seed_user_file. Only the former matters to remove.
  cat > "$W_PACKS_DEPLOY_SDK" <<EOF
w_home_users() { printf 'alice\t$ALICE\nbob\t$BOB\n'; }
seed_user_file() { :; }
EOF

  source "$REPO/$PACK_BIN"
  # -e stays ON: bats reports a failed assertion through errexit.
  set +u; set +o pipefail

  # System paths in a fixture manifest are absolute and would point at the real
  # filesystem, so the tests use a tmp prefix and w-pack is told to leave root
  # gates alone — the privilege model is not what this suite is about.
  require_root() { :; }
  w_is_admin()   { return 0; }
}

# mkbundle <name> — a bundle with both layers, a managed and a user config row,
# an axis, an AI skill and a teardown pair that leaves a breadcrumb when it runs.
mkbundle() {
  local n="$1" d="$W_PACKS_DIR/$1"
  mkdir -p "$d/config/skel/.config/$n" "$d/wstyle/500-$n" "$d/ai"
  cat > "$d/meta.conf" <<EOF
NAME="$n"
DESC="test bundle $n"
DEPS="${2:-}"
EOF
  printf '%s\n' "pkg-$n-a" "pkg-$n-b" > "$d/pkgs.txt"
  printf '.config/%s/managed.conf\tmanaged\n.config/%s/mine.conf\tuser\n' "$n" "$n" > "$d/manifest"
  echo "managed" > "$d/config/skel/.config/$n/managed.conf"
  echo "mine"    > "$d/config/skel/.config/$n/mine.conf"
  echo "DESC=x"  > "$d/wstyle/500-$n/module.sh"
  echo "# skill" > "$d/ai/SKILL.md"
  cat > "$d/setup.sh" <<'EOF'
exit 0
EOF
  cat > "$d/setup-user.sh" <<'EOF'
exit 0
EOF
  cat > "$d/teardown.sh" <<EOF
echo "\$BUNDLE_NAME machine packages=\$PACK_PACKAGES" >> "$BATS_TEST_TMPDIR/trace"
EOF
  cat > "$d/teardown-user.sh" <<EOF
echo "\$BUNDLE_NAME user \$PACK_USER" >> "$BATS_TEST_TMPDIR/trace"
EOF
  # As if installed: the machine state, the deployed axis and skill.
  mkdir -p "$W_PACKS_WSTYLE_DROPIN/500-$n" "$W_PACKS_AI_SKILLS/$n"
  echo "DESC=x"  > "$W_PACKS_WSTYLE_DROPIN/500-$n/module.sh"
  echo "# skill" > "$W_PACKS_AI_SKILLS/$n/SKILL.md"
  [[ -f "$W_PACKS_STATE" ]] || echo '{"bundles":{}}' > "$W_PACKS_STATE"
  record_install "$n"
}

# give <bundle> <home> — hand one account the bundle's per-user layer.
give() {
  local n="$1" h="$2"
  mkdir -p "$h/.config/$n"
  echo "managed" > "$h/.config/$n/managed.conf"
  echo "MY EDIT" > "$h/.config/$n/mine.conf"
  user_record "$n" "$(basename "$h")" "$h"
}

# w-style is not installed here; the axis re-render is best-effort by design.
w-style() { :; }

@test "remove: drops the machine state, the axis and the AI skill" {
  mkbundle alpha
  give alpha "$ALICE"
  run cmd_remove alpha
  [[ "$status" -eq 0 ]]
  ! is_installed alpha
  [[ ! -d "$W_PACKS_WSTYLE_DROPIN/500-alpha" ]]
  [[ ! -d "$W_PACKS_AI_SKILLS/alpha" ]]
}

@test "remove: runs both teardown halves, machine one with packages=0" {
  mkbundle alpha
  give alpha "$ALICE"
  run cmd_remove alpha
  [[ "$status" -eq 0 ]]
  grep -qx "alpha user alice" "$BATS_TEST_TMPDIR/trace"
  grep -qx "alpha machine packages=0" "$BATS_TEST_TMPDIR/trace"
}

@test "remove: deletes the managed config but never the user's own" {
  mkbundle alpha
  give alpha "$ALICE"
  cmd_remove alpha
  [[ ! -f "$ALICE/.config/alpha/managed.conf" ]]
  [[ -f "$ALICE/.config/alpha/mine.conf" ]]
  [[ "$(cat "$ALICE/.config/alpha/mine.conf")" == "MY EDIT" ]]
}

@test "remove: backs the managed config up into the owner's own home" {
  mkbundle alpha
  give alpha "$ALICE"
  cmd_remove alpha
  run find "$ALICE/.local/state/w/reset-backups" -name managed.conf
  [[ -n "$output" ]]
  [[ "$(cat "$output")" == "managed" ]]
}

@test "remove: reaches every account that had the layer, and only those" {
  mkbundle alpha
  give alpha "$ALICE"
  give alpha "$BOB"
  cmd_remove alpha
  grep -qx "alpha user alice" "$BATS_TEST_TMPDIR/trace"
  grep -qx "alpha user bob"   "$BATS_TEST_TMPDIR/trace"
  ! user_has alpha "$ALICE"
  ! user_has alpha "$BOB"
}

@test "remove: an account that never had the layer is not touched" {
  mkbundle alpha
  give alpha "$ALICE"
  echo "BOBS OWN" > "$BOB/untouched"
  cmd_remove alpha
  ! grep -q "alpha user bob" "$BATS_TEST_TMPDIR/trace"
  [[ "$(cat "$BOB/untouched")" == "BOBS OWN" ]]
}

@test "remove: refuses while an installed bundle still depends on it" {
  mkbundle alpha
  mkbundle beta alpha
  run cmd_remove alpha
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required by installed bundle(s): beta"* ]]
  is_installed alpha
}

@test "remove: a dependent that is NOT installed does not block" {
  mkbundle alpha
  mkbundle beta alpha
  state_forget beta
  run cmd_remove alpha
  [[ "$status" -eq 0 ]]
  ! is_installed alpha
}

@test "removable_pkgs: excludes what another installed bundle still lists" {
  mkbundle alpha
  mkbundle beta
  # beta also ships alpha's second package.
  printf '%s\n' "pkg-beta-a" "pkg-alpha-b" > "$W_PACKS_DIR/beta/pkgs.txt"
  run removable_pkgs alpha
  [[ "$output" == "pkg-alpha-a" ]]
}

@test "removable_pkgs: a removed bundle no longer shields its packages" {
  mkbundle alpha
  mkbundle beta
  printf '%s\n' "pkg-alpha-b" > "$W_PACKS_DIR/beta/pkgs.txt"
  state_forget beta
  run removable_pkgs alpha
  [[ "$output" == *"pkg-alpha-a"* ]]
  [[ "$output" == *"pkg-alpha-b"* ]]
}

@test "remove without --packages: prints the pacman line, runs nothing" {
  mkbundle alpha
  pacman() { echo "PACMAN CALLED" >> "$BATS_TEST_TMPDIR/trace"; }
  run cmd_remove alpha
  [[ "$output" == *"sudo pacman -Rns pkg-alpha-a pkg-alpha-b"* ]]
  ! grep -q "PACMAN CALLED" "$BATS_TEST_TMPDIR/trace"
}

@test "remove --packages: removes them and tells the teardown so" {
  mkbundle alpha
  give alpha "$ALICE"
  WITH_PACKAGES=1
  pacman() { echo "PACMAN $*" >> "$BATS_TEST_TMPDIR/trace"; }
  run cmd_remove alpha
  [[ "$status" -eq 0 ]]
  grep -q "PACMAN -Rns --noconfirm pkg-alpha-a pkg-alpha-b" "$BATS_TEST_TMPDIR/trace"
  grep -qx "alpha machine packages=1" "$BATS_TEST_TMPDIR/trace"
}

@test "unsetup: undoes only my account, leaving the machine installed" {
  mkbundle alpha
  give alpha "$ALICE"
  give alpha "$BOB"
  TARGET_USER=alice; TARGET_HOME="$ALICE"
  require_user() { :; }
  run cmd_unsetup alpha
  [[ "$status" -eq 0 ]]
  ! user_has alpha "$ALICE"
  user_has alpha "$BOB"
  is_installed alpha
  ! grep -q "alpha machine" "$BATS_TEST_TMPDIR/trace"
}

@test "unsetup: an account that never had the layer is a no-op, not an error" {
  mkbundle alpha
  give alpha "$ALICE"
  TARGET_USER=bob; TARGET_HOME="$BOB"
  require_user() { :; }
  run cmd_unsetup alpha
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"not set up for bob"* ]]
  [[ ! -f "$BATS_TEST_TMPDIR/trace" ]]
}

@test "remove: unknown and not-installed bundles fail with their own message" {
  mkbundle alpha
  run cmd_remove nosuch
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown bundle"* ]]
  state_forget alpha
  run cmd_remove alpha
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"nothing to remove"* ]]
}

# ── Hyprland rule drop-ins ───────────────────────────────────────────────────
# A bundle's window rule lands in the vendor rules.d and is picked up by every
# session only on `hyprctl reload`. The hook must reach each account that has a
# live compositor (its instance signature under $XDG_RUNTIME_DIR/hypr/), skip the
# ones without, and stay silent for bundles that ship no rule at all. Stubbed:
# `id` (alice=1000 with a session, bob=1001 without), `runuser` (drops to a plain
# exec) and `hyprctl` (a PATH shim that records what it was called with).
hypr_fixture() {
  # w-pack is already sourced by setup(), so the seam is set directly.
  export W_PACKS_HYPR_RULES_DIR="$BATS_TEST_TMPDIR/rules.d"; HYPR_RULES_DIR="$W_PACKS_HYPR_RULES_DIR"
  export W_RUNTIME_BASE="$BATS_TEST_TMPDIR/run"
  mkdir -p "$W_RUNTIME_BASE/1000/hypr/sig-alice" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/hyprctl" <<EOF
#!/bin/bash
echo "\$HYPRLAND_INSTANCE_SIGNATURE \$XDG_RUNTIME_DIR \$*" >> "$BATS_TEST_TMPDIR/hyprctl.trace"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/hyprctl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  id() {
    [[ "$1" == -u && -n "${2:-}" ]] || { command id "$@"; return; }
    case "$2" in alice) echo 1000 ;; bob) echo 1001 ;; *) return 1 ;; esac
  }
  runuser() { shift 2; [[ "$1" == "--" ]] && shift; "$@"; }
}

# rules_row <bundle> — give the bundle a deployed rules.d drop-in + manifest row.
rules_row() {
  local n="$1" d="$W_PACKS_DIR/$1"
  mkdir -p "$d/config/root$W_PACKS_HYPR_RULES_DIR" "$W_PACKS_HYPR_RULES_DIR"
  echo "hl.window_rule({})" > "$d/config/root$W_PACKS_HYPR_RULES_DIR/$n.lua"
  cp "$d/config/root$W_PACKS_HYPR_RULES_DIR/$n.lua" "$W_PACKS_HYPR_RULES_DIR/$n.lua"
  printf '%s/%s.lua\tmanaged\n' "$W_PACKS_HYPR_RULES_DIR" "$n" >> "$d/manifest"
}

@test "remove: a rules.d row reloads Hyprland for the account with a session only" {
  hypr_fixture
  mkbundle alpha; rules_row alpha
  cmd_remove alpha
  [[ ! -f "$W_PACKS_HYPR_RULES_DIR/alpha.lua" ]]
  run cat "$BATS_TEST_TMPDIR/hyprctl.trace"
  [[ "$output" == "sig-alice $W_RUNTIME_BASE/1000 reload" ]]
}

@test "remove: no rules.d row, no Hyprland reload" {
  hypr_fixture
  mkbundle alpha
  cmd_remove alpha
  [[ ! -f "$BATS_TEST_TMPDIR/hyprctl.trace" ]]
}

# ── mcp.d: the bundle's MCP server drop-ins (packs.md, the fourth channel) ───
# A drop-in leaves with the bundle exactly like an axis does: no bundle, no
# server offered to the assistant. Only the file mechanics are asserted here —
# what w-ai does with a drop-in is ai-host.bats' subject.
mcp_row() {                                             # <bundle>
  local n="$1" d="$W_PACKS_DIR/$1"
  mkdir -p "$d/mcp"
  printf 'COMMAND="%s-server"\nARGS="--stdio"\n' "$n" > "$d/mcp/$n.conf"
}

@test "mcp.d: install registers the bundle's drop-in, remove takes it away" {
  mkbundle alpha; mcp_row alpha
  deploy_mcp alpha
  [[ -f "$W_PACKS_MCP_DROPIN/alpha.conf" ]]
  grep -qx 'COMMAND="alpha-server"' "$W_PACKS_MCP_DROPIN/alpha.conf"
  cmd_remove alpha
  [[ ! -f "$W_PACKS_MCP_DROPIN/alpha.conf" ]]
}

@test "mcp.d: a bundle without mcp/ neither creates the root nor fails" {
  mkbundle alpha
  deploy_mcp alpha
  remove_mcp alpha
  [[ ! -d "$W_PACKS_MCP_DROPIN" ]]
}

@test "mcp.d: remove leaves another bundle's drop-in alone" {
  mkbundle alpha; mcp_row alpha; deploy_mcp alpha
  mkbundle beta;  mcp_row beta;  deploy_mcp beta
  cmd_remove alpha
  [[ ! -f "$W_PACKS_MCP_DROPIN/alpha.conf" ]]
  [[   -f "$W_PACKS_MCP_DROPIN/beta.conf" ]]
}
