#!/usr/bin/env bats
# ai-protocol.bats — a real w-mcp spoken to over stdio JSON-RPC, as a host does
# (mcp-wire.py): initialize → tools/list → resources/list → prompts/list →
# tools/call, then concurrent tools/call and a crashing tool. contract.py and
# `--selftest` never touch the wire; this suite is what notices an SDK major that
# moves it. Needs python-mcp (ci/check-packages.txt) — absent, it SKIPs and
# --strict turns the skip red.
#
# Sandboxed: state, HOME and every w-conf layer point into BATS_FILE_TMPDIR, so
# the profile is the default `full` and nothing outside the temp dir is written.
# setup_file runs the driver once; the cases read its cached output.

load helpers

has_mcp() { python3 -c 'import mcp.server.mcpserver' &>/dev/null; }

setup_file() {
  has_mcp || return 0
  local t="$BATS_FILE_TMPDIR" rc=0
  mkdir -p "$t/home" "$t/state" "$t/etc" "$t/vendor"
  W_MCP_EXPECT_VERSION="$(sed -n 's/^IMAGE_VERSION=//p' "$REPO/rootfs/etc/os-release" | tr -d '"')" \
  W_OS_RELEASE="$REPO/rootfs/etc/os-release" \
  W_MCP_LIB="$REPO/rootfs/usr/lib/w/w-mcp" \
  W_AI_SYS_ROOT="$REPO/rootfs/usr/share/w/ai" \
  W_AI_STATE_ROOT="$t/state" HOME="$t/home" XDG_CONFIG_HOME="$t/home/.config" \
  WCONF_ETC="$t/etc" WCONF_VENDOR_DIR="$t/vendor" W_AI_SKILLS_NATIVE='' \
    python3 "$BATS_TEST_DIRNAME/mcp-wire.py" "$REPO/rootfs/usr/bin/w-mcp" > "$t/wire.txt" 2>&1 || rc=$?
  echo "$rc" > "$t/wire-rc.txt"
}

setup() {
  has_mcp || skip "python-mcp not installed"
  OUT="$(cat "$BATS_FILE_TMPDIR/wire.txt")"
}

@test "wire: the whole stdio session passes" {
  [[ "$(cat "$BATS_FILE_TMPDIR/wire-rc.txt")" -eq 0 ]] || { echo "$OUT"; false; }
}

@test "wire: initialize reports w-mcp with the W release as its version" {
  [[ "$OUT" == *"ok initialize (w-mcp $(sed -n 's/^IMAGE_VERSION=//p' "$REPO/rootfs/etc/os-release" | tr -d '"'),"* ]] || { echo "$OUT"; false; }
}

@test "wire: tools/list carries no outputSchema and no pydantic titles" {
  [[ "$OUT" == *"no outputSchema, no schema titles"* ]] || { echo "$OUT"; false; }
}

@test "wire: resources/list and prompts/list answer" {
  [[ "$OUT" == *"ok resources/list"* && "$OUT" == *"ok prompts/list (5 prompts)"* ]] || { echo "$OUT"; false; }
}

@test "wire: tools/call of a read-only tool succeeds" {
  [[ "$OUT" == *"ok tools/call w_time_status"* && "$OUT" == *"ok tools/call w_machine_profile"* ]] || { echo "$OUT"; false; }
}

@test "wire: concurrent tools/call on one store lose nothing" {
  [[ "$OUT" == *"ok parallel tools/call"* ]] || { echo "$OUT"; false; }
}

@test "wire: a crashing tool reaches the model with its cause" {
  [[ "$OUT" == *"ok tool error (Error executing tool w_task_add: NotADirectoryError"* ]] || { echo "$OUT"; false; }
}
