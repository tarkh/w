# check/landmines.sh — project-specific booby traps, encoded from the library.
#
# Each rule here is a gotcha that already cost a VM debugging session (see
# dev-workflow.md / installer.md). Static greps can't catch everything (the
# set-e pipefail class needs eyes), but these two are mechanical:
#
#   1. Every deploy rsync must carry --chown: rsync from the virtiofs share
#      preserves the host's uid, silently leaving root-owned trees on the
#      target (essentials rule "rsync --chown во всех модулях").
#   2. mkarchiso copies airootfs with --no-preserve=mode: an executable in git
#      ships 644 unless declared in profiledef.sh file_permissions — the ONLY
#      channel mkarchiso honors (bit us twice: install.sh, then every w-*).
#      Two sources feed the image: files already committed under
#      archiso/profile/airootfs/, and scripts/+packages/+rootfs/ which
#      build-iso.sh rsyncs into airootfs/root/w/ at build time — the latter
#      never shows up under git ls-files archiso/profile/airootfs/, so it
#      needs its own mapping or this rule misses it (bit us a third time:
#      rootfs/usr/lib/w/w-pacnew-reconcile shipped 644, silently
#      broke its pacman hook — 5 siblings in the same blind spot).

chk_landmines() {
  local rc=0 f hits

  # 1. rsync --chown in everything that deploys onto the target as root.
  #    The bundle glob is every *.sh in the bundle, not setup*.sh: the layer split
  #    added setup-user.sh and phase 7 added the teardown pair, and each narrowing
  #    of this glob has had to be widened again afterwards. A bundle script is a
  #    bundle script — the rule applies to all of them.
  for f in scripts/apply.sh scripts/install/lib/deploy.sh \
           scripts/install/modules/*.sh scripts/packs/*/*.sh; do
    [[ -f "$f" ]] || continue
    # Join backslash-continued lines so multi-line rsync invocations are one
    # record, strip comments, then flag rsync calls without --chown.
    hits="$(awk '/\\$/ { sub(/\\$/, ""); buf = buf $0; next }
                 { print buf $0; buf = "" }' "$f" \
            | grep -vE '^[[:space:]]*#' \
            | grep -E '(^|[[:space:];({&])rsync[[:space:]]' \
            | grep -v -- '--chown' || true)"
    [[ -z "$hits" ]] || { echo "  $f: rsync without --chown:"; echo "$hits" | sed 's/^/    /'; rc=1; }
  done

  # 2. Executables that ship into the ISO must be re-declared in profiledef.sh
  #    (exact entry, or covered by a recursive "dir/" entry).
  local prof="archiso/profile/profiledef.sh" mode hash stage path rel key covered
  local -a exec_keys=() dir_keys=() candidates=()
  while IFS= read -r key; do
    if [[ "$key" == */ ]]; then dir_keys+=("$key"); else exec_keys+=("$key"); fi
  done < <(grep -oE '\["[^"]+"\]="0:0:[0-7]*[157][0-7]*"' "$prof" | sed -E 's/^\["([^"]+)"\].*/\1/')

  # Already-baked airootfs files: git path IS the ISO path (minus the prefix).
  while read -r mode hash stage path; do
    [[ "$mode" == 100755 ]] || continue
    candidates+=("/${path#archiso/profile/airootfs/}")
  done < <(git ls-files -s archiso/profile/airootfs/)

  # Dynamically staged trees: build-iso.sh rsyncs these into airootfs/root/w/.
  while read -r mode hash stage path; do
    [[ "$mode" == 100755 ]] || continue
    candidates+=("/root/w/$path")
  done < <(git ls-files -s scripts/ packages/ rootfs/)

  for rel in "${candidates[@]}"; do
    covered=""
    for key in "${exec_keys[@]}"; do [[ "$rel" == "$key" ]] && covered=1; done
    for key in "${dir_keys[@]}";  do [[ "$rel" == "$key"* ]] && covered=1; done
    [[ -n "$covered" ]] || { echo "  $prof: no file_permissions entry for executable $rel"; rc=1; }
  done

  # 3. Every package transaction goes through the w_pac seam (installer.md §5).
  #    A bare `pacman -S…` under `set -e` dies on the first stalled mirror and takes
  #    the whole phase with it — which is how one bad host killed three release-gate
  #    runs in a row, each time in a different module. The seam retries, but only
  #    after changing the mirrorlist and only for failures whose SIGNATURE says
  #    transport. This is a rule and not a convention for the same reason `routing`
  #    is one: enforcement in a single point, because the next module added would
  #    otherwise regress silently. `-U` (local package files) is out of scope: no
  #    mirror is involved, so there is nothing to retry against.
  #    Since Ф.3 the seam ships to the machine (rootfs/usr/lib/w/w-pac-lib.sh),
  #    so the runtime scripts that install packages on an installed system are in
  #    scope too — they were the last three bare call sites in the tree. Their trees
  #    are matched WHOLE rather than by a hand-kept file list, for the same reason
  #    check/routing.sh matches trees: a list is a registry to forget.
  local -a pac_files=(scripts/apply.sh scripts/install/modules/*.sh)
  while IFS= read -r f; do pac_files+=("$f"); done < <(
    git ls-files 'rootfs/usr/bin/*' 'rootfs/usr/lib/w/*.sh' \
      | grep -v '/w-pac-lib\.sh$')
  #    The command-position anchors are narrower here than "any whitespace": half
  #    the W tools carry a `(pacman -S <pkg>)` hint inside an error string, and a
  #    rule that flags prose teaches people to ignore it.
  #    The read-only SYNC QUERIES are out of scope for the same reason `-U` is:
  #    -Si/-Ss/-Sg/-Sl/-Sp answer from the local sync db, start no transaction and
  #    touch no mirror, so there is nothing for the seam to retry or demote.
  #    w-langpack probes its whole package catalogue with `pacman -Si`.
  for f in "${pac_files[@]}"; do
    [[ -f "$f" ]] || continue
    hits="$(awk '/\\$/ { sub(/\\$/, ""); buf = buf $0; next }
                 { print FNR ": " buf $0; buf = "" }' "$f" \
            | grep -vE '^[0-9]+: [[:space:]]*#' \
            | grep -E '(^[0-9]+:[[:space:]]*|[;&|]+[[:space:]]*|=\()pacman[[:space:]]+-S([^isglp]|$)' || true)"
    [[ -z "$hits" ]] || { echo "  $f: bare pacman -S (use the w_pac seam):"; echo "$hits" | sed 's/^/    /'; rc=1; }
  done

  #    Ф.4 closed the one transaction that was outside the seam for a different
  #    reason: `pacstrap` takes none of pacman's arguments, so w_pac cannot front it
  #    and it needs the generic w_run_retry instead. It is also the step with the
  #    least room for error (keyring init and the first transaction in one), and two
  #    of the three observed release-gate failures were in it — so the rule matters
  #    more here than for any single module, not less.
  #    Unlike `pacman -S` above, this one canNOT anchor on command position: the
  #    real call is wrapped (`progress_pacman "<title>" pacstrap -K …`), so pacstrap
  #    sits mid-line as an argument — which is exactly the shape the pre-Ф.4 code
  #    had, and an anchored rule waved it straight through when it was reinstated to
  #    test this. Instead: strip comments, then strip quoted spans (the module also
  #    prints the word "pacstrap" inside an echo, and a rule that flags its own log
  #    messages is one people learn to ignore), then any surviving mention is a real
  #    invocation.
  for f in scripts/install.sh scripts/install/modules/*.sh; do
    [[ -f "$f" ]] || continue
    hits="$(awk '/\\$/ { sub(/\\$/, ""); buf = buf $0; next }
                 { line = buf $0; buf = ""
                   printf "%d: %s\n", FNR, line }' "$f" \
            | grep -vE '^[0-9]+: [[:space:]]*#' \
            | sed -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g" \
            | grep -E '(^|[^[:alnum:]_-])pacstrap([^[:alnum:]_-]|$)' \
            | grep -v 'w_run_retry' || true)"
    [[ -z "$hits" ]] || { echo "  $f: bare pacstrap (use the w_run_retry seam):"; echo "$hits" | sed 's/^/    /'; rc=1; }
  done

  # 5. The mirror-ranking numbers exist twice and must stay identical.
  #    Ф.1 calibrated them against reflector's real rating mechanic and hardcoded
  #    them in the installer (modules/base.sh, which runs on the ISO and cannot
  #    read the machine's layered config); Ф.3 put the same numbers in the vendor
  #    layer /usr/share/w/defaults/mirrors.conf, where w-mirrors reads them for the
  #    periodic re-ranking. A machine whose list is built one way at install time
  #    and another way a month later would make every field report ambiguous — and
  #    nothing else in the tree would notice the drift.
  local vendor="rootfs/usr/share/w/defaults/mirrors.conf" base="scripts/install/modules/base.sh"
  if [[ -f "$vendor" && -f "$base" ]]; then
    local pair key flag want got
    # <config key>:<reflector flag as spelled in base.sh>
    for pair in PROTOCOL:--protocol AGE:--age SCORE:--score COUNT:--number \
                THREADS:--threads CONNECT_TIMEOUT:--connection-timeout \
                DOWNLOAD_TIMEOUT:--download-timeout; do
      key="${pair%%:*}"; flag="${pair#*:}"
      want="$(sed -nE "s/^${key}=([^#[:space:]]+).*/\1/p" "$vendor" | tail -n1)"
      got="$(grep -oE -- "${flag} [^ \\\\]+" "$base" | head -n1 | awk '{print $2}')"
      [[ -n "$want" && -n "$got" ]] || { echo "  mirror ranking: cannot compare $key / $flag (one side missing)"; rc=1; continue; }
      [[ "$want" == "$got" ]] || {
        echo "  mirror ranking drift: $vendor $key=$want vs $base $flag $got"; rc=1; }
    done
  fi

  # 4. Unescaped backticks inside an UNQUOTED heredoc are command substitution.
  #    Our --help texts use `cat <<EOF` on purpose, so that $PACKS_DIR and friends
  #    expand to real paths — which makes every backtick in that prose executable.
  #    w-pack shipped `w-sync update` unescaped in its usage text, so `w-pack`
  #    with no arguments ran the system updater. shellcheck only rates this style
  #    (SC2006, info) and the gate stops at warnings, so it needs its own rule.
  #    The convention everywhere else is already right: escape them (\`like this\`)
  #    or quote the delimiter (<<'EOF') when nothing needs to expand.
  hits="$(git ls-files -z | xargs -0 awk '
    FNR == 1 { delim = "" }
    delim != "" {
      if ($0 == delim) { delim = ""; next }
      if (index($0, "`") && $0 !~ /\\`/) print FILENAME ":" FNR ": " $0
      next
    }
    /<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/ && !/<<</ {
      line = $0
      sub(/^.*<<-?[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      delim = line
    }' 2>/dev/null || true)"
  [[ -z "$hits" ]] || {
    echo "  unescaped backtick inside an unquoted heredoc (runs as a command):"
    echo "$hits" | sed 's/^/    /'; rc=1; }

  # 6. A `setsid` that leaves stdin on the terminal is not detached.
  #    Measured on the VM 2026-08-25: `setsid -f cmd >/dev/null 2>&1` run from a
  #    terminal leaves the child a session leader still holding the pty, so it takes
  #    that pty as its CONTROLLING terminal (tty_nr 136:0) — and closing the window
  #    HUPs it 79 ms later. Redirecting stdout alone READS as detached and is not.
  #    That is precisely how the reboot at the end of `w-update` went missing for six
  #    weeks: w-session-exit died inside `w-session save`, before it could ask one
  #    window to close, with every descriptor pointed at /dev/null so not a line of
  #    it reached any log. The python twin (w-session's detach()) always had it
  #    right — it dup2's fd 0, 1 AND 2 — which is the whole reason `layout apply`
  #    survives closing its own terminal while the two bash call sites did not.
  #    git grep -lI pre-filters, so the awk join only runs on files that mention it;
  #    the command-position anchor keeps `os.setsid()` and the prose in the comments
  #    explaining this very trap out of the results.
  local sf
  while IFS= read -r sf; do
    [[ -f "$sf" ]] || continue
    hits="$(awk '/\\$/ { sub(/\\$/, ""); buf = buf $0; next }
                 { print FNR ": " buf $0; buf = "" }' "$sf" \
            | grep -vE '^[0-9]+: [[:space:]]*#' \
            | grep -E '(^[0-9]+:[[:space:]]*|[;&|(]+[[:space:]]*)setsid[[:space:]]' \
            | grep -vE '<[[:space:]]*/dev/null' || true)"
    [[ -z "$hits" ]] || {
      echo "  $sf: setsid without </dev/null (keeps the pty, dies on hangup):"
      echo "$hits" | sed 's/^/    /'; rc=1; }
  done < <(git grep -lI -e setsid -- rootfs scripts devtools 2>/dev/null || true)

  return $rc
}
