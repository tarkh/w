# W Linux — where Go keeps its per-user state (login-shell env, managed by W).
#
# Go follows XDG for its build cache and env file but hardwires GOPATH=~/go
# (upstream declined XDG for it), and the module cache and `go install`
# binaries follow it there. Any Go build run as the user creates that
# directory — an AUR rebuild of yay through w-update included, so this is not a
# developer-only concern. Route the pieces to their XDG homes instead:
#
#   ~/.cache/go/{mod,build}  module + build cache — one subvolume outside @home
#                            snapshots (defaults/home-subvols), both recoverable
#   ~/.local/share/go        what is left of GOPATH (pkg/sumdb — tiny)
#   ~/.local/bin             `go install` binaries, next to uv's tools, on PATH
#
# /etc/profile.d rather than /etc/w/env.d: a login-shell variable reaches TTY
# and SSH shells and, via greetd's login shell → uwsm import, the graphical
# session too — so a terminal's yay inherits it. env.d is session-only and is
# the W-Packs drop-in root, not core's.
#
# `:=` keeps a value already in the environment: a personal override belongs in
# the user's own shell profile, and this file will not fight it. Sourced by sh,
# bash and zsh (`emulate sh`) — POSIX only.
: "${GOPATH:=$HOME/.local/share/go}"
: "${GOMODCACHE:=$HOME/.cache/go/mod}"
: "${GOCACHE:=$HOME/.cache/go/build}"
: "${GOBIN:=$HOME/.local/bin}"
export GOPATH GOMODCACHE GOCACHE GOBIN
