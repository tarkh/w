// W Linux bar block — network indicator.
// A light, read-only status block: a connection-type glyph (icon from bar.json) plus
// the primary IP, inside an optional zone — same settings shape as the clock block. All
// real management is delegated to nm-applet in the tray (left-click its icon for the NM
// menu / Wi-Fi list); this block only reflects state. It does NOT auto-hide (a network
// is universal) — with no connectivity it shows the "disconnected" glyph instead.
//
// Source = `ip -j route get 1.1.1.1`: one JSON call returns { dev, prefsrc } for the
// interface that currently carries the default route, which naturally resolves the
// "wired AND Wi-Fi both up" edge case (the kernel reports the winning link, usually
// ethernet by metric) and surfaces a VPN as its tun*/wg* device. No route → empty
// output → disconnected. The type is classified by the device-name prefix
// (en/eth → ethernet, wl → wifi, tun/wg/ppp → vpn). Liveness comes from two places: a
// slow Timer poll, plus `nmcli monitor` — any NM event triggers an immediate (debounced)
// re-poll, so connect/disconnect shows up at once without fast polling. The value is not
// width-reserved (it changes only on a network event, like the keyboard-layout block).
// Left-click opens nm-connection-editor (W's GUI network utility, from the same applet
// package). See quickshell-bar.md.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool   showIcon:    settings.showIcon    !== undefined ? settings.showIcon    : true
    readonly property bool   showText:    settings.showText    !== undefined ? settings.showText    : true
    readonly property int    fontSize:    settings.fontSize    !== undefined ? settings.fontSize    : 12
    readonly property int    interval:    settings.interval    !== undefined ? settings.interval    : 5000
    readonly property string display:     settings.display     !== undefined ? settings.display     : "ip"   // ip | ifname
    readonly property string offlineText: settings.offlineText !== undefined ? settings.offlineText : ""     // "" → glyph only
    readonly property var    zoneRadius:  settings.zoneRadius  !== undefined ? settings.zoneRadius  : BarConfig.radiusZone
    readonly property var    zonePad:     settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    // Default-route interface + its source IP (empty when offline).
    property string dev: ""
    property string ip:  ""
    readonly property string connState: classify(dev)   // ethernet | wifi | vpn | disconnected (not Item.state)

    function classify(d) {
        if (!d) return "disconnected";
        if (/^(tun|tap|wg|ppp)/.test(d)) return "vpn";
        if (/^(wl)/.test(d))             return "wifi";
        return "ethernet";   // en*/eth* and any other wired-like device
    }

    // Built-in default glyph per state (Nerd Font; overridable per state in bar.json).
    function defaultGlyph(s) {
        switch (s) {
        case "wifi":         return String.fromCodePoint(0xf1eb);   // nf-fa-wifi
        case "vpn":          return String.fromCodePoint(0xf0582);  // nf-md-vpn
        case "disconnected": return String.fromCodePoint(0xf0c9d);  // nf-md-network_off
        default:             return String.fromCodePoint(0xf0200);  // nf-md-ethernet
        }
    }

    function valueText() {
        if (block.connState === "disconnected") return block.offlineText;
        return block.display === "ifname" ? block.dev : block.ip;
    }

    // ── Poll: ip -j route get 1.1.1.1 → { dev, prefsrc } ────────────────────────
    Process {
        id: routeProc
        command: ["ip", "-j", "route", "get", "1.1.1.1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = "", a = "";
                try {
                    const arr = JSON.parse(this.text || "");
                    if (Array.isArray(arr) && arr.length) {
                        d = arr[0].dev || "";
                        a = arr[0].prefsrc || "";
                    }
                } catch (e) {}
                block.dev = d;
                block.ip  = a;
            }
        }
    }
    Timer {
        interval: block.interval; running: true; repeat: true; triggeredOnStart: true
        onTriggered: routeProc.running = true
    }

    // ── Liveness: nmcli monitor streams a line on any NM event → debounced re-poll.
    Process {
        id: monitorProc
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: debounce.restart() }
        // NM restarts are rare; if the monitor ever exits, bring it back after a beat.
        onExited: monitorRestart.start()
    }
    Timer { id: debounce;        interval: 400;  onTriggered: routeProc.running = true }
    Timer { id: monitorRestart;  interval: 3000; onTriggered: monitorProc.running = true }

    function fg(role) {
        if (role === "icon")
            return BarConfig.col(
                block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity);
        return BarConfig.col(block.settings.textColor, block.settings.textOpacity);
    }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

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
                text: BarConfig.glyph(block.settings.icon, block.connState, block.defaultGlyph(block.connState))
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                visible: block.showText && text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: block.valueText()
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                font.features: ({ "tnum": 1 })   // tabular figures: constant digit width
                color: block.fg("text")
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
            onPressed: (mouse) => flash.pulse(mouse.button)
            onClicked: (mouse) => { if (mouse.button === Qt.LeftButton) Quickshell.execDetached(["nm-connection-editor"]); }
        }
    }
}
