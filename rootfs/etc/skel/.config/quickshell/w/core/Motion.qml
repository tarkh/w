pragma Singleton

// W Linux — shared motion profile for the Quickshell shell.
// Reads motion.json (rendered by `w-style apply motion` from the active theme's
// motion.conf — default /etc/w/themes/w/motion.conf — the same source that renders
// Hyprland's animations.conf), so shell transitions stay in sync with the
// compositor. Live-reloads on change.
// Durations are milliseconds; `bezier` is the shared cubic-bezier control points.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int fast: 180   // quick feedback (backdrop tint fade, hovers)
    property int base: 300   // default (matches Hyprland windows/fade/workspaces)
    property int slow: 400   // layer surfaces (matches Hyprland `layers`)
    property var bezier: [0.25, 0.1, 0.25, 1.0]

    // QML easing.bezierCurve expects the (1,1) end point appended to the 4 control points.
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
