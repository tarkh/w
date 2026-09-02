pragma Singleton

// W Linux — shared geometry scale for the Quickshell greeter (system-scope copy of
// the user shell's Geometry singleton). Reads geometry.json (rendered by
// `w-style apply greeter` from the system-fallback theme's geometry.conf), so the
// login card's roundness/spacing follows the active theme. Live-reloads on change.
// Pure FileView/JSON — no exec, no extra modules (greeter security contract).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int radius:   14
    property int radiusSm:  8
    property int padding:  12
    property int gap:       6
    property int border:    1

    readonly property var tokens: ({
        "radius":   radius,   "lg":  radius,   "md": radius,
        "radiusSm": radiusSm, "sm":  radiusSm,
        "padding":  padding,  "pad": padding,
        "gap":      gap,
        "border":   border
    })

    function px(value, fallback) {
        if (typeof value === "number") return value;
        if (typeof value === "string" && root.tokens[value] !== undefined) return root.tokens[value];
        return fallback;
    }

    function apply(jsonText) {
        try {
            const g = JSON.parse(jsonText);
            if (g.radius   !== undefined) root.radius   = g.radius;
            if (g.radiusSm !== undefined) root.radiusSm = g.radiusSm;
            if (g.padding  !== undefined) root.padding  = g.padding;
            if (g.gap      !== undefined) root.gap      = g.gap;
            if (g.border   !== undefined) root.border   = g.border;
        } catch (e) {
        }
    }

    FileView {
        path: Qt.resolvedUrl("geometry.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
