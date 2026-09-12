# tui.sh — i18n, navigation-aware dialog widgets, and the config-driven wizard.
#
# Depends on ui.sh (DIALOG_BACKTITLE, DIALOG_COMMON, DIALOGRC). The wizard is
# stateless per screen: it keeps a step index plus an ANSWERS[] map and drives
# steps.conf, so options are declared, not hard-coded (see steps.conf).

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
I18N_DIR="$TUI_DIR/../i18n"
STEPS_FILE="$TUI_DIR/../steps.conf"

# ── i18n ──────────────────────────────────────────────────────────────────────
# -g: a no-op when sourced at top level (install.sh / w-firstboot), but keeps
# these global when the file is sourced from inside a function (bats setup()) —
# a plain `declare` there would silently make them function-local.
declare -gA MSG         # active language dictionary
LANG_CODE=""            # e.g. en / ru

# t <key> → localized string (falls back to the raw key if missing).
t() { printf '%s' "${MSG[$1]:-$1}"; }

# Parse a `key=value` file into a named assoc array (value = rest of line).
_parse_conf() {
  local file="$1"; local -n dest="$2"; local k v line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"; v="${line#*=}"
    k="${k//[[:space:]]/}"
    [[ -n "$k" ]] && dest["$k"]="$v"
  done < "$file"
}

i18n_load() {
  LANG_CODE="$1"
  MSG=()
  _parse_conf "$I18N_DIR/$LANG_CODE.conf" MSG
}

# Discover available languages → "code _lang_name code _lang_name …".
i18n_langs() {
  local f code name; local -A one
  for f in "$I18N_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    code="$(basename "$f" .conf)"
    one=(); _parse_conf "$f" one
    name="${one[_lang_name]:-$code}"
    printf '%s\t%s\n' "$code" "$name"
  done
}

# ── Navigation button set (labels depend on the loaded language) ──────────────
DIALOG_NAV=()
nav_init() {
  # Rebuild the shared button labels in the chosen language (dialog's built-in
  # Yes/No/OK are English otherwise). Idempotent — safe to re-run on relanguage.
  DIALOG_COMMON=(--backtitle "$DIALOG_BACKTITLE" --colors --no-cancel
    --ok-label "$(t ok)" --yes-label "$(t yes)" --no-label "$(t no)")
  DIALOG_NAV=(--backtitle "$DIALOG_BACKTITLE" --colors
    --ok-label "$(t next)" --extra-button --extra-label "$(t back)"
    --cancel-label "$(t quit)")
}
# Widget exit convention: 0 = forward (OK), 3 = back, 1 = quit/cancel.

# ── Navigation-aware widgets (result in $UI_RESULT) ───────────────────────────
UI_INPUT_W=64                    # every input step is this wide, for a uniform look
UI_INPUT_TEXT_W=$((UI_INPUT_W - 4))   # minus the frame and its one-column margin

# Rows an --inputbox needs for the prompt, the field AND the buttons, with the
# same breathing room every other step has. dialog spends nine rows on furniture —
# two borders, the leading blank line, the three-row input widget, the blank below
# it, the separator and the button row — and gives the prompt whatever is left.
#
# Critically, it does NOT grow the box to fit. It degrades, silently and in stages:
# first the blank line under the field disappears, then the field is drawn ON the
# separator with its own text overwritten by the frame, and finally the button row
# is pushed out of the window entirely. The hard-coded 10 that used to be here did
# all three to the edge-repo step, whose prompt wraps to five lines — the step
# looked deliberately button-less rather than broken.
#
# LC_ALL is pinned so `fold` counts characters, not bytes: the wizard runs before
# the locale is settled, and a Cyrillic prompt measured in bytes reads as twice its
# real length.
_w_input_rows() { # <prompt> → rows
  local n
  n=$(printf '%s\n' "$1" | LC_ALL=C.UTF-8 fold -s -w "$UI_INPUT_TEXT_W" | wc -l)
  (( n < 1 )) && n=1
  n=$((n + 9))
  (( n < 10 )) && n=10           # one-line prompts keep exactly the old proportions
  (( n > 20 )) && n=20           # never taller than the smallest console we target
  printf '%s' "$n"
}

# w_input <title> <prompt> <default>
w_input() {
  local rc=0 h
  h=$(_w_input_rows "$2")
  UI_RESULT=$(dialog "${DIALOG_NAV[@]}" --title " $1 " \
    --inputbox "\n$2" "$h" "$UI_INPUT_W" "$3" 3>&1 1>&2 2>&3) || rc=$?
  return "$rc"
}

# w_menu <title> <prompt> <default> <item1> <desc1> …
w_menu() {
  local title="$1" prompt="$2" def="$3"; shift 3
  local rc=0
  UI_RESULT=$(dialog "${DIALOG_NAV[@]}" --default-item "$def" --title " $title " \
    --menu "\n$prompt" 20 72 12 "$@" 3>&1 1>&2 2>&3) || rc=$?
  return "$rc"
}

# w_checklist <title> <prompt> <selected> <tag1> <desc1> … → UI_RESULT="tag tag …"
# `selected` is a space-separated set of pre-checked tags (so Back re-entry keeps
# the prior picks). Descriptions may contain spaces — items arrive as tag/desc
# pairs and we attach the on/off state here. dialog prints the chosen tags,
# space-separated, on OK.
w_checklist() {
  local title="$1" prompt="$2" selected="$3"; shift 3
  local args=() tag desc st
  while (( $# >= 2 )); do
    tag="$1"; desc="$2"; shift 2
    st=off
    [[ " $selected " == *" $tag "* ]] && st=on
    args+=("$tag" "$desc" "$st")
  done
  local rc=0
  UI_RESULT=$(dialog "${DIALOG_NAV[@]}" --title " $title " \
    --checklist "\n$prompt" 20 72 12 "${args[@]}" 3>&1 1>&2 2>&3) || rc=$?
  return "$rc"
}

# w_timezone <title> <search-prompt> <default> <zone1> <offset1> …
# Search-then-pick: an inputbox filters the (zone, offset) pairs by substring
# on the zone name, then a --menu shows the matches ("+03:00" as description).
# Back on the search box bubbles straight out (→ previous wizard step); Back on
# the results menu returns to the search box instead (refine, keyword kept) —
# `dialog` has no live/incremental filtering, so this two-step loop is the
# closest equivalent a single-call TUI widget can offer.
w_timezone() {
  local title="$1" prompt="$2" def="$3"; shift 3
  local all_tags=() all_descs=()
  while (( $# >= 2 )); do all_tags+=("$1"); all_descs+=("$2"); shift 2; done
  local n=${#all_tags[@]} kw="" rc i
  while true; do
    rc=0
    kw=$(dialog "${DIALOG_NAV[@]}" --title " $title " \
      --inputbox "\n$prompt" "$(_w_input_rows "$prompt")" "$UI_INPUT_W" "$kw" \
      3>&1 1>&2 2>&3) || rc=$?
    (( rc == 0 )) || return "$rc"
    local margs=() matched=0
    for ((i = 0; i < n; i++)); do
      if [[ -z "$kw" || "${all_tags[$i],,}" == *"${kw,,}"* ]]; then
        margs+=("${all_tags[$i]}" "${all_descs[$i]}")
        matched=$((matched + 1))
      fi
    done
    if (( matched == 0 )); then
      w_error "$(t err_tz_nomatch)"
      continue
    fi
    rc=0
    UI_RESULT=$(dialog "${DIALOG_NAV[@]}" --default-item "$def" --title " $title " \
      --menu "\n$(t s_tz_pick_prompt)" 20 72 12 "${margs[@]}" 3>&1 1>&2 2>&3) || rc=$?
    case $rc in
      0) return 0 ;;
      3) continue ;;
      *) return "$rc" ;;
    esac
  done
}

# w_yesno <title> <prompt> → UI_RESULT=yes|no, rc 0 (answered) / 3 (back)
w_yesno() {
  local rc=0
  dialog "${DIALOG_COMMON[@]}" --colors --extra-button --extra-label "$(t back)" \
    --title " $1 " --yesno "\n$2" 11 64 || rc=$?
  case $rc in
    0) UI_RESULT=yes; return 0 ;;
    3) return 3 ;;
    *) UI_RESULT=no;  return 0 ;;
  esac
}

