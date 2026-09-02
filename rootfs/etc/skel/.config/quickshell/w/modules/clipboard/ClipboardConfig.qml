pragma Singleton

// W Linux — clipboard-history viewer config for the Quickshell shell.
// Like LauncherConfig, this is a USER-OWNED config: w-style/w-theme never touch it.
// Edit clipboard.json and the running shell picks it up live via FileView{watchChanges}.
// Defaults below mirror the committed clipboard.json, so the viewer behaves sanely
// even if the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border (outline) width. `borderCfg` holds the raw clipboard.json
    // value (a number OR a geometry token name like "border"/"sm"); `border` is a live
    // binding that re-resolves it via Geometry.px — so it tracks BOTH a clipboard.json
    // edit AND a Geometry change (w-style apply geometry). Must stay a binding (see
    // LauncherConfig for why).
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    // Max characters of an entry's preview shown in a row (the stored value is always
    // full — cliphist decode recalls it byte-for-byte). Long entries elide past this.
    property int maxPreview: 120

    // Master on/off for the whole clipboard manager. When false the $mod+V viewer
    // won't open AND w-cliphist-store (the watch-daemon gate) records nothing — one
    // toggle, read live by both the QML viewer and the shell gate. A foundation for
    // the future system-settings UI.
    property bool enabled: true

    // Drop password-manager-flagged offers (x-kde-passwordManagerHint=secret) from the
    // history. Consumed by w-cliphist-store, NOT by this QML — exposed here so a
    // settings UI has a single binding surface for the whole clipboard feature.
    property bool filterSensitive: true

    // Show image thumbnails in the list (decoded lazily per visible row). Off → the
    // image type glyph is used instead, like text rows.
    property bool showThumbnails: true
    // Side of the square leading media cell (glyph OR thumbnail). Rows stay one height.
    property int thumbSize: 32

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined)          root.borderCfg       = c.border;
            if (c.maxPreview !== undefined)      root.maxPreview      = c.maxPreview;
            if (c.enabled !== undefined)         root.enabled         = c.enabled;
            if (c.filterSensitive !== undefined) root.filterSensitive = c.filterSensitive;
            if (c.showThumbnails !== undefined)  root.showThumbnails  = c.showThumbnails;
            if (c.thumbSize !== undefined)       root.thumbSize       = c.thumbSize;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/clipboard.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
