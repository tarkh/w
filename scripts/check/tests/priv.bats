#!/usr/bin/env bats
# priv.bats — w-priv-lib.sh: who counts as an administrator.
#
# The lib shells out to `id`/`getent`, so the tests shadow both with bash
# functions (the same shading trick core.bats uses for privileged commands) —
# nothing here depends on the groups of whoever runs the suite. The complementary
# check for the Python twin (_is_admin in w-mcp/core.py) is the contract selftest's
# privilege-invariant, which asserts _actuate() still calls it.

load helpers

setup() {
  source "$REPO/rootfs/usr/lib/w/w-priv-lib.sh"
  # Default shading: a wheel group exists, the caller is `plain` and is not in it.
  getent() { [[ "$2" == wheel ]]; }
  id() { case "$1" in -un) echo plain ;; -nG) echo "plain users" ;; esac; }
  export -f getent id
}

@test "w_is_admin: a wheel member is an admin" {
  id() { case "$1" in -un) echo boss ;; -nG) echo "boss wheel users" ;; esac; }
  run w_is_admin
  [ "$status" -eq 0 ]
}

# Explicit user: the no-argument form short-circuits on EUID, so a suite that
# happened to run as root would pass this test for the wrong reason.
@test "w_is_admin: a non-member is not" {
  run w_is_admin plain
  [ "$status" -ne 0 ]
}

@test "w_is_admin: an explicit user argument is honoured over the caller" {
  id() { case "$1" in -un) echo plain ;; -nG) [[ "$2" == boss ]] && echo "boss wheel" || echo "plain" ;; esac; }
  run w_is_admin boss
  [ "$status" -eq 0 ]
}

@test "w_is_admin: root is always an admin, without consulting groups" {
  id() { echo "SHOULD NOT BE CALLED"; }
  run w_is_admin root
  [ "$status" -eq 0 ]
}

@test "w_is_admin: fails open when the machine has no wheel group" {
  getent() { return 2; }
  run w_is_admin
  [ "$status" -eq 0 ]
}

@test "w_is_admin: a group merely containing 'wheel' does not count" {
  id() { case "$1" in -un) echo plain ;; -nG) echo "plain wheelchair nowheel" ;; esac; }
  run w_is_admin plain
  [ "$status" -ne 0 ]
}

@test "w_admin_msg: names the action, the user and the remedy" {
  run w_admin_msg "updating W"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updating W requires administrator rights"* ]]
  [[ "$output" == *"'plain'"* ]]
  [[ "$output" == *"wheel"* ]]
}
