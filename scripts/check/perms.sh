# check/perms.sh — executable bits where execution depends on them.
#
# rootfs/ and devtools/ deploy via rsync (mode-preserving) and archiso stages
# strip modes entirely (profiledef gotcha, see landmines) — a script that is
# 644 in git ships broken and fails only at runtime on a clean install (bit us
# twice already). Top-level scripts/ and vm/ orchestrators are invoked directly.
# Out of scope by design: sourced fragments and files run via `bash x`
# (install/lib, install/modules, packs setup.sh, scripts/check).

chk_perms() {
  local rc=0 f mode
  declare -A GIT_MODE=()
  while read -r mode _ _ f; do GIT_MODE[$f]=$mode; done < <(git ls-files -s)

  for f in "${SH_ENTRY[@]}" "${PY_FILES[@]}"; do
    case "$f" in
      scripts/packs/*) continue ;;  # bundle setup.sh runs via `bash x` (w-pack)
      rootfs/*|devtools/*|scripts/*.sh|vm/*.sh) ;;
      *) continue ;;
    esac
    # scripts/check/*.sh are sourced by check.sh — exempt.
    [[ "$f" == scripts/check/* ]] && continue
    if [[ -n "${GIT_MODE[$f]:-}" ]]; then
      [[ "${GIT_MODE[$f]}" == "100755" ]] \
        || { echo "  not executable in git (${GIT_MODE[$f]}): $f"; rc=1; }
    else
      # Untracked (pre-`git add`): the filesystem bit is what git will record.
      [[ -x "$f" ]] || { echo "  not executable (untracked): $f"; rc=1; }
    fi
  done
  return $rc
}
