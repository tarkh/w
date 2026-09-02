# w-pac-lib.sh — the one seam every package transaction goes through (shared, sourced).
#
# Sourced from two sides, deliberately one file:
#   • installer / apply.sh — via scripts/install/lib/pac.sh, which is a two-line
#     shim onto this file (it runs off the ISO or the source checkout, where
#     /usr/lib/w does not exist yet);
#   • the installed machine — /usr/lib/w/w-pac-lib.sh, sourced by w-pack,
#     w-kernel and w-actuate-lib.sh. Those three ran bare `pacman -S` until Ф.3
#     (installer.md §5) because they could not see scripts/install/lib; a second
#     copy of the classifier would have been the drift this project gates away.
#
# Layer 2 of the package-delivery plan (installer.md §5): surviving a mirror that
# goes bad AFTER it was chosen. Layer 1 (mod_reflector + mod_mirror_preflight in
# modules/base.sh) can only judge a mirror at selection time, and the failure that
# actually broke three release-gate runs in a row was a host that rated fine and
# stalled a minute later, mid-transaction. No amount of ranking catches that — only
# a retry does. But a retry is worth having only if it obeys three rules, and every
# one of them is load-bearing:
#
#   1. It must CHANGE something between attempts, otherwise it is a `sleep` with
#      extra steps. The mirror that failed is demoted to the bottom of the
#      mirrorlist — pacman names it in the error line itself — so the next attempt
#      starts at a different host. Reordering the list we already have needs nothing
#      but the file, which is exactly why it is the mechanism. Re-ranking stays out
#      of here even now that Ф.3 made it possible on an installed machine
#      (w-mirrors): rebuilding the list costs minutes and hundreds of megabytes,
#      which is not something to start in the middle of a transaction that is
#      already failing. That escalation belongs one level up, where a human (or the
#      updater, see w-update) can decide — a `PAC: … class=network` line is exactly
#      the signal it keys off.
#   2. It must classify BY OUTPUT SIGNATURE, not by exit code — pacman returns 1 for
#      everything, so the code cannot tell a stalled download from an invalid
#      signature. Retrying a real defect does not fix it, it hides it (the same
#      reasoning that keeps auto-retry out of test.sh, see e2e-preset.md). So
#      anything not recognisably transport is NOT retried, including output we do
#      not recognise at all: an unconditional retry is precisely the variant §5
#      rejects.
#   3. The mirror name and the failure class go into the W log as their own line, so
#      e2e/logscan can tell a network stall from a defect without reading the raw
#      pacman wall of text — the misreading that kept the pacstrap failure filed as
#      a "mysterious keyring flake" for years.
#
# Log tag `PAC:` (layer 1 writes `MIRRORS:`). The split is deliberate: a `MIRRORS:`
# line is printed on every healthy install — it describes list SELECTION, background
# by design. A `PAC:` line is an EVENT, of which a healthy run has none, so a single
# grep answers "was package delivery in trouble on this run?". The `CRITICAL:` tag is
# reserved for the terminal failure: a flake we successfully survived must stay
# untagged, or vm/e2e.sh's "no CRITICAL apply warnings" assertion would fail on
# exactly the case this seam exists to fix.
#
# Two things this deliberately does NOT do:
#   • it never dies — modules run under `set -e`, and returning pacman's own status
#     keeps their behaviour byte-for-byte what a bare `pacman` call gave them;
#   • it does not capture pacman's output away from the terminal (tee, not `$(…)`,
#     and no XferCommand): progress.sh parses "downloading …" / "( n/m ) installing"
#     out of that same stream to drive the real progress bars, and a custom transfer
#     command would cost ParallelDownloads on top (§5, rejected alternatives).

# Attempts per transaction. 3 matches the retry precedents already in the tree
# (git_clone_retry in build-iso.sh, the yay clone in apply.sh).
W_PAC_TRIES="${W_PAC_TRIES:-3}"

# Transport gave up: another host may well serve the same files.
# `download library error` is the wording pacman actually prints when it runs out
# of servers for a file — measured against a 0 B/s endpoint (Ф.4), where the older
# `(failed to retrieve some files)` phrasing shows up only as the warning above it.
_W_PAC_RETRY='Operation too slow|failed retrieving file|failed to commit transaction \((failed to retrieve some files|download library error)\)|failed to synchronize all databases|Could not resolve host|Connection timed out|Connection refused|Recv failure|Timeout was reached'
# Truths about the packages, the keyring or the disk. A retry cannot fix any of
# these — it can only turn a clear error into a slow one and bury the real cause.
_W_PAC_FATAL='signature from .* is invalid|invalid or corrupted package|required key missing|conflicting files|exists in filesystem|No space left on device|not enough free disk space|target not found'

