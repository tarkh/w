# progress.sh — real progress bars for long-running install work.
#
# progress_pacman drives a dialog --gauge from what the transaction has really
# done: bytes landed in the target's package cache, then packages registered in its
# local db. No fake spinners — the bar only advances when work actually happens.
#
# progress_modules drives the same gauge from apply.sh's own module markers
# (`@@WFB i n label@@`, emitted by run_all — see apply.sh), for the firstboot
# `apply --all` where module count is the denominator (Session 2).

# progress_pacman <title> <cmd> [args…]
progress_pacman() {
  local title="$1"; shift
  local fifo; fifo="$(mktemp -u)"
  mkfifo "$fifo"

  # dialog draws its SCREEN to stdout — send it to the saved terminal fd ($W_TTY)
  # while stdin reads gauge updates from the fifo (work-phase stdout goes to the log).
  dialog "${DIALOG_COMMON[@]}" --colors --title " $title " \
    --gauge "\n  $(t please_wait)" 8 72 0 < "$fifo" 1>&"${W_TTY:-1}" &
  local dpid=$! rc=0

  exec 3> "$fifo"
  set +e
  # Piped pacman can't drive the bar by itself: off a tty it prints " <file>
  # downloading..." / "installing <pkg>..." WITHOUT flushing stdout, so they arrive
  # in 4 KiB bursts; it fetches the largest files first, so a per-file count sits at
  # 0% through most of the bytes; and those lines carry no "( n/m )" counter. Only
  # the two totals arrive on time (pacman flushes before its "Proceed?" question):
  #   "Packages (N)"              → packages to install
  #   "Total Download Size: X U"  → bytes to fetch
  # So _progress_ticks measures the target root ($W_PAC_CACHE_ROOT — pacstrap
  # downloads into its cache and registers into its local db) once a second, and
  # gawk turns it into: download 0–45% · packages 45–90% · post-transaction hooks
  # 90–100%. Without a root the bursty lines are counted instead. The ticks never
  # reach the log: tee sits before them.
  (
    _progress_ticks "${W_PAC_CACHE_ROOT:-}" & tick=$!
    "$@" 2>&1 | tee -a "${W_LOG:-/dev/null}"
    prc=${PIPESTATUS[0]}
    kill "$tick" 2>/dev/null; wait "$tick" 2>/dev/null
    exit "$prc"
  ) | gawk -v mib="$(t u_mib)" '
    function show(p, m) {
      if (p < pct) p = pct
      if (p > 100) p = 100
      pct = p; printf "XXX\n%d\n%s\nXXX\n", pct, m; fflush()
    }
    # A tick can land inside a half-flushed pacman line — match it anywhere, cut it out.
    match($0, /@@WTICK (-?[0-9]+) ([0-9]+)@@/, k) {
      sub(/@@WTICK -?[0-9]+ [0-9]+@@/, ""); ticks = 1
      if (!hooks && k[2] > 0 && total > 0)
        show(45 + int(k[2] * 45 / total), sprintf("( %d/%d ) %s", k[2], total, last))
      else if (!hooks && dl > 0 && k[1] > 0)
        show(int(k[1] * 45 / dl), sprintf("%d / %d %s", k[1] / 1048576, dl / 1048576, mib))
      if ($0 == "") next
    }
    match($0, /Packages? \(([0-9]+)\)/, a) { total = a[1] + 0 }
    match($0, /^Total Download Size:[[:space:]]+([0-9.]+) ([KMG]?)i?B/, s) {
      dl = s[1] * (s[2] == "G" ? 1073741824 : s[2] == "M" ? 1048576 : s[2] == "K" ? 1024 : 1)
    }
    /downloading\.\.\.$/ {
      d++; last = $0; sub(/^[[:space:]]+/, "", last)
      if (!ticks && total > 0) show(int(d * 45 / total), last)
      next
    }
    /^installing / {
      i++; last = $0; sub(/\.\.\.$/, "", last)
      if (!ticks && total > 0) show(45 + int(i * 45 / total), last)
      next
    }
    /^:: Running post-transaction hooks/ { hooks = 1 }
    hooks && match($0, /^\([[:space:]]*([0-9]+)\/([0-9]+)\)/, b) {
      show(90 + int(b[1] * 10 / b[2]), $0)
    }' >&3
  rc=${PIPESTATUS[0]}
  set -e
  printf 'XXX\n100\n%s\nXXX\n' "$(t please_wait)" >&3
  exec 3>&-

  wait "$dpid" 2>/dev/null || true
  rm -f "$fifo"
  return "$rc"
}

# _progress_ticks <root> — once a second "@@WTICK <bytes> <pkgs>@@": bytes added to
# <root>'s package cache (partial downloads included — pacman writes them there too)
# and packages added to its local db, both since this attempt started (a retry
# keeps what the last one fetched). No root → no ticks.
_progress_ticks() {
  [[ -n "$1" ]] || return 0
  local cache="$1/var/cache/pacman/pkg" db="$1/var/lib/pacman/local" b0 n0
  b0=$(_progress_bytes "$cache"); n0=$(_progress_pkgs "$db")
  while sleep 1; do
    printf '@@WTICK %d %d@@\n' $(( $(_progress_bytes "$cache") - b0 )) \
      $(( $(_progress_pkgs "$db") - n0 ))
  done
}
_progress_bytes() { local s; s=$(du -sb "$1" 2>/dev/null | cut -f1); echo "${s:-0}"; }
_progress_pkgs() { find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l; }

# progress_modules <title> <cmd> [args…]
# The bar itself only moves on "@@WFB i n label@@" markers (module-level, as
# decided — no pacman-% blending). But apply.sh's own info() breadcrumbs and
# pacman/yay's "downloading …" / "( n/m ) installing …" lines (same non-tty
# textual format progress_pacman already parses) flow through the same pipe —
# surface those as a live "<module>: <what's happening>" line so a long module
# never looks frozen at the same percentage with no sign of life, mirroring S1.
progress_modules() {
  local title="$1"; shift
  local fifo; fifo="$(mktemp -u)"
  mkfifo "$fifo"

  dialog "${DIALOG_COMMON[@]}" --colors --title " $title " \
    --gauge "\n  $(t please_wait)" 8 72 0 < "$fifo" 1>&"${W_TTY:-1}" &
  local dpid=$! rc=0

  exec 3> "$fifo"
  set +e
  "$@" 2>&1 | tee -a "${W_LOG:-/dev/null}" | gawk '
    match($0, /^@@WFB ([0-9]+) ([0-9]+) (.*)@@$/, a) {
      pct = int(a[1] * 100 / a[2])
      label = a[3]
      printf "XXX\n%d\n%s\nXXX\n", pct, label; fflush(); next
    }
    /downloading/ || /retrieving/ || match($0, /\([[:space:]]*[0-9]+\/[0-9]+\)[[:space:]]+installing/) {
      line = $0; sub(/^[[:space:]]+/, "", line)
      printf "XXX\n%d\n%s: %s\nXXX\n", pct, label, line; fflush(); next
    }
    /==>/ {
      line = $0
      gsub(/\033\[[0-9;]*m/, "", line)
      sub(/^[[:space:]]*==>[[:space:]]*/, "", line)
      if (line != "" && line != label) {
        printf "XXX\n%d\n%s: %s\nXXX\n", pct, label, line; fflush()
      }
    }' >&3
  rc=${PIPESTATUS[0]}
  set -e
  printf 'XXX\n100\n%s\nXXX\n' "$(t please_wait)" >&3
  exec 3>&-

  wait "$dpid" 2>/dev/null || true
  rm -f "$fifo"
  return "$rc"
}
