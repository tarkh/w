# helpers.bash — shared paths for the unit tests (bats `load helpers`).
#
# fixtures/ holds FROZEN inputs (a snapshot of the `w` theme + skel starship.toml)
# so the golden files test the RENDERER, not the live theme — editing the real
# theme must not break these tests. golden/ holds the expected render output;
# regenerate it only on a deliberate render-logic change (see unit.sh header).

REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"
GOLDEN="$BATS_TEST_DIRNAME/golden"
