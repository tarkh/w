// W Linux bar block — workspaces.
// Numbered Hyprland workspaces as clickable buttons inside an optional zone
// background. The focused workspace gets the "active" tone/font; clicking a button
// switches to it. Colors resolve through BarConfig.col (theme token or #hex + a
// separate per-element opacity) so any element can be made fully transparent (e.g.
// a button with no border). Tone transitions use Motion (synced with Hyprland).
//
// Special workspaces (the scratchpad: negative id, name "special:<x>") are part of
// Hyprland.workspaces too. They render as a glyph button after the numbered ones
// (by id they would sort first), get the active tone while shown on the focused
// monitor, and toggle on click. Quickshell never marks a special workspace
// `focused` (it does not consume the `activespecial` event), so the shown state is
// read from the monitor's IPC object, refreshed on the raw `activespecialv2` event.
// `special:w-restore` is w-session's parking area — an implementation detail that
// must never surface as a button (a click would expose it mid-restore).
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    // Zone (the strip behind all buttons).
    readonly property var zonePad: settings.zonePadding || ({})
    readonly property var zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    // Button strips are inset evenly (padGroup), unlike the text blocks' left/right padding.
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padGroup)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padGroup)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padGroup)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padGroup)

    // Buttons.
    readonly property int buttonGap:    BarConfig.geo(settings.buttonGap, BarConfig.gapButton)
    readonly property var buttonRadius: settings.buttonRadius !== undefined ? settings.buttonRadius : BarConfig.radiusButton
    readonly property int buttonSize:   settings.buttonSize   !== undefined ? settings.buttonSize   : 0  // 0 = square (band height)
    readonly property int buttonBorder: BarConfig.geo(settings.buttonBorderWidth, BarConfig.borderButton)
    readonly property int fontSize:     settings.fontSize     !== undefined ? settings.fontSize     : 12
    readonly property string specialGlyph: BarConfig.glyph(settings.icon, undefined, String.fromCodePoint(0xf0328))  // nf-md-layers

    // Name of the special workspace currently shown on the focused monitor ("" = none).
    readonly property string shownSpecial: {
        const m = Hyprland.focusedMonitor;
        const s = m && m.lastIpcObject ? m.lastIpcObject.specialWorkspace : null;
        return s && s.name ? s.name : "";
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "activespecialv2") Hyprland.refreshMonitors(); }
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
                // Numbered ascending (left→right by workspace number), specials last.
                model: [...Hyprland.workspaces.values]
                    .filter(w => w.name !== "special:w-restore")
                    .sort((a, b) => (a.id < 0) - (b.id < 0) || a.id - b.id)
                delegate: wsButton
            }
        }
    }

    Component {
        id: wsButton
        Rectangle {
            id: btn
            required property var modelData
            readonly property bool isSpecial: modelData.id < 0
            readonly property bool isActive: isSpecial ? block.shownSpecial === modelData.name : modelData.focused

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

            Text {
                anchors.centerIn: parent
                text: btn.isSpecial ? block.specialGlyph : btn.modelData.name
                font.family: btn.isSpecial ? Fonts.mono : Fonts.family
                font.pixelSize: block.fontSize
                color: btn.isActive
                    ? BarConfig.col(block.settings.fontActiveColor   !== undefined ? block.settings.fontActiveColor   : block.settings.fontColor,
                                    block.settings.fontActiveOpacity !== undefined ? block.settings.fontActiveOpacity : block.settings.fontOpacity)
                    : BarConfig.col(block.settings.fontColor, block.settings.fontOpacity)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
                acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
                onPressed: (mouse) => flash.pulse(mouse.button)
                onClicked: (mouse) => {
                    if (mouse.button !== Qt.LeftButton) return;
                    // toggle_special takes the bare name and adds the "special:" prefix itself.
                    Hyprland.dispatch(btn.isSpecial
                        ? 'hl.dsp.workspace.toggle_special("' + btn.modelData.name.replace(/^special:/, "") + '")'
                        : 'hl.dsp.focus({ workspace = ' + btn.modelData.id + ' })');
                }
            }
        }
    }
}
