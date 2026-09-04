# bitwarden bundle — session env (sourced by env-hyprland at graphical-session-pre).
#
# Pin the app's SSH agent socket to the path W's catalog names (SOCKET_bitwarden in
# ssh.conf). Without this the app picks its own default, and the two would only
# agree by coincidence — the day upstream changes that default, `w-ssh` would point
# a symlink at a socket nobody listens on and every ssh would fail with a
# "Error connecting to agent" that names no cause.
#
# The variable is Bitwarden's own (read by its Rust agent core); setting it here is
# the supported way to place the socket, and it happens to be the only knob that
# keeps the two sides of this bundle honest about one path.
#
# NOTE this is NOT SSH_AUTH_SOCK. That one stays W's stable indirection path for
# the whole session (env-hyprland) and is re-pointed by `w-ssh use` — which is what
# lets you switch back to gcr, or to another manager, without touching this file.
export BITWARDEN_SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
