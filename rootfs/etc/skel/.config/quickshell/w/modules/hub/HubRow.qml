// W Linux — Hub row.
// A general-purpose settings row shared by the Hub panels: a leading chrome icon +
// a label (with an optional muted sub-label) on the left, and a right side that is any
// combination of a read-only value text (status rows: About, AI), an action button
// (Update / Install) and a "done" check glyph (an already-installed pack). Value + button
// coexist — e.g. "3 pending" beside an Update button. Purely presentational: it emits
// activated() when its button is clicked and the owning panel actuates. Generalises the
// one-off "Connections…" link NetworkPanel built inline; unlike SelectRow it is for
// value/action rows, not multi-state dropdowns. Colors/motion/fonts from the shared
// singletons; the leading icon is a ChromeIcon (glyph, flat, one ink).
import QtQuick
import qs.core
import qs.modules.shading

Item {
    id: root

    property string icon: ""
    property string glyph: ""
    property string label: ""
    property string sublabel: ""         // optional second line (e.g. a pack description)
    property string value: ""            // optional right-aligned status text
    property color  valueColor: Colors.muted
    property string actionText: ""       // non-empty → render a right-side button
    property bool   done: false          // render a check instead of a button (mutually excl.)
    // enabled shadows QQuickItem.enabled by design — interaction is gated
    // manually below, native input-blocking is unused.
    // qmllint disable property-override
    property bool   enabled: true
    // qmllint enable property-override
    // Keyboard roving-focus indicator — same contract as Tile.focused/SelectRow.focused.
    property bool   focused: false

    signal activated()

    implicitWidth: parent ? parent.width : 320
    implicitHeight: Math.max(38, content.implicitHeight + 8)
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
        radius: Geometry.radiusSm
        visible: root.focused
        color: Colors.hover
    }

    // ── Left: icon + label / sublabel ────────────────────────────────────────────────
    Row {
        id: content
        anchors {
            left: parent.left
            right: rightSlot.left; rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        spacing: 10

        ChromeIcon {
            anchors.verticalCenter: parent.verticalCenter
            size: 22
            icon: root.icon
            glyph: root.glyph
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: root.label
                color: Colors.text
                font.family: Fonts.family
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                visible: root.sublabel.length > 0
                width: Math.max(0, content.width - 32)
                text: root.sublabel
                color: Colors.muted
                font.family: Fonts.family
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }

    // ── Right: value text + action button / done check ───────────────────────────────
    Item {
        id: rightSlot
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: rightRow.implicitWidth
        height: parent.height

        Row {
            id: rightRow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8

            Text {
                visible: root.value.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.value
                color: root.valueColor
                font.family: Fonts.family
                font.pixelSize: 13
            }

            // Installed marker.
            Text {
                visible: root.done
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xf05e0)   // nf-md-check_circle
                font.family: Fonts.mono
                font.pixelSize: 16
                color: Colors.accentInk
            }

            // Action button.
            Rectangle {
                visible: root.actionText.length > 0 && !root.done
                anchors.verticalCenter: parent.verticalCenter
                width: btnLbl.implicitWidth + 24
                height: 30
                radius: Geometry.radiusSm
                color: (btnMa.containsMouse || root.focused) && root.enabled ? Colors.hover : Colors.alpha(Colors.hover, 0)
                border.color: root.focused ? Colors.accentInk : Colors.border
                border.width: root.focused ? 2 : HubConfig.border
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: btnLbl
                    anchors.centerIn: parent
                    text: root.actionText
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                MouseArea {
                    id: btnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (root.enabled) root.activated()
                }
            }
        }
    }
}
