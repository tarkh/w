pragma Singleton

// W Linux — terminal launch helper.
// The single entry point for opening the terminal from the Quickshell shell. Call
// sites never name a terminal binary: they build their argv through Term, and the
// `w-term` script maps it to the active terminal's fastest, systemd/D-Bus-correct
// invocation (for ghostty: `+new-window` into the pre-warmed daemon — one shared
// process, ~20ms). Switching the terminal is a `w-term set <name>` away, with no
// QML changes. See w-term / package-ghostty.md.
import Quickshell

Singleton {
    // Open a bare interactive terminal window (Super+Return equivalent).
    function window() { return ["w-term"]; }

    // Run a command in a new terminal window. `argv` is the command as a string
    // array, e.g. Term.exec(["btop"]) or Term.exec(["sudo","w-pack","install",n]).
    function exec(argv) { return ["w-term", "-e"].concat(argv); }

    // Same, but the window asks before closing so the command's LAST output stays on
    // screen. For anything whose tail is the point — `w-pack remove` ends with what it
    // left in place, where the backup went and the pacman line to run — a window that
    // vanishes on exit throws away the reason it was opened. See w-term's --hold.
    function execHold(argv) { return ["w-term", "--hold", "-e"].concat(argv); }
}
