# w-style module: icons (dual-scope: theme name user, folder retint system).
# W_ICON_THEME is the REAL theme "Papirus-Dark" (NOT a meta-theme): Qt's icon loader
# (and Quickshell.iconPath, which rides Qt's QIcon theme) rejects inheritance-only
# meta-themes (empty Directories=), silently falling back to breeze; only a real theme
# with its own icons works. Papirus-Dark natively inherits breeze-dark → hicolor, so
# genuine gaps fill from breeze-dark (matching monochrome). One stable name serves
# GTK3, GTK4, Qt (qt5ct.conf/qt6ct.conf icon_theme) and Quickshell (Quickshell.iconPath
# via the Qt icon theme). This axis writes that NAME into the GTK settings.ini files
# (kdeglobals [Icons] is written by the qt axis, which owns that file for the
# KColorScheme). System channel (root only) retints that theme's folders/places to
# W_ICON_FOLDER via the vendored papirus-folders — so Nemo/GTK/Qt/Quickshell folders
# carry the brand tone. NOT live: theme name is read at app startup, a folder retint
# needs an icon-cache refresh + app restart. Folder retint is system-wide (like
# grub/plymouth/greeter): a per-user `w-theme set` (non-root) renders the name but NOT
# folders, which follow the system theme.
# Band 400 = toolkit palettes.
DESC="icon theme name (GTK/Qt/Quickshell) + Papirus folder retint (system)"

GTK3_SETTINGS_REL=".config/gtk-3.0/settings.ini"
GTK4_SETTINGS_REL=".config/gtk-4.0/settings.ini"

# Papirus folder retint (system-scope; vendored MIT script in rootfs/usr/lib/w).
# The retint targets the theme the theme.conf actually names (W_ICON_THEME), so
# retinted folders/places show in every toolkit without indirection. It used to
# be hardcoded to Papirus-Dark, which was invisible for as long as W shipped only
# dark themes and wrong the moment it did not: a light theme names Papirus-Light,
# and the folders being recoloured were the dark theme's — nobody's file manager
# would show them. PAPIRUS_FALLBACK covers a theme naming an icon set that is not
# installed, so a missing icon theme degrades to a named warning rather than to
# silently unretinted folders.
#
# ABSOLUTE path, not a bare name: the helper is not a command and does not sit in
# PATH. Before P9 it shipped to /usr/local/bin, which IS in PATH, so a bare name
# resolved and this read as a working call; the move to /usr/lib/w turned it into
# a lookup that always fails — and because a missing helper is a deliberate skip
# rather than an error, every machine installed after that quietly kept stock
# folders. Every other helper under /usr/lib/w is reached by absolute path (unit
# ExecStart, alpm hook Exec, pkexec); this was the one exception. check/paths.sh
# now enforces the rule.
PAPIRUS_FOLDERS_BIN="/usr/lib/w/papirus-folders"
PAPIRUS_FALLBACK="Papirus-Dark"

render_user() {
  load_conf "$(w_userscope_theme_dir)"
  echo "w-style: rendering icons (theme name)..."

  patch_gtk_key "$GTK3_SETTINGS_REL" gtk-icon-theme-name "$W_ICON_THEME"
  patch_gtk_key "$GTK4_SETTINGS_REL" gtk-icon-theme-name "$W_ICON_THEME"
  # kdeglobals [Icons] Theme is written by the qt axis (it owns kdeglobals wholesale
  # for the KColorScheme); no separate write here.

  # Live channel for a running user dbus session: push the icon theme into
  # gsettings on both the GNOME and Cinnamon interfaces. Without an XSETTINGS
  # daemon (our case under Hyprland) GTK reads settings.ini, but Nemo descends from
  # Cinnamon and may honour org.cinnamon.desktop.interface; setting both keeps every
  # GTK app on the brand theme regardless of which it reads. Schemas may be absent
  # (no cinnamon-desktop) → tolerate failure. Skipped at root/install time.
  if [[ $EUID -ne 0 ]] && command -v gsettings &>/dev/null \
       && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    gsettings set org.gnome.desktop.interface icon-theme "$W_ICON_THEME" 2>/dev/null || true
    gsettings set org.cinnamon.desktop.interface icon-theme "$W_ICON_THEME" 2>/dev/null || true
  fi

  echo "w-style: icons done (theme name)."
}

# Retint one absolute Papirus theme dir to W_ICON_FOLDER (papirus-folders + cache).
retint_papirus_dir() {
  "$PAPIRUS_FOLDERS_BIN" -C "$W_ICON_FOLDER" -t "$1" -u &>/dev/null \
    || { echo "  WARN: papirus-folders failed for '$W_ICON_FOLDER' in '$1'." >&2; return 1; }
}

# Retint the active icon theme's folders/places to W_ICON_FOLDER (root).
# Vendored papirus-folders (MIT) edits the icon-theme symlinks + refreshes caches.
#
# Retints the system theme AND every per-user ~/.local/share/icons/<theme>
# mirror that the `flatpak` W-Pack reflink-copies for the sandbox (see pack-flatpak).
# That bundle mirrors Papirus and Papirus-Dark only, so a light theme finds no
# mirror to retint and the loop simply does nothing — sandboxed apps keep stock
# folders until the mirror learns to follow the theme. No bundle, no mirror: the
# loop is then a plain no-op and this axis is unaffected.
# Those user mirrors live in the icon search path AHEAD of /usr/share/icons, so a
# stale mirror would SHADOW a fresh system retint for host GTK/Qt apps (Nemo). Each
# copy is retinted by ABSOLUTE PATH so papirus-folders edits exactly that dir (its
# readlink-f branch), never the XDG-resolved first match — keeping host + sandbox in
# sync on every `--style`, independent of when the bundle's setup last ran.
render_system() {
  load_conf "$(w_system_theme_dir)"
  echo "w-style: rendering icons (folder retint)..."
  command -v "$PAPIRUS_FOLDERS_BIN" &>/dev/null \
    || { echo "  $PAPIRUS_FOLDERS_BIN not found — skipping folder retint." >&2; return 0; }

  local base="${W_ICON_THEME:-$PAPIRUS_FALLBACK}"
  if [[ ! -d "/usr/share/icons/$base" ]]; then
    echo "  icon theme $base not installed — falling back to $PAPIRUS_FALLBACK." >&2
    base="$PAPIRUS_FALLBACK"
  fi
  [[ -d "/usr/share/icons/$base" ]] \
    || { echo "  icon theme $base not installed — skipping folder retint." >&2; return 0; }

  echo "  Papirus folders → $W_ICON_FOLDER (base $base)"
  retint_papirus_dir "/usr/share/icons/$base"

  # Per-user flatpak mirrors (uid 1000..65533, as in the bundle's setup-user.sh).
  local u uid home mirror
  while IFS=: read -r u _ uid _ _ home _; do
    (( uid >= 1000 && uid < 65534 )) || continue
    mirror="$home/.local/share/icons/$base"
    [[ -d "$mirror" ]] || continue
    echo "  Papirus folders → $W_ICON_FOLDER ($u mirror)"
    retint_papirus_dir "$mirror" && chown -R "$u:$u" "$mirror"
  done < /etc/passwd
}