# w_password <title> <prompt> → confirmed, non-empty; loops until it matches.
w_password() {
  local title="$1" prompt="$2" p1 p2 rc
  while true; do
    rc=0
    p1=$(dialog "${DIALOG_NAV[@]}" --insecure --title " $title " \
      --passwordbox "\n$prompt" 10 64 3>&1 1>&2 2>&3) || rc=$?
    (( rc == 0 )) || return "$rc"
    rc=0
    p2=$(dialog "${DIALOG_NAV[@]}" --insecure --title " $title " \
      --passwordbox "\n$(t pass_confirm)" 10 64 3>&1 1>&2 2>&3) || rc=$?
    (( rc == 0 )) || return "$rc"
    if [[ "$p1" == "$p2" && -n "$p1" ]]; then
      UI_RESULT="$p1"; return 0
    fi
    dialog "${DIALOG_COMMON[@]}" --colors --title " $(t error) " \
      --msgbox "\n$(t pass_mismatch)" 8 54
  done
}

w_error() {
  dialog "${DIALOG_COMMON[@]}" --colors --title " $(t error) " --msgbox "\n$1" 8 60
}

confirm_quit() {
  dialog "${DIALOG_COMMON[@]}" --colors --title " $(t quit_title) " \
    --yesno "\n$(t quit_prompt)" 8 56
}

