# check/modules.sh — the module registry vs. everything that consumes it.
#
# scripts/install/modules.conf declares which modules exist, when they run, what
# each is called, and what must run before it. Before it existed the same facts sat
# in four hand-kept copies (apply.sh's source list / ALL_MODULES / case dispatch,
# install.sh's source list, w-sync's ORDER, sync-map's install-only skip list), and
# the copies drifted silently: eight modules added to apply.sh were never mirrored
# into w-sync's ORDER, so a selective sync ran them out of the order that array
# exists to preserve. Nothing failed — the machine just converged differently.
#
# The registry removed the copies; this suite is what keeps the file honest, since a
# declaration nothing validates is prose with pipes in it. Checked here:
#   1. every row parses, and its fields agree with its phase
#   2. every row's function really exists, in its module file or its driver script
#   3. every modules/*.sh is declared, and every declared file exists
#   4. `after` names real modules, and the curated order satisfies every constraint
#      (a valid linearization — which also proves the graph is acyclic)
#   5. the consumers derive, rather than restate: no hardcoded source lists left
#   6. install.sh's call sequence matches the registry's install order
#   7. sync-map routes each module file to exactly the module's own effect

_CHK_MOD_CONF="scripts/install/modules.conf"

# Resolve a path through sync-map exactly as w-sync's map_file() does (first match
# wins, the glob unquoted so a single '*' spans '/').
_chk_mod_route() {
  local path="$1" glob flag
  while IFS=$'\t' read -r glob flag || [[ -n "$glob" ]]; do
    [[ -z "$glob" || "$glob" == \#* ]] && continue
    flag="${flag//[[:space:]]/}"
    # shellcheck disable=SC2053  # intentional glob match, not a literal compare
    [[ "$path" == $glob ]] && { echo "$flag"; return; }
  done < rootfs/usr/share/w/update/sync-map
  echo "--all"
}

chk_modules() {
  local rc=0 i j n f fn phase name dep route want_flag driver found g

  [[ -f "$_CHK_MOD_CONF" ]] || { echo "  registry not found: $_CHK_MOD_CONF"; return 1; }

  # shellcheck source=../install/lib/modules.sh
  source scripts/install/lib/modules.sh
  w_modules_load "$_CHK_MOD_CONF" || { echo "  registry does not parse"; return 1; }
  n=$W_MOD_N

  # ── 1. field shape per phase ────────────────────────────────────────────────
  # A label is the firstboot gauge's step name, so exactly the --all steps carry
  # one; a flag is a CLI entry point, so install-phase rows must not have one.
  local -A seen_row=() seen_flag=()
  for ((i = 0; i < n; i++)); do
    name="${W_MOD_NAME[i]}"; phase="${W_MOD_PHASE[i]}"
    if [[ -n "${seen_row[$name/$phase]:-}" ]]; then
      echo "  duplicate row: $name ($phase)"; rc=1
    fi
    seen_row["$name/$phase"]=1

    if [[ -n "${W_MOD_FLAG[i]}" ]]; then
      [[ "${W_MOD_FLAG[i]}" == "--$name" ]] \
        || { echo "  $name ($phase): flag ${W_MOD_FLAG[i]} does not match the module name"; rc=1; }
      if [[ -n "${seen_flag[${W_MOD_FLAG[i]}]:-}" ]]; then
        echo "  duplicate flag: ${W_MOD_FLAG[i]}"; rc=1
      fi
      seen_flag["${W_MOD_FLAG[i]}"]=1
      if [[ "$phase" == install ]]; then
        echo "  $name: install-phase rows must not declare a flag"; rc=1
      fi
    elif [[ "$phase" == manual || "$phase" == dev ]]; then
      echo "  $name ($phase): a $phase module is reachable only by flag"; rc=1
    fi

    if [[ "$phase" == apply ]]; then
      if [[ -z "${W_MOD_LABEL[i]}" ]]; then
        echo "  $name: an --all module needs a progress label"; rc=1
      fi
    elif [[ -n "${W_MOD_LABEL[i]}" ]]; then
      echo "  $name ($phase): only --all modules get a progress label"; rc=1
    fi
  done

  # ── 2. every declared function exists ───────────────────────────────────────
  # Either in the module's own file, or — for a pseudo-module like apply_rootfs, and
  # for plymouth, whose install and post-boot halves live in different places — in
  # the driver script that runs that phase.
  for ((i = 0; i < n; i++)); do
    name="${W_MOD_NAME[i]}"; phase="${W_MOD_PHASE[i]}"; fn="${W_MOD_FN[i]}"
    driver="scripts/apply.sh"; found=0
    [[ "$phase" == install ]] && driver="scripts/install.sh"
    f="scripts/install/modules/$name.sh"
    if [[ -f "$f" ]] && grep -qE "^$fn\(\)" "$f"; then found=1; fi
    if grep -qE "^$fn\(\)" "$driver"; then found=1; fi
    if [[ $found -eq 1 ]]; then continue; fi
    echo "  $name ($phase): $fn is defined neither in $f nor in $driver"; rc=1
  done

  # ── 3. no module file is undeclared, no declared file is missing ────────────
  for f in scripts/install/modules/*.sh; do
    name="$(basename "$f" .sh)"; found=0
    for ((i = 0; i < n; i++)); do
      [[ "${W_MOD_NAME[i]}" == "$name" ]] && { found=1; break; }
    done
    [[ $found -eq 1 ]] || { echo "  undeclared module file: $f (add a row to $_CHK_MOD_CONF)"; rc=1; }
  done

  # ── 4. the graph, and the order that must satisfy it ────────────────────────
  # Dependencies resolve inside a run group: the installer's phase, or the post-boot
  # stream (apply + manual + dev, which run against the same live system). A dep must
  # sit EARLIER in the file — the curated order is checked to be a valid linearization
  # of the graph, which is also what proves the graph has no cycle.
  local -A idx_of=() group_of=() last_of_phase=()
  for ((i = 0; i < n; i++)); do
    phase="${W_MOD_PHASE[i]}"
    g="post"; [[ "$phase" == install ]] && g="install"
    idx_of["${W_MOD_NAME[i]}/$g"]=$i
    group_of[$i]="$g"
    last_of_phase["$phase"]=$i
  done
  for ((i = 0; i < n; i++)); do
    name="${W_MOD_NAME[i]}"; phase="${W_MOD_PHASE[i]}"
    [[ -z "${W_MOD_AFTER[i]}" ]] && continue
    if [[ "${W_MOD_AFTER[i]}" == "*" ]]; then
      if [[ "${last_of_phase[$phase]}" -ne $i ]]; then
        echo "  $name: declared last of phase '$phase', but other rows follow it"; rc=1
      fi
      continue
    fi
    # `read -ra`, not an unquoted expansion: word-splitting a field that may hold
    # a literal '*' would let pathname expansion turn it into the working directory.
    local -a deps=()
    read -ra deps <<< "${W_MOD_AFTER[i]}"
    for dep in "${deps[@]}"; do
      if [[ "$dep" == "*" ]]; then
        echo "  $name: '*' cannot be combined with named deps"; rc=1; continue
      fi
      j="${idx_of[$dep/${group_of[$i]}]:-}"
      if [[ -z "$j" ]]; then
        echo "  $name ($phase): after '$dep' — no such module in this run group"; rc=1
      elif [[ "$j" -ge "$i" ]]; then
        echo "  order: $name must run after $dep, but $dep is listed later"; rc=1
      fi
    done
  done

  # ── 5. consumers derive, never restate ──────────────────────────────────────
  if grep -qE 'source "\$MODULES/[a-z]+\.sh"' scripts/apply.sh; then
    echo "  scripts/apply.sh still sources modules by hand"; rc=1
  fi
  if grep -qE 'source "\$INSTALL_MODULES/[a-z]+\.sh"' scripts/install.sh; then
    echo "  scripts/install.sh still sources modules by hand"; rc=1
  fi
  if grep -qE '^ORDER=\(--' rootfs/usr/bin/w-sync; then
    echo "  w-sync still carries a hand-written ORDER array"; rc=1
  fi

  # ── 6. install.sh calls the install phase in the declared order ─────────────
  local -a want=() got=()
  for ((i = 0; i < n; i++)); do
    [[ "${W_MOD_PHASE[i]}" == install ]] && want+=("${W_MOD_FN[i]}")
  done
  mapfile -t got < <(
    sed -n '/^main() {/,$p' scripts/install.sh \
      | grep -oE '^[[:space:]]*(\[\[[^]]*\]\][[:space:]]*&&[[:space:]]*)?mod_[a-z_]+' \
      | grep -oE 'mod_[a-z_]+'
  )
  # Helper functions that live in a module file but are not modules themselves
  # (mod_reflector, mod_fault_inject …) are not in the registry — ignore them.
  local -a got_reg=()
  for fn in "${got[@]}"; do
    for ((i = 0; i < n; i++)); do
      if [[ "${W_MOD_PHASE[i]}" == install && "${W_MOD_FN[i]}" == "$fn" ]]; then
        got_reg+=("$fn"); break
      fi
    done
  done
  if [[ "${want[*]}" != "${got_reg[*]}" ]]; then
    echo "  install.sh main() calls the install phase in a different order than the registry:"
    echo "    registry:   ${want[*]}"
    echo "    install.sh: ${got_reg[*]}"
    rc=1
  fi

  # ── 7. sync-map routes each module file to that module's own effect ─────────
  # An install-only or dev-only module must reach nothing on an installed machine; a
  # post-boot one must reach its own flag and no other.
  for ((i = 0; i < n; i++)); do
    name="${W_MOD_NAME[i]}"
    f="scripts/install/modules/$name.sh"
    [[ -f "$f" ]] || continue
    route="$(_chk_mod_route "$f")"
    want_flag="$(w_modules_flag_of "$name")"
    if [[ -z "$want_flag" ]]; then
      if [[ "$route" != "--skip" && "$route" != "AUTO" ]]; then
        echo "  sync-map: $f routes to $route, but $name never runs post-boot"; rc=1
      fi
    else
      case "$route" in
        AUTO|"$want_flag") ;;
        *) echo "  sync-map: $f routes to $route, expected AUTO or $want_flag"; rc=1 ;;
      esac
    fi
  done
  if [[ "$(_chk_mod_route "$_CHK_MOD_CONF")" == "--skip" ]]; then
    echo "  sync-map: the registry itself routes to --skip"; rc=1
  fi

  local -a mod_files=(scripts/install/modules/*.sh)
  echo "  registry: $n rows, ${#seen_flag[@]} flags, ${#mod_files[@]} module files"
  return $rc
}
