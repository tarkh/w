pragma Singleton

// W Linux — greeter runtime state (last successful login).
// Remembers the last user + session so they are preselected next time. Written on
// a successful authentication, read on startup. This is RUNTIME STATE, not config
// and not theme: never edited by hand, never touched by w-style/w-theme.
//
// Persisted via the canonical FileView+JsonAdapter pattern (see the user shell's
// LauncherUsage) in Quickshell's per-shell state dir — for the greeter that is
// under the writable greeter HOME (/var/lib/w-greeter/.local/state/…). Only the
// username and session NAME are stored — never a password.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string lastUser: adapter.lastUser
    readonly property string lastSession: adapter.lastSession

    function remember(user, session) {
        adapter.lastUser = user || "";
        adapter.lastSession = session || "";
    }

    FileView {
        path: Quickshell.stateDir + "/greeter-state.json"
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: adapter
            property string lastUser: ""
            property string lastSession: ""
        }
    }
}
