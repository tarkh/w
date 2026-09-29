// W Linux bar block — screen-recording indicator + stop button.
// Reads $XDG_RUNTIME_DIR/w/record.state, the file `w-record` writes when a recording
// starts and removes when it stops, so the block follows every way a recording
// begins or ends: a keybind, the CLI, the AI. It is absent while nothing records.
//
// The state file alone is not proof of a recording: it outlives a backend that died
// under it (a full disk, a lost compositor), and a stale file would pin a timer to the
// bar forever. So every tick also checks /proc/<PID>/comm names the backend — the same
// two-part liveness test `w-record` itself uses, PIDs being reused by the kernel.
//
// LMB stops the recording (`w-record stop`, never a signal from here — one owner of the
// backend's lifecycle). No menu, deliberately: while the whole screen is being recorded
// a popup lands in the video, and stopping is the only action a recording has. RMB
// deep-links to Hub → Displays → Screen capture, where the next take is configured.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:   settings.showIcon   !== undefined ? settings.showIcon   : true
    readonly property bool showText:   settings.showText   !== undefined ? settings.showText   : true
    readonly property bool pulse:      settings.pulse      !== undefined ? settings.pulse      : true
    readonly property int  fontSize:   settings.fontSize   !== undefined ? settings.fontSize   : 12
    readonly property var  zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    readonly property var  zonePad:    settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    readonly property string statePath: {
        const r = Quickshell.env("XDG_RUNTIME_DIR");
        return ((r && r.length > 0) ? r : "/tmp") + "/w/record.state";
    }

    property int  pid: 0
    property int  started: 0
    property string backend: ""            // comm to expect, as the kernel truncates it
    property bool alive: false
    property int  nowSec: Math.floor(Date.now() / 1000)

    readonly property bool recording: block.pid > 0 && block.alive
    readonly property bool barVisible: block.recording

    // m:ss, h:mm:ss past the hour — tabular digits keep the zone from twitching.
    readonly property string label: {
        const s = Math.max(0, block.nowSec - block.started);
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
        const p = (n) => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + p(m) + ":" + p(ss) : m + ":" + p(ss);
    }

    function parse(text) {
        const kv = {};
        for (const line of (text || "").split("\n")) {
            const i = line.indexOf("=");
            if (i > 0) kv[line.slice(0, i)] = line.slice(i + 1);
        }
        block.pid     = parseInt(kv.PID) || 0;
        block.started = parseInt(kv.STARTED) || 0;
        block.backend = (kv.RECORDER === "gsr" ? "gpu-screen-recorder" : "wf-recorder").slice(0, 15);
        if (block.pid > 0) comm.reload(); else block.alive = false;
    }

    function fg(role) {
        if (role === "icon")
            return BarConfig.col(
                block.settings.iconColor   !== undefined ? block.settings.iconColor   : "dangerBorder",
                block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : 1.0);
        return BarConfig.col(block.settings.textColor, block.settings.textOpacity);
    }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    FileView {
        id: sf
        path: block.statePath
        watchChanges: true
        printErrors: false                 // absent whenever nothing records — the normal state
        onFileChanged: reload()
        onLoaded: block.parse(sf.text())
        onLoadFailed: block.parse("")
    }
    FileView {
        id: comm
        path: block.pid > 0 ? "/proc/" + block.pid + "/comm" : ""
        printErrors: false
        onLoaded: block.alive = comm.text().trim() === block.backend
        onLoadFailed: block.alive = false
    }
    // The watch cannot see a file that does not exist yet, and `w-record stop` deletes
    // it, so a poll backs it up: every second while recording (it also drives the
    // timer and the liveness check), every two while idle — a tmpfs read, nothing more.
    Timer {
        interval: block.recording ? 1000 : 2000
        running: true
        repeat: true
        onTriggered: { block.nowSec = Math.floor(Date.now() / 1000); sf.reload(); }
    }

    Process { id: proc }

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
            apexOpacity: block.settings.clickOpacity  !== undefined ? block.settings.clickOpacity  : 0.5
            duration:    block.settings.clickDuration !== undefined ? block.settings.clickDuration : Motion.base
        }

        Row {
            id: contentRow
            anchors.left: parent.left
            anchors.leftMargin: BarConfig.minSquare ? (zone.width - contentRow.implicitWidth) / 2 : block.padL
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                id: dot
                visible: block.showIcon
                anchors.verticalCenter: parent.verticalCenter
                text: BarConfig.glyph(block.settings.icon, "recording",
                                      String.fromCodePoint(0xf111))   // nf-fa-circle
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")

                // A slow breath, the universal "on air" cue; the text beside it stays put.
                SequentialAnimation on opacity {
                    running: block.pulse && block.recording
                    loops: Animation.Infinite
                    onStopped: dot.opacity = 1
                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                }
            }
            Text {
                visible: block.showText
                anchors.verticalCenter: parent.verticalCenter
                text: block.label
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                font.features: ({ "tnum": 1 })
                color: block.fg("text")
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => flash.pulse(mouse.button)
            // Right click: the capture settings, not a menu (see the header). They
            // apply from the next recording — this one keeps what it started with.
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    proc.running = false; proc.command = ["w-record", "stop"]; proc.running = true;
                } else Overlays.open("hub", { route: "displays", args: { scope: "capture" } });
            }
        }
    }
}
