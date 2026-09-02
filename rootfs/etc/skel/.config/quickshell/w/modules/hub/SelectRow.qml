// W Linux — Hub select row.
// A full-width setting row for a multi-state control (DNS mode, firewall zone): a leading
// chrome icon (ChromeIcon: glyph, flat, one ink) + label on the left, and a right-aligned "value ▾" button that opens
// a dropdown (HubMenu, hosted by RootGrid). The row itself is presentational — it exposes
// its options + current value and an anchor for the menu, and emits activated() when the
// value button is clicked; RootGrid opens the menu and actuates the pick. Disabled (its
// backing tool absent) dims it and blocks interaction. Colors/motion/fonts from the shared
// singletons.
import QtQuick
import QtQuick.Controls
import qs.core
import qs.modules.shading

Item {
    id: root

    property string icon: ""
    property string glyph: ""
    property string label: ""
    property string value: ""            // current value shown on the button
    property var options: []             // [{ id, label }] — passed to the menu
    property string currentId: ""
    // enabled shadows QQuickItem.enabled by design — interaction is gated
    // manually below, native input-blocking is unused.
    // qmllint disable property-override
    property bool enabled: true
    // qmllint enable property-override
    // Fleet policy owns this key (/etc/w/policy.d — the `policy` layer of w-conf).
    // Distinct from `enabled: false` ("the backing tool isn't here") on purpose:
    // the control exists and the value is real, the local machine just may not
    // change it. Silently letting the click through would be worse than useless —
    // the setter refuses, so the UI must say so BEFORE the user tries.
    property bool locked: false
    property string lockedHint: ""       // tooltip: which file locks it
    readonly property bool interactive: enabled && !locked
    property bool menuOpen: false        // RootGrid sets this while our menu is up
    // Keyboard roving-focus indicator — set by the owning panel's roving index, same
    // contract as Tile.focused (see RootGrid). Enter/Space at that index calls
    // activated() directly; this property only drives the visual.
    property bool focused: false

    // The value button — RootGrid anchors the dropdown under it.
    readonly property Item anchorItem: valueBtn

    signal activated()

    implicitWidth: parent ? parent.width : 320
    implicitHeight: 30
    opacity: interactive ? 1 : 0.45

    // Full-row wash so a keyboard-focused row reads the same as a hovered one even
    // though only the value button is clickable — matches Tile/HubRow's whole-row
    // affordance instead of a highlight isolated to the small button on the right.
    Rectangle {
        anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
        radius: Geometry.radiusSm
        visible: root.focused
        color: Colors.hover
    }

    Row {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: 10

        ChromeIcon {
            // No icon/glyph given (a plain field row, e.g. AIProfilesPanel's editor) →
            // collapse out of the Row entirely so the label sits flush left, aligned
            // with sibling text-field rows that carry no icon slot at all.
            visible: root.icon.length > 0 || root.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            size: 22
            icon: root.icon
            glyph: root.glyph
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Colors.text
            font.family: Fonts.family
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }

    // Value button (opens the dropdown).
    Rectangle {
        id: valueBtn
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: valueRow.implicitWidth + 24
        height: 30
        radius: Geometry.radiusSm
        color: root.menuOpen ? Colors.selection
               : ((btnMa.containsMouse || root.focused) && root.interactive ? Colors.hover : Colors.alpha(Colors.hover, 0))
        border.color: root.focused ? Colors.accentInk : Colors.border
        border.width: root.focused ? 2 : HubConfig.border
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: valueRow
            anchors.centerIn: parent
            spacing: 6

            // Padlock instead of the chevron's promise of a choice.
            Text {
                visible: root.locked
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xf033e)   // nf-md-lock
                font.family: Fonts.mono
                font.pixelSize: 13
                color: Colors.muted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.value
                color: Colors.text
                font.family: Fonts.family
                font.pixelSize: 13
            }
            Text {
                visible: !root.locked
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xf0140)   // nf-md-chevron_down
                font.family: Fonts.mono
                font.pixelSize: 14
                color: Colors.muted
                rotation: root.menuOpen ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Motion.fast } }
            }
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.interactive) root.activated()
            // Hover a locked row → say why it cannot be changed.
            WToolTip {
                text: root.lockedHint
                visible: btnMa.containsMouse && root.locked && root.lockedHint.length > 0
            }
        }
    }
}
