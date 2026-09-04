# check/unit.sh — bats-core unit tests for pure bash functions.
#
# Tests live in scripts/check/tests/*.bats with fixtures/ (frozen inputs) and
# golden/ (expected render output) beside them. GNU-only code paths
# (install -D, sed -i) skip themselves on Darwin — CI on Arch runs everything.
# Golden files regenerate ONLY on a deliberate render-logic change: run the
# render into a tmp HOME (see golden.bats setup) and copy the outputs over.

chk_unit() {
  if ! command -v bats &>/dev/null; then
    warn "bats not installed (pacman -S bats / brew install bats-core)"
    return 0
  fi
  [[ ${STRICT:-0} -eq 1 ]] || { bats "$SRC/scripts/check/tests"; return; }

  # --strict (the container): a case that skips ITSELF for a missing tool is
  # invisible to the suite-level SKIPPED flag — bats exits 0 and the run looks
  # complete. Read it back out of the output instead. Only "not installed" is
  # fatal: the other skips here are statements about the tree, not the machine
  # (a public checkout has no publish.sh; Darwin has no GNU install -D).
  local log rc=0 holes
  log="$(mktemp)"
  bats "$SRC/scripts/check/tests" | tee "$log" || rc=$?
  holes="$(grep -E '(# skip|skipped:).*not installed' "$log" || true)"
  rm -f "$log"
  if [[ -n "$holes" ]]; then
    echo "  --strict: cases skipped for a missing tool — CI must install it:"
    sed 's/^/    /' <<< "$holes"
    rc=1
  fi
  return "$rc"
}
