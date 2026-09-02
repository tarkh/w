// W Linux — Hub tile.
// A reusable rounded control tile for the Hub root grid: a chrome icon (the tile's
// Nerd Font glyph, flat, in one ink — see ChromeIcon), a label, and an
// optional state-value line (e.g. "strict", "home"). Two visual roles from one
// component:
//   • toggle  — `active` paints the tile in the accent (an "on" quick-setting), the
//               value line shows the current state; click emits activated().
//   • action/link — `active` stays false; click emits activated() to run a command
//               or open another popup.
// `enabled:false` dims it and blocks interaction (e.g. a privileged tile whose backing
// tool is unavailable). Colors/motion/fonts come from the shared singletons.
// Mirrors the powermenu tile's selection feel, scaled down.
import QtQuick
import qs.core
import qs.modules.shading

Item {
    id: root

    // Theme icon name (Papirus) — falls back to `glyph` when the theme has no such
    // icon. Provide at least one.
    property string icon: ""
    property string glyph: ""            // Nerd Font char (String.fromCodePoint)
    property string label: ""
    property string value: ""            // optional state line; "" hides it
    property bool active: false          // accent "on" state
    // enabled shadows QQuickItem.enabled by design — interaction is gated
    // manually below, native input-blocking is unused.
    // qmllint disable property-override
    property bool enabled: true
    // qmllint enable property-override
    property int badge: 0                // optional count badge (0 = none)
    // Keyboard roving-focus indicator — set by the owning grid's roving index, NOT
    // by this item's own Qt focus (RootGrid holds the actual active focus and drives
    // this the same way `ma.containsMouse` drives the hover look, so a keyboard user
    // sees the identical affordance a mouse user would get by hovering).
    property bool focused: false

    signal activated()

    implicitWidth: 100
    implicitHeight: 92

    // Background: accent when active, input-bg on hover/keyboard-focus, transparent
    // otherwise. A focused (non-active) tile also gets an accent ring — hover alone
    // would be indistinguishable from a mouse that happens to be resting over a
    // different tile.
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Geometry.radiusSm
        color: root.active ? Colors.accent
               : ((ma.containsMouse || root.focused) && root.enabled ? Colors.hover : Colors.alpha(Colors.hover, 0))
        border.color: root.active ? "transparent" : (root.focused ? Colors.accentInk : Colors.border)
        border.width: root.active ? 0 : (root.focused ? 2 : HubConfig.border)
        opacity: root.enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }

    // Foreground color: on the accent tile flip to accentFg for legibility.
    readonly property color fg: root.active ? Colors.accentFg : Colors.text
    readonly property color fgMuted: root.active ? Colors.accentFg : Colors.muted

    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 5
        opacity: root.enabled ? 1 : 0.5

        // Chrome icon: the tile's curated glyph, flat, in one ink (see ChromeIcon).
        // On the accent-filled active tile the ink flips to accentFg.
        ChromeIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 26
            icon: root.icon
            glyph: root.glyph
            tint: root.active ? Colors.accentFg : Colors.iconTint
            Behavior on tint { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            color: root.fg
            font.family: Fonts.family
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.value.length > 0
            text: root.value
            color: root.fgMuted
            font.family: Fonts.family
            font.pixelSize: 11
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    // Count badge (updates): a small accent pill at the top-right.
    Rectangle {
        visible: root.badge > 0
        anchors { right: parent.right; top: parent.top; margins: 6 }
        width: Math.max(16, badgeText.implicitWidth + 8)
        height: 16
        radius: 8
        color: Colors.accent
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge > 99 ? "99+" : root.badge
            color: Colors.accentFg
            font.family: Fonts.family
            font.pixelSize: 10
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.activated()
    }
}