# ── Validators (return non-zero to re-ask) ────────────────────────────────────
v_nonempty() { [[ -n "$1" ]]; }
v_timezone() { [[ -f "/usr/share/zoneinfo/$1" ]]; }
# Preset-only (the wizard's disk menu can't pick a non-device; a preset can typo
# one). A function so tests can shadow it on hosts without the target device.
v_blockdev() { [[ -b "$1" ]]; }

# ── Step registry (loaded from steps.conf) + collected answers ────────────────
declare -gA ANSWERS     # var → user's answer (string keys → must be associative)
STEP_IDS=()
declare -gA S_TYPE S_VAR S_TITLE S_PROMPT S_OPTS S_VALID S_COND

_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

load_steps() {
  STEP_IDS=(); S_TYPE=(); S_VAR=(); S_TITLE=(); S_PROMPT=(); S_OPTS=(); S_VALID=(); S_COND=()
  local line id type var title prompt opts valid cond
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$(_trim "$line")" ]] && continue
    IFS='|' read -r id type var title prompt opts valid cond <<< "$line"
    id="$(_trim "$id")"; [[ -n "$id" ]] || continue
    STEP_IDS+=("$id")
    S_TYPE["$id"]="$(_trim "$type")"
    S_VAR["$id"]="$(_trim "$var")"
    S_TITLE["$id"]="$(_trim "$title")"
    S_PROMPT["$id"]="$(_trim "$prompt")"
    S_OPTS["$id"]="$(_trim "$opts")"
    S_VALID["$id"]="$(_trim "$valid")"
    S_COND["$id"]="$(_trim "$cond")"
  done < "$STEPS_FILE"
}

# A step is visible when it has no condition or the condition succeeds.
_step_visible() {
  local id="$1"
  [[ -z "${S_COND[$id]}" ]] && return 0
  eval "${S_COND[$id]}"
}

