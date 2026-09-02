pragma Singleton

// W Linux — greeter copy of the shell's surface translucency scale (system-scope).
// Reads effects.json (rendered by `w-style apply greeter` from the system-fallback
// theme's effects.conf), byte-compatible with the user shell's Effects, so greeter
// and desktop share one look. Not live: the greeter reads fresh files each login.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property real surfaceOpacity: 0.4
    property real scrimOpacity:   0.45

    readonly property var tokens: ({
        "surface": surfaceOpacity,
        "scrim":   scrimOpacity
    })

    function op(value, fallback) {
        if (typeof value === "number") return Math.max(0, Math.min(1, value));
        if (typeof value === "string" && root.tokens[value] !== undefined) return root.tokens[value];
        return fallback;
    }

    function apply(jsonText) {
        try {
            const e = JSON.parse(jsonText);
            if (e.surfaceOpacity !== undefined) root.surfaceOpacity = e.surfaceOpacity;
            if (e.scrimOpacity   !== undefined) root.scrimOpacity   = e.scrimOpacity;
        } catch (e) {
        }
    }

    FileView {
        path: Qt.resolvedUrl("effects.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
