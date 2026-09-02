// W Linux bar block — pending package updates.
// A read-only indicator of available repo+AUR updates, with the same settings shape
// as the cpu/network blocks. It does NOT poll pacman itself: the `w-update-check`
// user timer runs `w-update check` (non-root) and writes ~/.local/state/w/updates.json
// ({ repo, aur, rebootPending, ts }); this block just watches that file (FileView
// watchChanges) and reflects it — so the count is shared, survives a shell restart,
// and updates instantly when `w-update` finishes an upgrade (it rewrites the file).
// A slow reload Timer is a fallback so the very first file-creation is picked up.
//
// count = repo (+ aur, if includeAur). Visibility: hidden when count is 0 (hideWhenZero,
// default true) UNLESS a reboot is pending — a fresh kernel that isn't running yet must
// stay visible even at zero updates. Highlight (highColor, like cpu's over-threshold)
// means exactly one thing: rebootPending — you're on a stale kernel and should reboot.
// Glyph is multi-state (bar.json `icon`): "available" (updates) vs "reboot" (kernel owed).
// Left-click runs the interactive upgrade in W's terminal; right-click shows Arch news.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:     settings.showIcon     !== undefined ? settings.showIcon     : true
    readonly property bool showCount:    settings.showCount    !== undefined ? settings.showCount    : true
    readonly property bool includeAur:   settings.includeAur   !== undefined ? settings.includeAur   : true
    readonly property bool hideWhenZero: settings.hideWhenZero !== undefined ? settings.hideWhenZero : true
    readonly property int  fontSize:     settings.fontSize     !== undefined ? settings.fontSize     : 12
    readonly property int  interval:     settings.interval     !== undefined ? settings.interval     : 60000
    readonly property var  zoneRadius:   settings.zoneRadius   !== undefined ? settings.zoneRadius   : BarConfig.radiusZone
    readonly property var  zonePad:      settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    property int  repo:          0
    property int  aur:           0
    property bool rebootPending: false

    readonly property int    count:      block.includeAur ? block.repo + block.aur : block.repo
    readonly property bool    over:       block.rebootPending
    // "reboot" only when there's nothing left to install but a kernel reboot is owed;
    // otherwise the normal "available" glyph (even if a reboot is also pending).
    readonly property string  uState:     (block.count === 0 && block.rebootPending) ? "reboot" : "available"
    // Stay on the bar while there are updates OR a reboot is owed; hideWhenZero only
    // collapses the fully-idle state.
    readonly property bool    barVisible: !block.hideWhenZero || block.count > 0 || block.rebootPending

    // Status file written by `w-update check` (outside Quickshell's own stateDir, so
    // resolve it from the environment the same way the shell resolves other paths).
    readonly property string statePath: {
        const x = Quickshell.env("XDG_STATE_HOME");
        const base = (x && x.length > 0) ? x : (Quickshell.env("HOME") + "/.local/state");
        return base + "/w/updates.json";
    }

    function defaultGlyph(s) {
        return s === "reboot" ? String.fromCodePoint(0xf0709)   // nf-md-restart
                              : String.fromCodePoint(0xf4f9);  // nf-md-package_up
    }

    function reset() { block.repo = 0; block.aur = 0; block.rebootPending = false; }

    FileView {
        id: sf
        path: block.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(sf.text() || "{}");
                block.repo          = d.repo  || 0;
                block.aur           = d.aur   || 0;
                block.rebootPending = !!d.rebootPending;
            } catch (e) { block.reset(); }
        }
    }
    // Fallback: catch the first-ever creation of the file (a fresh watch on a path
    // that doesn't exist yet may miss its creation) and any missed event.
    Timer { interval: block.interval; running: true; repeat: true; onTriggered: sf.reload() }

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

    // No fixed width reservation here, unlike cpu/ram/temp/disk. Those poll every couple
    // of seconds, so a digit appearing/disappearing would visibly jitter their neighbours
    // and reserving the widest reading is worth the dead space. The update count changes
    // once an hour at most, and tabular figures already hold the width steady within a
    // digit count — reserving 3 digits for a number that is normally 1–2 just padded the
    // block with permanently blank space (visible as extra room on its right).

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
            anchors.left: parent.left
            anchors.leftMargin: BarConfig.minSquare ? (zone.width - contentRow.implicitWidth) / 2 : block.padL
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                visible: block.showIcon
                anchors.verticalCenter: parent.verticalCenter
                text: BarConfig.glyph(block.settings.icon, block.uState, block.defaultGlyph(block.uState))
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                // No number in the pure reboot-owed state (count 0) — the glyph says it all.
                visible: block.showCount && block.count > 0
                anchors.verticalCenter: parent.verticalCenter
                text: block.count
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                font.features: ({ "tnum": 1 })   // tabular figures: constant digit width
                color: block.fg("text")
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => flash.pulse(mouse.button)
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)
                    Quickshell.execDetached(Term.exec(["w-update"]));
                else if (mouse.button === Qt.RightButton)
                    Quickshell.execDetached(Term.exec(["sh", "-c", "w-update news; echo; read -n1 -r -p 'Press any key to close…'"]));
            }
        }
    }
}
