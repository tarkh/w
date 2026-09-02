// W Linux bar block — battery.
// Shows the battery charge as a percentage with a Nerd Font glyph that follows the
// level, inside an optional zone background — same settings shape as the clock and
// volume blocks. The icon comes from bar.json as an object { levels: [5 glyphs full→
// empty], charging } (a bare glyph string degrades to that one glyph everywhere). A
// small bolt prefixes the glyph while charging; at/below lowThreshold (and not
// charging) the text/glyph switch to lowColor. Reads the UPower display device
// natively and auto-hides on machines without a laptop battery (barVisible → the zone
// and its gap collapse, like apps/tray with no items). The percentage uses tabular
// figures and reserves the width of "100%" so the block never jitters. Not interactive.
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:     settings.showIcon     !== undefined ? settings.showIcon     : true
    readonly property bool showPercent:  settings.showPercent  !== undefined ? settings.showPercent  : true
    readonly property int  fontSize:     settings.fontSize     !== undefined ? settings.fontSize     : 12
    readonly property var  zoneRadius:   settings.zoneRadius   !== undefined ? settings.zoneRadius   : BarConfig.radiusZone
    readonly property int  lowThreshold: settings.lowThreshold !== undefined ? settings.lowThreshold : 15
    readonly property var  zonePad:      settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    readonly property var  dev:      UPower.displayDevice
    // Until the device is ready isLaptopBattery can read false — gate on ready so the
    // block doesn't flash in on startup before UPower has answered.
    readonly property bool barVisible: dev && dev.ready && dev.isLaptopBattery
    // Quickshell normalizes UPower percentage to a 0..1 fraction (not 0..100).
    readonly property int  level:    dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging
                                          || dev.state === UPowerDeviceState.FullyCharged
                                          || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool low:      level <= block.lowThreshold && !charging

    // Default level ramp (nf-fa, full f240 → empty f244) + charging bolt (f0e7).
    // Built with String.fromCodePoint so the file stays pure ASCII (raw PUA chars can
    // get dropped on write). bar.json overrides via "icon": { levels:[...], charging }.
    readonly property var defaultLevels: [
        String.fromCodePoint(0xf240), String.fromCodePoint(0xf241),
        String.fromCodePoint(0xf242), String.fromCodePoint(0xf243),
        String.fromCodePoint(0xf244)
    ]

    // Battery level glyph: a bare icon string applies to every level; otherwise pick
    // from the levels array by the same thresholds, per-entry falling back to the
    // built-in ramp when an entry is missing/empty (so the icon never goes blank).
    function levelGlyph() {
        const ic = block.settings.icon;
        if (typeof ic === "string" && ic.length > 0) return ic;
        const lv = (ic && Array.isArray(ic.levels)) ? ic.levels : [];
        const i = level >= 90 ? 0 : level >= 65 ? 1 : level >= 40 ? 2 : level >= 15 ? 3 : 4;
        return (lv[i] && lv[i].length > 0) ? lv[i] : block.defaultLevels[i];
    }

    function fg(role) {
        // role: "text" | "icon" — low state overrides both with lowColor.
        if (block.low)
            return BarConfig.col(
                block.settings.lowColor   !== undefined ? block.settings.lowColor   : "dangerBorder",
                block.settings.lowOpacity !== undefined ? block.settings.lowOpacity : 1.0);
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
                visible: block.showIcon && block.charging
                anchors.verticalCenter: parent.verticalCenter
                text: BarConfig.glyph(block.settings.icon, "charging", String.fromCodePoint(0xf0e7))  // nf-fa-bolt
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                visible: block.showIcon
                anchors.verticalCenter: parent.verticalCenter
                text: block.levelGlyph()
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

        // Not interactive yet (a battery/power-profile popup may come later); the
        // MouseArea just carries the click-flash + cursor controls. Default cursor
        // is the arrow.
        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.ArrowCursor)
            acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
            onPressed: (mouse) => flash.pulse(mouse.button)
        }
    }
}