# _w_pac_class <output-file> — network | defect | unknown.
# Fatal is tested FIRST on purpose: a transaction that reports both a stalled
# download and an invalid signature is a defect and has to surface as one.
_w_pac_class() {
  grep -qE "$_W_PAC_FATAL" "$1" && { echo defect;  return 0; }
  grep -qE "$_W_PAC_RETRY" "$1" && { echo network; return 0; }
  echo unknown
}

# _w_pac_mirrors <output-file> — hosts pacman blamed, one per line, deduplicated.
# Keyed on pacman's two canonical shapes rather than a loose "… from X …", so a
# line like "required key missing from keyring" can never be read as a host name:
#   error: failed retrieving file 'x.pkg.tar.zst' from mirror.example.org : …
#   warning: too many errors from mirror.example.org, skipping for the remainder…
# The name is taken WITH its port. pacman prints "from 10.0.2.2:18083 :" verbatim
# (measured, Ф.4), and a pattern that stopped at the colon handed _w_pac_demote a
# bare host that matches no Server line — the demotion then silently fell through
# to a rotate. A mirrorlist entry with an explicit port is perfectly legal, so this
# was a real gap, not just a test-harness artefact.
# Every host named here is one that already failed, so all of them are demoted
# (ParallelDownloads can implicate more than one). Nothing is ever deleted, so even
# a run where our own link is down only churns the order.
_w_pac_mirrors() {
  sed -nE -e "s/.*failed retrieving file '[^']*' from ([^[:space:],]+)[[:space:]]+:.*/\1/p" \
          -e 's/.*too many errors from ([^[:space:],]+),.*/\1/p' "$1" \
    | awk '!seen[$0]++'
}

# _w_pac_demote <mirrorlist> <host>… — move those hosts' Server lines to the bottom.
# Demote, never delete: the list is inherited by the target (§5, fact #1) and depth
# is what pacman's own "too many errors from X, skipping" fallback runs on.
# A host matches a Server line on "//host/" or "//host:" — the second form covers
# both directions of the port question: a named "host:port" against a list entry
# that carries the port, and a bare host against an entry that adds one.
_w_pac_demote() {
  local list="$1"; shift
  [[ -f "$list" && -w "$list" ]] || return 1

  local tmp="$list.w-pac.$$" moved=0
  if awk -v hosts="$*" '
        BEGIN { n = split(hosts, h, " ") }
        /^[[:space:]]*Server/ {
          for (i = 1; i <= n; i++)
            if (index($0, "//" h[i] "/") || index($0, "//" h[i] ":")) { bad[++m] = $0; next }
        }
        { print }
        END {
          for (i = 1; i <= m; i++) {
            if (i == 1) print "# W: demoted by w_pac — failed mid-transaction"
            print bad[i]
          }
          exit (m ? 0 : 1)
        }' "$list" > "$tmp"
  then
    cat "$tmp" > "$list"; moved=1
  fi
  rm -f "$tmp"

  (( moved )) && return 0
  return 1
}

# _w_pac_rotate <mirrorlist> — nothing was named (a bare "failed to commit
# transaction" names no host), so still change something: send the head to the
# bottom. Pointless with a single entry — say so rather than pretend.
_w_pac_rotate() {
  local list="$1"
  [[ -f "$list" && -w "$list" ]] || return 1
  (( $(grep -c '^[[:space:]]*Server' "$list") >= 2 )) || return 1

  local tmp="$list.w-pac.$$"
  awk '!done && /^[[:space:]]*Server/ { head = $0; done = 1; next }
       { print }
       END { if (done) { print "# W: rotated by w_pac"; print head } }' "$list" > "$tmp"
  cat "$tmp" > "$list"
  rm -f "$tmp"
}