# _next_visible <start-index> <dir> → index, or -1 / count when past the ends.
_next_visible() {
  local j="$1" dir="$2" n="${#STEP_IDS[@]}"
  while (( j >= 0 && j < n )); do
    _step_visible "${STEP_IDS[$j]}" && { printf '%s' "$j"; return; }
    (( j += dir ))
  done
  printf '%s' "$j"
}

# Render one step, re-asking until valid. Echoes nothing; sets ANSWERS[var].
# Returns 0 forward / 3 back / 1 quit.
render_step() {
  # Separate statements: in one `local`, RHS is expanded before `id` is set,
  # which trips `set -u` ("id: unbound variable").
  local id="$1"
  local type="${S_TYPE[$id]}" var="${S_VAR[$id]}"
  local title prompt rc
  title="$(t "${S_TITLE[$id]}")"; prompt="$(t "${S_PROMPT[$id]}")"
  while true; do
    rc=0
    { case "$type" in
        input)    w_input "$title" "$prompt" "${ANSWERS[$var]:-}" ;;
        password) w_password "$title" "$prompt" ;;
        yesno)    w_yesno "$title" "$prompt" ;;
        menu)
          # Options fn prints one row per line as "tag<TAB>desc" (same contract as
          # checklist/timezone) so descriptions may contain spaces. The old
          # whitespace-split form fed dialog a mis-paired or odd argument list on
          # any disk model with a space ("Samsung SSD 970 …"): odd → dialog exits
          # 255 before drawing and the wizard re-rendered the step forever behind
          # the previous infobox; even → tags and descriptions shifted by one.
          local opts=() mtag mdesc
          while IFS=$'\t' read -r mtag mdesc; do
            [[ -n "$mtag" ]] && opts+=("$mtag" "$mdesc")
          done < <("${S_OPTS[$id]}")
          (( ${#opts[@]} )) || die "Step '$id': no options to choose from."
          w_menu "$title" "$prompt" "${ANSWERS[$var]:-}" "${opts[@]}" ;;
        checklist)
          local cl=() ptag pdesc
          while IFS=$'\t' read -r ptag pdesc; do
            [[ -n "$ptag" ]] && cl+=("$ptag" "$pdesc")
          done < <("${S_OPTS[$id]}")
          w_checklist "$title" "$prompt" "${ANSWERS[$var]:-}" "${cl[@]}" ;;
        network)  w_network "$title" "$prompt" ;;
        timezone)
          local tzp=() ztag zoff
          while IFS=$'\t' read -r ztag zoff; do
            [[ -n "$ztag" ]] && tzp+=("$ztag" "$zoff")
          done < <("${S_OPTS[$id]}")
          w_timezone "$title" "$prompt" "${ANSWERS[$var]:-}" "${tzp[@]}" ;;
        *) die "Unknown step type '$type' for step '$id'." ;;
      esac
    } || rc=$?
    (( rc != 0 )) && return "$rc"
    if [[ -n "${S_VALID[$id]}" ]] && ! "${S_VALID[$id]}" "$UI_RESULT"; then
      # v_edge_repo reports a dynamic reason (git error) via V_EDGE_MSG; the rest
      # map to a fixed i18n key.
      if [[ "${S_VALID[$id]}" == v_edge_repo ]]; then
        w_error "${V_EDGE_MSG:-$(t err_invalid)}"
      else
        local errkey=err_invalid
        [[ "${S_VALID[$id]}" == v_timezone ]] && errkey=err_timezone
        w_error "$(t "$errkey")"
      fi
      continue
    fi
    ANSWERS["$var"]="$UI_RESULT"
    return 0
  done
}

