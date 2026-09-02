pragma Singleton

// W Linux — auth prompt behaviour config for the Quickshell shell.
// USER-OWNED config (like LauncherConfig/NotifConfig): w-style/w-theme never touch it.
// Edit auth.json and the running shell picks it up live via FileView{watchChanges}.
// Defaults below mirror the committed auth.json, so the prompt behaves sanely even if
// the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border width. `borderCfg` holds the raw auth.json value (a number OR a
    // geometry token like "border"/"sm"); `border` re-resolves it live via Geometry.px.
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    // Backdrop dim under the card. The user chose dim WITHOUT blur (unlike the launcher's
    // frosted backdrop) so the context stays legible — "what am I authorizing" — while the
    // card is clearly the focus. Opacity of the scrim over the theme backdrop color.
    property real dim: 0.45

    // Compact dialog width (a password prompt, not the 720px list-modal width).
    property int cardWidth: 460

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined)    root.borderCfg  = c.border;
            if (c.dim !== undefined)       root.dim        = c.dim;
            if (c.cardWidth !== undefined) root.cardWidth  = c.cardWidth;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/auth.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
