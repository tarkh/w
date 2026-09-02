// W Linux bar block — clock.
// Current time, optionally prefixed by a Nerd Font clock glyph (icon from bar.json),
// inside an optional zone background. Left-clicking opens the Calendar popup (the same
// Hyprland global the quickshell:calendar shortcut triggers). Right-clicking cycles
// through the configured clock faces — the "format" array in bar.json lists Qt
// date-format strings (e.g. "HH:mm", "HH:mm:ss", "h:mm ap"), so a right-click can add
// ticking seconds or flip 24h↔12h am/pm, useful to catch the exact time. Tokens are
// standard Qt.formatDateTime placeholders and are locale-aware (ap/AP follow the
// system locale). The chosen face index is remembered across restarts via the
// universal Store (core/Store.qml), keyed per block ("clock.face.<stateKey>").
// All colors go through BarConfig.col (theme token or #hex + a separate per-element
// opacity); timing/icon font follow the shell singletons. The block fills the bar's
// content band height; its width is intrinsic (driven by the text + zone padding). The
// value uses tabular figures so digit width stays constant; switching faces changes the
// block width intentionally (a different format is a different string).
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block

    // Set by the Bar Loader from the block's "settings" object in bar.json.
    property var settings: ({})

    // Settings with sane fallbacks (mirroring bar.json). "format" is an array of clock
    // faces; a bare string is accepted and wrapped for backward compatibility. The array
    // crosses the config→model boundary as a QVariantList (Array.isArray is false for it),
    // so normalise anything list-like into a real JS array by copying element by element.
    readonly property var faces: {
        const f = settings.format;
        if (f === undefined || f === null) return ["HH:mm"];
        if (typeof f === "string") return [f];
        const a = [];
        for (let i = 0; i < f.length; i++) a.push(f[i]);
        return a.length ? a : ["HH:mm"];
    }
    readonly property bool   showIcon:   settings.showIcon   !== undefined ? settings.showIcon   : false
    readonly property int    fontSize:   settings.fontSize   !== undefined ? settings.fontSize   : 12
    readonly property var    zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    readonly property var    zonePad:    settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    // Persisted face index (Store), clamped to the current faces array.
    readonly property string stateKey: "clock.face." + (settings.stateKey !== undefined ? settings.stateKey : "default")
    readonly property int    faceIndex: {
        const i = Store.get(stateKey, 0);
        return (i >= 0 && i < faces.length) ? i : 0;
    }
    readonly property string face: faces[faceIndex] !== undefined ? faces[faceIndex] : "HH:mm"

    function cycleFace() {
        if (faces.length < 2) return;
        Store.set(stateKey, (faceIndex + 1) % faces.length);
    }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    SystemClock {
        id: clock
        // Tick per second only when the active face renders seconds; otherwise per minute.
        precision: /s/.test(block.face) ? SystemClock.Seconds : SystemClock.Minutes
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
                // Glyph default String.fromCodePoint(): pure ASCII in the file, so raw
                // PUA chars never get dropped on write (bar.json may override via "icon").
                text: BarConfig.glyph(block.settings.icon, undefined, String.fromCodePoint(0xf017))  // nf-fa-clock_o
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: BarConfig.col(
                    block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                    block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, block.face)
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                font.features: ({ "tnum": 1 })   // tabular figures: constant digit width, no jitter
                color: BarConfig.col(block.settings.textColor, block.settings.textOpacity)
            }
        }

        // Left-click opens the Calendar popup; right-click cycles the clock face.
        // The MouseArea also carries the click-flash + cursor controls. Default cursor
        // is the pointing hand.
        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => flash.pulse(mouse.button)
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) Hyprland.dispatch('hl.dsp.global("quickshell:calendar")');
                else if (mouse.button === Qt.RightButton) block.cycleFace();
            }
        }
    }
}
