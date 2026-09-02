#!/bin/bash
# w-greeter-wrapper.sh — W Linux Quickshell greeter lifecycle.
#
# Launched by the greeter Hyprland session (exec-once in /etc/greetd/hyprland.lua).
# greetd → Hyprland (greeter, black bg) → this wrapper → quickshell greeter, which
# talks to greetd over $GREETD_SOCK and, on success, launches the user session.
#
# Steps, in order:
#   1. Load the system locale so the UI follows the default system language (the
#      Strings singleton reads $LANG). The greeter session is not a normal user
#      session, so /etc/locale.conf is not applied for us — source it explicitly.
#   2. Point the wallpaper symlink at the system theme's wallpaper. The shell draws
#      it directly (no hyprpaper), so this only needs the /run symlink in place.
#   3. Exec the Quickshell greeter. XDG_CONFIG_HOME selects the system-scope config
#      at /etc/greetd/quickshell/w (so `qs.*` imports resolve as in the user shell);
#      HOME gives Qt a writable shader cache (without it Qt falls back to software
#      rendering and pegs the CPU — the lesson learned with regreet).

set -u

# 1) System locale → greeter UI language.
if [ -r /etc/locale.conf ]; then
  # shellcheck source=/dev/null
  . /etc/locale.conf
  export LANG LC_MESSAGES LC_TIME LC_ALL
fi

# 2) Greeter runtime environment.
export HOME=/var/lib/w-greeter
export XDG_CONFIG_HOME=/etc/greetd
export XDG_CACHE_HOME="$HOME/.cache"
export QT_QPA_PLATFORM=wayland

# 3) Wallpaper symlink for the system theme (best-effort; the shell handles a
#    missing image gracefully).
w-wallpaper set || true

# 4) The greeter itself. `-c w` + XDG_CONFIG_HOME → /etc/greetd/quickshell/w.
#    Run it (NOT exec) so we regain control the instant it exits and can tear down
#    this greeter Hyprland ourselves. quickshell quits right after it tells greetd to
#    start the user session (Greetd.launch(..., quit=true)) — but quitting the
#    exec-once child does NOT end Hyprland, and for greetd the greeter session *is*
#    this Hyprland. Left alone, greetd waits for it to die and only force-terminates
#    it after a multi-second timeout: that idle window (compositor still live, cursor
#    movable) is the long pause between the login UI vanishing and the user session
#    appearing. start_session is already accepted, so exiting now is safe and makes
#    greetd hand off immediately.
quickshell -c w

# 5) Tear down the greeter's xdg-desktop-portal stack BEFORE killing the compositor.
#    The greeter needs no portals (it only authenticates), but Qt/Quickshell touching
#    the Settings portal D-Bus-activates xdg-desktop-portal + the hyprland backend
#    anyway. If we let `hyprctl dispatch 'hl.dsp.exit()'` kill the compositor first, XDPH's exit
#    handlers marshal into a dead wayland socket and SIGSEGV (a coredump every login).
#    SIGKILL (not TERM) so no exit handlers run at all: a clean shutdown would still
#    marshal teardown into wayland, racing the compositor's death. Match the full
#    command line (-f), since the kernel truncates the process comm to 15 chars and an
#    exact name match (-x) on the 27-char binary never fires. Scoped to the greeter
#    uid; non-fatal if it never started.
pkill -9 -u "$(id -u)" -f xdg-desktop-portal-hyprland 2>/dev/null || true

hyprctl dispatch "hl.dsp.exit()"
