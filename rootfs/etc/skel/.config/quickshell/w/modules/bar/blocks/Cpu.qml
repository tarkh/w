// W Linux bar block — CPU usage.
// Shows total CPU load as a percentage with an optional Nerd Font chip glyph (icon
// from bar.json), inside an optional zone background — same settings shape as the
// clock/battery/brightness blocks. Quickshell has no native CPU service; /proc/stat
// doesn't emit inotify on value changes, so a Timer drives FileView.reload() (poll,
// not watch). Usage is the delta of busy vs idle jiffies between two ticks (the first
// sample is since-boot average, then it tracks live). At/above highThreshold the
// text+glyph switch to highColor (same convention as battery's lowColor). The value
// uses tabular figures and reserves the width of "100%" so the block never jitters.
// Click opens btop in W's terminal.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:      settings.showIcon      !== undefined ? settings.showIcon      : true
    readonly property bool showPercent:   settings.showPercent   !== undefined ? settings.showPercent   : true
    readonly property int  fontSize:      settings.fontSize      !== undefined ? settings.fontSize      : 12
    readonly property int  interval:      settings.interval      !== undefined ? settings.interval      : 2000
    readonly property int  highThreshold: settings.highThreshold !== undefined ? settings.highThreshold : 85
    readonly property var  zoneRadius:    settings.zoneRadius    !== undefined ? settings.zoneRadius    : BarConfig.radiusZone
    readonly property var  zonePad:       settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    // Previous cumulative jiffies, for the busy/idle delta across ticks.
    property real prevIdle:  0
    property real prevTotal: 0
    property int  level:     0
    readonly property bool over: level >= block.highThreshold

    Timer { interval: block.interval; running: true; repeat: true; onTriggered: stat.reload() }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            // "cpu  user nice system idle iowait irq softirq steal guest guest_nice"
            const line = ((text() || "").split("\n")[0] || "").trim();
            const f = line.split(/\s+/);
            if (f.length < 6 || f[0] !== "cpu") return;
            let total = 0;
            for (let i = 1; i < f.length; i++) total += parseInt(f[i]) || 0;
            const idle = (parseInt(f[4]) || 0) + (parseInt(f[5]) || 0); // idle + iowait
            const dTotal = total - block.prevTotal;
            const dIdle  = idle  - block.prevIdle;
            block.prevTotal = total;
            block.prevIdle  = idle;
            if (dTotal > 0) block.level = Math.max(0, Math.min(100, Math.round(100 * (1 - dIdle / dTotal))));
        }
    }

    function fg(role) {
        // role: "text" | "icon" — over-threshold overrides both with highColor.
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
                text: BarConfig.glyph(block.settings.icon, undefined, String.fromCodePoint(0xf4bc))  // nf-oct-cpu
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
            onClicked: (mouse) => { if (mouse.button === Qt.LeftButton) Quickshell.execDetached(Term.exec(["btop"])); }
        }
    }
}
