pragma Singleton

// W Linux — shared font axis for the Quickshell shell.
// Reads font.json (rendered by `w-style apply font` from the active theme's
// font.conf — default /etc/w/themes/w/font.conf) and live-reloads on change via
// FileView{watchChanges}, so `w-theme set` re-fonts a running shell with no
// signal/restart — like Colors/Motion. The shell uses Fonts.family explicitly so
// it strictly matches the system UI font instead of relying on the fontconfig
// sans-serif default. Defaults below mirror the committed font.json (theme `w`).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string family: "Inter"            // UI font (matches GTK gtk-font-name)
    property string mono: "JetBrains Mono"      // monospace (matches ghostty)
    property int uiSize: 11
    property int monoSize: 11

    function apply(jsonText) {
        try {
            const f = JSON.parse(jsonText);
            if (f.ui)       root.family   = f.ui;
            if (f.mono)     root.mono     = f.mono;
            if (f.uiSize)   root.uiSize   = f.uiSize;
            if (f.monoSize) root.monoSize = f.monoSize;
        } catch (e) {
            // keep current/default fonts on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("font.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
