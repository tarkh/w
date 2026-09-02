# check/bash.sh — bash syntax (`bash -n`) + shellcheck over the shell inventory.
#
# Gate is severity=warning: the codebase starts clean at that level, so any new
# warning is a regression. Structural noise is silenced in .shellcheckrc; point
# exceptions are inline `# shellcheck disable=` directives with a reason.

chk_bash() {
  local rc=0 f

  # Syntax first — a parse error would also drown shellcheck in follow-ups.
  # `bash -n` accepts the posix-sh files too (superset), so one pass covers all.
  # $BASH = the interpreter running us (>=4 guaranteed by check.sh), not
  # whatever `bash` PATH resolves to (macOS system bash is 3.2).
  for f in "${SH_ENTRY[@]}" "${SH_LIB[@]}"; do
    "$BASH" -n "$f" || rc=1
  done
  [[ $rc -eq 0 ]] || return 1

  if ! command -v shellcheck &>/dev/null; then
    warn "shellcheck not installed (pacman -S shellcheck / brew install shellcheck)"
    return 0
  fi
  echo "  bash -n + shellcheck: ${#SH_ENTRY[@]} scripts, ${#SH_LIB[@]} sourced fragments"
  shellcheck -S warning "${SH_ENTRY[@]}" || rc=1
  # Sourced fragments have no shebang — force the bash dialect.
  shellcheck -S warning -s bash "${SH_LIB[@]}" || rc=1
  return $rc
}
