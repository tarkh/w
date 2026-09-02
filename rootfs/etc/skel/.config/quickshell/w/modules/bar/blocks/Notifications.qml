// W Linux bar block — Do Not Disturb indicator + toggle.
// Reads the DND state straight from the NotifConfig singleton (which watches the state
// file `w-notify` writes), so the glyph flips no matter what changed it: this block, the
// Hub panel, a hotkey, the CLI or the AI.
//
// This block is the safety valve for the whole DND feature: silencing notifications with
// nothing on screen to say so is how people miss things for days. It therefore stays
// visible by default even when DND is off (hideWhenIdle opts into the minimal look) and
// paints itself in highColor while DND is active, exactly like the updates block's
// reboot state.
//
// LMB toggles DND (via `w-notify`, never by writing JSON here — one writer per file).
// RMB deep-links into the Hub's Notifications panel, where the history lives.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.notifications

Item {
    id: block
    property var settings: ({})

    readonly property bool showIcon:     settings.showIcon     !== undefined ? settings.showIcon     : true
    readonly property bool showText:     settings.showText     !== undefined ? settings.showText     : false
    readonly property bool hideWhenIdle: settings.hideWhenIdle !== undefined ? settings.hideWhenIdle : false
    readonly property int  fontSize:     settings.fontSize     !== undefined ? settings.fontSize     : 12
    readonly property var  zoneRadius:   settings.zoneRadius   !== undefined ? settings.zoneRadius   : BarConfig.radiusZone
    readonly property var  zonePad:      settings.zonePadding || ({})
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    readonly property bool dnd: NotifConfig.dndActive
    readonly property bool over: block.dnd                  // paint in highColor while silenced
    readonly property bool barVisible: !block.hideWhenIdle || block.dnd

    // Optional label: the deadline when there is one, otherwise the plain state.
    readonly property string label: {
        if (!block.dnd) return "";
        if (NotifConfig.dndUntil > 0)
            return Qt.formatTime(new Date(NotifConfig.dndUntil * 1000), "HH:mm");
        return Strings.t("notif.on");
    }

    function defaultGlyph(s) {
        return s === "dnd" ? String.fromCodePoint(0xf009b)    // nf-md-bell_off
                           : String.fromCodePoint(0xf009e);   // nf-md-bell
    }

    function fg(role) {
        if (block.over)
            return BarConfig.col(
                block.settings.highColor   !== undefined ? block.settings.highColor   : "accent",
                block.settings.highOpacity !== undefined ? block.settings.highOpacity : 1.0);
        if (role === "icon")
            return BarConfig.col(
                block.settings.iconColor   !== undefined ? block.settings.iconColor   : block.settings.textColor,
                block.settings.iconOpacity !== undefined ? block.settings.iconOpacity : block.settings.textOpacity);
        return BarConfig.col(block.settings.textColor, block.settings.textOpacity);
    }

    implicitWidth:  zone.implicitWidth
    implicitHeight: parent ? parent.height : zone.implicitHeight

    Process { id: proc }
    function run(cmd) { proc.running = false; proc.command = cmd; proc.running = true; }

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
                text: BarConfig.glyph(block.settings.icon, block.dnd ? "dnd" : "idle",
                                      block.defaultGlyph(block.dnd ? "dnd" : "idle"))
                font.family: Fonts.mono
                font.pixelSize: block.fontSize
                color: block.fg("icon")
            }
            Text {
                visible: block.showText && text.length > 0
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
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) block.run(["w-notify", "dnd", "toggle"]);
                else Overlays.open("hub", { route: "notifications" });
            }
        }
    }
}
