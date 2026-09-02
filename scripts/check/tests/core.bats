#!/usr/bin/env bats
# core.bats — w-style core.sh SDK: theme resolution, config loader, converters,
# scope-aware writers. GNU-only branches (install -D, sed -i) skip on Darwin —
# CI on Arch exercises them.

load helpers

setup() {
  source "$REPO/rootfs/usr/lib/w/w-style/lib/core.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "resolve_theme_file: theme's own copy wins" {
  local theme="$BATS_TEST_TMPDIR/theme"
  mkdir -p "$theme"
  touch "$theme/motion.conf"
  [[ "$(resolve_theme_file "$theme" motion.conf)" == "$theme/motion.conf" ]]
}

@test "resolve_theme_file: absent file falls back to the w baseline" {
  [[ "$(resolve_theme_file "$BATS_TEST_TMPDIR/theme" motion.conf)" == "/etc/w/themes/w/motion.conf" ]]
}

@test "load_conf: sources theme.conf and resolves tier references" {
  load_conf "$FIXTURES/theme"
  [[ "$W_PRIMARY" == "#91619b" ]]                     # tier 2 ← W_PALETTE_ACCENT
  [[ "$W_SHELL_MUTED" == "#5a4a63" ]]                 # tier 3 ← ANSI bright black
  [[ "$W_HYPR_BORDER_ACTIVE" == "$W_PRIMARY" ]]       # role chain intact
}

@test "load_conf: missing theme.conf exits with a message" {
  run load_conf "$BATS_TEST_TMPDIR/ghost"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"theme config not found"* ]]
}

@test "hypr_rgba: hex → rgba(RRGGBBAA), # optional" {
  [[ "$(hypr_rgba '#aabbcc')" == "rgba(aabbccff)" ]]
  [[ "$(hypr_rgba 'aabbcc')"  == "rgba(aabbccff)" ]]
}

@test "write_user_file: rewrites an existing file IN-PLACE (inode preserved)" {
  mkdir -p "$HOME/.config/w"
  echo "old" > "$HOME/.config/w/x.conf"
  local before after
  before="$(ls -i "$HOME/.config/w/x.conf" | awk '{print $1}')"
  write_user_file ".config/w/x.conf" <<<"new content"
  after="$(ls -i "$HOME/.config/w/x.conf" | awk '{print $1}')"
  [[ "$before" == "$after" ]]
  [[ "$(cat "$HOME/.config/w/x.conf")" == "new content" ]]
}

@test "write_user_file: creates an absent file with parents (GNU install -D)" {
  [[ "$(uname)" == Darwin ]] && skip "GNU-only path (runs on Arch/CI)"
  write_user_file ".config/w/deep/y.conf" <<<"seeded"
  [[ "$(cat "$HOME/.config/w/deep/y.conf")" == "seeded" ]]
}

@test "write_user_file_atomic: replaces the target via rename (new inode, dir-watcher visible)" {
  mkdir -p "$HOME/.config/qt6ct"
  echo "old" > "$HOME/.config/qt6ct/qt6ct.conf"
  local before after
  before="$(ls -i "$HOME/.config/qt6ct/qt6ct.conf" | awk '{print $1}')"
  write_user_file_atomic ".config/qt6ct/qt6ct.conf" <<<"new"
  after="$(ls -i "$HOME/.config/qt6ct/qt6ct.conf" | awk '{print $1}')"
  [[ "$before" != "$after" ]]
  [[ "$(cat "$HOME/.config/qt6ct/qt6ct.conf")" == "new" ]]
}

@test "patch_gtk_key: creates, patches and appends (GNU sed -i)" {
  [[ "$(uname)" == Darwin ]] && skip "GNU-only path (runs on Arch/CI)"
  local rel=".config/gtk-3.0/settings.ini"
  patch_gtk_key "$rel" gtk-theme-name W           # absent file → created
  grep -q '^\[Settings\]$' "$HOME/$rel"
  grep -q '^gtk-theme-name=W$' "$HOME/$rel"
  patch_gtk_key "$rel" gtk-theme-name Adwaita     # existing key → patched
  grep -q '^gtk-theme-name=Adwaita$' "$HOME/$rel"
  patch_gtk_key "$rel" gtk-font-name Inter        # new key → inserted
  grep -q '^gtk-font-name=Inter$' "$HOME/$rel"
  [[ "$(grep -c '^\[Settings\]$' "$HOME/$rel")" -eq 1 ]]
}
