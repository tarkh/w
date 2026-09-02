# W Linux — dev bundle interactive-shell hook (managed by W-Packs, do not edit).
# Sourced by ~/.zshrc via the /etc/w/zshrc.d drop-in loop (see packs.md).
#
# `mise activate` is the PATH mode: mise recomputes PATH and env on every prompt, so
# cd-ing into a project switches its toolchain with no shim indirection — ~5-10 ms,
# and `which node` reports the real binary. Upstream recommends it for interactive
# shells and shims for everything else; W does both (the shims half is in
# /etc/w/env.d/dev.sh, which also covers GUI apps that never read a shell rc).
#
# Guarded on the binary so a half-removed bundle cannot break the shell, and on
# MISE_SHELL so a nested shell that already inherited an active session skips it.
if [[ -z "${MISE_SHELL:-}" ]] && command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi
