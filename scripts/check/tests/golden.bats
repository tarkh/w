#!/usr/bin/env bats
# golden.bats — w-style golden render: the frozen fixture theme rendered through
# the pure axes (500-shell, 500-tmux) must reproduce golden/ byte-for-byte.
# A diff means the RENDER LOGIC changed — if deliberate, regenerate the goldens
# (run the render exactly like setup() below and copy the outputs to golden/).
#
# Targets are pre-created: skel ships them on a real system, and the
# existing-file branch of write_user_file (plain printf) is portable to macOS.

load helpers

setup() {
  source "$REPO/rootfs/usr/lib/w/w-style/lib/core.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/w/theme" "$HOME/.config/tmux"
  ln -s "$FIXTURES/theme" "$HOME/.config/w/theme/active"   # per-user theme pin
  : > "$HOME/.config/w/shell-colors.zsh"
  : > "$HOME/.config/tmux/w-colors.conf"
  cp "$FIXTURES/starship.toml" "$HOME/.config/starship.toml"
}

@test "golden: shell axis — shell-colors.zsh + starship [palettes.w] region" {
  source "$REPO/rootfs/usr/lib/w/w-style/modules/500-shell/module.sh"
  render_user >/dev/null
  diff -u "$GOLDEN/shell-colors.zsh" "$HOME/.config/w/shell-colors.zsh"
  diff -u "$GOLDEN/starship.toml" "$HOME/.config/starship.toml"
}

@test "golden: tmux axis — w-colors.conf" {
  source "$REPO/rootfs/usr/lib/w/w-style/modules/500-tmux/module.sh"
  render_user >/dev/null
  diff -u "$GOLDEN/tmux-colors.conf" "$HOME/.config/tmux/w-colors.conf"
}
