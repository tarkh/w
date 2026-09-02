pragma Singleton

// W Linux — power-menu icon-shading config for the Quickshell shell.
// USER-OWNED (w-style/w-theme never touch it), mirrors LauncherConfig: edit
// powermenu.json and the running shell picks it up live via FileView{watchChanges}.
// The power-menu tiles draw Papirus full-color action icons (system-shutdown,
// system-suspend…) recolored into the brand through the shared ShadedIcon, so a
// theme switch and these knobs control their look — not the icon theme.
// Defaults below mirror the committed powermenu.json so the menu behaves sanely if
// the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border (outline) width. `borderCfg` holds the raw powermenu.json value
    // (a number OR a geometry token name like "border"/"sm"); `border` is a live binding
    // re-resolved via Geometry.px — tracks BOTH a powermenu.json edit AND a Geometry change
    // (w-style apply geometry). Must stay a binding (imperative assign would freeze it).
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    // Icon shading (via the shared ShadedIcon component):
    //   "tint"     — premium brand duotone (luminance → brand ramp). Default.
    //   "solid"    — flat brand silhouette.
    //   "original" — no recolor (raw multicolor Papirus icons).
    property string iconMode: "tint"
    // Live-tunable duotone shape for "tint" mode (the tint COLOR is the theme's
    // Colors.iconTint = W_QS_ICON_TINT, not set here). Edit powermenu.json to tune:
    //   iconStrength — mix original ↔ duotone (0..1)
    //   iconShade    — shadow end as a fraction of the tint (0 = black, 1 = tint)
    //   iconLift     — highlight lift toward white (0 = pure tint, 1 = white)
    property real iconStrength: 1.0
    property real iconShade: 0.9
    property real iconLift: 0.5

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined)       root.borderCfg    = c.border;
            if (c.iconMode !== undefined)     root.iconMode     = c.iconMode;
            if (c.iconStrength !== undefined) root.iconStrength = c.iconStrength;
            if (c.iconShade !== undefined)    root.iconShade    = c.iconShade;
            if (c.iconLift !== undefined)     root.iconLift     = c.iconLift;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/powermenu.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
