// W Linux bar block — keyboard layout.
// Shows the active XKB layout, optionally prefixed by a Nerd Font keyboard glyph (icon
// from bar.json), inside an optional zone background — same settings shape as the
// clock/volume/battery blocks. Source is the native Quickshell.Hyprland service: a
// one-shot `hyprctl devices -j` at startup reads the main keyboard's layout list (for
// the count + auto-hide) and the initial active_keymap; thereafter the `activelayout`
// event (Hyprland.rawEvent) keeps the current layout live without polling.
//
// Hyprland reports the layout by its full XKB name ("English (US)", "Russian",
// "Russian (Macintosh)"). To show a short code ("US"/"RU") we resolve that name back
// to its layout code via the shared Xkb registry (core/Xkb.qml — the single home for
// XKB name↔code, including variant names, so the Hub Input panel and this block agree).
// `display` picks code (default) or the full name; `labels` can override per layout.
//
// Auto-hides when only one layout is configured (barVisible follows layoutCount):
// the zone and its gap collapse, like battery without a laptop battery. LMB cycles
// to the next layout (switchxkblayout). RMB is reserved for a future native W
// layout-manager popup (add/remove layouts) — not wired yet. No width reserve here:
// the label only changes on a user switch (not a live counter), and codes are letters.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar

Item {
    id: block
    property var settings: ({})

    readonly property bool   showIcon:   settings.showIcon   !== undefined ? settings.showIcon   : true
    readonly property string display:    settings.display    !== undefined ? settings.display    : "code"   // "code" | "full"
    readonly property bool   uppercase:  settings.uppercase  !== undefined ? settings.uppercase  : true
    readonly property bool   clickCycle: settings.clickCycle !== undefined ? settings.clickCycle : true
    readonly property string device:     settings.device     !== undefined ? settings.device     : ""
    readonly property int    fontSize:   settings.fontSize   !== undefined ? settings.fontSize   : 12
    readonly property var    zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    readonly property var    zonePad:    settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    // Configured layout codes (e.g. ["us","ru"]) for count/auto-hide, every
    // keyboard's real device name (for the cycle dispatch), and the current layout's
    // full XKB name (name→code resolution lives in the shared Xkb registry).
    property var    codes:      []
    property var    kbNames:    []
    property string layoutFull: ""

    readonly property int  layoutCount: codes.length
    readonly property bool barVisible:  layoutCount > 1
    readonly property string label:     displayText()

    // Resolve the string to show: explicit labels override > full name > short code.
    // The code comes from the shared Xkb registry (handles variant names too, so a
    // "Russian (Macintosh)" resolves to "ru", not "Macintosh").
    function displayText() {
        const full = block.layoutFull;
        if (!full) return "";
        const lbl = block.settings.labels;
        if (lbl && lbl[full] !== undefined) return lbl[full];
        if (block.display === "full") return full;
        const code = Xkb.codeOf(full);
        return block.uppercase ? code.toUpperCase() : code;
    }

    // Initial state: configured layout list + current keymap.
    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text || "{}");
                    const kbs = d.keyboards || [];
                    block.kbNames = kbs.map(k => k.name).filter(n => n);
                    const kb = kbs.find(k => k.main) || kbs[0];
                    if (kb) {
                        block.codes = (kb.layout || "").split(",")
                            .map(s => s.trim()).filter(s => s.length > 0);
                        if (block.layoutFull === "")
                            block.layoutFull = kb.active_keymap || "";
                    }
                } catch (e) { /* keep defaults → block stays hidden */ }
            }
        }
    }

    // Live updates: activelayout fires as "<keyboard>,<Layout Full Name>" on every
    // switch (key combo or our click). The full name may contain a comma, so drop
    // only the first field (the keyboard) and re-join the rest.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const parts = (event.data || "").split(",");
            parts.shift();
            block.layoutFull = parts.join(",");
        }
    }

    // Advance to the next layout. switchxkblayout is a hyprctl COMMAND, not a
    // dispatcher (Hyprland.dispatch → "/dispatch …" rejects it: "Invalid
    // dispatcher"), so call hyprctl directly. Prefer an explicit settings.device;
    // otherwise target every real keyboard by name (keeping them in sync, like the
    // grp toggle). switchxkblayout emits activelayout, so the label updates live
    // through the same path as the key-combo toggle.
    function cycle() {
        var targets = block.device !== "" ? [block.device]
                    : (block.kbNames.length > 0 ? block.kbNames : ["current"]);
        for (var i = 0; i < targets.length; i++)
            Quickshell.execDetached({ command: ["hyprctl", "switchxkblayout", targets[i], "next"] });
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
                text: BarConfig.glyph(block.settings.icon, undefined, String.fromCodePoint(0xf11c))  // nf-fa-keyboard
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: block.label
                font.family: Fonts.family
                font.pixelSize: block.fontSize
                color: block.fg("text")
            }
        }
    }

    // LMB → next layout (see cycle()). Direct child of the block Item — matches the
    // proven volume/clock pattern, so it reliably receives the bar's clicks. Stays
    // enabled even when clickCycle is off so the click-flash / cursor controls still
    // work; the cycle action itself is gated on clickCycle + LeftButton.
    MouseArea {
        anchors.fill: parent
        cursorShape: BarConfig.cursor(block.settings.cursor, block.clickCycle ? Qt.PointingHandCursor : Qt.ArrowCursor)
        acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
        onPressed: (mouse) => flash.pulse(mouse.button)
        onClicked: (mouse) => { if (mouse.button === Qt.LeftButton && block.clickCycle) block.cycle(); }
    }
}
