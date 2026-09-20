# w-conf-lib.sh — W Linux layered configuration reader/writer (shared, sourced).
#
# ONE reader for every W subsystem. Before this library each script rolled its
# own: an awk KEY= scan (w-power), a bare `source` (w-term/w-time/w-dns/w-logs/
# w-crypt/w-ai), a grep|cut (w-sync) and two Python parsers (w-mcp core.py,
# diagnostics.py) — four dialects that disagreed on quoting, inline comments and
# duplicate keys. See update-system.md ("Рефакторинг Edge → трёхслойный конфиг").
#
# ── The two orthogonal axes ───────────────────────────────────────────────────
# PRIORITY (who wins on read) is what this file implements. OWNERSHIP (what an
# update does to a file) stays declared in the ownership manifests
# (/usr/share/w/update/<module>.manifest, class managed|override|user) and is
# enforced by apply_rootfs. Never conflate them: a layer is not a class.
#
# ── Layers, low → high priority ───────────────────────────────────────────────
#   vendor        /usr/share/w/defaults/<s>.conf     W's own defaults; the update
#                                                    OVERWRITES it (no admin edits
#                                                    live there) — phase 2+
#   site-default  /etc/w/site-defaults.d/<s>.conf    fleet ADVICE: below the local
#                                                    admin, so locality still holds
#   system        /etc/w/<s>.conf                    the local admin (root, w-* setters,
#                                                    Hub/AI through polkit)
#   user          ~/.config/w/<s>.conf               the logged-in user
#   user-features ~/.config/w/ai-features.conf       ai only: survives `w-ai profile
#                                                    use`, which rewrites the user file
#   policy        /etc/w/policy.d/<s>.conf           fleet MANDATE: above everything and
#                                                    LOCKS the key (setters must refuse,
#                                                    not silently write a shadowed value)
#
# Every layer also reads `<file>.d/*.conf` (lexicographic, later file wins), so
# growing a layer into drop-ins is never a breaking change. The site/policy roots
# and the vendor dir are read from day one; they simply do not exist yet, so the
# effective behaviour is today's two-layer system → user until phases 2/5 ship
# files into them.
#
# ── Scope: which keys a user may override ────────────────────────────────────
# Priority alone would let ~/.config/w/power.conf decide the battery charge limit
# or the lid action — root-domain policy that has never been the user's to set.
# Which keys the user layer may speak to is therefore DECLARED, not folklore
# inside each script (w-power's "idle timers yes, lid no" lived only in its head):
#
#   /usr/share/w/defaults/<subsys>.schema   TSV: <KEY> \t system|user|both [\t enum]
#
# A user-layer assignment to a `system`-scope key is dropped during the load with
# a warning — enforced HERE so every consumer (w-* scripts, Hub, AI tools, w-conf)
# obeys the same declaration without repeating it. Keys with no schema row are
# unconstrained: a subsystem that has not been split yet behaves exactly as before.
#
# ── Parsing contract ──────────────────────────────────────────────────────────
# Vendor files are gated strictly by check.sh (every key carries a schema row and
# a `source`-vs-parser equivalence check). Admin/user files are parsed LENIENTLY:
# a line that is not KEY=value is ignored with a warning instead of breaking the
# whole subsystem — one shell flourish by an admin must not blind w-power.
#   • split on the FIRST '='; keys match [A-Za-z_][A-Za-z0-9_]*
#   • "…" / '…' take the quoted string (a '#' inside it is data)
#   • otherwise a '#' PRECEDED BY WHITESPACE starts a comment — bash's own rule,
#     so `MODEL=gpt#4` keeps its hash while `KEY=v   # note` does not
#   • surrounding whitespace is stripped; the LAST assignment in a file wins
#   • values are single-line by contract. A shell array (TERMINAL_OPTS=(…)) is
#     kept verbatim as "(…)" — w-term still `source`s that one key on purpose.
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   source /usr/lib/w/w-conf-lib.sh
#   wconf_load power                     # one pass over every layer
#   wconf_get power CHARGE_LIMIT 100     # default applies only if the key is ABSENT
#   wconf_origin power CHARGE_LIMIT      # → system | user | vendor | policy | …
#   wconf_set power CHARGE_LIMIT 80      # atomic; refuses a policy-locked key
# Callers that run as root for another user (pkexec, mod_power) set WCONF_HOME to
# that user's home BEFORE loading, so the user layer resolves to the right file.
#
# Seams for the test suite (never set in production): WCONF_ETC, WCONF_VENDOR_DIR,
# WCONF_HOME.

