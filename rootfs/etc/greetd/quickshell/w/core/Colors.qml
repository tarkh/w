pragma Singleton

// W Linux — design-system palette for the Quickshell greeter.
// Reads colors.json (rendered by `w-style apply greeter` from the active SYSTEM
// theme's theme.conf) on startup. Unlike the user shell this need not live-reload
// — the greeter reads a fresh file each login. Defaults below match the committed
// colors.json (theme `w`) so the UI is themed even if the file is missing.
// Kept byte-identical to the user shell's Colors.qml so the JSON contract — and
// thus the rendered look — is shared.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property color backdrop: "#16001c"
    property color surface:  "#32003c"
    property color inputBg:  "#22002a"
    property color text:     "#a296a5"
    property color muted:    "#897b8d"
    property color accent:   "#663372"
    property color accentFg: "#ffffff"
    property color border:   "#935ea0"

    property color iconTint: "#c746e3"

    property color dangerBg:     "#3e100d"
    property color dangerFg:     "#ffd8d2"
    property color dangerBorder: "#e54a40"

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.backdrop) root.backdrop = c.backdrop;
            if (c.surface)  root.surface  = c.surface;
            if (c.inputBg)  root.inputBg  = c.inputBg;
            if (c.text)     root.text     = c.text;
            if (c.muted)    root.muted    = c.muted;
            if (c.accent)   root.accent   = c.accent;
            if (c.accentFg) root.accentFg = c.accentFg;
            if (c.border)   root.border   = c.border;
            if (c.iconTint) root.iconTint = c.iconTint;
            if (c.dangerBg)     root.dangerBg     = c.dangerBg;
            if (c.dangerFg)     root.dangerFg     = c.dangerFg;
            if (c.dangerBorder) root.dangerBorder = c.dangerBorder;
        } catch (e) {
            // keep current/default colors on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("colors.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
