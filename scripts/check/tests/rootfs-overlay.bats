#!/usr/bin/env bats
# rootfs-overlay.bats — what apply_rootfs must NOT copy over an installed machine.
#
# apply.sh cannot be sourced (it dispatches at the bottom), so the function under
# test is lifted out of it, as in snapshots.bats.

load helpers

lift() { eval "$(sed -n "/^$1()/,/^}/p" "$2")"; }

setup() {
  lift override_excludes "$REPO/scripts/apply.sh"
  SRC="$BATS_TEST_TMPDIR/src"
  local d="$SRC/rootfs/usr/share/w/update" t="$BATS_TEST_TMPDIR/t"
  mkdir -p "$d" "$t"
  : > "$t/admin.conf"; : > "$t/colors.json"; : > "$t/managed.conf"
  printf '%s\t%s\n' \
    "$t/admin.conf" override  "$t/gone.conf" override \
    "$t/colors.json" rendered "$t/absent.json" rendered \
    "$t/managed.conf" managed > "$d/x.manifest"
  T="$t"
}

@test "override_excludes: existing override AND rendered paths are spared, absent ones seeded" {
  run override_excludes
  [ "$status" -eq 0 ]
  [ "$output" = "--exclude=$T/admin.conf
--exclude=$T/colors.json" ]
}

# The regression this class exists for: a --rootfs-only update reverted the greeter
# and splash of a non-`w` system theme to the `w`-coloured seeds. Any file a
# system-scope w-style axis writes that rootfs also ships must be declared.
@test "every shipped greeter/Plymouth render output is declared class 'rendered'" {
  local mdir="$REPO/rootfs/usr/share/w/update" f n=0 missing=()
  for f in $(sed -n 's|.*cat > "\$GREETER_QS_CORE/\([a-z]*\.json\)".*|/etc/greetd/quickshell/w/core/\1|p' \
               "$REPO/rootfs/usr/lib/w/w-style/modules/900-greeter/module.sh") \
           $(grep -o '"\$PLYMOUTH_DIR/[a-z-]*\.png"' \
               "$REPO/rootfs/usr/lib/w/w-style/modules/900-plymouth/module.sh" \
             | sed 's|"\$PLYMOUTH_DIR/\(.*\)"|/usr/share/plymouth/themes/w/\1|'); do
    [[ -e "$REPO/rootfs$f" ]] || continue          # not shipped → nothing to clobber
    n=$((n + 1))
    grep -qxF "$f"$'\trendered' "$mdir"/*.manifest || missing+=("$f")
  done
  [ "$n" -ge 10 ]                                  # the scrape still finds the outputs
  [ "${#missing[@]}" -eq 0 ] || { printf 'undeclared: %s\n' "${missing[@]}"; false; }
}
