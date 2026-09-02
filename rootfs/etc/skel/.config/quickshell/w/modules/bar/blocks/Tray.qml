// W Linux bar block — system tray (StatusNotifier / SNI).
// Same zone/button styling as Apps. Each button is a tray item's icon; left click
// activates the item, right click opens its menu (rendered natively by TrayMenu, our
// full-screen overlay — platform/QsMenuAnchor menus never showed on a Top-layer
// panel), middle click is secondary-activate, scroll forwards to the item. The
// button hands TrayMenuState the item's menu handle, its global rect (for placement)
// and our icon-shading settings (so menu icons shade like the tray icons). Tray icons are
// app-provided image sources (not theme names), so they go through ShadedIcon's
// `source` override — full shading parity with Apps (tint/solid/original) via the
// one shared shading component. The block collapses when the tray is empty.
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.shading

// (TrayMenuState / TrayMenu live in qs.modules.bar — the menu overlay is mounted
//  once in shell.qml; this block just asks it to open.)

Item {
    id: block
    property var settings: ({})

    // Collapse the whole block (zone + its gap) when there are no tray items.
    readonly property bool barVisible: SystemTray.items.values.length > 0

    readonly property var zonePad: settings.zonePadding || ({})
    readonly property var zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    // Button strips are inset evenly (padGroup), unlike the text blocks' left/right padding.
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padGroup)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padGroup)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padGroup)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padGroup)

    readonly property int buttonGap:    BarConfig.geo(settings.buttonGap, BarConfig.gapButton)
    readonly property var buttonRadius: settings.buttonRadius !== undefined ? settings.buttonRadius : BarConfig.radiusButton
    readonly property int buttonSize:   settings.buttonSize   !== undefined ? settings.buttonSize   : 0
    readonly property int buttonBorder: BarConfig.geo(settings.buttonBorderWidth, BarConfig.borderButton)
    readonly property int iconSize:     settings.iconSize     !== undefined ? settings.iconSize     : 18

    // Icon shading (mirrors launcher.json; "smart" has no meaning for raw sources).
    function iconMode() {
        switch (settings.iconMode) {
        case "tint":  return ShadedIcon.Tint;
        case "solid": return ShadedIcon.Solid;
        default:      return ShadedIcon.Original;
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
                model: SystemTray.items.values
                delegate: trayButton
            }
        }
    }

    Component {
        id: trayButton
        Rectangle {
            id: btn
            required property var modelData

            height: parent.height
            width:  block.buttonSize > 0 ? block.buttonSize : height
            radius: BarConfig.elemRadius(block.buttonRadius, height, 6)
            color: BarConfig.col(block.settings.buttonColor, block.settings.buttonOpacity)
            border.width: block.buttonBorder
            border.color: BarConfig.buttonBorderColor(block.settings)

            // Click feedback: a colored fill that flashes on left/right click and
            // fades out, so activating / opening a menu gives a clear indication.
            // Sits below the icon (declared first) so the glyph stays crisp. The
            // shared ClickFlash primitive is opt-in via clickColorLeft/clickColorRight
            // (a button with no color set doesn't flash).
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
                source: btn.modelData.icon
                size: block.iconSize
                mode: block.iconMode()
                tint: Colors.iconTint
                strength: block.settings.iconStrength !== undefined ? block.settings.iconStrength : 1.0
                shade:    block.settings.iconShade    !== undefined ? block.settings.iconShade    : 0.45
                lift:     block.settings.iconLift     !== undefined ? block.settings.iconLift     : 0.20
            }

            // Open the item's menu in our native overlay, anchored to this button.
            // We pass the button's global rect for placement; the menu's own look and
            // icon shading come from TrayMenuConfig (separate from the bar's tray
            // icons), so nothing else is forwarded here.
            function openMenu() {
                if (!btn.modelData.hasMenu) return;
                const g = btn.mapToGlobal(0, 0);
                TrayMenuState.show(btn.modelData.menu, Qt.rect(g.x, g.y, btn.width, btn.height));
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: (mouse) => flash.pulse(mouse.button)
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        if (btn.modelData.onlyMenu) btn.openMenu();
                        else btn.modelData.activate();
                    } else if (mouse.button === Qt.RightButton) {
                        btn.openMenu();
                    } else if (mouse.button === Qt.MiddleButton) {
                        btn.modelData.secondaryActivate();
                    }
                }
                onWheel: (wheel) => btn.modelData.scroll(wheel.angleDelta.y, false)
            }
        }
    }
}
