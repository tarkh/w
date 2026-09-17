# w-style module: rgb (user-scope) — push the theme's RGB pigment to every RGB
# device through OpenRGB. Applied on every theme switch and login render
# (w-style apply user), so a later re-theme recolors the hardware without any
# service — the devices are driven one-shot via the CLI.
#   controls  → OpenRGB udev rules carry TAG+=uaccess: as the logged-in user in
#               a graphical session the devices are directly accessible.
#   color     → theme.conf's W_RGB_SOFT/MEDIUM/CRISP (calibrated for a light-
#               emitting device, NOT the screen-tuned W_PRIMARY — see theme.conf's
#               "RGB lighting" pigment block), picked by the per-user override
#               `appearance.RGB_LEVEL` (default MEDIUM).
#   override  → Hub -> Appearance -> Settings: `appearance.RGB` (see
#               /usr/share/w/defaults/appearance.schema, read on every render
#               like the effects/motion overrides). Unset = on (theme colors
#               are applied); "off" = leave devices untouched.
#   root      → /etc/skel render only (EUID guard below); installing never
#               recolors the hardware.
# Band 600 = hardware devices; no other axis depends on it.
DESC="RGB lighting: theme colour → all OpenRGB devices"

render_user() {
  # Root's user channel renders /etc/skel only — never touch hardware from an
  # install-time render.
  [[ $EUID -eq 0 ]] && return 0
  # Installed by mod_openrgb; packs or stripped systems may lack it — no-op.
  command -v openrgb >/dev/null 2>&1 || return 0

  # Per-user override beats the theme, same contract as 100-effects (read on
  # every render so a later override survives a theme switch).
  # shellcheck source=/dev/null
  source /usr/lib/w/w-conf-lib.sh
  if [[ "$(wconf_get appearance RGB "")" == "off" ]]; then
    echo "w-style: rgb: disabled by user override (appearance.RGB=off) — leaving devices untouched"
    return 0
  fi

  load_conf "$(w_userscope_theme_dir)"
  local level pigment hex
  level="$(wconf_get appearance RGB_LEVEL "")"
  case "$level" in
    soft)  pigment="${W_RGB_SOFT:-}" ;;
    crisp) pigment="${W_RGB_CRISP:-}" ;;
    *)     pigment="${W_RGB_MEDIUM:-}" ;;
  esac
  # Fallback for a theme generated before the RGB_* pigments existed (only
  # `w-theme edit` backfills them) — degrade to the old default rather than fail
  # an axis that is best-effort by design.
  hex="${pigment:-${W_PRIMARY:-}}"
  hex="${hex#\#}"
  if [[ ! "$hex" =~ ^[0-9a-fA-F]{6}$ ]]; then
    echo "w-style: rgb: bad theme color: '${pigment:-${W_PRIMARY:-}}'" >&2
    return 1
  fi

  echo "w-style: rendering rgb (OpenRGB -> #${hex}, level=${level:-medium})..."
  # Best-effort by design: no RGB hardware or a failed probe exits non-zero, and
  # that must never fail the surrounding batch — the axis is cosmetic. timeout
  # bounds a slow hardware probe (some controllers hang on detection).
  if ! pgrep -x openrgb >/dev/null 2>&1; then
    timeout 20 openrgb --server >/dev/null 2>&1 & disown
  fi

  # Emit commands without waiting for their completion. Both modes are sent —
  # some devices only take `direct`, some only `static` — and each is `|| true`
  # because this whole block runs under the orchestrator's inherited `set -e`:
  # a bare failing command here would abort the subshell and skip the SECOND
  # mode too, silently defeating the fallback the two calls exist for.
  (
    for ((i = 0; i < 40; i++)); do
      devices="$(openrgb --nodetect --list-devices)"
      if [[ -n "$devices" ]]; then
        openrgb --client --nodetect --mode direct --color "$hex" || true
        openrgb --client --nodetect --mode static --color "$hex" || true
        break
      fi
      sleep 0.5
    done
  ) >/dev/null 2>&1 & disown

  return 0
}
