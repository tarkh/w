#!/usr/bin/env bats
# monitor.bats — w-monitor's black-screen guards.
#
# There is exactly one known way to brick a W desktop from the GUI: leave every
# connected output disabled. Hyprland then synthesises its internal FALLBACK
# pseudo-monitor, never bootstraps a renderer for the real hardware, and the boot
# safety net in hyprland.lua cannot climb back out (that file carries the full
# post-mortem). Black screen, live IPC, nothing to click.
#
# Three pieces stand between the user and that state, and all three are here:
#   • `disable` refuses the primary output;
#   • `disable` refuses the last output that would still be drawing;
#   • `sanity` repairs a layout that reached the bad state anyway — because the
#     first two are point-in-time and the failure is temporal. Turning the laptop
#     panel off with an external attached is legitimate, and both guards allow it;
#     what breaks the machine is unplugging the external afterwards.
#
# None of it needs a monitor, a compositor or root, which is the point: the guards
# have to hold on a TTY and in the pre-session hook, so their inputs are seams.
# W_DRM_ROOT stands in for the kernel's connector list and a PATH stub for a live
# hyprctl; the fragment paths are plain variables once the script is sourced.

load helpers

setup() {
  # Source-guarded (BASH_SOURCE vs $0) and takes W_CONF_LIB — the same pair w-ai
  # carries, so this needs no W installation on the machine.
  W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh"
  export W_CONF_LIB
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export W_DRM_ROOT="$BATS_TEST_TMPDIR/drm"
  mkdir -p "$XDG_CONFIG_HOME/hypr" "$W_DRM_ROOT"
  source "$REPO/rootfs/usr/bin/w-monitor"
  # The script sets -euo pipefail on source. Drop -u (the fragment readers probe
  # unset array slots) and pipefail, but LEAVE -e ON: bats reports a failed
  # assertion through errexit, so a suite that turns it off in setup() passes
  # unconditionally — every assertion in it, the last one included, is ignored.
  set +u; set +o pipefail
}

# A connector as the kernel presents it: /sys/class/drm/card<N>-<NAME>/status.
drm() { # <name> <connected|disconnected|unknown>
  mkdir -p "$W_DRM_ROOT/card1-$1"
  echo "$2" > "$W_DRM_ROOT/card1-$1/status"
}

# Write a monitors.lua fragment. Rules are "<output>:<on|off>", in order.
frag() { # <path> <primary> <rule>...
  local path="$1" primary="$2"; shift 2
  local r name state dis
  {
    echo 'return {'
    printf '  primary = "%s",\n' "$primary"
    echo '  outputs = {'
    for r in "$@"; do
      name="${r%:*}"; state="${r#*:}"
      dis=false; [[ "$state" == off ]] && dis=true
      printf '    { output = "%s", mode = "preferred", position = "auto", scale = "auto", transform = 0, disabled = %s },\n' \
        "$name" "$dis"
    done
    echo '  },'
    echo '}'
  } > "$path"
}

# Pretend a compositor is running. Only the output NAMES are read back, so the
# stub answers `version` (that is what have_hypr probes) and `monitors all -j`.
hypr_stub() { # <name>...
  local bin="$BATS_TEST_TMPDIR/bin" json="[" n
  mkdir -p "$bin"
  for n in "$@"; do json+="{\"name\":\"$n\"},"; done
  json="${json%,}]"
  printf '#!/usr/bin/env bash\ncase "$1" in\n  version) exit 0 ;;\n  monitors) echo %s ;;\nesac\nexit 0\n' \
    "'$json'" > "$bin/hyprctl"
  chmod +x "$bin/hyprctl"
  PATH="$bin:$PATH"
}

# ── connected_outputs: the kernel's view, with no compositor ──────────────────

@test "connected_outputs: reports plugged-in connectors under their Hyprland names" {
  drm eDP-1 connected
  drm HDMI-A-1 connected
  [[ "$(connected_outputs | LC_ALL=C sort | tr '\n' ' ')" == "HDMI-A-1 eDP-1 " ]]
}

@test "connected_outputs: skips disconnected heads and synthetic writebacks" {
  drm eDP-1 connected
  drm DP-2 disconnected
  # Writeback connectors always read "unknown" — they are not displays, and a
  # count that included them would think the machine still had a screen.
  drm Writeback-1 unknown
  [[ "$(connected_outputs)" == "eDP-1" ]]
}

@test "connected_outputs: empty when sysfs has nothing to say" {
  [[ -z "$(connected_outputs)" ]]
}

# ── disable: the two refusals ─────────────────────────────────────────────────

@test "disable: refuses the last connected output with NO live session" {
  # The regression this file exists for. The guard used to read `hyprctl monitors`
  # and was therefore skipped whole on a TTY, where the primary check does not
  # bite either: the shipped monitors.lua has primary = "".
  drm eDP-1 connected
  frag "$FRAG" "" "eDP-1:on"
  run cmd_disable eDP-1
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"last active output"* ]]
  # And it refused BEFORE writing: the layout on disk is untouched.
  grep -q 'output = "eDP-1".*disabled = false' "$FRAG"
}

@test "disable: refuses the primary output even when others are live" {
  drm eDP-1 connected
  drm HDMI-A-1 connected
  frag "$FRAG" "eDP-1" "eDP-1:on" "HDMI-A-1:on"
  run cmd_disable eDP-1
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"primary output"* ]]
}

