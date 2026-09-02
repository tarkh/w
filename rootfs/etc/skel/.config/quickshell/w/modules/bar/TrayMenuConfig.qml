pragma Singleton

// W Linux — tray context-menu config for the Quickshell shell.
// Like BarConfig/NotifConfig (and unlike Colors/Motion/Fonts, which w-style renders
// from the active theme), this is a USER-OWNED config: w-style/w-theme never touch
// it. Edit config/traymenu.json and the running shell picks it up live via
// FileView{watchChanges} — no restart. Defaults below mirror the committed json so
// the menu behaves sanely even if the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Default follows the theme's Geometry scale (база); traymenu.json may override
    // with an absolute number OR a geometry token name (override). radiusCfg = raw
    // traymenu.json value; radius = live binding via Geometry.px (tracks json edit
    // AND Geometry change) — same pattern as border below.
    property var  radiusCfg: "radius"
    readonly property int radius: Geometry.px(radiusCfg, Geometry.radius)     // menu card corner radius
    // Menu card outer border width. borderCfg = raw traymenu.json value (number or token);
    // border = live binding via Geometry.px (tracks json edit AND Geometry change).
    property var  borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)
    // opacityCfg = raw traymenu.json value (number or token "surface"/"scrim"); opacity is a LIVE
    // binding via Effects.op (tracks json edit AND theme) — never resolve eagerly (load-order bug).
    property var  opacityCfg: "surface"
    readonly property real opacity: Effects.op(opacityCfg, Effects.surfaceOpacity)  // card bg translucency; content stays opaque
    // Shifts the menu from its bar-aware baseline. The baseline is the bar's
    // reserved zone + Hyprland gap (contentTop for a top bar, contentBottom for a
    // bottom bar) — the same offset OSD/notifications use. marginOffset always
    // changes that offset the same way: + grows it (menu further from the edge),
    // - shrinks it (closer to the edge), regardless of bar position.
    property int  marginOffset: 0

    // Icon shading for the menu's own item icons (via the shared ShadedIcon) —
    // configured here, separately from the bar's tray-icon shading, since the menu
    // is its own element. Same knobs as the power menu:
    //   iconMode     — "tint" | "solid" | "original"
    //   iconStrength — mix original ↔ duotone (0..1)
    //   iconShade    — shadow end as a fraction of the tint (0 = black, 1 = tint)
    //   iconLift     — highlight lift toward white (0 = pure tint, 1 = white)
    // The tint color itself is Colors.iconTint (W_QS_ICON_TINT), not set here.
    property string iconMode:     "tint"
    property real   iconStrength: 0.8
    property real   iconShade:    0.2
    property real   iconLift:     0.4

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.radius       !== undefined) root.radiusCfg    = c.radius;
            if (c.border       !== undefined) root.borderCfg    = c.border;
            if (c.opacity      !== undefined) root.opacityCfg    = c.opacity;  // raw; opacity binding resolves live
            if (c.marginOffset !== undefined) root.marginOffset = c.marginOffset;
            if (c.iconMode     !== undefined) root.iconMode     = c.iconMode;
            if (c.iconStrength !== undefined) root.iconStrength = c.iconStrength;
            if (c.iconShade    !== undefined) root.iconShade    = c.iconShade;
            if (c.iconLift     !== undefined) root.iconLift     = c.iconLift;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/traymenu.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
