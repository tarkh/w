pragma Singleton

// W Linux — shared session state for the Quickshell shell.
// A tiny cross-component flag set when a session-ending action begins (logout /
// reboot / shutdown via the Power Menu → w-session-exit). Surfaces that should
// gracefully disappear as Hyprland minimizes the windows — e.g. the bar fading
// out — bind to `exiting`. Lock/suspend do NOT set it (the session stays).
import Quickshell

Singleton {
    id: root
    property bool exiting: false
}
