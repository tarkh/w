// W Linux bar block — temperature.
// Shows a temperature reading with an optional Nerd Font thermometer glyph (icon from
// bar.json), inside an optional zone background — same settings shape as the cpu/ram/
// battery blocks. Reads lm_sensors (`sensors -j`), which already normalizes the zoo of
// hwmon/thermal sources across Intel/AMD/laptops, re-run on a Timer (no inotify on these
// values). The chip / label are auto-detected with a sensible preference order (Intel
// coretemp package → AMD k10temp/zenpower → ARM/SoC → ACPI), overridable via sensorChip/
// sensorLabel. Auto-hides when no temperature is found (no lm_sensors / VM): barVisible →
// the zone and its gap collapse, like battery without a laptop battery. Reading is in °C,
// shown in °C or °F (unit). At/above highThreshold the text+glyph switch to highColor.
// The value uses tabular figures and reserves the width of "100°C" so the block never
// jitters. Click opens btop in W's terminal.
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
    readonly property int    interval:      settings.interval      !== undefined ? settings.interval      : 2000
    readonly property int    highThreshold: settings.highThreshold !== undefined ? settings.highThreshold : 80
    readonly property string unit:          settings.unit          !== undefined ? settings.unit          : "C"  // C | F
    readonly property bool   showDegree:    settings.showDegree    !== undefined ? settings.showDegree    : true
    readonly property string sensorChip:    settings.sensorChip    !== undefined ? settings.sensorChip    : ""   // override, "" = auto
    readonly property string sensorLabel:   settings.sensorLabel   !== undefined ? settings.sensorLabel   : ""   // override, "" = auto
    readonly property var    zoneRadius:    settings.zoneRadius    !== undefined ? settings.zoneRadius    : BarConfig.radiusZone
    readonly property var    zonePad:       settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    property real tempC: NaN
    readonly property bool   found:     !isNaN(tempC)
    readonly property bool   barVisible: found
    readonly property real   tempVal:   unit === "F" ? tempC * 9 / 5 + 32 : tempC
    readonly property bool   over:      found && tempVal >= block.highThreshold

    Process {
        id: proc
        command: ["sensors", "-j"]
        stdout: StdioCollector { onStreamFinished: block.parse(this.text || "") }
    }
    // Re-run sensors each tick; triggeredOnStart fills the value immediately.
    Timer {
        interval: block.interval; running: true; repeat: true; triggeredOnStart: true
        onTriggered: proc.running = true
    }

    // ── sensors -j JSON → a single representative CPU temperature (°C) ───────────
    function parse(jsonText) {
        let data;
        try { data = JSON.parse(jsonText); } catch (e) { block.tempC = NaN; return; }
        const v = pickChip(data);
        block.tempC = (v === null) ? NaN : v;
    }
    function pickChip(data) {
        if (block.sensorChip) return readChip(data[block.sensorChip]);
        // Preference: chip-name prefix, most specific CPU sources first.
        const prefs = ["coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"];
        const chips = Object.keys(data || {});
        for (const p of prefs)
            for (const c of chips)
                if (c.indexOf(p) === 0) { const v = readChip(data[c]); if (v !== null) return v; }
        for (const c of chips) { const v = readChip(data[c]); if (v !== null) return v; }  // any
        return null;
    }
    function readChip(chip) {
        if (!chip || typeof chip !== "object") return null;
        if (block.sensorLabel && chip[block.sensorLabel] !== undefined) return featTemp(chip[block.sensorLabel]);
        const prefs = ["Package id 0", "Tctl", "Tdie", "Tccd1", "temp1"];
        for (const l of prefs) if (chip[l] !== undefined) { const v = featTemp(chip[l]); if (v !== null) return v; }
        for (const k in chip) { const v = featTemp(chip[k]); if (v !== null) return v; }   // any feature
        return null;
    }
    function featTemp(feat) {
        if (!feat || typeof feat !== "object") return null;   // skips the "Adapter" string
        for (const k in feat)
            if (k.indexOf("temp") === 0 && k.indexOf("_input") > 0) return feat[k];
        return null;
    }

    function valueText() {
        return Math.round(block.tempVal) + (block.showDegree ? "°" : "") + block.unit;
    }
    // Widest plausible string ("100" + optional degree + unit) — the value reserve.
    function reserveText() {
        return "100" + (block.showDegree ? "°" : "") + block.unit;
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

    // Reserve the widest value ("100°C") so the block width is fixed.
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
                text: BarConfig.glyph(block.settings.icon, undefined, String.fromCodePoint(0xf2c9))  // nf-fa-thermometer_half
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
