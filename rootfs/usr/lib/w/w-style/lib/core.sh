# core.sh — W Linux w-style shared SDK (sourced by the orchestrator; inherited by
# each module's isolated subshell). Holds only cross-cutting infrastructure:
# theme resolution, config loaders, scope-aware writers, guards, converters.
# Axis-specific logic lives in the modules under ../modules/<NNN>-<name>/.
#
# This file defines functions/constants ONLY — no side effects on source.

# ── Shared constants ──────────────────────────────────────────────────────────
SYSTEM_POINTER="/etc/w/active-theme"      # persistent system-fallback symlink
DEFAULT_THEME_DIR="/etc/w/themes/w"       # last-resort default; also the baseline
                                          # a theme inherits optional files from
                                          # (motion.conf, ...) when it omits them.

# Brand logo within a theme dir (resolve_theme_file falls back to the baseline).
# Shared by the quickshell (SVG bar icon) and grub/plymouth (PNG) axes.
THEME_LOGO_REL="logo/W-logo-256x256.png"
THEME_LOGO_SVG_REL="logo/W-logo.svg"       # vector logo (shell `w-logo` bar icon)

# ── Theme resolution ──────────────────────────────────────────────────────────
# System fallback theme directory (changed only by `sudo w-theme set`).
w_system_theme_dir() {
  if [[ -e "$SYSTEM_POINTER" ]]; then readlink -f "$SYSTEM_POINTER"
  else echo "$DEFAULT_THEME_DIR"; fi
}

# Effective theme directory for the invoking (non-root) user: per-user pin if
# present, otherwise the system fallback.
w_user_theme_dir() {
  local pin="${HOME:-/nonexistent}/.config/w/theme/active"
  if [[ -e "$pin" ]]; then readlink -f "$pin"
  else w_system_theme_dir; fi
}

# Theme dir to use for a user-scope render: system theme when root (skel
# template), the invoking user's effective theme otherwise.
w_userscope_theme_dir() {
  if [[ $EUID -eq 0 ]]; then w_system_theme_dir; else w_user_theme_dir; fi
}

# Resolve an optional per-theme file: the active theme's copy if present,
# otherwise the default theme `w` baseline. Lets a theme override files like
# motion.conf while themes that omit them inherit the system default.
resolve_theme_file() {
  local dir="$1" name="$2"
  if [[ -f "$dir/$name" ]]; then echo "$dir/$name"
  else echo "$DEFAULT_THEME_DIR/$name"; fi
}

