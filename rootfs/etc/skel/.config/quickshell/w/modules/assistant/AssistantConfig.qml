pragma Singleton

// W Linux — "Ask W" assistant palette config for the Quickshell shell.
// USER-OWNED, like LauncherConfig: w-style/w-theme never touch it. Edit
// assistant.json and the running shell picks it up live via FileView{watchChanges}.
// Defaults below mirror the committed assistant.json, so the palette behaves sanely
// even if the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border (outline) width. `borderCfg` holds the raw assistant.json value
    // (a number OR a geometry token name like "border"/"sm"); `border` is a live binding
    // that re-resolves it via Geometry.px — so it tracks BOTH an assistant.json edit AND a
    // Geometry change (w-style apply geometry). Must stay a binding (see LauncherConfig).
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined) root.borderCfg = c.border;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/assistant.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
