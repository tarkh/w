// W Linux bar block — screen brightness.
// Shows the backlight level as a percentage with an optional Nerd Font sun glyph
// (icon from bar.json), inside an optional zone background — same settings shape as
// the clock/volume/battery blocks. Quickshell has no native backlight service, so we
// read sysfs: a one-shot `brightnessctl -m -c backlight` at startup auto-detects the
// default backlight device (no config needed), then FileView watches its sysfs
// `brightness` for live updates (same approach as the OSD, no polling). Auto-hides on
// machines without a backlight (desktops, VMs): brightnessctl prints nothing → devName
// stays empty → barVisible false → the zone and its gap collapse (like battery without
// a laptop battery). The percentage uses tabular figures and reserves the width of
// "100%" so the block never jitters. Clicking opens the Brightness Control popup (same
// pattern as the Volume block).
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:    settings.showIcon    !== undefined ? settings.showIcon    : true
    readonly property bool showPercent: settings.showPercent !== undefined ? settings.showPercent : true
    readonly property int  fontSize:    settings.fontSize    !== undefined ? settings.fontSize    : 12
    readonly property var  zoneRadius:  settings.zoneRadius  !== undefined ? settings.zoneRadius  : BarConfig.radiusZone
    readonly property var  zonePad:     settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    // Detected backlight device name (e.g. "intel_backlight"); empty → no backlight.
    property string devName: ""
    property real   bmax:    1
    property int    braw:    0
    readonly property bool barVisible: devName !== ""
    readonly property int  level:      Math.round((braw / bmax) * 100)

    // Discover the default backlight device once. `-c backlight` ignores led-class
    // devices (keyboard backlight); the machine-readable line is
    // "name,class,current,percent,max" — we only need the name for the sysfs path.
    Process {
        running: true
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (this.text || "").trim().split("\n")[0] || "";
                block.devName = line ? (line.split(",")[0] || "") : "";
            }
        }
    }

    FileView {
        path: block.devName ? "/sys/class/backlight/" + block.devName + "/max_brightness" : ""
        onLoaded: block.bmax = Math.max(1, parseInt(text()) || 1)
    }
    FileView {
        path: block.devName ? "/sys/class/backlight/" + block.devName + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: block.braw = parseInt(text()) || 0
    }

    function fg(role) {
        if (role === "icon")
            return BarConfig.col(
                block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity);
        return BarConfig.col(block.settings.textColor, block.settings.textOpacity);
    }

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
                text: BarConfig.glyph(block.settings.icon, undefined, Glyphs.brightness)
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                visible: block.showPercent
                anchors.verticalCenter: parent.verticalCenter
                text: block.level + "%"
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                font.features: ({ "tnum": 1 })   // tabular figures: constant digit width
                width: Math.max(implicitWidth, vm.advanceWidth)
                horizontalAlignment: Text.AlignHCenter
                color: block.fg("text")
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
            onPressed: (mouse) => flash.pulse(mouse.button)
            onClicked: (mouse) => { if (mouse.button === Qt.LeftButton) Hyprland.dispatch('hl.dsp.global("quickshell:brightnesscontrol")'); }
        }
    }
}
