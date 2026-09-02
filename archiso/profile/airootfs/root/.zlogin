# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# W Linux: launch the installer TUI automatically on the primary console. Guarded
# by a flag so a manual re-run (Ctrl+C back to shell, then `bash install.sh` by
# hand) never gets clobbered by a second automatic invocation on tty re-login.
if [[ $(tty) == /dev/tty1 && -f /root/w/scripts/install.sh && ! -e /tmp/.w-install-launched ]]; then
    touch /tmp/.w-install-launched
    # Unattended sources, in priority order. A preset wipes the target disk with
    # no confirmation, so each source is an explicit operator action — a stock
    # ISO has neither and always gets the interactive TUI:
    #   1. dev/E2E: preset on the QEMU virtiofs share (written by vm/e2e.sh;
    #      the share only exists on the dev host's QEMU, never on real hardware)
    #   2. fleet:   preset baked into the ISO by `build-iso.sh --preset FILE`
    preset=""
    mkdir -p /w-src 2>/dev/null
    if mountpoint -q /w-src 2>/dev/null || mount -t virtiofs w-src /w-src 2>/dev/null; then
        [[ -f /w-src/vm/e2e/preset.conf ]] && preset=/w-src/vm/e2e/preset.conf
    fi
    [[ -z $preset && -f /root/w/preset.conf ]] && preset=/root/w/preset.conf
    if [[ -n $preset ]]; then
        bash /root/w/scripts/install.sh --preset "$preset"
    else
        bash /root/w/scripts/install.sh
    fi
    rc=$?
    # install.sh normally ends in `systemctl reboot` and never returns. Getting
    # here means it exited early (error or Ctrl+C) — say so instead of silently
    # dropping to a bare prompt that looks like nothing happened.
    echo
    echo "install.sh exited (status $rc). Re-run with: bash /root/w/scripts/install.sh"
    # Unattended/preset run: nobody is at this console to read that message or
    # retry. Falling through to an idle root shell makes any early installer
    # failure look like a hang — the E2E harness then burns its full S1 timeout
    # (~45 min) before giving up, with no signal. Power off instead so QEMU exits
    # promptly and the harness gets a clean, fast S1 failure. Interactive installs
    # keep the shell (operator can fix + re-run). Skip if install.sh already
    # succeeded and (somehow) returned — only a nonzero exit powers off.
    if [[ -n $preset && $rc -ne 0 ]]; then
        echo "Unattended install failed — powering off."
        systemctl poweroff
    fi
fi
