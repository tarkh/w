pragma Singleton

// W Linux — shared font axis for the Quickshell greeter.
// Reads font.json (rendered by `w-style apply greeter` from the active system
// theme's font.conf). The greeter uses Fonts.family explicitly so it matches the
// system UI font. Byte-identical to the user shell's Fonts.qml.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string family: "Inter"
    property string mono: "JetBrains Mono"
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
