#!/usr/bin/env bats
# qt.bats — the QPalette colour scheme written by the `qt` axis (400-qt).
#
# qt5ct and qt6ct read `active_colors` POSITIONALLY: entry i becomes QPalette
# role i. The list's LENGTH and ORDER are therefore the mapping itself, and one
# extra entry shifts every role after it — which is exactly what shipped once
# (a leftover debug entry after Base put an invalid colour in Window and black
# in Highlight). No other suite could see it: the file stayed syntactically
# valid, the values were all real theme colours, and Kvantum — W's default
# engine — paints from its own SVG and hid the damage.
#
# So this suite gates the shape of the palette rather than its colours: one
# entry per role, every entry a parseable opaque colour, and the role names in
# the module's own comments still in QPalette::ColorRole order.

load helpers

MODULE="$REPO/rootfs/usr/lib/w/w-style/modules/400-qt/module.sh"

# QPalette::ColorRole in enum order. Qt5 and Qt6 agree up to PlaceholderText;
# Qt 6.6 appends Accent, which the module deliberately does not emit (unset, Qt
# derives it from Highlight — see the module's header).
ROLES="WindowText Button Light Midlight Dark Mid Text BrightText ButtonText Base
       Window Shadow Highlight HighlightedText Link LinkVisited AlternateBase
       NoRole ToolTipBase ToolTipText PlaceholderText"

setup() {
  # The module reads its colours from $W_* in THIS shell, so an inherited token
  # (a live W session exports the active theme) would silently stand in for one
  # the fixture no longer defines — a dropped token has to surface as an empty
  # entry, which is the failure the suite exists to catch.
  local v
  while IFS= read -r v; do unset "$v"; done < <(compgen -v | grep '^W_' || true)
  source "$REPO/rootfs/usr/lib/w/w-style/lib/core.sh"
  set -a; source "$FIXTURES/theme/theme.conf"; set +a
  source "$MODULE"
}

@test "qt: the palette carries exactly one entry per QPalette role" {
  local want set n
  want="$(echo $ROLES | wc -w | tr -d ' ')"
  for set in 0 1; do
    n="$(qt5ct_palette "$set" | tr ',' '\n' | wc -l | tr -d ' ')"
    [ "$n" -eq "$want" ]
  done
}

@test "qt: every palette entry is an opaque #ffrrggbb colour" {
  local set entry rc=0
  for set in 0 1; do
    while IFS= read -r entry; do
      [[ "$entry" =~ ^#[fF]{2}[0-9a-fA-F]{6}$ ]] || { echo "set $set: bad entry '$entry'"; rc=1; }
    done < <(qt5ct_palette "$set" | tr ',' '\n' | tr -d ' ')
  done
  [ "$rc" -eq 0 ]
}

@test "qt: the roles array names the Qt roles in enum order" {
  local got
  got="$(sed -n '/^  local roles=(/,/^  )$/p' "$MODULE" \
         | sed -n 's/.*#[[:space:]]*\([A-Za-z]\{1,\}\)[[:space:]]*$/\1/p')"
  [ "$(echo $got)" = "$(echo $ROLES)" ]
}
