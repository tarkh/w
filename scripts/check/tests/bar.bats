#!/usr/bin/env bats
# bar.bats — w-bar's per-monitor bar composition, and the shipped bar.json it addresses.
#
# Two things are under test and they fail in different ways:
#
#   • The CONTRACT of the shipped config. Every block is addressed by its "id", and
#     the W Hub names it from i18n.json — so a block added later with no id, a
#     duplicated id, or an id nobody translated is a silent hole in the settings UI
#     (the row is missing, or shows a raw key). No gate but this one sees that:
#     bar.json is valid JSON either way and qmllint never opens it.
#
#   • The RESOLUTION rules, which are the whole feature: an explicit per-output
#     `enabled` beats the primary role, `show` beats the block's global `enabled`,
#     and writing back the value the file already yields must DELETE the override
#     rather than pin it — otherwise `monitors` slowly grows into a second copy of
#     the composition and stops following bar.json.
#
# Everything here is a plain JSON file plus jq: no compositor, no session, no root.

load helpers

BAR_SRC="rootfs/etc/skel/.config/quickshell/w/config/bar.json"
I18N_SRC="rootfs/etc/skel/.config/quickshell/w/core/i18n.json"

setup() {
  W_BAR="$REPO/rootfs/usr/bin/w-bar"
  export W_BAR_JSON="$BATS_TEST_TMPDIR/bar.json"
  export W_DISPLAYS_JSON="$BATS_TEST_TMPDIR/displays.json"
  cp "$REPO/$BAR_SRC" "$W_BAR_JSON"
  echo '{"primary":"eDP-1"}' > "$W_DISPLAYS_JSON"
  # A PATH without hyprctl: `outputs` must fall back to the config + the primary
  # mirror, which is also the headless case (a TTY, the AI over ssh).
  export PATH="/usr/bin:/bin"
  # jq is w-bar's whole implementation, and a shipped W package — on a W box it
  # is always there. Elsewhere its absence is the environment's answer, not the
  # code's: skip rather than paint 23 cases red (checks.md: a missing tool skips
  # with a hint). Checked against the PATH above, the one the cases actually
  # run under. CI installs it and runs --strict, where this skip is a failure.
  command -v jq >/dev/null || skip "jq not installed"
  source "$W_BAR"
  # The script sets -euo pipefail on source. Drop -u and pipefail, but LEAVE -e ON:
  # bats reports a failed assertion through errexit, so a suite that clears it in
  # setup() passes unconditionally (checks.md rule 12).
  set +u; set +o pipefail
}

cfg() { jq -r "$1" "$W_BAR_JSON"; }

