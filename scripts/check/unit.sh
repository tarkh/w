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
  bats "$SRC/scripts/check/tests"
}
