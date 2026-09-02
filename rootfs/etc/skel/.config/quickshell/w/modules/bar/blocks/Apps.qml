// W Linux bar block — open apps (taskbar).
// Same zone/button styling as Workspaces, but each button is an open window's icon
// (via Hyprland toplevels → appId → themed icon, brand-shaded through ShadedIcon
// like the launcher). The focused window gets the "active" tone; clicking focuses
// the window (which also switches to its workspace). Colors resolve through
// BarConfig.col; icon shading is configured per the launcher.json scheme.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.shading

Item {
    id: block
    property var settings: ({})

    // Wayland app_id (X11 WM_CLASS under XWayland) of a toplevel, "" if unknown.
    function appIdOf(t) { return t && t.wayland ? (t.wayland.appId || "") : "" }

    // Failsafe against misbehaving apps (e.g. Electron under XWayland) that spawn
    // ephemeral surfaces — menus/tooltips — as foreign-toplevels with no app_id.
    // Without this they render as empty buttons and linger after the app exits.
    // A real taskbar entry always carries an app_id; everything else is dropped.
    readonly property var windows: Hyprland.toplevels.values.filter(t => block.appIdOf(t).length > 0)

    // Collapse the whole block (zone + its gap) when no windows are open.
    readonly property bool barVisible: windows.length > 0

    // Resolve a window's icon name the same way the launcher does: map the app_id
    // to its desktop entry (heuristicLookup also matches StartupWMClass) and use its
    // Icon= field. Many apps (notably Electron) report an app_id that is NOT itself a
    // themed-icon name, which is why the bar showed blanks while the launcher didn't.
    // Fall back to a direct theme lookup, then to the default glyph in ShadedIcon.
    function iconNameFor(appId) {
        if (!appId) return "";
        const e = DesktopEntries.heuristicLookup(appId);
        if (e && e.icon) return e.icon;
        return Quickshell.hasThemeIcon(appId) ? appId : "";
    }

    // Zone.
    readonly property var zonePad: settings.zonePadding || ({})
    readonly property var zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    // Button strips are inset evenly (padGroup), unlike the text blocks' left/right padding.
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padGroup)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padGroup)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padGroup)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padGroup)

    // Buttons + icon.
    readonly property int buttonGap:    BarConfig.geo(settings.buttonGap, BarConfig.gapButton)
    readonly property var buttonRadius: settings.buttonRadius !== undefined ? settings.buttonRadius : BarConfig.radiusButton
    readonly property int buttonSize:   settings.buttonSize   !== undefined ? settings.buttonSize   : 0   // 0 = square (band height)
    readonly property int buttonBorder: BarConfig.geo(settings.buttonBorderWidth, BarConfig.borderButton)
    readonly property int iconSize:     settings.iconSize     !== undefined ? settings.iconSize     : 18

    // Icon shading (mirrors launcher.json: tint / smart / solid / original).
    function iconModeFor(mono) {
        switch (settings.iconMode) {
        case "tint":   return ShadedIcon.Tint;
        case "solid":  return ShadedIcon.Solid;
        case "smart":  return mono ? ShadedIcon.Solid : ShadedIcon.Original;
        default:       return ShadedIcon.Original;   // recognizable app logos by default
        }
    }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    Rectangle {
        id: zone
        anchors.centerIn: parent
        height: parent.height
        implicitWidth: row.implicitWidth + block.padL + block.padR
        radius: BarConfig.elemRadius(block.zoneRadius, height, 0)
        color:  BarConfig.col(block.settings.zoneColor, block.settings.zoneOpacity)
        border.width: BarConfig.zoneBorderWidth(block.settings)
        border.color: BarConfig.zoneBorderColor(block.settings)

        Row {
            id: row
            anchors.left: parent.left
            anchors.leftMargin: block.padL
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - block.padT - block.padB
            spacing: block.buttonGap

            Repeater {
                model: block.windows
                delegate: appButton
            }
        }
    }

    Component {
        id: appButton
        Rectangle {
            id: btn
            required property var modelData
            readonly property string appId: block.appIdOf(modelData)
            readonly property string iconName: block.iconNameFor(appId)
            readonly property bool isActive: Hyprland.activeToplevel && modelData.address === Hyprland.activeToplevel.address
            readonly property bool mono: iconName.length > 0 && Quickshell.hasThemeIcon(iconName + "-symbolic")

            height: parent.height
            width:  block.buttonSize > 0 ? block.buttonSize : height
            radius: BarConfig.elemRadius(block.buttonRadius, height, 6)
            color: isActive
                ? BarConfig.col(block.settings.buttonActiveColor, block.settings.buttonActiveOpacity)
                : BarConfig.col(block.settings.buttonColor, block.settings.buttonOpacity)
            border.width: block.buttonBorder
            border.color: BarConfig.buttonBorderColor(block.settings)

            Behavior on color {
                ColorAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            ClickFlash {
                id: flash
                anchors.fill: parent
                radius: btn.radius
                colorLeft:   block.settings.clickColorLeft
                colorRight:  block.settings.clickColorRight
                apexOpacity: block.settings.clickOpacity  !== undefined ? block.settings.clickOpacity  : 0.5
                duration:    block.settings.clickDuration !== undefined ? block.settings.clickDuration : Motion.base
            }

            ShadedIcon {
                anchors.centerIn: parent
                icon: btn.iconName
                // No themed icon at all (e.g. some Electron apps) → default app glyph.
                fallbackGlyph: String.fromCodePoint(0xf08c6)   // nf-md-application
                size: block.iconSize
                mode: block.iconModeFor(btn.mono)
                tint: Colors.iconTint
                strength: block.settings.iconStrength !== undefined ? block.settings.iconStrength : 1.0
                shade:    block.settings.iconShade    !== undefined ? block.settings.iconShade    : 0.45
                lift:     block.settings.iconLift     !== undefined ? block.settings.iconLift     : 0.20
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
                acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
                onPressed: (mouse) => flash.pulse(mouse.button)
                // Activating the toplevel handle focuses it AND switches to its
                // workspace; fall back to a Hyprland dispatch if the handle is gone.
                onClicked: (mouse) => {
                    if (mouse.button !== Qt.LeftButton) return;
                    if (btn.modelData.wayland) btn.modelData.wayland.activate();
                    else Hyprland.dispatch('hl.dsp.focus({ window = "address:' + btn.modelData.address + '" })');
                }
            }
        }
    }
}
