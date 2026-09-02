# check/paths.sh — W lives in the distribution's paths, not the admin's.
#
# Until P9 every W script shipped to /usr/local/bin and every helper to
# /usr/local/lib/w. /usr/local belongs to the local administrator: a distribution
# writing there contradicts the FHS and the plain expectation that pacman never
# touches that tree. Commands now ship to /usr/bin and non-command helpers to
# /usr/lib/w.
#
# That move buys a new hazard in exchange, and this suite is the price:
#
#   * /usr/bin is a SHARED namespace. Nothing stops a repo package from shipping
#     a file at a path W also writes; apply_rootfs is rsync, so it would simply
#     overwrite it — or be overwritten by the next `pacman -Syu` — with no error
#     from either side. Rule 3 asks pacman's own file database.
#
#   * /usr/local/bin precedes /usr/bin in the default PATH. A single leftover or
#     re-introduced W script under /usr/local therefore SHADOWS the shipped one,
#     permanently and silently. Rules 1 and 2 keep the tree from drifting back.
#
# Deliberately NOT flagged — these belong in /usr/local and depend on it:
#   * the sudo → sudo-rs shim (modules/sudo.sh) and the `zed` link (packs/dev):
#     both exist precisely BECAUSE /usr/local/bin wins the PATH race;
#   * goose (installed by its upstream installer, root scope);
#   * devtools/ — dev-VM tooling, which is what /usr/local is for;
#   * the mkinitcpio shim limine-mkinitcpio-hook ships, referenced in prose.

# Executables under rootfs/usr/lib/w must each be named in profiledef's
# file_permissions. Unlike usr/bin (declared as a whole directory) the tree mixes
# executables with sourced libraries and Python modules, so it cannot be covered
# by one recursive entry without shipping libraries 755 from an ISO install and
# 644 from a repo apply. mkarchiso discards every mode bit on the way into the
# image, so a missing entry means a 644 script and a failure that only shows up
# on a real firstboot — the exact way this bit us twice before.
_paths_profiledef_perms() {
  sed -n 's/^  \["\/root\/w\/\([^"]*\)"\]=.*/\1/p' archiso/profile/profiledef.sh
}

# Bare names of the executables under rootfs/usr/lib/w — what rule 5 hunts for.
_paths_helper_names() {
  git ls-files -s 'rootfs/usr/lib/w/*' \
    | awk '$1=="100755"{n=split($4,p,"/"); print p[n]}'
}

