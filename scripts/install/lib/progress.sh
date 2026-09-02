# progress.sh — real progress bars for long-running install work.
#
# progress_pacman drives a dialog --gauge from genuine package counts: pacman /
# pacstrap print "( n/m ) installing …" lines, which we parse into a percentage.
# No fake spinners — the bar only advances when a package actually lands.
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
  # Two real phases from piped (non-tty) pacman output:
  #   "Packages (N) …"        → total package count (denominator)
  #   "downloading <file>"    → retrieve phase   → 0–45%  (+ live file name)
  #   "( n/m ) installing …"  → transaction      → 50–100%
  # The message line always shows the current action, so a slow download never
  # looks frozen at 0%. pacstrap output is also tee'd to the install log.
  "$@" 2>&1 | tee -a "${W_LOG:-/dev/null}" | gawk '
    match($0, /Packages? \(([0-9]+)\)/, a) { total = a[1] + 0 }
    /downloading/ {
      d++
      pct = (total > 0) ? int(d * 45 / total) : 0
      if (pct > 45) pct = 45
      msg = $0; sub(/^[[:space:]]+/, "", msg)
      printf "XXX\n%d\n%s\nXXX\n", pct, msg; fflush(); next
    }
    match($0, /\([[:space:]]*([0-9]+)\/([0-9]+)\)/, b) {
      cur = b[1] + 0; tot = b[2] + 0
      if (total <= 0) total = tot
      pct = 50 + ((tot > 0) ? int(cur * 50 / tot) : 0)
      msg = $0; sub(/^[[:space:]]+/, "", msg)
      printf "XXX\n%d\n%s\nXXX\n", pct, msg; fflush()
    }' >&3
  rc=${PIPESTATUS[0]}
  set -e
  printf 'XXX\n100\n%s\nXXX\n' "$(t please_wait)" >&3
  exec 3>&-

  wait "$dpid" 2>/dev/null || true
  rm -f "$fifo"
  return "$rc"
}

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
