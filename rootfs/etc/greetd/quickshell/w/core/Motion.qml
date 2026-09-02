pragma Singleton

// W Linux — shared motion profile for the Quickshell greeter.
// Reads motion.json (rendered by `w-style apply greeter` from the active system
// theme's motion.conf), so the greeter's fade timings match the rest of the
// system. Byte-identical to the user shell's Motion.qml.
// Durations are milliseconds; `bezier` is the shared cubic-bezier control points.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int fast: 180
    property int base: 300
    property int slow: 400
    property var bezier: [0.25, 0.1, 0.25, 1.0]

    readonly property var bezierCurve: [bezier[0], bezier[1], bezier[2], bezier[3], 1, 1]

    function apply(jsonText) {
        try {
            const m = JSON.parse(jsonText);
            if (m.fast !== undefined) root.fast = m.fast;
            if (m.base !== undefined) root.base = m.base;
            if (m.slow !== undefined) root.slow = m.slow;
            if (Array.isArray(m.bezier) && m.bezier.length === 4) root.bezier = m.bezier;
        } catch (e) {
            // keep current/default motion on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("motion.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
