# check/wconf.sh — the layered config reader vs the shell it replaced.
#
# Phase 1 of update-system.md retired four homegrown config parsers (an awk scan,
# a bare `source`, a grep|cut and two Python variants) in favour of
# /usr/lib/w/w-conf-lib.sh. Swapping a dialect is the one change in that
# work that can break a subsystem silently: a quoting or comment rule that
# differs by a hair turns POWER_KEY=menu into POWER_KEY=menu# and nobody notices
# until the machine misbehaves.
#
# So this is not "some unit tests" — it is a structural gate over the REAL
# shipped files: for every rootfs/etc/w/*.conf, what bash itself gets by sourcing
# the file must equal what the reader parses out of it, key for key. As a side
# effect it also enforces the format contract the vendor layer will rely on in
# phase 2: literal single-line KEY=value, no expansions, no command
# substitution — anything cleverer makes the two dumps disagree and fails here.
#
# Arrays are the one accepted exception (TERMINAL_OPTS): no KEY=value reader can
# represent a shell array, w-term still sources that single key on purpose, and
# the reader keeps it verbatim.

# Dump the scalar variables a conf file assigns, using bash's own semantics.
#
# `env -i` is load-bearing, not tidiness: the probe measures which names the file
# INTRODUCES (the before/after delta below), and an exported variable of the same
# name inherited from the caller sits in both snapshots, so `comm -13` drops it.
# One `AGENT=…` in the developer's environment was enough to make ssh.conf report
# a reader/`source` disagreement over a key both sides read correctly. PATH is
# carried through because the probe shells out to comm and sort.
_wconf_dump_source() { # <file>
  env -i PATH="$PATH" bash --noprofile --norc -c '
    set +u
    _before="$(compgen -v | sort)"
    # shellcheck disable=SC1090
    source "$1" >/dev/null 2>&1 || exit 3
    _after="$(compgen -v | sort)"
    while IFS= read -r v; do
      case "$v" in _before|_after|v|BASH_*|_) continue ;; esac
      # Arrays are out of scope by contract (see header).
      case "$(declare -p "$v" 2>/dev/null)" in "declare -a"*|"declare -A"*) continue ;; esac
      printf "%s=%s\n" "$v" "${!v}"
    done < <(comm -13 <(printf "%s\n" "$_before") <(printf "%s\n" "$_after"))
  ' _ "$1" | sort
}

# Dump the same file through the shared reader, with the file mounted as the
# system layer of a throwaway subsystem.
_wconf_dump_reader() { # <file>
  local f="$1" tmp
  tmp="$(mktemp -d)"
  cp "$f" "$tmp/probe.conf"
  (
    export WCONF_ETC="$tmp" WCONF_VENDOR_DIR="$tmp/none" WCONF_HOME="$tmp/nohome"
    # shellcheck disable=SC1091
    source rootfs/usr/lib/w/w-conf-lib.sh
    wconf_list probe
  ) | sort
  rm -rf "$tmp"
}

# Every shipped config file the layered reader parses. Both trees matter, and the
# second one matters MORE since phase 3: splitting a subsystem moves all of its
# content into the vendor layer, which would leave this gate cross-checking empty
# admin stubs if it only looked at /etc/w.
_wconf_shipped_confs() {
  local f
  for f in rootfs/etc/w/*.conf rootfs/usr/share/w/defaults/*.conf; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}

# Keys the vendor layer of one subsystem defines. `power` has no shipped vendor
# file — w-power GENERATES it from its preset tables — so its key set is read out
# of those tables instead (plus MODE, the admin-only selector that chooses which
# table applies). Evaluating just that array assignment is safe and beats grepping
# it out: a reordered or reflowed array keeps working.
_wconf_vendor_keys() { # <subsys>
  if [[ "$1" == power ]]; then
    bash -c 'eval "$(sed -n "/^PRESET_SYS_KEYS=(/,/)/p" rootfs/usr/bin/w-power)"
             printf "%s\n" "${PRESET_SYS_KEYS[@]}"'
    printf '%s\n' MODE AC_LOCK AC_DISPLAY AC_SUSPEND BAT_LOCK BAT_DISPLAY BAT_SUSPEND
  else
    sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' \
      "rootfs/usr/share/w/defaults/$1.conf" 2>/dev/null
  fi | sort -u
}

# Every key the vendor layer ships must carry a scope row (exact or glob).
#
# This is the half that matters: an undeclared key is UNCONSTRAINED, so the user
# layer may decide it — and the keys most likely to be added without thinking
# about scope are exactly the root-domain ones. Catching it here is the difference
# between "forgot a line in a TSV" and "a user file quietly overrides machine
# policy". The reverse direction (a row naming a key that no longer exists) is
# deliberately NOT enforced: `MODE` and `TERMINAL_OPTS` are declared for the
# record without living in the vendor file, and hard-coding those exceptions into
# the gate would put back the folklore the schema replaced.
chk_wconf_scopes() {
  local rc=0 sch s key scope missing
  for sch in rootfs/usr/share/w/defaults/*.schema; do
    [[ -f "$sch" ]] || continue
    s="$(basename "$sch" .schema)"
    missing=()
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      scope="$(WCONF_VENDOR_DIR=rootfs/usr/share/w/defaults \
               bash -c 'source rootfs/usr/lib/w/w-conf-lib.sh
                        WCONF_ETC=/nonexistent WCONF_HOME=/nonexistent
                        wconf_scope "$1" "$2"' _ "$s" "$key")"
      [[ -n "$scope" ]] || missing+=("$key")
    done < <(_wconf_vendor_keys "$s")
    if ((${#missing[@]})); then
      echo "  $s.schema: no scope row for: ${missing[*]}"
      rc=1
    fi
  done
  return $rc
}

chk_wconf() {
  local rc=0 f n=0 a b
  for f in $(_wconf_shipped_confs); do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    a="$(_wconf_dump_source "$f")" || { echo "  ${f##*/}: bash refused to source it"; rc=1; continue; }
    b="$(_wconf_dump_reader "$f")"
    if [[ "$a" != "$b" ]]; then
      echo "  ${f##*/}: reader disagrees with \`source\`:"
      diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/    /'
      rc=1
    fi
  done

  # Python twin (w-mcp core.py) against the bash reference, same files. Two
  # implementations of one precedence rule drift the moment nobody compares them.
  if command -v python3 &>/dev/null; then
    for f in $(_wconf_shipped_confs); do
      a="$(_wconf_dump_reader "$f")"
      b="$(_wconf_dump_python "$f")"
      if [[ "$a" != "$b" ]]; then
        echo "  ${f##*/}: python twin disagrees with the bash reader:"
        diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/    /'
        rc=1
      fi
    done
  else
    warn "python3 missing — skipped the bash↔python reader contract"
  fi

  chk_wconf_scopes || rc=1

  echo "  wconf: $n config(s) cross-checked across /etc/w + the vendor layer (source ↔ bash reader ↔ python twin), scope rows complete"
  return $rc
}

_wconf_dump_python() { # <file>
  local f="$1" tmp out
  tmp="$(mktemp -d)"
  cp "$f" "$tmp/probe.conf"
  out="$(WCONF_ETC="$tmp" WCONF_VENDOR_DIR="$tmp/none" WCONF_HOME="$tmp/nohome" \
    python3 -c '
import sys
sys.path.insert(0, "rootfs/usr/lib/w/w-mcp")
import core
for k, (v, _layer) in sorted(core.conf_read("probe").items()):
    print(f"{k}={v}")
')"
  rm -rf "$tmp"
  printf '%s\n' "$out" | sort
}
