# lib/modules.sh — reader for the module registry (scripts/install/modules.conf).
#
# The registry is the single source of truth for which modules exist, when they
# run, and what must run before them. This is the only parser: apply.sh (source
# list, --all order, flag dispatch, usage), install.sh (source list), w-sync (the
# canonical flag order and the sync-map AUTO rule) and check/modules.sh all read
# it through here, so none of them can drift from the file or from each other.
#
# Loaded rows land in parallel arrays, in FILE ORDER (which is the run order):
#   W_MOD_NAME W_MOD_PHASE W_MOD_FN W_MOD_FLAG W_MOD_LABEL W_MOD_AFTER, W_MOD_N
# The '-' placeholder becomes an empty string; `after` stays a space-separated list.
#
# Every array is assigned with `=()`, never bare-declared: an unset array's first
# ${#arr[@]} is fatal under `set -u`, and this file is sourced into scripts that
# run it.

W_MOD_PHASES="install apply manual dev"

# Trims into the global _W_MOD_T rather than printing: this runs six times per row
# and a command substitution each time would fork ~360 subshells on every apply.
_W_MOD_T=""
_w_mod_trim() {
  local s="${1-}"
  s="${s#"${s%%[![:space:]]*}"}"
  _W_MOD_T="${s%"${s##*[![:space:]]}"}"
}

# w_modules_load <modules.conf>
# Strict by design: a malformed row aborts with a message naming the line, rather
# than yielding a short module list that would silently under-apply the system.
w_modules_load() {
  local conf="$1" line n p f fl lb af lineno=0 rest
  [[ -r "$conf" ]] || { echo "modules.conf not readable: $conf" >&2; return 1; }

  W_MOD_NAME=(); W_MOD_PHASE=(); W_MOD_FN=(); W_MOD_FLAG=(); W_MOD_LABEL=(); W_MOD_AFTER=()
  W_MOD_CONF="$conf"
  W_MOD_DIR="$(cd "$(dirname "$conf")" && pwd)/modules"

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    _w_mod_trim "${line%$'\r'}"; line="$_W_MOD_T"
    [[ -z "$line" || "$line" == \#* ]] && continue

    IFS='|' read -r n p f fl lb af rest <<< "$line"
    _w_mod_trim "${n-}";  n="$_W_MOD_T"
    _w_mod_trim "${p-}";  p="$_W_MOD_T"
    _w_mod_trim "${f-}";  f="$_W_MOD_T"
    _w_mod_trim "${fl-}"; fl="$_W_MOD_T"
    _w_mod_trim "${lb-}"; lb="$_W_MOD_T"
    _w_mod_trim "${af-}"; af="$_W_MOD_T"

    [[ -n "$n" && -n "$p" && -n "$f" ]] \
      || { echo "$conf:$lineno: row needs at least name|phase|fn" >&2; return 1; }
    [[ -z "${rest-}" ]] \
      || { echo "$conf:$lineno: too many fields (expected 6)" >&2; return 1; }
    [[ " $W_MOD_PHASES " == *" $p "* ]] \
      || { echo "$conf:$lineno: unknown phase '$p' (want: $W_MOD_PHASES)" >&2; return 1; }

    [[ "$fl" == - ]] && fl=""
    [[ "$lb" == - ]] && lb=""
    [[ "$af" == - ]] && af=""

    W_MOD_NAME+=("$n"); W_MOD_PHASE+=("$p"); W_MOD_FN+=("$f")
    W_MOD_FLAG+=("$fl"); W_MOD_LABEL+=("$lb"); W_MOD_AFTER+=("$af")
  done < "$conf"

  W_MOD_N=${#W_MOD_NAME[@]}
  if [[ $W_MOD_N -eq 0 ]]; then echo "$conf: no module rows" >&2; return 1; fi
  return 0
}

# _w_mod_in_phase <index> <phase…> — true when the row's phase is one of those given.
_w_mod_in_phase() {
  local i="$1"; shift
  [[ " $* " == *" ${W_MOD_PHASE[i]} "* ]]
}

# w_modules_files <phase…> — module file basenames to source, deduplicated, in order.
# A name with no modules/<name>.sh is a pseudo-module implemented in the caller
# (apply.sh's apply_rootfs, install_yay, …); the caller's `declare -F` guard is what
# catches a genuinely missing function, so absence here is not an error.
w_modules_files() {
  local i seen=" " file
  for ((i = 0; i < W_MOD_N; i++)); do
    _w_mod_in_phase "$i" "$@" || continue
    file="${W_MOD_NAME[i]}.sh"
    [[ -f "$W_MOD_DIR/$file" ]] || continue
    [[ "$seen" == *" $file "* ]] && continue
    seen+="$file "
    printf '%s\n' "$file"
  done
  return 0
}

# w_modules_flags <phase…> — the flags of those phases, in canonical run order.
w_modules_flags() {
  local i
  for ((i = 0; i < W_MOD_N; i++)); do
    _w_mod_in_phase "$i" "$@" || continue
    [[ -n "${W_MOD_FLAG[i]}" ]] && printf '%s\n' "${W_MOD_FLAG[i]}"
  done
  return 0
}

# w_modules_flag_of <name> — the post-boot flag of a module, empty when it has none.
# Deliberately limited to the production post-boot phases: an install-only module
# (base, network, …) and the dev-only one must never be reachable from a path route.
w_modules_flag_of() {
  local name="$1" i
  for ((i = 0; i < W_MOD_N; i++)); do
    _w_mod_in_phase "$i" apply manual || continue
    if [[ "${W_MOD_NAME[i]}" == "$name" && -n "${W_MOD_FLAG[i]}" ]]; then
      printf '%s\n' "${W_MOD_FLAG[i]}"
      return 0
    fi
  done
  return 0
}