# Idempotent: sourcing twice must not wipe an already-populated cache.
if [[ -z "${WCONF_LIB_LOADED:-}" ]]; then
  WCONF_LIB_LOADED=1

  # -g: this file is routinely sourced from inside a function (apply modules, w-*
  # subcommands), where a bare `declare -A` would create a LOCAL array that
  # vanishes on return.
  # The `=()` is not decoration: `declare -a foo` alone leaves the variable
  # DECLARED BUT UNSET, so the first `${#foo[@]}` under `set -u` (which every W
  # script runs) aborts with "unbound variable". Assigning empty makes it set.
  declare -gA WCONF=()          # "<subsys>/<KEY>" → effective value
  declare -gA WCONF_ORIGIN=()   # "<subsys>/<KEY>" → winning layer name
  declare -gA WCONF_FILE=()     # "<subsys>/<KEY>" → winning file
  declare -gA WCONF_LAYERED=()  # "<subsys>/<layer>/<KEY>" → that layer's own value
  declare -gA WCONF_LOCKED=()   # "<subsys>/<KEY>" → 1 when set by the policy layer
  declare -gA WCONF_LOADED=()   # "<subsys>" → 1
  declare -gA WCONF_SCOPE=()    # "<subsys>/<KEY>" → system | user | both
  declare -ga WCONF_WARN=()     # "file:line: …" notes from the lenient parser
fi

WCONF_ETC="${WCONF_ETC:-/etc/w}"
WCONF_VENDOR_DIR="${WCONF_VENDOR_DIR:-/usr/share/w/defaults}"

# Subsystems that ship a config today — used to enumerate, never to restrict:
# an unknown name resolves through the same layer convention.
WCONF_SUBSYS=(ai crypt dns fingerprint kbdlight logs mirrors nightlight power ssh terminal time update)

# ── Whose user layer are we acting on? ───────────────────────────────────────
# Every W subsystem that renders into a home has to answer this, and until now
# each answered it alone: three copies of `awk '$3>=1000 … exit'` (w-power,
# w-nightlight, w-monitor) plus one in w-conf, all hardcoding /home/$user and
# none of them asking who actually invoked the command. Two bugs came out of
# that, both real: an update rendered for exactly ONE account (a second user's
# idle policy froze at the /etc/skel copy their account was created with), and a
# second user editing their own idle timer through the Hub wrote into the FIRST
# user's ~/.config/w/power.conf, because pkexec's invoker was never consulted.
#
# The order below is the whole contract:
#   explicit name  — a module iterating w_home_users, or `--user` on the CLI
#   the invoker    — SUDO_USER, then PKEXEC_UID (the Hub's path; pkexec sets no
#                    SUDO_USER, which is exactly how that bug hid)
#   first account  — LAST resort, and only meaningful at firstboot, where there
#                    is no invoker and exactly one account exists
# Home comes from getent, never from /home/<user>: a home that lives elsewhere
# would otherwise be silently created under /home by the first `install -d`.
#
# Sets WCONF_TARGET_USER / WCONF_TARGET_HOME and exports WCONF_HOME, so the user
# layer resolves to that account for every read and write that follows. Call it
# BEFORE wconf_load — the load pass caches per subsystem.
#
# Exit codes mirror w-pack's resolve_user (the precedent this generalises):
#   0  resolved
#   1  nothing to resolve (no human account at all) — silent, the caller decides
#   2  refused, reason already on stderr — the caller must not add noise
# Test seams (never set in production): W_PASSWD — the passwd file, the same seam
# lib/deploy.sh uses; W_EUID — the effective uid, because bash makes EUID readonly
# and the whole interesting half of this function is the root branch.
WCONF_TARGET_USER=""; WCONF_TARGET_HOME=""
wconf_resolve_target() { # [<name>]
  local u="${1:-}" self euid="${W_EUID:-$EUID}"; self="$(id -un)"
  if [[ -z "$u" ]]; then
    if [[ $euid -ne 0 ]]; then u="$self"
    elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then u="$SUDO_USER"
    elif [[ -n "${PKEXEC_UID:-}" ]]; then
      local ent=""
      ent="$(getent passwd "$PKEXEC_UID" 2>/dev/null)" && u="${ent%%:*}"
    fi
    # Still nothing: firstboot, a system unit, or root in a bare shell.
    [[ -n "$u" ]] || u="$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false|sync)$/ {print $1; exit}' \
      "${W_PASSWD:-/etc/passwd}")"
  fi
  [[ -n "$u" ]] || return 1
  # Acting on someone else's home is root's call to make.
  if [[ $euid -ne 0 && "$u" != "$self" ]]; then
    echo "acting on $u's account requires root" >&2; return 2
  fi
  # NOT `home="$(getent … | cut …)"`: under pipefail an unknown user fails the
  # whole substitution and `set -e` kills the caller before the message prints.
  local ent="" home=""
  if ent="$(getent passwd "$u" 2>/dev/null)"; then home="$(cut -d: -f6 <<<"$ent")"; fi
  [[ -n "$home" && "$home" != / ]] || { echo "no usable home for user: $u" >&2; return 2; }
  WCONF_TARGET_USER="$u"; WCONF_TARGET_HOME="$home"
  export WCONF_HOME="$home"
}

