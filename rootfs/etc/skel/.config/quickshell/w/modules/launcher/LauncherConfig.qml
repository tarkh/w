pragma Singleton

// W Linux — launcher behaviour config for the Quickshell shell.
// Like NotifConfig, this is a USER-OWNED config: w-style/w-theme never touch it.
// Edit launcher.json and the running shell picks it up live via FileView{watchChanges}.
// Defaults below mirror the committed launcher.json, so the launcher behaves sanely
// even if the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border (outline) width. `borderCfg` holds the raw launcher.json value
    // (a number OR a geometry token name like "border"/"sm"); `border` is a live binding
    // that re-resolves it via Geometry.px — so it tracks BOTH a launcher.json edit AND a
    // Geometry change (w-style apply geometry). Must stay a binding: assigning border
    // imperatively in apply() would freeze it (theme change → no live update till relogin).
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    // Sort the (unfiltered) app list by launch frequency, most-used first, with
    // never-launched apps falling alphabetically below. Also a tiebreaker for
    // equally-scored search results. See LauncherUsage for the persisted chart.
    property bool rankByUsage: true

    // Icon shading (via the shared ShadedIcon component):
    //   "tint"     — premium brand duotone on every icon, logos included (mac-style).
    //   "smart"    — colorful app logos stay original; only monochrome/symbolic
    //                system icons (Volume Control, Avahi…) get a flat brand tint.
    //   "solid"    — every icon as a flat brand silhouette.
    //   "original" — no recolor.
    property string iconMode: "tint"
    // Live-tunable duotone shape for "tint" mode (the tint COLOR is the theme's
    // Colors.iconTint = W_QS_ICON_TINT, not set here). Edit launcher.json to tune:
    //   iconStrength — mix original ↔ duotone (0..1)
    //   iconShade    — shadow end as a fraction of the tint (0 = black, 1 = tint)
    //   iconLift     — highlight lift toward white (0 = pure tint, 1 = white)
    property real iconStrength: 0.9
    property real iconShade: 0.45
    property real iconLift: 0.20

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined)       root.borderCfg    = c.border;
            if (c.rankByUsage !== undefined)  root.rankByUsage  = c.rankByUsage;
            if (c.iconMode !== undefined)     root.iconMode     = c.iconMode;
            if (c.iconStrength !== undefined) root.iconStrength = c.iconStrength;
            if (c.iconShade !== undefined)    root.iconShade    = c.iconShade;
            if (c.iconLift !== undefined)     root.iconLift     = c.iconLift;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/launcher.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
