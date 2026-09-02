pragma Singleton

// W Linux — brand logo path for the Quickshell shell.
// Reads logo.json (rendered by `w-style apply quickshell` from the active theme's
// logo/W-logo.svg, with a baseline `w` fallback) and live-reloads on change via
// FileView{watchChanges}. A theme switch changes the resolved path (per-theme dir),
// so any Image bound to `svg` reloads on `w-theme set` with no signal/restart.
// Consumed by the bar `button` block's special `w-logo` icon. The default below
// mirrors the committed logo.json (baseline `w`) so it works if the file is missing.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Absolute filesystem path to the vector logo (no scheme). Consumers prefix
    // "file://" when handing it to an Image/ShadedIcon source.
    property string path: "/etc/w/themes/w/logo/W-logo.svg"

    // Ready-to-use image source (file:// URL), empty when unset.
    readonly property string svg: path.length > 0 ? "file://" + path : ""

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.svg) root.path = c.svg;
        } catch (e) {
            // keep current/default path on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("logo.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
