# helpers.bash — shared paths for the unit tests (bats `load helpers`).
#
# fixtures/ holds FROZEN inputs (a snapshot of the `w` theme + skel starship.toml)
# so the golden files test the RENDERER, not the live theme — editing the real
# theme must not break these tests. golden/ holds the expected render output;
# regenerate it only on a deliberate render-logic change (see unit.sh header).

REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"
GOLDEN="$BATS_TEST_DIRNAME/golden"

# Every w-* CLI sources the i18n library for its localized help. Point that seam
# at the checkout here rather than in each suite's setup(): the tests source
# these scripts on machines with no W installed, and a suite that forgets would
# fail on the `source` line, nowhere near what it was testing.
W_I18N_LIB="$REPO/rootfs/usr/lib/w/w-i18n-lib.sh"
export W_I18N_LIB
# …and at NO catalog, so a test asserting English help does not start passing or
# failing because the machine running it happens to be Russian.
W_I18N_DIR="$BATS_TEST_DIRNAME/fixtures/absent-i18n"
export W_I18N_DIR
