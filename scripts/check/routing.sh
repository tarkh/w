# check/routing.sh — sync-map routing vs what actually ships.
#
# `w-sync` decides which apply.sh modules to run after a pull by routing every
# changed path through rootfs/usr/share/w/update/sync-map (first match wins).
# A path routed to --skip is deployed by nothing — which is correct for docs and
# dev-only trees, and silently wrong for anything that ships.
#
# That failure mode has bitten twice, both times invisibly: the updater could not
# deliver a fix to itself (2026-08-01), and the `*.md --skip` rule swallowed the
# AI knowledge layer, which is Markdown but is payload (2026-08-03) — `llms.txt`
# and `AGENTS.md` sit in the same directory and had opposite fates purely because
# of the extension. Neither produced an error: w-sync just reported "no target
# modules affected" while the machine drifted from the repo.
#
# The invariant, checked here: everything under a tree that apply.sh rsyncs
# wholesale MUST route to something. The rule is about the tree, not the file
# type, so a new file of any kind cannot reintroduce the bug.

# Trees that are copied to the target verbatim, by the module named alongside:
#   rootfs/       → apply_rootfs (rsync of the whole tree)
#   scripts/packs/→ mod_packs    (rsync into /usr/share/w/packs)
#   packages/     → mod_packages (read by the installer)
SHIPPED_TREES=(rootfs scripts/packs packages)

# Resolve one path through the map, mirroring w-sync's map_file(): first match
# wins, the glob is matched unquoted so a single `*` spans '/', unmatched → --all.
_route() {
  local path="$1" glob flag
  while IFS=$'\t' read -r glob flag || [[ -n "$glob" ]]; do
    [[ -z "$glob" || "$glob" == \#* ]] && continue
    flag="${flag//[[:space:]]/}"
    # shellcheck disable=SC2053  # intentional glob match, not a literal compare
    [[ "$path" == $glob ]] && { echo "$flag"; return; }
  done < rootfs/usr/share/w/update/sync-map
  echo "--all"
}

chk_routing() {
  local rc=0 f flag n=0 skipped=0
  local map=rootfs/usr/share/w/update/sync-map
  [[ -f "$map" ]] || { echo "  sync-map not found: $map"; return 1; }

  while IFS= read -r f; do
    n=$((n + 1))
    flag="$(_route "$f")"
    if [[ "$flag" == "--skip" ]]; then
      echo "  ships but routes to --skip: $f"
      skipped=$((skipped + 1)); rc=1
    fi
  done < <(git ls-files "${SHIPPED_TREES[@]}")

  if [[ "$rc" -ne 0 ]]; then
    echo "  → $skipped shipped file(s) would never reach an edge target."
    echo "    Add a rule ABOVE the skip block in $map (first match wins)."
  fi
  echo "  routing: $n shipped files, $skipped unroutable"
  return $rc
}
