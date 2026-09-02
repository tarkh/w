pragma Singleton

// W Linux — layouts-panel config for the Quickshell shell.
// USER-OWNED, like LauncherConfig/ClipboardConfig: w-style/w-theme never touch it.
// Edit layouts.json and the running shell picks it up live via FileView{watchChanges}.
// Defaults below mirror the committed layouts.json, so the panel behaves sanely even
// if the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border width. `borderCfg` holds the raw layouts.json value (a number
    // OR a geometry token like "border"/"sm"); `border` re-resolves it live through
    // Geometry.px, so it tracks both a layouts.json edit and a Geometry change. Must
    // stay a binding — see LauncherConfig for why.
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    // Master on/off for the panel. False → the shortcut does not open it. The saved
    // layouts and the `w-session layout` verbs are unaffected: this hides a UI, it
    // does not disable a feature.
    property bool enabled: true

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined)  root.borderCfg = c.border;
            if (c.enabled !== undefined) root.enabled   = c.enabled;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/layouts.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
