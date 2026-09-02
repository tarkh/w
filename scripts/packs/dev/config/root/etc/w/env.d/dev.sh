# W Linux — dev bundle session env (managed by W-Packs, do not edit).
# Sourced by /etc/xdg/uwsm/env-hyprland at graphical-session-pre (see packs.md).
# POSIX sh: this is `.`-sourced, not run.
#
# lazygit config layering. lazygit natively accepts a comma-separated list of
# config files and merges them left to right, so the last one wins. That gives the
# bundle the ownership split it needs without ever writing into the user's file:
#
#   ~/.config/lazygit/config.yml   the USER's (seeded once, behaviour only)
#   ~/.config/w/lazygit-theme.yml  W's (rendered by the w-style axis 500-lazygit)
#
# Only the palette is in the second file, so a `w-theme set` recolours lazygit
# without touching a byte the user owns. Takes effect at the next login (this file
# is session env); outside the graphical session — a bare SSH shell, say — the
# variable is absent and lazygit simply falls back to its own config alone: stock
# colours, everything else intact.
if [ -z "${LG_CONFIG_FILE:-}" ]; then
  export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml,$HOME/.config/w/lazygit-theme.yml"
fi

# mise shims on PATH — the non-interactive half of mise activation (equivalent to
# `mise activate sh --shims`, without spawning mise here in the session-env path).
#
# This half is NOT optional on W: GUI applications start from the Hyprland launcher
# and never read .zshrc, so without the shims Zed — and every language server it
# spawns — would see the system node/python instead of the project's. The
# interactive half (`mise activate zsh`, per-prompt PATH) lives in
# /etc/w/zshrc.d/dev.zsh; upstream recommends exactly this pair.
#
# Order: env-hyprland prepends ~/.local/bin BEFORE sourcing this drop-in, so the
# shims land ahead of it — deliberate. ~/.local/bin holds user-global CLIs (uv tool
# install), the shims hold the toolchain the current project asked for, and the
# project must win. Unconditional: the directory is created the first time mise
# installs a tool, and a missing PATH entry is harmless.
case ":$PATH:" in
  *":$HOME/.local/share/mise/shims:"*) ;;
  *) export PATH="$HOME/.local/share/mise/shims:$PATH" ;;
esac
