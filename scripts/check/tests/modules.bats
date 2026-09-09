#!/usr/bin/env bats
# modules.bats — the module registry reader (scripts/install/lib/modules.sh).
#
# check/modules.sh validates the REAL registry; what it cannot cover is how the
# reader behaves on a file that is wrong, because the real file is right. Yet that
# is the branch that matters most: apply.sh sources every post-boot module through
# this parser and then dispatches --all from it, so a reader that quietly returns a
# short list on a malformed row would under-apply the system with no error anywhere
# — the firstboot equivalent of a silent no-op. Each rejection below is therefore an
# assertion that the parser fails LOUDLY instead.
#
# The order/graph invariants themselves are asserted against synthetic registries
# here (a cycle, a dep pointing forward, a stray '*'), which the live file must
# never contain and so could never exercise.

load helpers

LIB="$REPO/scripts/install/lib/modules.sh"

# Load a registry written inline; prints nothing on success.
_load() {
  local conf="$BATS_TEST_TMPDIR/modules.conf"
  cat > "$conf"
  mkdir -p "$BATS_TEST_TMPDIR/modules"
  # shellcheck disable=SC1090
  ( set -euo pipefail; source "$LIB"; w_modules_load "$conf" >/dev/null; )
}

# Load and then run a snippet against the populated arrays.
_load_then() {
  local snippet="$1" conf="$BATS_TEST_TMPDIR/modules.conf"
  cat > "$conf"
  mkdir -p "$BATS_TEST_TMPDIR/modules"
  ( set -euo pipefail; source "$LIB"; w_modules_load "$conf"; eval "$snippet" )
}

@test "reader: parses rows, trims fields, and resolves the '-' placeholder" {
  run _load_then 'echo "$W_MOD_N|${W_MOD_NAME[1]}|${W_MOD_PHASE[1]}|${W_MOD_FN[1]}|[${W_MOD_FLAG[0]}]|[${W_MOD_LABEL[0]}]|[${W_MOD_AFTER[0]}]"' <<'EOF'
# a comment, and a blank line follow

  base   |  install |  mod_base  |  -  |  -  |  -
other    | apply    | mod_other  | --other | Other | base
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "2|other|apply|mod_other|[]|[]|[]" ]
}

@test "reader: rejects an unknown phase" {
  run _load <<'EOF'
base | someday | mod_base | - | - | -
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown phase 'someday'"* ]]
}

@test "reader: rejects a row missing name, phase or fn" {
  run _load <<'EOF'
base | install |  | - | - | -
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs at least name|phase|fn"* ]]
}

@test "reader: rejects a row with an extra field" {
  run _load <<'EOF'
base | install | mod_base | - | - | - | oops
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"too many fields"* ]]
}

@test "reader: rejects an empty registry rather than reporting zero modules" {
  run _load <<'EOF'
# nothing but comments
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"no module rows"* ]]
}

@test "reader: rejects an unreadable file" {
  run bash -c "source '$LIB'; w_modules_load '$BATS_TEST_TMPDIR/absent.conf'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not readable"* ]]
}

@test "reader: files are deduplicated, ordered, and limited to the phases asked for" {
  cat > "$BATS_TEST_TMPDIR/modules.conf" <<'EOF'
grub    | install | mod_grub   | -       | -     | -
base    | install | mod_base   | -       | -     | -
grub    | manual  | mod_grub   | --grub  | -     | -
ghost   | apply   | mod_ghost  | --ghost | Ghost | -
EOF
  mkdir -p "$BATS_TEST_TMPDIR/modules"
  touch "$BATS_TEST_TMPDIR/modules/grub.sh" "$BATS_TEST_TMPDIR/modules/base.sh"
  run bash -c "source '$LIB'; w_modules_load '$BATS_TEST_TMPDIR/modules.conf'; w_modules_files install manual | tr '\n' ' '"
  [ "$status" -eq 0 ]
  # grub twice in the registry, once here; ghost has no file (a pseudo-module).
  [ "$output" = "grub.sh base.sh " ]
}

@test "reader: flags come back in registry order, install-only ones excluded" {
  run _load_then 'w_modules_flags apply manual | tr "\n" " "' <<'EOF'
base   | install | mod_base   | -        | -      | -
rootfs | apply   | apply_root | --rootfs | Rootfs | -
grub   | manual  | mod_grub   | --grub   | -      | rootfs
style  | apply   | mod_style  | --style  | Style  | rootfs
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "--rootfs --grub --style " ]
}

@test "reader: flag_of answers only for post-boot modules" {
  run _load_then 'echo "[$(w_modules_flag_of style)][$(w_modules_flag_of base)][$(w_modules_flag_of devtools)]"' <<'EOF'
base     | install | mod_base     | -           | -     | -
style    | apply   | mod_style    | --style     | Style | -
devtools | dev     | mod_devtools | --devtools  | -     | -
EOF
  [ "$status" -eq 0 ]
  # An install-only module and the dev-only one must never be reachable from a
  # sync-map path route — that is what keeps dev tooling off a user's machine.
  [ "$output" = "[--style][][]" ]
}

# ── the graph checks, driven against registries the real file may never contain ──

_chk_against() {
  local dir="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$dir/scripts/install/modules" "$dir/rootfs/usr/share/w/update" "$dir/rootfs/usr/bin"
  mkdir -p "$dir/scripts/install/lib"
  cp "$LIB" "$dir/scripts/install/lib/modules.sh"
  cat > "$dir/scripts/install/modules.conf"
  # Minimal stand-ins for the consumers the suite cross-checks.
  printf '*\t--all\n' > "$dir/rootfs/usr/share/w/update/sync-map"
  : > "$dir/rootfs/usr/bin/w-sync"
  printf 'main() {\n}\n' > "$dir/scripts/install.sh"
  : > "$dir/scripts/apply.sh"
  ( cd "$dir" \
    && SRC="$dir" \
    && source "$REPO/scripts/check/modules.sh" \
    && chk_modules )
}

@test "graph: a dependency listed later than its dependent is an error" {
  run _chk_against <<'EOF'
early | apply | apply_early | --early | Early | late
late  | apply | apply_late  | --late  | Late  | -
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"early must run after late, but late is listed later"* ]]
}

@test "graph: a cycle cannot linearize, so both edges are reported" {
  run _chk_against <<'EOF'
a | apply | apply_a | --a | A | b
b | apply | apply_b | --b | B | a
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"a must run after b"* ]]
}

@test "graph: a dependency on a module of another run group is an error" {
  run _chk_against <<'EOF'
base | install | mod_base    | -        | -      | -
last | apply   | apply_last  | --last   | Last   | base
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such module in this run group"* ]]
}

@test "graph: '*' means last of its phase and is checked as such" {
  run _chk_against <<'EOF'
snapper | apply | apply_snapper | --snapper | Snapper | *
after   | apply | apply_after   | --after   | After   | -
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"declared last of phase 'apply', but other rows follow it"* ]]
}

@test "graph: '*' may not be mixed with named dependencies" {
  run _chk_against <<'EOF'
first | apply | apply_first | --first | First | -
last  | apply | apply_last  | --last  | Last  | * first
EOF
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be combined with named deps"* ]]
}
