pragma Singleton

// W Linux — primary-monitor service.
// "Primary" (which monitor carries the main bar, and later the greeter login card) is
// a W concept, not a Hyprland one, so `w-monitor primary` mirrors it into a small JSON
// state file this singleton watches (no Lua parsing needed here). One home for the
// primary-monitor lookup so the bar (and later the Hub Displays panel) share it.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string primary: ""

    // Monitor that carries the primary role: the configured connector name, else the
    // monitor at the layout origin (0,0), else the first screen. Mirrors the greeter's
    // own primaryScreen() (Greeter.qml) — same fallback, different config source.
    function primaryScreen() {
        const list = Quickshell.screens;
        if (!list || list.length === 0) return null;
        if (root.primary) for (const s of list) if (s.name === root.primary) return s;
        for (const s of list) if (s.x === 0 && s.y === 0) return s;
        return list[0];
    }

    // Whether `name` holds the primary role, accounting for the same fallback as
    // primaryScreen() (so an empty/stale `primary` still picks exactly one screen).
    function isPrimary(name) {
        const s = root.primaryScreen();
        return !!s && s.name === name;
    }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/w/displays.json"
        watchChanges: true
        printErrors: false   // absent until the first `w-monitor primary` call
        onFileChanged: reload()
        onLoaded: {
            try { root.primary = JSON.parse(text() || "{}").primary || ""; }
            catch (e) { root.primary = ""; }
        }
    }
}
