// W Linux bar block — button (generic launcher).
// A clickable pill that runs a shell command on left-click and (optionally) a
// different one on right-click. It carries an optional icon and an optional label,
// with a gap between them that vanishes when either side is absent (Row spacing only
// applies between visible children).
//
// The icon accepts, like the Zone fold handle:
//   • a Nerd Font glyph string        → drawn as text (colored by iconColor)
//   • a theme-icon name / png / svg    → drawn via ShadedIcon (honors iconMode)
//   • the special keyword "w-logo"     → the active theme's brand SVG (Logo.svg,
//                                        theme-aware + live via w-style)
// Image icons are brand-shaded through ShadedIcon per iconMode (tint/solid/original/
// smart) + iconStrength/iconShade/iconLift, exactly like apps/tray/zone icons.
//
// Actions run detached via `sh -c` so any command works; the shell's own popups are
// reached through their Hyprland globals, e.g. hyprctl dispatch
// 'hl.dsp.global("quickshell:launcher")'. An empty command is a no-op. Right-click is accepted only when a right
// command (or a right click-flash color) is configured.
//
// All colors go through BarConfig.col (theme token or #hex + separate opacity); the
// block fills the bar's content-band height and sizes its width to its content.
import Quickshell
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.shading

Item {
    id: block

    // Set by the Bar Loader from the block's "settings" object in bar.json.
    property var settings: ({})

    // ── Content ───────────────────────────────────────────────────────────────
    readonly property string icon:  settings.icon  !== undefined ? settings.icon  : ""
    readonly property string label: settings.label !== undefined ? settings.label : ""
    readonly property int    iconSize: settings.iconSize !== undefined ? settings.iconSize : 16
    readonly property int    fontSize: settings.fontSize !== undefined ? settings.fontSize : 12
    readonly property int    gap:      settings.gap      !== undefined ? settings.gap      : 6

    // ── Actions (detached shell commands) ─────────────────────────────────────
    readonly property string commandLeft:  settings.commandLeft  !== undefined ? settings.commandLeft  : ""
    readonly property string commandRight: settings.commandRight !== undefined ? settings.commandRight : ""
    function run(cmd) { if (cmd && cmd.length > 0) Quickshell.execDetached(["sh", "-c", cmd]); }

    // ── Icon classification ───────────────────────────────────────────────────
    // "w-logo" resolves to the theme brand SVG; otherwise an icon string is an image
    // when it looks like a path / has an extension / is a theme icon, else a glyph.
    readonly property bool isLogo:     icon === "w-logo"
    readonly property bool iconIsPath: icon.indexOf("/") >= 0 || icon.indexOf(".") >= 0
    readonly property bool iconIsImage: icon.length > 0
                            && (isLogo || iconIsPath || Quickshell.hasThemeIcon(icon))
    readonly property string imageSource:
        isLogo ? Logo.svg
               : (iconIsPath ? (icon.charAt(0) === "/" ? "file://" + icon : icon) : "")
    function iconShadeMode() {
        switch (settings.iconMode) {
        case "tint":  return ShadedIcon.Tint;
        case "solid": return ShadedIcon.Solid;
        default:      return ShadedIcon.Original;
        }
    }

    // ── Zone (the button itself) ──────────────────────────────────────────────
    readonly property var zonePad:    settings.zonePadding || ({})
    readonly property var zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    Rectangle {
        id: zone
        anchors.centerIn: parent
        height: parent.height - block.padT - block.padB
        implicitWidth: Math.max(contentRow.implicitWidth + block.padL + block.padR, BarConfig.minSquare ? height : 0)
        radius: BarConfig.elemRadius(block.zoneRadius, height, 0)
        color:  BarConfig.col(block.settings.zoneColor, block.settings.zoneOpacity)
        // Zone outline, same contract as every other block ("zoneBorder*"); the width
        // follows the theme unless bar.json overrides it.
        border.width: BarConfig.zoneBorderWidth(block.settings)
        border.color: BarConfig.zoneBorderColor(block.settings)

        ClickFlash {
            id: flash
            anchors.fill: parent
            radius: zone.radius
            colorLeft:   block.settings.clickColorLeft
            colorRight:  block.settings.clickColorRight
            apexOpacity: block.settings.clickOpacity  !== undefined ? block.settings.clickOpacity  : 0.5
            duration:    block.settings.clickDuration !== undefined ? block.settings.clickDuration : Motion.base
        }

        Row {
            id: contentRow
            // Left-anchored so zonePadding.left/.right act as independent gaps
            // (mirrors Clock/Zone). spacing is the icon↔label gap; an absent side
            // drops out of the Row, so the gap disappears with it.
            anchors.left: parent.left
            anchors.leftMargin: BarConfig.minSquare ? (zone.width - contentRow.implicitWidth) / 2 : block.padL
            anchors.verticalCenter: parent.verticalCenter
            spacing: block.gap

            // Glyph icon.
            Text {
                visible: block.icon.length > 0 && !block.iconIsImage
                anchors.verticalCenter: parent.verticalCenter
                text: block.icon
                font.family: Fonts.mono
                font.pixelSize: block.iconSize
                color: BarConfig.col(
                    block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                    block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity)
            }
            // Image / themed / w-logo icon (brand-shaded).
            ShadedIcon {
                visible: block.iconIsImage
                anchors.verticalCenter: parent.verticalCenter
                size: block.iconSize
                icon:   (block.iconIsPath || block.isLogo) ? "" : block.icon
                source: block.imageSource
                mode:   block.iconShadeMode()
                tint:   BarConfig.col(block.settings.iconColor !== undefined ? block.settings.iconColor : "text", 1.0)
                opacity: block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : 1.0
                strength: block.settings.iconStrength !== undefined ? block.settings.iconStrength : 1.0
                shade:    block.settings.iconShade    !== undefined ? block.settings.iconShade    : 0.45
                lift:     block.settings.iconLift     !== undefined ? block.settings.iconLift     : 0.20
            }
            // Label.
            Text {
                visible: block.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: block.label
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                color: BarConfig.col(block.settings.textColor, block.settings.textOpacity)
            }
        }

        // Left-click runs commandLeft; right-click runs commandRight (accepted only
        // when a right command or right click-flash color is set). Carries the shared
        // click-flash + cursor controls; default cursor is the pointing hand.
        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton
                | ((block.commandRight.length > 0 || block.settings.clickColorRight !== undefined)
                   ? Qt.RightButton : Qt.NoButton)
            onPressed: (mouse) => flash.pulse(mouse.button)
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)       block.run(block.commandLeft);
                else if (mouse.button === Qt.RightButton) block.run(block.commandRight);
            }
        }
    }
}