@test "disable: allows turning off one of two connected outputs" {
  drm eDP-1 connected
  drm HDMI-A-1 connected
  frag "$FRAG" "" "eDP-1:on" "HDMI-A-1:on"
  run cmd_disable HDMI-A-1
  [[ "$status" -eq 0 ]]
  read_frag
  find_rule HDMI-A-1
  [[ "${R_DISABLED[$RULE_IDX]}" == "true" ]]
}

@test "disable: allows turning off an output that is not plugged in" {
  # Nothing is lost by disabling a head that isn't there, and refusing would make
  # the guard punish a legitimate tidy-up.
  drm eDP-1 connected
  drm HDMI-A-1 disconnected
  frag "$FRAG" "" "eDP-1:on" "HDMI-A-1:on"
  run cmd_disable HDMI-A-1
  [[ "$status" -eq 0 ]]
}

@test "disable: an unruled connected output counts as the one still drawing" {
  # No rule means hyprland.lua's catch-all `output = ""` picks it up enabled, so
  # HDMI-A-1 rescues the session and eDP-1 may go off.
  drm eDP-1 connected
  drm HDMI-A-1 connected
  frag "$FRAG" "" "eDP-1:on"
  run cmd_disable eDP-1
  [[ "$status" -eq 0 ]]
}

@test "disable: with a live session, refuses the last output it reports" {
  # The original live-session path, still exercised: sysfs says two heads exist,
  # the compositor says one, and the compositor wins.
  drm eDP-1 connected
  drm HDMI-A-1 connected
  hypr_stub eDP-1
  frag "$FRAG" "" "eDP-1:on"
  run cmd_disable eDP-1
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"last active output"* ]]
}

# ── sanity: the repair ────────────────────────────────────────────────────────

@test "sanity: re-enables the only connected output when everything is off" {
  # The temporal failure, reproduced: both heads were configured while both were
  # attached, the external is now gone, and the survivor is disabled.
  drm eDP-1 connected
  frag "$FRAG" "" "eDP-1:off" "HDMI-A-1:off"
  run sanity_frag "$FRAG"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"re-enabled eDP-1"* ]]
  read_frag
  find_rule eDP-1
  [[ "${R_DISABLED[$RULE_IDX]}" == "false" ]]
  # Minimum intervention: the head the user cannot see is left as they set it.
  find_rule HDMI-A-1
  [[ "${R_DISABLED[$RULE_IDX]}" == "true" ]]
}

@test "sanity: prefers the primary output when several are connected" {
  drm eDP-1 connected
  drm HDMI-A-1 connected
  # Fragment order would pick eDP-1; the primary is where the bar goes, so it wins.
  frag "$FRAG" "HDMI-A-1" "eDP-1:off" "HDMI-A-1:off"
  run sanity_frag "$FRAG"
  [[ "$output" == *"re-enabled HDMI-A-1"* ]]
}

@test "sanity: is a silent no-op on a healthy layout" {
  drm eDP-1 connected
  drm HDMI-A-1 connected
  frag "$FRAG" "" "eDP-1:on" "HDMI-A-1:off"
  cp "$FRAG" "$BATS_TEST_TMPDIR/before"
  run sanity_frag "$FRAG"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  cmp -s "$BATS_TEST_TMPDIR/before" "$FRAG"
}

@test "sanity: no-op when the only disabled output is unplugged" {
  drm eDP-1 connected
  drm HDMI-A-1 disconnected
  frag "$FRAG" "" "eDP-1:on" "HDMI-A-1:off"
  run sanity_frag "$FRAG"
  [[ -z "$output" ]]
}

@test "sanity: no-op with no rules at all (everything is auto)" {
  drm eDP-1 connected
  frag "$FRAG" ""
  run sanity_frag "$FRAG"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "sanity: no-op when nothing is plugged in" {
  # A headless box, or sysfs unreadable in a container: there is no display to
  # rescue, and guessing would only churn the config.
  frag "$FRAG" "" "eDP-1:off"
  run sanity_frag "$FRAG"
  [[ "$status" -eq 0 ]]
  read_frag
  find_rule eDP-1
  [[ "${R_DISABLED[$RULE_IDX]}" == "true" ]]
}

@test "runs in a systemd system unit, which has no HOME" {
  # greetd calls `greeter sanity` from ExecStartPre, and a system unit is started
  # with no HOME at all (systemd exports it only for units with User=). With `set -u`
  # on, resolving the session paths off a bare $HOME aborted this script on its first
  # line — the rescue never ran, and the VM came up to the black screen it was meant
  # to prevent. Run it as a subprocess, since the crash is at load time.
  drm eDP-1 connected
  run env -u HOME -u XDG_CONFIG_HOME -u XDG_STATE_HOME \
      W_CONF_LIB="$W_CONF_LIB" W_DRM_ROOT="$W_DRM_ROOT" \
      bash "$REPO/rootfs/usr/bin/w-monitor" status
  [[ "$output" != *"unbound variable"* ]]
  [[ "$status" -eq 0 ]]
}

@test "sanity: repairs the greeter fragment through the same code" {
  # The login screen has its own root-owned copy and no live compositor ever —
  # greetd's ExecStartPre calls this on the same function.
  drm eDP-1 connected
  GREETER_FRAG="$BATS_TEST_TMPDIR/monitors-greeter.lua"
  frag "$GREETER_FRAG" "" "eDP-1:off"
  run sanity_frag "$GREETER_FRAG"
  [[ "$output" == *"re-enabled eDP-1"* ]]
  grep -q 'output = "eDP-1".*disabled = false' "$GREETER_FRAG"
}