# ── Layer resolution ─────────────────────────────────────────────────────────
# The user-scope root. An explicitly passed WCONF_HOME wins over XDG_CONFIG_HOME:
# root acting for a user (pkexec, mod_power) carries root's own XDG vars, which
# would otherwise point the user layer at /root.
#
# HOME is resolved, never assumed: a systemd SYSTEM unit runs without it (systemd
# only exports HOME for units with User=), and every consumer of this library runs
# `set -u`, so a bare $HOME aborted the first firstboot that reached `apply --dns`
# — a fresh install died at DNS with "HOME: unbound variable" (caught by the
# release gate, 2026-08-06). Falling back to passwd rather than to a placeholder is
# deliberate: root running w-dns from w-firstboot must resolve the same user layer
# as root running it from a shell, or the reader would answer differently depending
# on who started it — the exact class of bug the one-reader rule exists to kill.
_wconf_user_dir() {
  if [[ -n "${WCONF_HOME:-}" ]]; then printf '%s/.config/w' "$WCONF_HOME"; return 0; fi
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then printf '%s/w' "$XDG_CONFIG_HOME"; return 0; fi
  local home="${HOME:-}"
  # `|| true` because callers run pipefail: a failing getent must yield an empty
  # home, not abort the subsystem that merely asked where its config lives.
  [[ -n "$home" ]] || home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
  printf '%s/.config/w' "${home:-/nonexistent}"
}

# Print "<layer>\t<base file>" per line, low → high priority.
wconf_layer_table() { # <subsys>
  local s="$1" udir; udir="$(_wconf_user_dir)"
  printf 'vendor\t%s\n'        "$WCONF_VENDOR_DIR/$s.conf"
  printf 'site-default\t%s\n'  "$WCONF_ETC/site-defaults.d/$s.conf"
  printf 'system\t%s\n'        "$WCONF_ETC/$s.conf"
  printf 'user\t%s\n'          "$udir/$s.conf"
  # ai keeps its feature toggles in a second user file on purpose: `w-ai profile
  # use` rewrites ~/.config/w/ai.conf wholesale, and W_AI_EMBED & friends must
  # survive a profile switch (ai-integration.md §8).
  [[ "$s" == ai ]] && printf 'user-features\t%s\n' "$udir/ai-features.conf"
  printf 'policy\t%s\n'        "$WCONF_ETC/policy.d/$s.conf"
  return 0
}

