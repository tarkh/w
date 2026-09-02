// W Linux bar block — disk usage.
// Shows filesystem usage for a mountpoint with an optional Nerd Font drive glyph,
// inside an optional zone background — same settings shape as the cpu/ram/battery
// blocks. There's no procfs counter for free space, so it runs `df` on a Timer (a far
// longer interval than the live blocks — disks move slowly). The threshold always
// tracks the used percentage; "display" only changes what text is shown. At/above
// highThreshold the text+glyph switch to highColor (battery's lowColor convention).
// Click opens btop in W's terminal.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool   showIcon:      settings.showIcon      !== undefined ? settings.showIcon      : true
    readonly property int    fontSize:      settings.fontSize      !== undefined ? settings.fontSize      : 12
    readonly property int    interval:      settings.interval      !== undefined ? settings.interval      : 30000
    readonly property int    highThreshold: settings.highThreshold !== undefined ? settings.highThreshold : 90
    readonly property string path:          settings.path          !== undefined ? settings.path          : "/"
    readonly property string display:       settings.display       !== undefined ? settings.display       : "percent" // percent | used | free | usedTotal
    readonly property var    zoneRadius:    settings.zoneRadius    !== undefined ? settings.zoneRadius    : BarConfig.radiusZone
    readonly property var    zonePad:       settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    property real usedB: 0
    property real sizeB: 0
    readonly property real freeB: Math.max(0, sizeB - usedB)
    readonly property int  pct:   sizeB > 0 ? Math.round(100 * usedB / sizeB) : 0
    readonly property bool over:  pct >= block.highThreshold

    Process {
        id: proc
        command: ["df", "-B1", "--output=used,size", block.path]
        stdout: StdioCollector { onStreamFinished: {
            // header line + one data line: "<used> <size>" (bytes).
            const lines = (this.text || "").trim().split("\n");
            if (lines.length < 2) return;
            const f = lines[lines.length - 1].trim().split(/\s+/);
            block.usedB = parseInt(f[0]) || 0;
            block.sizeB = parseInt(f[1]) || 0;
        } }
    }
    Timer {
        interval: block.interval; running: true; repeat: true; triggeredOnStart: true
        onTriggered: proc.running = true
    }

    // bytes → "12.3G" / "1.5T" / "640M".
    function human(b) {
        const g = b / 1073741824;
        if (g >= 1024) return (g / 1024).toFixed(1) + "T";
        return g >= 1 ? g.toFixed(1) + "G" : Math.round(b / 1048576) + "M";
    }
    function valueText() {
        if (block.display === "used")      return block.human(block.usedB);
        if (block.display === "free")      return block.human(block.freeB);
        if (block.display === "usedTotal") return block.human(block.usedB) + "/" + block.human(block.sizeB);
        return block.pct + "%";
    }
    // Widest plausible string for the active mode — what the value field reserves.
    function reserveText() {
        if (block.display === "used" || block.display === "free") return "999.9G";
        if (block.display === "usedTotal")                        return "999.9G/999.9G";
        return "100%";
    }

    function fg(role) {
        if (block.over)
            return BarConfig.col(
                block.settings.highColor   !== undefined ? block.settings.highColor   : "dangerBorder",
                block.settings.highOpacity !== undefined ? block.settings.highOpacity : 1.0);
        if (role === "icon")
            return BarConfig.col(
                block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity);
        return BarConfig.col(block.settings.textColor, block.settings.textOpacity);
    }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    // Reserve the widest value for the active display mode so the block width is fixed.
    TextMetrics {
        id: vm
        font.family: Fonts.family
        font.pixelSize: block.fontSize
        font.features: ({ "tnum": 1 })
        text: block.reserveText()
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
                text: BarConfig.glyph(block.settings.icon, undefined, String.fromCodePoint(0xf0a0))  // nf-fa-hdd_o
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: block.valueText()
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
            onClicked: (mouse) => { if (mouse.button === Qt.LeftButton) Quickshell.execDetached(Term.exec(["btop"])); }
        }
    }
}