# ── Wizard driver ─────────────────────────────────────────────────────────────
# Linear pass over the visible steps; Back walks to the previous visible step.
# Returns 0 when the user reaches the end, 1 if they quit.
wizard_run() {
  local n="${#STEP_IDS[@]}" i
  i=$(_next_visible 0 1)
  while (( i >= 0 && i < n )); do
    local rc=0
    render_step "${STEP_IDS[$i]}" || rc=$?
    case $rc in
      0) i=$(_next_visible $((i + 1)) 1) ;;
      3) local p; p=$(_next_visible $((i - 1)) -1); (( p >= 0 )) && i=$p ;;
      1) confirm_quit && return 1 ;;
    esac
  done
  return 0
}

# Password answers are shown masked in the review list.
_mask() { local s="$1"; [[ -z "$s" ]] && return; printf '%*s' "${#s}" '' | tr ' ' '•'; }

# Review hub: a menu of "title: value" rows; picking one re-opens that step.
# Rebuilt every pass so conditional rows appear/disappear correctly. Returns 0
# to proceed, 1 to quit.
wizard_review() {
  local sel id var val disp
  while true; do
    local items=()
    for id in "${STEP_IDS[@]}"; do
      _step_visible "$id" || continue
      var="${S_VAR[$id]}"; val="${ANSWERS[$var]:-}"
      [[ "${S_TYPE[$id]}" == password ]] && val="$(_mask "$val")"
      disp="$(t "${S_TITLE[$id]}"): $val"
      items+=("$id" "$disp")
    done
    items+=("__proceed__" "$(t review_proceed)")
    sel=$(dialog "${DIALOG_COMMON[@]}" --colors --cancel-label "$(t quit)" \
      --title " $(t review_title) " --menu "\n$(t review_prompt)" 22 72 12 \
      "${items[@]}" 3>&1 1>&2 2>&3) || { confirm_quit && return 1; continue; }
    [[ "$sel" == "__proceed__" ]] && return 0
    render_step "$sel" || true
  done
}

# ── install.conf (single source for both install phases; consumed in S2) ──────
answers_serialize() {
  local out="$1" id var
  mkdir -p "$(dirname "$out")"
  {
    echo "# W Linux install answers — generated by the installer wizard."
    echo "lang=$LANG_CODE"
    for id in "${STEP_IDS[@]}"; do
      var="${S_VAR[$id]}"
      printf '%s=%q\n' "$var" "${ANSWERS[$var]:-}"
    done
    # Non-step preset keys whose consumer runs after the reboot. `if`, not
    # `[[ … ]] && printf`: an AND-list whose test fails leaves the enclosing group
    # at exit 1, and under set -e that has already aborted an installer once.
    for var in "${PRESET_FORWARD_VARS[@]}"; do
      if [[ -n "${!var:-}" ]]; then printf '%s=%q\n' "$var" "${!var}"; fi
    done
    # Preset installs stay unattended through firstboot too (w-firstboot skips
    # its blocking dialogs when it sees this).
    if [[ -n "${W_UNATTENDED:-}" ]]; then echo "unattended=1"; fi
  } > "$out"
  # Holds the root/user passwords and (encrypted installs) the LUKS passphrase in
  # plaintext until firstboot's scrub_install_conf strips them — keep it root-only
  # for that whole window (S1 target → first boot).
  chmod 600 "$out"
}

# ── Preset (unattended install; audit P2) ─────────────────────────────────────
# A preset is an install.conf-format file (var=%q-value — exactly what
# answers_serialize writes), authored by the operator or captured from a prior
# install. Extra keys beyond the step vars:
#   lang               — installer/firstboot language (default en)
#   unattended         — set implicitly by --preset, may appear in captured files
#   ssh_authorized_key — optional pubkey line installed for root on the target
#                        (headless fleet/E2E access; sshd is enabled anyway)
#   site_repo/site_ref/site_profile — the fleet (site) overlay this machine
#                        belongs to; seeded into /etc/w/update.conf by
#                        mod_updatesys. Deliberately preset-only for now: rolling
#                        out twenty machines is the fleet path, and a wizard step
#                        for it would ask every single-machine installer a
#                        question they have no reason to understand.
PRESET_EXTRA_VARS=(lang unattended ssh_authorized_key site_repo site_ref site_profile)

