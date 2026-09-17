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

# A compositor that is installed but not running — which is what "no live session"
# actually looks like on a machine where W is developed, and what several tests
# meant all along without saying so. They used to get it for free by NOT putting a
# `hyprctl` stub on PATH, which reads as "no compositor" only where Hyprland is
# not installed: CI containers, and a development box that is not itself running
# W. On this project's own machine /usr/bin/hyprctl is real, answers with real
# monitors, and four monitor tests plus one bar test failed for the environment's
# reason rather than the code's.
#
# Shadowing with a stub that fails makes the intent explicit and matches both
# consumers' own definition of liveness: w-monitor's have_hypr() is
# `command -v hyprctl && hyprctl version`, and w-bar takes an empty
# `hyprctl monitors all -j` the same way it takes an absent binary. PATH is only
# prepended to, so jq and the rest of the suite's tools stay reachable — stripping
# PATH down to nothing would take those with it.
hyprctl_offline() {
  mkdir -p "$BATS_TEST_TMPDIR/nobin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/nobin/hyprctl"
  chmod 755 "$BATS_TEST_TMPDIR/nobin/hyprctl"
  PATH="$BATS_TEST_TMPDIR/nobin:$PATH"
  export PATH
}
