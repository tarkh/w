# check/publish.sh — the public tree may only lose what an installed machine
# does not need.
#
# W publishes to GitHub as a filtered snapshot of the dev tree: the public tree is
# the dev tree minus scripts/publish.exclude (see that file's header for why the
# filter is subtractive-only). The danger is asymmetric and one-directional:
#
#   * excluding one path too FEW  → a dev-only file leaks. Embarrassing, visible,
#     fixable in the next release.
#   * excluding one path too MANY → every public machine silently runs an
#     incomplete W. `apply.sh` rsyncs whole trees, so a missing file does not
#     error: it just never arrives, and w-sync reports a clean update.
#
# The second failure has no symptom, so it gets a mechanical gate rather than a
# review habit.
#
# The invariant: every file the filter removes must route to --skip in
# rootfs/usr/share/w/update/sync-map. That map is the updater's own answer to
# "which apply.sh modules does this path affect", and --skip is its word for
# "none". Reusing it means the gate is not a second, drifting opinion about what
# ships — it is the same one w-sync acts on. Anything else (a wrong flag, or the
# --all catch-all that swallows unlisted paths) fails here.
#
# Corollary the gate enforces for free: content under a shipping tree (rootfs/,
# scripts/packs/, packages/) can never be excluded, because those trees are never
# --skip. Content that should not reach users has to be deleted from the dev tree,
# not hidden at publish time.
#
# Dev-only suite. The public tree has no exclude list — the suite skips there
# rather than failing, which is why scripts/check/publish.sh itself is published
# (check.sh's SUITES table would otherwise call an undefined function).

EXCLUDE_FILE="scripts/publish.exclude"

# Read the exclude list into git pathspecs. Echoes one pathspec per line.
_publish_pathspecs() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && printf ':(exclude)%s\n' "$line"
  done < "$EXCLUDE_FILE"
}

chk_publish() {
  if [[ ! -f "$EXCLUDE_FILE" ]]; then
    echo "  no $EXCLUDE_FILE — not a publishing checkout, skipping"
    return 0
  fi

  local rc=0 patterns=() published=() all=() removed=() f flag

  mapfile -t patterns < <(_publish_pathspecs)
  if (( ${#patterns[@]} == 0 )); then
    echo "  $EXCLUDE_FILE lists nothing — the public tree would be the dev tree"
    return 1
  fi

  mapfile -t all       < <(git ls-files)
  mapfile -t published < <(git ls-files -- . "${patterns[@]}")

  # What the filter removes = tracked minus published. comm needs sorted input and
  # compares using the CURRENT locale, so both the sort and comm itself are pinned
  # to C — sorting in one collation and comparing in another silently produces
  # nonsense output instead of an error.
  mapfile -t removed < <(LC_ALL=C comm -23 \
    <(printf '%s\n' "${all[@]}" | LC_ALL=C sort) \
    <(printf '%s\n' "${published[@]}" | LC_ALL=C sort))

  if (( ${#removed[@]} == 0 )); then
    echo "  $EXCLUDE_FILE matches no tracked file — every rule is dead"
    return 1
  fi

  # 1. Nothing removed may be anything other than --skip. _route() comes from
  #    check/routing.sh and mirrors w-sync's map_file() exactly.
  local bad=0
  for f in "${removed[@]}"; do
    flag="$(_route "$f")"
    if [[ "$flag" != "--skip" ]]; then
      echo "  SHIPPED but excluded: $f → sync-map says $flag"
      bad=$((bad + 1)); rc=1
    fi
  done
  if (( bad )); then
    echo "  → $bad file(s) would be missing from a public machine with no error."
    echo "    Either drop the rule from $EXCLUDE_FILE, or — if the file truly does"
    echo "    not belong on a target — give it a --skip rule in the sync-map."
  fi

  # 2. Every rule must actually match something. A rule left behind after the path
  #    it named was renamed is invisible rot: it protects nothing and reads as if
  #    it does.
  local pat p dead=0
  while IFS= read -r p; do
    pat="${p#:(exclude)}"
    if [[ -z "$(git ls-files -- "$pat")" ]]; then
      echo "  dead rule (matches no tracked file): $pat"
      dead=$((dead + 1)); rc=1
    fi
  done < <(printf '%s\n' "${patterns[@]}")
  (( dead )) && echo "  → remove the stale rule(s) from $EXCLUDE_FILE."

  # 3. The gate itself must stay published, or the public check.sh calls an
  #    undefined chk_publish.
  if ! printf '%s\n' "${published[@]}" | grep -qx "scripts/check/publish.sh"; then
    echo "  scripts/check/publish.sh is excluded — the public check.sh would break"
    echo "  (check.sh sources every suite and SUITES lists 'publish')."
    rc=1
  fi

  echo "  publish: ${#published[@]} public / ${#all[@]} tracked, ${#removed[@]} withheld, all --skip"
  return $rc
}