chk_paths() {
  local rc=0 f p owner

  # 1. Nothing of ours under rootfs/usr/local at all.
  local -a stray=()
  mapfile -t stray < <(git ls-files 'rootfs/usr/local/*')
  if (( ${#stray[@]} )); then
    printf '  ships to /usr/local (belongs to the admin, and shadows /usr/bin): %s\n' "${stray[@]}"
    rc=1
  fi

  # 2. No shipped file may point back at the old locations. Scoped to the trees
  #    that reach a machine — a comment in devtools or a dev-only script naming
  #    its own /usr/local path is not a regression.
  #    This file is exempt: a rule has to be able to name what it forbids, and the
  #    header above explains the migration in the very terms it bans. Same reason
  #    check/publish.sh is never excluded from its own exclude list. The exemption
  #    only showed up once this suite was committed — `git grep` reads tracked
  #    files, so while it was still untracked the rule could not see itself.
  local -a back=()
  mapfile -t back < <(
    git grep -InE '/usr/local/(bin/w-|lib/w)' -- rootfs scripts packages archiso/profile/profiledef.sh \
      | grep -v 'devtools/usr/local' \
      | grep -v '^scripts/check/paths\.sh:' || true)
  if (( ${#back[@]} )); then
    printf '  refers to the pre-P9 location: %s\n' "${back[@]}"
    echo "  → commands live in /usr/bin, helpers in /usr/lib/w."
    rc=1
  fi

  # 3. Collision with a package-owned path. pacman's files database answers who
  #    owns a path in the enabled repos; anything it names is a path W and pacman
  #    would take turns overwriting, with neither reporting a thing.
  #
  #    Every path goes in ONE `pacman -F` call. Asking per path is the obvious
  #    shape and costs ~1.1s EACH — two minutes for this tree, which is how a
  #    suite stops being run. Batched it is ~1.1s total, because the cost is
  #    opening the database, not the lookup. Non-quiet on purpose: `-Fq` prints
  #    only package names, and the line this needs to report is which of OUR
  #    paths collided. Unowned paths make pacman exit non-zero and write to
  #    stderr — that is the expected case here, not an error.
  #
  #    The database is a local cache that may be absent on a contributor's
  #    machine and cannot be refreshed without network, so a missing one skips
  #    with a note: a gate nobody can run offline is a gate people learn to
  #    bypass. AUR has no files database and is not covered — which is why
  #    vendored third-party scripts go to /usr/lib/w regardless of what this says.
  local -a shipped=()
  mapfile -t shipped < <(git ls-files 'rootfs/usr/bin/*' 'rootfs/usr/lib/w/*' | sed 's|^rootfs/||')
  if ! command -v pacman >/dev/null 2>&1; then
    echo "  pacman absent — skipping the package-collision probe"
  elif ! compgen -G '/var/lib/pacman/sync/*.files' >/dev/null; then
    echo "  no pacman files database (run: pacman -Fy) — skipping the collision probe"
  elif (( ${#shipped[@]} == 0 )); then
    echo "  nothing shipped under /usr/bin or /usr/lib/w"
  else
    local -a owned=()
    mapfile -t owned < <(pacman -F "${shipped[@]}" 2>/dev/null | grep ' is owned by ' || true)
    if (( ${#owned[@]} )); then
      printf '  /%s — W would silently fight it on every upgrade\n' "${owned[@]}"
      rc=1
    else
      echo "  paths: ${#shipped[@]} shipped path(s) under /usr/bin + /usr/lib/w, none package-owned"
    fi
  fi

  # 4. Every executable under rootfs/usr/lib/w is declared in profiledef.
  local -a declared=()
  mapfile -t declared < <(_paths_profiledef_perms)
  local -a missing=() mode
  declare -A GIT_MODE=()
  while read -r mode _ _ f; do GIT_MODE[$f]=$mode; done \
    < <(git ls-files -s 'rootfs/usr/lib/w/*')
  for f in "${!GIT_MODE[@]}"; do
    [[ "${GIT_MODE[$f]}" == "100755" ]] || continue
    printf '%s\n' "${declared[@]}" | grep -qxF "$f" || missing+=("$f")
  done
  if (( ${#missing[@]} )); then
    printf '  executable but not in profiledef file_permissions: %s\n' "${missing[@]}"
    echo "  → mkarchiso strips every mode bit; it would ship 644 and fail at firstboot."
    rc=1
  fi

  # 5. /usr/lib/w is NOT in PATH, so a helper there may only be reached by its
  #    absolute path. Before P9 the helpers lived in /usr/local/bin — which is in
  #    PATH — so a bare name resolved, and code written then reads as correct
  #    today while resolving to nothing. That is how the Papirus folder retint
  #    died silently for two weeks: `command -v papirus-folders` simply stopped
  #    finding it, and a missing helper is a deliberate skip, not an error. Rule 4
  #    guards how a helper is SHIPPED; this guards how it is CALLED.
  #
  #    Scoped to code that actually executes (shell/python/lua/qml and anything
  #    shipped 755): a policy file's prose or a unit's Description names helpers
  #    too, and neither runs them. Comments are stripped for the same reason — the
  #    tree explains these helpers far more often than it calls them, and a rule
  #    that cries at prose is a rule people stop reading.
  #
  #    Two shapes are flagged, and only those, because only those reach an exec:
  #    a bare literal assigned to a variable (`FOO=helper`, how the retint broke),
  #    and a bare name in command position — start of a command, after a pipeline
  #    or list separator, inside a substitution, or behind exec/command -v/pkexec/
  #    sudo. A name carrying its directory never matches.
  local -a hnames=()
  mapfile -t hnames < <(_paths_helper_names)
  if (( ${#hnames[@]} )); then
    local alt assign run text lno
    alt="$(IFS='|'; echo "${hnames[*]}")"; alt="${alt//./\\.}"
    assign="^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[\"']?($alt)[\"']?[[:space:]]*$"
    run="(^[[:space:]]*|[;&|][[:space:]]*|\\\$\([[:space:]]*|\`[[:space:]]*"
    run+="|\bexec[[:space:]]+|\bcommand -v[[:space:]]+|\bpkexec[[:space:]]+"
    run+="|\bsudo[[:space:]]+)[\"']?($alt)\b"

    declare -A EXECBIT=()
    while read -r mode _ _ f; do
      [[ "$mode" == 100755 ]] && EXECBIT[$f]=1
    done < <(git ls-files -s -- rootfs scripts)

    local -a bare=()
    while IFS= read -r line; do
      f="${line%%:*}"; line="${line#*:}"; lno="${line%%:*}"; text="${line#*:}"
      case "$f" in
        *.sh|*.bash|*.py|*.lua|*.qml) ;;
        *) [[ -n "${EXECBIT[$f]:-}" ]] || continue ;;
      esac
      case "$f" in *.qml|*.js|*.lua) text="${text%%//*}" ;; esac
      text="$(printf '%s' "$text" | sed -E 's/(^|[[:space:]])#.*$//')"
      [[ -n "${text// /}" ]] || continue
      printf '%s' "$text" | grep -qE "$assign" \
        || printf '%s' "$text" | grep -qE "$run" || continue
      bare+=("$f:$lno:$text")
    done < <(git grep -InE "($alt)" -- rootfs scripts | grep -vE "/usr/lib/w/($alt)")

    if (( ${#bare[@]} )); then
      printf '  calls a /usr/lib/w helper by bare name: %s\n' "${bare[@]}"
      echo "  → /usr/lib/w is not in PATH; call it as /usr/lib/w/<helper>."
      rc=1
    else
      echo "  paths: ${#hnames[@]} helper(s) in /usr/lib/w, all called by absolute path"
    fi
  fi

  # 6. RECOVERY.md exists twice on purpose and must stay one document. The copy at
  #    the repo root is what a user finds on GitHub next to README/SECURITY; the copy
  #    under rootfs/ is the one on the machine, which is where it is actually needed,
  #    since a machine that will not boot has no browser. Two files, one text: a
  #    silent divergence would ship a recovery procedure nobody verified.
  local doc_root="RECOVERY.md" doc_box="rootfs/usr/share/doc/w/RECOVERY.md"
  if [[ ! -f "$doc_root" || ! -f "$doc_box" ]]; then
    echo "  missing recovery doc: both $doc_root and $doc_box must exist"
    rc=1
  elif ! cmp -s "$doc_root" "$doc_box"; then
    echo "  $doc_root and $doc_box have diverged"
    echo "  → they are one document; copy the edited one over the other."
    rc=1
  else
    echo "  paths: RECOVERY.md identical at repo root and on-box"
  fi

  return $rc
}
