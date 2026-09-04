#!/usr/bin/env bats
# ai-contract.bats — contract.py: the mechanical Tool Contract Selftest.
# Runs the REAL w-mcp module tree (no fixtures — this exercises
# the actual shipped tools) through contract.py's checks, without needing the
# `mcp` package installed (contract.py is import-only, like core.py).
#
# setup_file runs contract.py exactly once (module discovery + all checks import
# every modules/*.py) and caches stdout; individual @test cases just grep it —
# cheaper than re-discovering the whole tree per assertion.

load helpers

setup_file() {
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
  export W_AI_SYS_ROOT="$REPO/rootfs/usr/share/w/ai"
  OUT="$BATS_FILE_TMPDIR/contract-output.txt"
  PYTHONPATH="$LIB" python3 "$LIB/contract.py" > "$OUT" 2>&1
  echo "$?" > "$BATS_FILE_TMPDIR/contract-rc.txt"
}

@test "contract.py: every mechanical check passes against the real shipped tool tree" {
  rc="$(cat "$BATS_FILE_TMPDIR/contract-rc.txt")"
  out="$(cat "$BATS_FILE_TMPDIR/contract-output.txt")"
  [[ "$rc" -eq 0 ]] || { echo "$out"; false; }
  [[ "$out" == *"contract: 7/7 checks passed"* ]]
}

@test "contract.py: discovers every domain module" {
  out="$(cat "$BATS_FILE_TMPDIR/contract-output.txt")"
  [[ "$out" == *"modules loaded (22)"* ]]
  [[ "$out" == *"knowledge"* ]]
  [[ "$out" == *"web"* ]]
}

# ── Regression fixtures: prove each check actually catches what it claims to ──
# (run against small synthetic registries, not the real tree, so a real future
# violation can't accidentally get masked by one of these tests passing).

setup() {
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
}

run_py() {  # run_py <python source on stdin>
  PYTHONPATH="$LIB" python3 -c "$1"
}

@test "_check_schema_validity: flags a parameter with no type annotation" {
  result="$(run_py "
import contract
def bad(x) -> str: return 'ok'
print(contract._check_schema_validity([{'name': 'bad', 'domain': 'x', 'minimal': False, 'fn': bad}]))
")"
  [[ "$result" == *"no type annotation"* ]]
}

@test "_check_name_collision: flags a duplicate tool name" {
  result="$(run_py "
import contract
reg = [{'name': 'w_dup', 'domain': 'a', 'minimal': False, 'fn': lambda: 1},
       {'name': 'w_dup', 'domain': 'b', 'minimal': False, 'fn': lambda: 2}]
print(contract._check_name_collision(reg))
")"
  [[ "$result" == *"registered 2 times"* ]]
}

@test "_check_profile_gate: passes on the real core.tool() gating logic" {
  result="$(run_py "
import contract
print(contract._check_profile_gate([]))
")"
  [[ "$result" == "[]" ]]
}

@test "_check_privilege_invariant: flags a stray pkexec call outside core._actuate" {
  tmp="$BATS_TEST_TMPDIR/libtree"
  mkdir -p "$tmp/modules"
  echo 'ACTUATE = 1' > "$tmp/core.py"
  echo 'import subprocess
subprocess.run(["pkexec", "evil"])' > "$tmp/modules/rogue.py"
  result="$(run_py "
import contract
from pathlib import Path
print(contract._check_privilege_invariant(Path('$tmp')))
")"
  [[ "$result" == *"calls pkexec directly"* ]]
}

@test "_check_privilege_invariant: flags shell=True anywhere in the tree" {
  tmp="$BATS_TEST_TMPDIR/libtree2"
  mkdir -p "$tmp/modules"
  echo 'ACTUATE = 1
import subprocess
subprocess.run("pkexec x", shell=True)' > "$tmp/core.py"
  result="$(run_py "
import contract
from pathlib import Path
print(contract._check_privilege_invariant(Path('$tmp')))
")"
  [[ "$result" == *"shell=True"* ]]
}

@test "_check_tier2_guard: flags a tool that calls _actuate without a _tool_on guard" {
  result="$(run_py "
import contract, core
def unguarded():
    return core._actuate('cap')
print(contract._check_tier2_guard([{'name': 'w_unguarded', 'domain': 'x', 'minimal': False, 'fn': unguarded}]))
")"
  [[ "$result" == *"without a _tool_on"* ]]
}

@test "_check_disabled_tool_stub: flags a tool that ignores the disabled toggle" {
  result="$(run_py "
import contract, core
def broken(x: str = '') -> str:
    if not core._tool_on(\"BROKEN\"):
        return '(nope, wrong shape)'
    return core._actuate('cap')
print(contract._check_disabled_tool_stub([{'name': 'w_broken', 'domain': 'x', 'minimal': False, 'fn': broken}]))
")"
  [[ "$result" == *"expected"* ]]
}

@test "_check_disabled_tool_stub: two-step plan/apply tool is exercised via the apply branch" {
  result="$(run_py "
import contract, core
def two_step(action: str = 'plan') -> str:
    if action == 'plan':
        return 'plan output'
    if not core._tool_on(\"TWOSTEP\"):
        return core._disabled_msg('w_two_step', 'W_AI_TOOL_TWOSTEP')
    return core._actuate('cap')
print(contract._check_disabled_tool_stub([{'name': 'w_two_step', 'domain': 'x', 'minimal': False, 'fn': two_step}]))
")"
  [[ "$result" == "[]" ]]
}

@test "_check_agents_md: flags a missing mandatory section and a stale marker" {
  tmp="$BATS_TEST_TMPDIR/AGENTS.md"
  printf '## Identity\ncontent\n\n## Memory\ncontent\n\nTODO: fix this\n' > "$tmp"
  result="$(run_py "
import contract
from pathlib import Path
print(contract._check_agents_md(Path('$tmp'), []))
")"
  [[ "$result" == *"missing mandatory section '## How to use your knowledge'"* ]]
  [[ "$result" == *"missing mandatory section '## Operating rules'"* ]]
  [[ "$result" == *"stale marker 'TODO'"* ]]
}

@test "_check_agents_md: flags a tool mention with no matching registry entry" {
  tmp="$BATS_TEST_TMPDIR/AGENTS2.md"
  printf '## Identity\nc\n\n## How to use your knowledge\nc\n\n## Memory\nc\n\n## Operating rules\nUse \x60w_ghost_tool\x60 here.\n' > "$tmp"
  result="$(run_py "
import contract
from pathlib import Path
print(contract._check_agents_md(Path('$tmp'), [{'name': 'w_real_tool'}]))
")"
  [[ "$result" == *"mentions \`w_ghost_tool\`"* ]]
}