# ── Load config ───────────────────────────────────────────────────────────────
load_conf() {
  local dir="$1" conf="$1/theme.conf"
  [[ -f "$conf" ]] || { echo "w-style: theme config not found: $conf" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$conf"
}

# Load a motion.conf (resolved per theme with fallback to the `w` baseline).
load_motion() {
  local conf="$1"
  [[ -f "$conf" ]] || { echo "w-style: motion config not found: $conf" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$conf"
}

# Load a font.conf (resolved per theme with fallback to the `w` baseline).
load_font() {
  local conf="$1"
  [[ -f "$conf" ]] || { echo "w-style: font config not found: $conf" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$conf"
}
# Load a geometry.conf (resolved per theme with fallback to the `w` baseline), then
# fill in any token the theme predates. The axis grows over time and a third-party (or
# simply older) geometry.conf may not carry the newest section; under `set -u` an unset
# token would abort the whole render mid-module, so every token gets a baseline default
# here. Keep these in sync with themes/w/geometry.conf.
load_geometry() {
  local conf="$1"
  [[ -f "$conf" ]] || { echo "w-style: geometry config not found: $conf" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$conf"

  : "${W_GEO_WINDOW_ROUNDING:=14}" "${W_GEO_GAPS_IN:=4}" "${W_GEO_GAPS_OUT:=8}"
  : "${W_GEO_WINDOW_BORDER:=2}"
  : "${W_GEO_TAB_HEIGHT:=20}" "${W_GEO_TAB_ROUNDING:=10}"
  : "${W_GEO_TAB_GAP:=4}" "${W_GEO_TAB_GAP_IN:=4}"
  : "${W_GEO_RADIUS:=14}" "${W_GEO_RADIUS_SM:=8}" "${W_GEO_PADDING:=12}"
  : "${W_GEO_GAP:=6}" "${W_GEO_BORDER:=1}"

  : "${W_GEO_BAR_POSITION:=top}" "${W_GEO_BAR_HEIGHT:=32}"
  : "${W_GEO_BAR_MARGIN_EDGE:=6}" "${W_GEO_BAR_MARGIN_SIDE:=8}"
  : "${W_GEO_BAR_RADIUS:=pill}" "${W_GEO_BAR_RADIUS_ZONE:=pill}" "${W_GEO_BAR_RADIUS_BUTTON:=pill}"
  : "${W_GEO_BAR_PADDING_V:=2}" "${W_GEO_BAR_PADDING_H:=2}"
  : "${W_GEO_BAR_PADDING_ZONE_V:=0}" "${W_GEO_BAR_PADDING_ZONE_H:=8}" "${W_GEO_BAR_PADDING_GROUP:=2}"
  : "${W_GEO_BAR_GAP:=4}" "${W_GEO_BAR_GAP_ITEM:=2}" "${W_GEO_BAR_GAP_BUTTON:=4}"
  : "${W_GEO_BAR_BORDER:=0}" "${W_GEO_BAR_BORDER_ZONE:=0}" "${W_GEO_BAR_BORDER_BUTTON:=0}"
  : "${W_GEO_BAR_MIN_SQUARE:=true}"
}
# Load an effects.conf (resolved per theme with fallback to the `w` baseline), then
# fill in every token the file did not set — same contract as load_geometry: a theme
# carrying its OWN effects.conf does not inherit the baseline file, so one written
# before a token existed leaves it unset, and under `set -u` that aborts the render
# mid-module. Keep these in sync with themes/w/effects.conf.
load_effects() {
  local conf="$1"
  [[ -f "$conf" ]] || { echo "w-style: effects config not found: $conf" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$conf"

  : "${W_FX_WINDOW_OPACITY_ACTIVE:=1.0}" "${W_FX_WINDOW_OPACITY_INACTIVE:=1.0}"
  : "${W_FX_WINDOW_OPACITY_FULLSCREEN:=1.0}"
  : "${W_FX_BLUR_ENABLED:=true}" "${W_FX_BLUR_SIZE:=4}" "${W_FX_BLUR_PASSES:=3}"
  : "${W_FX_BLUR_IGNORE_ALPHA:=0.3}"
  : "${W_FX_SURFACE_OPACITY:=0.75}" "${W_FX_SCRIM_OPACITY:=0.45}"
  # The bar's chrome aliases the card surface unless the theme splits them.
  : "${W_FX_BAR_OPACITY:=$W_FX_SURFACE_OPACITY}" "${W_FX_BAR_BORDER_OPACITY:=1.0}"
  : "${W_FX_APP_BG_OPACITY:=0.85}" "${W_FX_APP_BG_GTK3:=true}"
  : "${W_FX_TERM_OPACITY:=0.85}"
}

# ── Guards ────────────────────────────────────────────────────────────────────
require_root() {
  [[ $EUID -eq 0 ]] || { echo "w-style: '$1' must be run as root." >&2; exit 1; }
}

require_magick() {
  command -v magick &>/dev/null \
    || { echo "w-style: ImageMagick (magick) required to regenerate '$1' assets." >&2; exit 1; }
}

# ── Converters ────────────────────────────────────────────────────────────────
# Hyprland wants rgba(RRGGBBAA); strip '#' and append full opacity.
hypr_rgba() { local h="${1#\#}"; echo "rgba(${h}ff)"; }

# ── Scope-aware writers ───────────────────────────────────────────────────────
# Write stdin to a user-scope path.
#   root → /etc/skel only (template for new accounts; never touch live homes)
#   user → $HOME
# $1 = relative path under home.
#
# Existing files are rewritten IN-PLACE (truncate + write), preserving the inode.
# This is critical for files watched by inode (e.g. Quickshell's colors.json via
# FileView{watchChanges}): replacing the inode (what `install` does — it unlinks
# dest first) deletes the watched inode, and the watcher races to re-arm; if it
# loses, it reads no file and falls back to compiled defaults, then stays stuck.
# An in-place write emits only IN_MODIFY on the stable inode, so the live recolor
# is reliable on every theme switch.
write_user_file() {
  local rel="$1" target content
  content="$(cat)"
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$rel"; else target="$HOME/$rel"; fi
  if [[ -f "$target" ]]; then
    printf '%s\n' "$content" >"$target"
  else
    install -Dm644 /dev/stdin "$target" <<<"$content"
  fi
}

# Like write_user_file but REPLACES the target via atomic rename (temp file in the
# same dir + mv), so a QFileSystemWatcher on the *directory* sees a dir-entry change
# and fires directoryChanged. qt5ct/qt6ct watch ~/.config/qtNct/ and live-reload only
# on such a change — an in-place rewrite (same inode) is invisible to them. Used for
# the *ct.conf files; everything else stays in-place (Quickshell watches inodes).
write_user_file_atomic() {
  local rel="$1" target dir tmp content
  content="$(cat)"
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$rel"; else target="$HOME/$rel"; fi
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  tmp="$dir/.${rel##*/}.tmp.$$"
  printf '%s\n' "$content" >"$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$target"
}

# Set <key>=<value> in a GTK settings.ini, preserving every other key. Ensures a
# [Settings] section and the key (patch or append); the file is created if absent.
# Scope-aware: $HOME for a user, /etc/skel as root. Shared by the appearance
# (gtk-application-prefer-dark-theme / gtk-theme-name), font (gtk-font-name) and
# icons (gtk-icon-theme-name) axes. $1 = relative path under home/skel, $2 = key,
# $3 = value.
patch_gtk_key() {
  local rel="$1" key="$2" value="$3" target
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$rel"; else target="$HOME/$rel"; fi

  if [[ ! -f "$target" ]]; then
    install -Dm644 /dev/stdin "$target" <<EOF
[Settings]
$key=$value
EOF
    return
  fi
  if grep -q "^$key=" "$target"; then
    sed -i "s|^$key=.*|$key=$value|" "$target"
  elif grep -q '^\[Settings\]' "$target"; then
    sed -i "0,/^\[Settings\]/s||[Settings]\n$key=$value|" "$target"
  else
    printf '[Settings]\n%s=%s\n' "$key" "$value" >>"$target"
  fi
}

# ── Live reload ───────────────────────────────────────────────────────────────
# Reload the caller's live Hyprland, if any. Best-effort, never fails the run.
#
# Coalescing: four axes (effects, geometry, hyprland, motion) render fragments
# that hyprland.lua require()s, so a bundle apply used to reload the compositor
# four times for ONE theme switch — and a reload re-executes the whole config,
# monitor rules included, which is wasted work at best and layout churn on a
# multi-monitor session at worst. Inside a bundle the axes therefore only RECORD
# that a reload is due and the orchestrator fires exactly one at the end. The
# marker is a file, not a variable: axes run in isolated subshells, so nothing a
# module sets can travel back to the caller. A standalone `w-style apply
# hyprland` has no marker set and reloads immediately, as before.
hypr_reload() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  command -v hyprctl &>/dev/null || return 0
  if [[ -n "${W_STYLE_RELOAD_MARKER:-}" ]]; then
    echo 1 >"$W_STYLE_RELOAD_MARKER"
    return 0
  fi
  hyprctl reload &>/dev/null || true
}

# Open a coalescing window: hypr_reload() now only marks. Call hypr_reload_flush
# to close it and reload once if any axis asked for it. The marker file is really
# created by mktemp (not just named by `mktemp -u`) so nothing else can sit on the
# path we are about to write to.
hypr_reload_defer() {
  W_STYLE_RELOAD_MARKER="$(mktemp "${TMPDIR:-/tmp}/w-style-reload.XXXXXX")" || return 0
  export W_STYLE_RELOAD_MARKER
}

hypr_reload_flush() {
  local marker="${W_STYLE_RELOAD_MARKER:-}"
  unset W_STYLE_RELOAD_MARKER          # drop the window first → the call below is real
  [[ -n "$marker" ]] || return 0
  local due=0
  [[ -s "$marker" ]] && due=1          # empty file = no axis asked for a reload
  rm -f "$marker"
  (( due )) && hypr_reload
  return 0
}