# ── The shipped config's contract ───────────────────────────────────────────────
@test "shipped bar.json: every block carries an id" {
  run jq -r '["start","center","end"][] as $z
             | ((.blocks[$z] // [])[]) | ., (.items // [])[]?
             | select(.id == null) | .type' "$REPO/$BAR_SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "shipped bar.json: ids are unique file-wide, nested items included" {
  local ids dupes
  ids="$(catalog_tsv < /dev/null | cut -f1)"
  dupes="$(sort <<< "$ids" | uniq -d)"
  [ -z "$dupes" ]
  [ "$(wc -l <<< "$ids")" -eq 19 ]
}

@test "shipped bar.json: nested items name their parent zone" {
  run bash -c "source '$W_BAR'; catalog_tsv | awk -F'\t' '\$4 != \"\" {print \$1\":\"\$4}'"
  [ "$status" -eq 0 ]
  [ "$output" = "cpu:systemMonitors
ram:systemMonitors
temp:systemMonitors
disk:systemMonitors" ]
}

@test "every shipped block has an en+ru name in i18n.json" {
  local id type key
  while IFS=$'\t' read -r id type _ _; do
    key="bar.block.$id"
    if [ "$(jq -r --arg k "$key" 'has($k)' "$REPO/$I18N_SRC")" != true ]; then
      key="bar.type.$type"
    fi
    run jq -r --arg k "$key" '(.[$k].en // "") + "|" + (.[$k].ru // "")' "$REPO/$I18N_SRC"
    [ "$status" -eq 0 ]
    # Both halves present: a missing translation would leave one side empty and the
    # Hub would echo the raw key back (Strings.t falls through to the key itself).
    [[ "$output" == *"|"* && "${output%|*}" != "" && "${output#*|}" != "" ]]
  done < <(catalog_tsv)
}

# ── Bar on/off per output ───────────────────────────────────────────────────────
@test "with no entry: the primary output has a bar, another one does not" {
  [ "$(bar_state eDP-1 eDP-1)" = on ]
  [ "$(bar_state HDMI-A-1 eDP-1)" = off ]
}

@test "a bare entry (no enabled key) turns a secondary output's bar on" {
  jq '.monitors["HDMI-A-1"] = { show: {} }' "$W_BAR_JSON" > "$W_BAR_JSON.t" && mv "$W_BAR_JSON.t" "$W_BAR_JSON"
  [ "$(bar_state HDMI-A-1 eDP-1)" = on ]
}

@test "an explicit enabled:false switches the PRIMARY output's bar off" {
  run "$W_BAR" monitor eDP-1 off
  [ "$status" -eq 0 ]
  [ "$(bar_state eDP-1 eDP-1)" = off ]
}

@test "switching a bar off keeps the per-block choices for when it comes back" {
  "$W_BAR" block eDP-1 tray off
  "$W_BAR" monitor eDP-1 off
  [ "$(cfg '.monitors["eDP-1"].show.tray')" = false ]
  "$W_BAR" monitor eDP-1 on
  [ "$(cfg '.monitors["eDP-1"].show.tray')" = false ]
  [ "$(block_state eDP-1 tray)" = off ]
}

# ── Per-block visibility ────────────────────────────────────────────────────────
@test "block off writes a sparse override, not a copy of the composition" {
  run "$W_BAR" block eDP-1 tray off
  [ "$status" -eq 0 ]
  [ "$(cfg '.monitors["eDP-1"].show | keys | length')" -eq 1 ]
  [ "$(cfg '.monitors["eDP-1"] | has("blocks")')" = false ]
  [ "$(block_state eDP-1 tray)" = off ]
  # Other outputs are untouched — this is per-monitor, not global.
  [ "$(block_state HDMI-A-1 tray)" = on ]
}

@test "setting a block back to its default drops the override entirely" {
  "$W_BAR" block eDP-1 tray off
  "$W_BAR" block eDP-1 tray on
  [ "$(cfg '.monitors | has("eDP-1")')" = false ]
}

@test "'default' drops the override but leaves the rest of the entry alone" {
  "$W_BAR" monitor eDP-1 off
  "$W_BAR" block eDP-1 tray off
  "$W_BAR" block eDP-1 tray default
  [ "$(cfg '.monitors["eDP-1"] | has("show")')" = false ]
  [ "$(cfg '.monitors["eDP-1"].enabled')" = false ]
}

@test "show:true revives a block whose global enabled is false" {
  jq '.blocks.end |= map(if .id == "tray" then .enabled = false else . end)' \
    "$W_BAR_JSON" > "$W_BAR_JSON.t" && mv "$W_BAR_JSON.t" "$W_BAR_JSON"
  [ "$(block_state eDP-1 tray)" = off ]
  run "$W_BAR" block eDP-1 tray on
  [ "$status" -eq 0 ]
  [ "$(cfg '.monitors["eDP-1"].show.tray')" = true ]
  [ "$(block_state eDP-1 tray)" = on ]
  # ...and only there.
  [ "$(block_state HDMI-A-1 tray)" = off ]
}

@test "a nested zone item is addressable without touching its parent zone" {
  # Asserted as "the parent did not move", not as a literal on/off: which blocks ship
  # enabled is a product decision that changes (systemMonitors went off by default in
  # 2026-09), and a test pinned to today's default would fail for the wrong reason.
  local before; before="$(block_state eDP-1 systemMonitors)"
  run "$W_BAR" block eDP-1 cpu off
  [ "$status" -eq 0 ]
  [ "$(block_state eDP-1 cpu)" = off ]
  [ "$(block_state eDP-1 systemMonitors)" = "$before" ]
  [ "$(cfg '.monitors["eDP-1"].show | keys | join(",")')" = cpu ]
}

@test "the shipped defaults are the ones we mean to ship" {
  # A default flipped by accident (a stray edit in a big JSON) is invisible until a user
  # reports a missing block, so the intended set is written down here on purpose.
  run bash -c "jq -r '[\"start\",\"center\",\"end\"][] as \$z
                       | ((.blocks[\$z] // [])[]) | ., (.items // [])[]?
                       | select(.enabled == false) | .id' '$REPO/$BAR_SRC' | sort | paste -sd,"
  [ "$status" -eq 0 ]
  [ "$output" = "brightness,kbdBacklight,network,systemMonitors" ]
}

@test "reset drops one output, or all of them" {
  "$W_BAR" block eDP-1 tray off
  "$W_BAR" monitor HDMI-A-1 on
  "$W_BAR" reset eDP-1
  [ "$(cfg '.monitors | keys | join(",")')" = "HDMI-A-1" ]
  "$W_BAR" reset
  [ "$(cfg '.monitors | length')" -eq 0 ]
}

# ── Refusals ────────────────────────────────────────────────────────────────────
@test "an unknown block id is refused, not written" {
  run "$W_BAR" block eDP-1 nosuch off
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown block id"* ]]
  [ "$(cfg '.monitors | length')" -eq 0 ]
}

@test "a bad value is a usage error" {
  run "$W_BAR" block eDP-1 tray maybe
  [ "$status" -eq 2 ]
  run "$W_BAR" monitor eDP-1 maybe
  [ "$status" -eq 2 ]
  run "$W_BAR" nonsense
  [ "$status" -eq 2 ]
}

# ── Environment ─────────────────────────────────────────────────────────────────
@test "no HOME: reports a missing config instead of dying on an unbound variable" {
  # Written as the consumer runs it — a SUBPROCESS under `set -euo pipefail` with the
  # variable actually gone. Sourcing it in-process would prove nothing: bats always
  # has a HOME (checks.md rule 9; the same class cost w-monitor a boot).
  run env -u HOME -u XDG_CONFIG_HOME -u W_BAR_JSON "$W_BAR" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"bar.json not found"* ]]
}

# ── The primary fallback (must mirror Displays.primaryScreen exactly) ───────────
# `w-monitor primary` has never run on a fresh machine, so the state file is absent
# and the SHELL falls back — layout origin, else the first screen — and draws a bar
# there. A CLI that stopped at "no primary configured" would report that visible bar
# as off, which is how a status command loses the user's trust.
hyprctl_stub() { # <json>
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf %%s %s\n' "$(printf '%q' "$1")" > "$BATS_TEST_TMPDIR/bin/hyprctl"
  chmod 755 "$BATS_TEST_TMPDIR/bin/hyprctl"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "no state file: the primary falls back to the output at the layout origin" {
  rm -f "$W_DISPLAYS_JSON"
  hyprctl_stub '[{"name":"HDMI-A-1","x":1920,"y":0},{"name":"eDP-1","x":0,"y":0}]'
  [ "$(primary_out)" = eDP-1 ]
  [ "$(bar_state eDP-1 "$(primary_out)")" = on ]
  [ "$(bar_state HDMI-A-1 "$(primary_out)")" = off ]
}

@test "no state file and no origin output: the first one carries the bar" {
  rm -f "$W_DISPLAYS_JSON"
  hyprctl_stub '[{"name":"DP-2","x":100,"y":0},{"name":"DP-3","x":2020,"y":0}]'
  [ "$(primary_out)" = DP-2 ]
}

@test "no compositor and no state file: no outputs, and status still exits clean" {
  rm -f "$W_DISPLAYS_JSON"
  run env PATH="/usr/bin:/bin" W_BAR_JSON="$W_BAR_JSON" W_DISPLAYS_JSON="$W_DISPLAYS_JSON" "$W_BAR" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"No outputs known here"* ]]
}

@test "an unplugged output keeps its entry visible in status" {
  "$W_BAR" monitor DP-9 off
  run env PATH="/usr/bin:/bin" W_BAR_JSON="$W_BAR_JSON" W_DISPLAYS_JSON="$W_DISPLAYS_JSON" "$W_BAR" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *"MONITOR"$'\t'"DP-9"$'\t'"off"* ]]
}

@test "the batched per-output pass agrees with the single-block resolver" {
  "$W_BAR" block eDP-1 tray off
  "$W_BAR" block eDP-1 cpu off
  local id state
  while IFS=$'\t' read -r id state; do
    [ "$state" = "$(block_state eDP-1 "$id")" ]
  done < <(block_states eDP-1)
  [ "$(block_states eDP-1 | wc -l)" -eq 19 ]
}
