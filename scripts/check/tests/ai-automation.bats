#!/usr/bin/env bats
# ai-automation.bats — modules/automation.py: _valid_recipe_name().
#
# core.py is import-only/testable without the `mcp` package (its own header
# docstring) — same reasoning as ai-memory.bats. This is the one piece of real
# validation logic in automation.py (the tools otherwise just shell out to
# `w-ai recipe/schedule`, which is VM-verified, not bats-verified). The regex
# is also what confines a scheduled recipe to
# the two curated recipe directories instead of an arbitrary path.

load helpers

setup() {
  command -v python3 &>/dev/null || skip "python3 not installed"
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
}

valid_name() {
  PYTHONPATH="$LIB" python3 -c "
from modules import automation
print(automation._valid_recipe_name('$1'))
"
}

@test "_valid_recipe_name: accepts a bare catalog name" {
  [[ "$(valid_name morning-digest)" == "True" ]]
}

@test "_valid_recipe_name: rejects path traversal" {
  [[ "$(valid_name ../../etc/passwd)" == "False" ]]
}

@test "_valid_recipe_name: rejects a bare slash" {
  [[ "$(valid_name foo/bar)" == "False" ]]
}

@test "_valid_recipe_name: rejects an empty name" {
  [[ "$(valid_name '')" == "False" ]]
}