# Extra keys that must SURVIVE into the target's /var/lib/w/install.conf, because
# what consumes them runs post-boot (mod_updatesys) rather than in the installer.
PRESET_FORWARD_VARS=(site_repo site_ref site_profile)

# answers_load <file> — parse a preset into ANSWERS[]. Every non-comment line
# must be an assignment to a known key; an unknown key aborts loudly (a typo'd
# key silently falling back to a default could format the wrong disk). Values
# are evaluated by the shell — the natural inverse of %q, and the same trust
# model as w-firstboot sourcing install.conf (the preset author is already root
# on the installer).
answers_load() {
  local file="$1" line key id n=0
  [[ -f "$file" ]] || die "Preset not found: $file"
  local -A allowed=()
  for id in "${STEP_IDS[@]}"; do allowed["${S_VAR[$id]}"]=1; done
  for key in "${PRESET_EXTRA_VARS[@]}"; do allowed["$key"]=1; done
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^([a-z_][a-z0-9_]*)= ]] || die "Preset $file:$n — not a key=value line: $line"
    key="${BASH_REMATCH[1]}"
    [[ -n "${allowed[$key]:-}" ]] || die "Preset $file:$n — unknown key '$key'."
  done < "$file"
  # shellcheck source=/dev/null
  source "$file"
  for id in "${STEP_IDS[@]}"; do
    key="${S_VAR[$id]}"
    if [[ -n "${!key:-}" ]]; then ANSWERS["$key"]="${!key}"; fi
  done
}

# preset_validate — the wizard's per-step validation, replayed offline over the
# loaded ANSWERS[]. Walks the same visible-step set (conditions included, so
# e.g. luks_pass is only required when encrypt=yes), runs each step's declared
# validator, and layers on the checks the interactive widgets enforce by
# construction (menu membership, yes/no, block device). Collects every problem
# and dies once with the full list.
preset_validate() {
  local id var val type errs=() b
  for id in "${STEP_IDS[@]}"; do
    _step_visible "$id" || continue
    var="${S_VAR[$id]}"; val="${ANSWERS[$var]:-}"; type="${S_TYPE[$id]}"
    case "$var" in
      wifi) continue ;;                       # live-only concern; ignored in presets
      computer_type)                          # optional; auto-detected (chassis) when omitted
        [[ -z "$val" ]] && continue
        [[ "$val" == laptop || "$val" == desktop ]] || errs+=("computer_type: '$val' is not laptop|desktop")
        continue ;;
      packs)                                  # optional; each named bundle must exist
        [[ -z "$val" ]] && continue
        for b in $val; do
          [[ -f "${SRC:-}/scripts/packs/$b/meta.conf" ]] || errs+=("packs: unknown bundle '$b'")
        done
        continue ;;
    esac
    [[ -n "$val" ]] || { errs+=("$var: missing (required)"); continue; }
    case "$var" in
      mode) [[ "$val" == stable || "$val" == edge ]] || errs+=("mode: '$val' is not stable|edge") ;;
      disk) v_blockdev "$val" || errs+=("disk: '$val' is not a block device") ;;
    esac
    [[ "$type" == yesno && "$val" != yes && "$val" != no ]] && errs+=("$var: '$val' is not yes|no")
    if [[ -n "${S_VALID[$id]}" ]] && ! "${S_VALID[$id]}" "$val"; then
      if [[ "${S_VALID[$id]}" == v_edge_repo ]]; then
        errs+=("$var: ${V_EDGE_MSG:-invalid}")
      else
        errs+=("$var: '$val' failed ${S_VALID[$id]}")
      fi
    fi
  done
  (( ${#errs[@]} == 0 )) || die "Invalid preset:"$'\n'"$(printf '  %s\n' "${errs[@]}")"
}