# _w_pac_who <host>… — the blamed mirrors as one readable field. ParallelDownloads
# and a deep list can implicate every entry at once (measured: a fully sick 20-deep
# pool names all twenty), and a 700-character log line is one nobody reads — which
# defeats the point of having a greppable tag at all. All of them are still demoted;
# only the message is capped.
_w_pac_who() {
  (( $# )) || { echo unnamed; return 0; }
  if (( $# <= 3 )); then echo "$*"; else echo "$1 $2 $3 and $(($# - 3)) more"; fi
}

# _w_pac_rotate_why <mirrorlist> <named-count> — why we fell back to rotating.
# Two very different situations reach the rotate branch and the log has to tell
# them apart: pacman named nobody (a bare "failed to commit transaction" does
# that), or it named hosts that are not in THIS list — which means the wrong list
# is being reordered, and a message reading "no mirror named" would send the next
# reader hunting a parser bug that is not there. Cost one session to learn.
_w_pac_rotate_why() {
  if (( $2 )); then echo "$2 mirror(s) named, none of them in $1"; else echo "no mirror named"; fi
}

# crit() exists in apply.sh; the installer logs with plain echo into install.log.
_w_pac_crit() {
  if declare -F crit >/dev/null; then crit "$*"
  else echo -e "\033[1;31mCRITICAL:\033[0m $*"; fi
}

# w_pac <pacman args…> — thin front over pacman itself, not over "install packages":
# --overwrite, -Sy, -Syu and the flags each call site already uses stay visible and
# unfiltered. Target follows $MNT (installer: the mounted target via arch-chroot;
# apply/firstboot: the running system), which is the same switch the modules used to
# spell out around every pacman call.
w_pac() {
  local root="${MNT:-}" sysroot list cache out cls who attempt=1 rc=0
  local -a cmd bad
  if [[ -n "$root" ]]; then cmd=(arch-chroot "$root" pacman); else cmd=(pacman); fi
  # W_PAC_SYSROOT is a test seam (unit tests point it at a tmpdir so a run as root
  # cannot touch the real mirrorlist); prod = the transaction target itself.
  sysroot="${W_PAC_SYSROOT-$root}"
  list="$sysroot/etc/pacman.d/mirrorlist"
  cache="$sysroot/var/cache/pacman/pkg"
  out="$(mktemp)"

  # errexit is saved rather than assumed: every caller today runs under set -e, but
  # a seam that switches it on for its caller would be a landmine of its own.
  local errexit=0; case $- in *e*) errexit=1 ;; esac

  while :; do
    # set +e around the pipeline is mandatory under the callers' set -euo pipefail:
    # without it the phase dies on pacman's exit status before we ever classify it.
    # tee keeps the output flowing to stdout (progress bars, install log).
    set +e
    "${cmd[@]}" "$@" 2>&1 | tee "$out"
    rc=${PIPESTATUS[0]}
    if (( errexit )); then set -e; fi
    if (( rc == 0 )); then break; fi

    cls="$(_w_pac_class "$out")"
    bad=(); mapfile -t bad < <(_w_pac_mirrors "$out")
    who="$(_w_pac_who "${bad[@]}")"

    if [[ "$cls" != network ]]; then
      _w_pac_crit "PAC: transaction failed, not retried (class=$cls, mirror=$who) — see the pacman output above"
      break
    fi
    if (( attempt >= W_PAC_TRIES )); then
      _w_pac_crit "PAC: transaction failed after $attempt attempts (class=network, last mirror=$who)"
      break
    fi

    if (( ${#bad[@]} )) && _w_pac_demote "$list" "${bad[@]}"; then
      echo "PAC: attempt $attempt/$W_PAC_TRIES failed on $who (class=network) — mirror demoted to the bottom of the list, retrying"
    elif _w_pac_rotate "$list"; then
      echo "PAC: attempt $attempt/$W_PAC_TRIES failed (class=network, $(_w_pac_rotate_why "$list" "${#bad[@]}")) — mirrorlist head rotated, retrying"
    else
      echo "PAC: attempt $attempt/$W_PAC_TRIES failed (class=network) — mirrorlist could not be reordered, retrying as is"
    fi

    # A partial file left behind by the mirror we just demoted makes the next host
    # answer the resumed range request with an error instead of the package.
    rm -f "$cache"/*.part 2>/dev/null || true
    sleep $(( attempt * 5 ))
    attempt=$(( attempt + 1 ))
  done

  rm -f "$out"
  if (( rc == 0 && attempt > 1 )); then
    echo "PAC: transaction succeeded on attempt $attempt after a network failure"
  fi
  return "$rc"
}

# w_run_retry <label> <command…> — the same contract as w_pac for a transaction
# that is NOT a bare `pacman` call. Today that means exactly one caller, `pacstrap`,
# which takes none of pacman's arguments and is wrapped in progress_pacman on top —
# so w_pac cannot front it, and until now the single step with the least room for
# error was the only one outside the seam. Two of the three observed release-gate
# failures were in it (installer.md §5).
#
# The premise that kept this unwritten — "the classifier has nothing to read,
# progress_pacman eats the output into gawk" — turned out to be wrong: that pipeline
# already tees into $W_LOG, and install.sh redirects the work phase there as well.
# So the output IS on disk; it just has to be read by byte offset (everything the
# command appended) rather than from a pipe. Hence the three differences from w_pac:
#
#   • Classification reads the slice of $W_LOG the command appended. No $W_LOG at
#     all means nothing to classify, and an unclassified retry is not a retry (§5) —
#     so it runs once and says why, rather than retrying blind.
#   • The mirrorlist to reorder is NOT derived from $MNT. During pacstrap $MNT is
#     set, but the transaction reads the HOST's list (pacstrap runs `pacman -r
#     $newroot` under the host's config and only copies the mirrorlist into the
#     target AFTER the packages land — read out of /usr/bin/pacstrap, not assumed).
#     Callers therefore state both roots outright, W_PAC_SYSROOT for the list and
#     W_PAC_CACHE_ROOT for the partial downloads, which for pacstrap are different
#     filesystems.
#   • W_PAC_PRERETRY names a function to run before each retry, for state the failed
#     attempt may have left half-built. Keeping it a caller-supplied hook is what
#     keeps pacstrap's specifics out of a library that also ships to machines where
#     pacstrap never runs.
w_run_retry() {
  local label="$1"; shift
  local sysroot cacheroot list cache log out cls who attempt=1 rc=0 pos=0
  local -a bad
  sysroot="${W_PAC_SYSROOT-${MNT:-}}"
  cacheroot="${W_PAC_CACHE_ROOT-$sysroot}"
  list="$sysroot/etc/pacman.d/mirrorlist"
  cache="$cacheroot/var/cache/pacman/pkg"
  log="${W_LOG:-}"
  out="$(mktemp)"

  local errexit=0; case $- in *e*) errexit=1 ;; esac

  while :; do
    pos=0
    if [[ -n "$log" && -f "$log" ]]; then
      pos=$(wc -c < "$log" 2>/dev/null | tr -d '[:space:]') || true
      pos=${pos:-0}
    fi

    # errexit is restored to what the CALLER had, not merely re-enabled if it was
    # on. The command here is a shell FUNCTION, and progress_pacman — the wrapper
    # the installer actually passes in — ends with an unconditional `set -e` of its
    # own. Only re-enabling would therefore hand errexit BACK ON to a caller that
    # never had it (measured: w-pack and the other runtime tools run without it),
    # turning the next harmless nonzero status anywhere in that script into a silent
    # exit. That is precisely the landmine w_pac's header promises this seam will
    # not lay. `|| rc=$?` keeps the call itself exempt from errexit regardless of
    # what the callee does to it.
    rc=0
    set +e
    "$@" || rc=$?
    if (( errexit )); then set -e; else set +e; fi
    if (( rc == 0 )); then break; fi

    if [[ -z "$log" || ! -f "$log" ]]; then
      _w_pac_crit "PAC: $label failed (rc=$rc) with no \$W_LOG to classify against — not retried"
      break
    fi
    tail -c "+$((pos + 1))" "$log" > "$out" 2>/dev/null || true

    cls="$(_w_pac_class "$out")"
    bad=(); mapfile -t bad < <(_w_pac_mirrors "$out")
    who="$(_w_pac_who "${bad[@]}")"

    if [[ "$cls" != network ]]; then
      _w_pac_crit "PAC: $label failed, not retried (class=$cls, mirror=$who) — see the output above"
      break
    fi
    if (( attempt >= W_PAC_TRIES )); then
      _w_pac_crit "PAC: $label failed after $attempt attempts (class=network, last mirror=$who)"
      break
    fi

    if (( ${#bad[@]} )) && _w_pac_demote "$list" "${bad[@]}"; then
      echo "PAC: $label attempt $attempt/$W_PAC_TRIES failed on $who (class=network) — mirror demoted to the bottom of the list, retrying"
    elif _w_pac_rotate "$list"; then
      # Two different situations land here and the log must tell them apart: pacman
      # named nobody at all, or it named hosts that are not in THIS list — which
      # means the wrong list is being reordered, and a message saying "no mirror
      # named" would send the next reader looking for a parser bug that isn't there.
      echo "PAC: $label attempt $attempt/$W_PAC_TRIES failed (class=network, $(_w_pac_rotate_why "$list" "${#bad[@]}")) — mirrorlist head rotated, retrying"
    else
      echo "PAC: $label attempt $attempt/$W_PAC_TRIES failed (class=network) — mirrorlist could not be reordered, retrying as is"
    fi

    rm -f "$cache"/*.part 2>/dev/null || true
    if [[ -n "${W_PAC_PRERETRY:-}" ]] && declare -F "$W_PAC_PRERETRY" >/dev/null; then
      "$W_PAC_PRERETRY" || true
    fi
    sleep $(( attempt * 5 ))
    attempt=$(( attempt + 1 ))
  done

  rm -f "$out"
  if (( rc == 0 && attempt > 1 )); then
    echo "PAC: $label succeeded on attempt $attempt after a network failure"
  fi
  return "$rc"
}
