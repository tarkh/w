// W Linux bar block — volume.
// Shows the default sink's volume as a percentage (optionally with a Nerd Font
// speaker glyph), inside an optional zone background — same settings shape as the
// clock block. The icon comes from bar.json: a bare glyph string, or an object
// { normal, muted } that swaps with the mute state. Clicking opens the custom
// Quickshell Volume Control popup (the same Hyprland global the $mod+A shortcut and
// .desktop entry trigger). Reads PipeWire natively; PwObjectTracker keeps the default
// sink live. The value uses tabular figures and reserves the width of "100%" so the
// block never changes width as the percentage digits change (no neighbor jitter).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:   settings.showIcon   !== undefined ? settings.showIcon   : false
    readonly property int  fontSize:   settings.fontSize   !== undefined ? settings.fontSize   : 12
    readonly property var  zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    readonly property var  zonePad:    settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    readonly property var  sink:   Pipewire.defaultAudioSink
    readonly property bool muted:  sink && sink.audio ? sink.audio.muted : false
    readonly property int  level:  sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

    // Keep the default sink bound so its audio props stay live.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    // Reserve the widest value the field can show ("100%") so the block width is fixed.
    TextMetrics {
        id: vm
        font.family: Fonts.family
        font.pixelSize: block.fontSize
        font.features: ({ "tnum": 1 })
        text: "100%"
    }

    Rectangle {
        id: zone
        anchors.centerIn: parent
        height: parent.height - block.padT - block.padB
        implicitWidth: Math.max(contentRow.implicitWidth + block.padL + block.padR, BarConfig.minSquare ? height : 0)
        radius: BarConfig.elemRadius(block.zoneRadius, height, 0)
        color:  BarConfig.col(block.settings.zoneColor, block.settings.zoneOpacity)
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
            // Anchor to the zone's left edge with the left padding so zonePadding
            // .left/.right act as independent gaps; centering would split any
            // asymmetry evenly across both sides. Mirrors the Zone block.
            anchors.left: parent.left
            anchors.leftMargin: BarConfig.minSquare ? (zone.width - contentRow.implicitWidth) / 2 : block.padL
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                visible: block.showIcon
                anchors.verticalCenter: parent.verticalCenter
                // Default from the shared vocabulary (core/Glyphs.qml) so the bar, the
                // OSD and the audio popup draw the same speaker; bar.json may still
                // override via "icon": { normal, muted }. The bar deliberately keeps a
                // two-state glyph (it prints the percentage next to it) while the OSD
                // uses Glyphs.volume()'s levels.
                text: BarConfig.glyph(block.settings.icon, block.muted ? "muted" : "normal",
                                      block.muted ? Glyphs.volumeOff : Glyphs.volumeHigh)
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: BarConfig.col(
                    block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                    block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: block.level + "%"
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                font.features: ({ "tnum": 1 })   // tabular figures: constant digit width
                width: Math.max(implicitWidth, vm.advanceWidth)
                horizontalAlignment: Text.AlignHCenter
                color: BarConfig.col(block.settings.textColor, block.settings.textOpacity)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
        acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
        onPressed: (mouse) => flash.pulse(mouse.button)
        onClicked: (mouse) => { if (mouse.button === Qt.LeftButton) Hyprland.dispatch('hl.dsp.global("quickshell:volumecontrol")'); }
    }
}