# Every file of one layer: the base file, then its .d/*.conf in lexicographic
# order. Missing paths are simply skipped.
_wconf_layer_files() { # <base file>
  local base="$1" f
  [[ -f "$base" ]] && printf '%s\n' "$base"
  if [[ -d "$base.d" ]]; then
    for f in "$base.d"/*.conf; do
      [[ -f "$f" ]] && printf '%s\n' "$f"
    done
  fi
  return 0
}

# ── Parser ───────────────────────────────────────────────────────────────────
# Sets _WCONF_V instead of echoing: this runs per key, and a command
# substitution per line would fork on every read (w-power renders hypridle on
# every AC/battery flip).
_wconf_scalar() { # <raw value>
  local v="$1"
  case "$v" in
    '"'*)  v="${v#\"}";  v="${v%%\"*}" ;;
    "'"*)  v="${v#\'}";  v="${v%%\'*}" ;;
    *)     v="${v%%[[:space:]]#*}" ;;   # first whitespace-preceded '#' = comment
  esac
  v="${v#"${v%%[![:space:]]*}"}"        # ltrim
  v="${v%"${v##*[![:space:]]}"}"        # rtrim
  _WCONF_V="$v"
}

# Declared scope of one key → _WCONF_SC (a variable, not an echo: this runs per
# key of every layer). An exact row wins; otherwise a GLOB row covers a family of
# keys — `DNS_*`, `NTP_*` are catalogs, i.e. data the admin extends, and enumerating
# every entry would mean editing the schema each time one is added, which is
# exactly the drift the schema exists to remove.
_wconf_key_scope() { # <subsys> <key>
  local s="$1" k="$2" e
  _WCONF_SC="${WCONF_SCOPE["$s/$k"]:-}"
  [[ -n "$_WCONF_SC" ]] && return 0
  for e in "${!WCONF_SCOPE[@]}"; do
    [[ "$e" == "$s/"*'*' ]] || continue
    # shellcheck disable=SC2053   # RHS is a pattern on purpose
    if [[ "$k" == ${e#"$s/"} ]]; then _WCONF_SC="${WCONF_SCOPE[$e]}"; return 0; fi
  done
  return 0
}

_wconf_read_file() { # <subsys> <layer> <file>
  local s="$1" lay="$2" f="$3" line key n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == '#'* ]] && continue
    if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      WCONF_WARN+=("$f:$n: ignored (not KEY=value): ${line:0:48}")
      continue
    fi
    key="${BASH_REMATCH[1]}"
    _wconf_scalar "${BASH_REMATCH[2]}"
    # Scope enforcement: a user-scope file may not decide root-domain policy.
    # The value is still recorded in the LAYERED map (so `w-conf cat` can explain
    # the refusal instead of the key vanishing) but never wins the effective one.
    _wconf_key_scope "$s" "$key"
    if [[ "$lay" == user || "$lay" == user-features ]] && [[ "$_WCONF_SC" == system ]]; then
      WCONF_WARN+=("$f: $key is system-scope — ignoring the user-layer value")
      WCONF_LAYERED["$s/$lay/$key"]="$_WCONF_V"
      continue
    fi
    WCONF["$s/$key"]="$_WCONF_V"
    WCONF_ORIGIN["$s/$key"]="$lay"
    WCONF_FILE["$s/$key"]="$f"
    WCONF_LAYERED["$s/$lay/$key"]="$_WCONF_V"
    if [[ "$lay" == policy ]]; then WCONF_LOCKED["$s/$key"]=1; fi
  done < "$f"
  return 0
}

# Scope declarations for one subsystem, if it ships a schema. Absent schema =
# every key unconstrained (the pre-split status quo).
_wconf_read_schema() { # <subsys>
  local s="$1" key scope rest n=0
  local f="$WCONF_VENDOR_DIR/$s.schema"
  [[ -f "$f" ]] || return 0
  # Rows are stored verbatim, glob and all; _wconf_key_scope resolves them.
  while IFS=$'\t' read -r key scope rest || [[ -n "$key" ]]; do
    n=$((n + 1))
    [[ -z "$key" || "$key" == '#'* ]] && continue
    case "$scope" in
      system|user|both) WCONF_SCOPE["$s/$key"]="$scope" ;;
      *) WCONF_WARN+=("$f:$n: unknown scope '${scope}' for $key (system|user|both)") ;;
    esac
  done < "$f"
  return 0
}

# One pass over every layer of one subsystem. Cached; wconf_reload after a write.
wconf_load() { # <subsys>
  local s="$1" lay base f
  [[ -n "${WCONF_LOADED[$s]:-}" ]] && return 0
  # Schema first: the layer loop consults it to refuse out-of-scope user values.
  _wconf_read_schema "$s"
  while IFS=$'\t' read -r lay base; do
    while IFS= read -r f; do
      [[ -n "$f" ]] && _wconf_read_file "$s" "$lay" "$f"
    done < <(_wconf_layer_files "$base")
  done < <(wconf_layer_table "$s")
  WCONF_LOADED[$s]=1
  return 0
}

wconf_reload() { # <subsys>
  local s="$1" k
  for k in "${!WCONF[@]}"; do
    [[ "$k" == "$s/"* ]] || continue
    unset "WCONF[$k]" "WCONF_ORIGIN[$k]" "WCONF_FILE[$k]" "WCONF_LOCKED[$k]"
  done
  for k in "${!WCONF_LAYERED[@]}"; do
    [[ "$k" == "$s/"* ]] && unset "WCONF_LAYERED[$k]"
  done
  unset "WCONF_LOADED[$s]"
  wconf_load "$s"
}

# ── Read API ─────────────────────────────────────────────────────────────────
# The default applies only when the key is ABSENT from every layer; a key
# declared empty stays empty (callers that want otherwise use ${v:-fallback},
# exactly as they do today).
wconf_get() { # <subsys> <key> [default]
  local s="$1" k="$2"
  wconf_load "$s"
  if [[ -n "${WCONF["$s/$k"]+x}" ]]; then printf '%s\n' "${WCONF["$s/$k"]}"
  else printf '%s\n' "${3:-}"; fi
}

wconf_has()    { wconf_load "$1"; [[ -n "${WCONF["$1/$2"]+x}" ]]; }

# Value as defined by ONE layer, ignoring the others. This is what a subsystem
# uses while it still owns a single file: /etc/w/<s>.conf is today both the
# vendor default and the admin state, so "effective" and "what the admin file
# says" are the same thing — but only until phase 2 splits them. Reading a
# specific layer keeps a migration honest (no accidental new precedence), and
# each subsystem switches to wconf_get when its own split lands.
wconf_layer_get() { # <subsys> <layer> <key> [default]
  local s="$1" lay="$2" k="$3"
  wconf_load "$s"
  if [[ -n "${WCONF_LAYERED["$s/$lay/$k"]+x}" ]]; then printf '%s\n' "${WCONF_LAYERED["$s/$lay/$k"]}"
  else printf '%s\n' "${4:-}"; fi
}
wconf_layer_has() { wconf_load "$1"; [[ -n "${WCONF_LAYERED["$1/$2/$3"]+x}" ]]; }

# Keys defined by ONE layer, sorted (w-time's NTP_* catalog lives in exactly one
# file today).
wconf_layer_keys() { # <subsys> <layer> [prefix]
  local s="$1" lay="$2" pre="${3:-}" k
  wconf_load "$s"
  for k in "${!WCONF_LAYERED[@]}"; do
    [[ "$k" == "$s/$lay/"* ]] || continue
    k="${k#"$s/$lay/"}"
    [[ -z "$pre" || "$k" == "$pre"* ]] && printf '%s\n' "$k"
  done | sort
}
wconf_origin() { wconf_load "$1"; printf '%s\n' "${WCONF_ORIGIN["$1/$2"]:-}"; }
wconf_path()   { wconf_load "$1"; printf '%s\n' "${WCONF_FILE["$1/$2"]:-}"; }
wconf_locked() { wconf_load "$1"; [[ -n "${WCONF_LOCKED["$1/$2"]:-}" ]]; }

# Declared scope of one key: system | user | both, or empty when the schema says
# nothing (unconstrained). This is what lets a FRONT-END stop hard-coding which
# knob needs root: the Hub routes a `system` key through polkit and a user/both
# key straight to the CLI, and the AI tools refuse before prompting, all reading
# the same declaration the loader enforces.
wconf_scope() { # <subsys> <key>
  wconf_load "$1"; _wconf_key_scope "$1" "$2"; printf '%s\n' "$_WCONF_SC"
}

# Every declared row of one subsystem: KEY\tscope, sorted (glob rows included, so
# `w-conf scope dns` shows the catalog rule rather than hiding it).
wconf_scopes() { # <subsys>
  local s="$1" k
  wconf_load "$s"
  for k in "${!WCONF_SCOPE[@]}"; do
    [[ "$k" == "$s/"* ]] || continue
    printf '%s\t%s\n' "${k#"$s/"}" "${WCONF_SCOPE[$k]}"
  done | sort
}

# Effective key names, sorted, optionally filtered by prefix (w-time's NTP_*
# catalog is exactly this: vendor entries plus whatever the admin added).
wconf_keys() { # <subsys> [prefix]
  local s="$1" pre="${2:-}" k
  wconf_load "$s"
  for k in "${!WCONF[@]}"; do
    [[ "$k" == "$s/"* ]] || continue
    k="${k#"$s/"}"
    [[ -z "$pre" || "$k" == "$pre"* ]] && printf '%s\n' "$k"
  done | sort
}

wconf_list() { # <subsys> [prefix]   → KEY=VALUE
  local s="$1" k
  # Load HERE, not only inside wconf_keys: that call sits in a process
  # substitution, i.e. a subshell whose populated arrays never reach us.
  wconf_load "$s"
  while IFS= read -r k; do
    printf '%s=%s\n' "$k" "${WCONF["$s/$k"]}"
  done < <(wconf_keys "$s" "${2:-}")
}

# KEY\tVALUE\tLAYER\tlocked?\tSCOPE — the stable machine-readable view (Hub, AI).
# SCOPE was appended, never inserted: a consumer that splits on TAB and reads
# fields 0..3 keeps working untouched.
wconf_list_porcelain() { # <subsys> [prefix]
  local s="$1" k
  wconf_load "$s"
  while IFS= read -r k; do
    _wconf_key_scope "$s" "$k"
    printf '%s\t%s\t%s\t%s\t%s\n' "$k" "${WCONF["$s/$k"]}" "${WCONF_ORIGIN["$s/$k"]}" \
      "${WCONF_LOCKED["$s/$k"]:+locked}" "$_WCONF_SC"
  done < <(wconf_keys "$s" "${2:-}")
}

# ── Write API ────────────────────────────────────────────────────────────────
# Three layers are writable by W's own tooling: `system` (root: w-* setters,
# Hub/AI via polkit), `user`, and `user-features` (ai only — `w-ai features set`;
# it is a second user file precisely so it survives `w-ai profile use` rewriting
# the first). vendor is the update's to own, site-default and policy belong to the
# fleet overlay — writing them locally would be a lie.
#
# The path itself comes from wconf_layer_table, so the writable layers cannot
# drift from the ones the reader knows: this function only decides WHICH layers
# may be written, never where they live.
_wconf_target_file() { # <subsys> <layer>
  case "$2" in system|user|user-features) ;; *) return 1 ;; esac
  local lay base
  while IFS=$'\t' read -r lay base; do
    [[ "$lay" == "$2" ]] && { printf '%s\n' "$base"; return 0; }
  done < <(wconf_layer_table "$1")
  return 1   # layer not offered by this subsystem (user-features on non-ai)
}

# File mode a freshly created layer file gets; an existing file keeps its own.
# Only the system layer is world-readable — a user's config is their own.
_wconf_layer_mode() { case "$1" in system) printf 644 ;; *) printf 600 ;; esac; }

# Atomic and mode-preserving. mktemp lands 0600 in the target's own directory
# (same filesystem → mv is atomic); an existing file keeps its mode, a new one
# gets 0644 (system) / 0600 (user). Missing this cost us once already — packs.json
# stayed 0600 after a mktemp+mv and the user-scope tools silently read nothing.
_wconf_write_atomic() { # <file> <default mode> <payload on stdin>
  local dst="$1" defmode="$2" dir tmp mode owner
  dir="$(dirname "$dst")"
  tmp="$(mktemp "$dir/.w-conf.XXXXXX")" || return 1
  cat > "$tmp"
  if [[ -f "$dst" ]]; then
    mode="$(stat -c '%a' "$dst" 2>/dev/null || echo "$defmode")"
    owner="$(stat -c '%u:%g' "$dst" 2>/dev/null || true)"
  else
    mode="$defmode"
    # A fresh user-layer file written by root (pkexec/mod_power) must belong to
    # the user, not to root — otherwise the desktop can never write it again.
    owner="$(stat -c '%u:%g' "$dir" 2>/dev/null || true)"
  fi
  chmod "$mode" "$tmp"
  if [[ $EUID -eq 0 && -n "$owner" ]]; then chown "$owner" "$tmp" 2>/dev/null || true; fi
  mv -f "$tmp" "$dst"
}

# Replace KEY's value in place (preserving any trailing comment — the shipped
# vendor files carry one per key) or append the assignment when absent: a config
# seeded before a key existed must still take a setter.
wconf_set() { # <subsys> <key> <value> [layer=system]
  local s="$1" k="$2" v="$3" lay="${4:-system}" dst dir
  [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "w-conf: invalid key: $k" >&2; return 1; }
  [[ "$v" != *$'\n'* ]] || { echo "w-conf: values are single-line: $k" >&2; return 1; }
  dst="$(_wconf_target_file "$s" "$lay")" || {
    echo "w-conf: layer '$lay' is not writable here (system|user|user-features)" >&2; return 1; }

  # Fleet policy is a MANDATE, not a preference: writing a shadowed value would
  # report success and change nothing, which is the worst possible outcome. The
  # check is live from day one; it only ever fires once a fleet ships policy.d.
  if wconf_locked "$s" "$k"; then
    echo "w-conf: $k is locked by site policy (${WCONF_FILE["$s/$k"]}) — not written" >&2
    return 1
  fi

  # Same rule, other source of shadowing: the loader DROPS a user-layer value for
  # a system-scope key, so writing one would also succeed and change nothing. The
  # schema has to bind the write side, not just the read side — otherwise every
  # front-end has to remember which keys are root-domain, which is exactly the
  # folklore it replaced.
  _wconf_key_scope "$s" "$k"
  if [[ "$lay" == user || "$lay" == user-features ]] && [[ "$_WCONF_SC" == system ]]; then
    echo "w-conf: $k is system-scope ($s.schema) — the user layer may not set it" >&2
    return 1
  fi

  local mode; mode="$(_wconf_layer_mode "$lay")"
  dir="$(dirname "$dst")"
  if [[ "$lay" == system ]]; then install -d -m755 "$dir"; else install -d -m700 "$dir"; fi
  if [[ -f "$dst" ]] && grep -qE "^[[:space:]]*${k}=" "$dst"; then
    KEY="$k" VAL="$v" awk '
      BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"] }
      $0 ~ "^[ \t]*" k "=" {
        # Keep the trailing "# …" annotation that documents the key, INCLUDING
        # its leading run of spaces: the shipped vendor files align those into a
        # column, and a setter has no business reflowing the file it touches.
        c = ""; if (match($0, /[ \t]+#.*$/)) c = substr($0, RSTART)
        print k "=" v c; next
      }
      { print }
    ' "$dst" | _wconf_write_atomic "$dst" "$mode"
  else
    { [[ -f "$dst" ]] && cat "$dst"; printf '%s=%s\n' "$k" "$v"; } \
      | _wconf_write_atomic "$dst" "$mode"
  fi
  wconf_reload "$s"
}

# ── One-shot migration to the split layout ───────────────────────────────────
# An installed machine's /etc/w/<s>.conf is a full copy of the vendor file with a
# couple of real edits in it. Left alone it pins every one of those values forever
# (the update preserves this file by ownership class), so improved defaults would
# still never arrive — the very bug the split exists to kill. So: drop the keys
# that merely repeat the vendor default and keep the rest.
#
# Baseline choice matters. Preferred is the PRE-SPLIT vendor copy staged by
# mod_reset (/usr/share/w/vendor/etc-w/<s>.conf) — that is the file this machine's
# admin state was derived from. The freshly shipped vendor layer is the fallback;
# it is honest only if the release that splits a subsystem does not also change
# its defaults (do not do that — a changed default would read as a deviation and
# get pinned, silently, forever).
#
# Anything we cannot explain stays. The failure mode is "kept a redundant line",
# never "lost a setting". Subsystems whose vendor layer is GENERATED from code
# (power) pass their own baseline getter instead — see w-power's migrate.
wconf_migrate() { # <subsys> [baseline-file]
  local s="$1" base_file="${2:-}"
  local mark="/var/lib/w/${s}.migrated"
  [[ -e "$mark" ]] && return 0
  local admin; admin="$(_wconf_target_file "$s" system)" || return 1
  if [[ ! -f "$admin" ]]; then
    install -d -m755 /var/lib/w; : > "$mark"; return 0
  fi
  if [[ -z "$base_file" ]]; then
    base_file="/usr/share/w/vendor/etc-w/$s.conf"
    [[ -f "$base_file" ]] || base_file="$WCONF_VENDOR_DIR/$s.conf"
  fi
  if [[ ! -f "$base_file" ]]; then
    # No baseline at all: keep the file as a full override and say so, rather
    # than guessing. The machine stays exactly as it is today; it just will not
    # receive new vendor keys until someone resolves this.
    echo "w-conf: no baseline for $s — $admin left as a full override (new vendor keys will not arrive)" >&2
    return 0
  fi

  local line key val bval dropped=0 kept=0 out
  out="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      printf '%s\n' "$line" >> "$out"; continue     # comments/blanks are kept
    fi
    key="${BASH_REMATCH[1]}"
    _wconf_scalar "${BASH_REMATCH[2]}"; val="$_WCONF_V"
    # Presence matters, not just the value: several vendor keys are legitimately
    # EMPTY (MAX_SIZE=, MODEL=, MCP_PROFILE=…), and treating "empty" as "no
    # baseline" would keep every one of them as a fake deviation forever.
    bval="$(_wconf_file_get "$base_file" "$key")"
    if _wconf_file_has "$base_file" "$key" && [[ "$val" == "$bval" ]]; then
      dropped=$((dropped + 1))
    else
      printf '%s\n' "$line" >> "$out"; kept=$((kept + 1))
    fi
  done < "$admin"

  install -d -m755 /var/lib/w/reset-backups
  cp -a "$admin" "/var/lib/w/reset-backups/$(basename "$admin").pre-split.$(date +%Y%m%d%H%M%S)"
  cat "$out" > "$admin"; rm -f "$out"
  install -d -m755 /var/lib/w; : > "$mark"
  wconf_reload "$s"
  if [[ "$dropped" -gt 0 ]]; then
    echo "w-conf: migrated $admin to the split layout — dropped $dropped key(s) identical to the W default (they follow the vendor layer now), kept $kept."
  fi
}

# One key straight out of ONE file, bypassing the layer stack (migration baselines).
_wconf_file_get() { # <file> <key>
  local f="$1" k="$2" line out=""
  [[ -r "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == "$k="* ]] || continue
    _wconf_scalar "${line#*=}"; out="$_WCONF_V"
  done < "$f"
  printf '%s' "$out"
}

# Does that file assign the key at all (regardless of the value being empty)?
_wconf_file_has() { # <file> <key>
  local f="$1" k="$2" line
  [[ -r "$f" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == "$k="* ]] && return 0
  done < "$f"
  return 1
}

# Drop a key from one layer (the effective value falls back to the layer below —
# this is the new w-reset semantics: "as on a fresh install", not "copy vendor
# over").
wconf_unset() { # <subsys> <key> [layer=system]
  local s="$1" k="$2" lay="${3:-system}" dst
  dst="$(_wconf_target_file "$s" "$lay")" || {
    echo "w-conf: layer '$lay' is not writable here (system|user|user-features)" >&2; return 1; }
  [[ -f "$dst" ]] || return 0
  KEY="$k" awk 'BEGIN { k = ENVIRON["KEY"] } $0 ~ "^[ \t]*" k "=" { next } { print }' "$dst" \
    | _wconf_write_atomic "$dst" "$(_wconf_layer_mode "$lay")"
  wconf_reload "$s"
}
