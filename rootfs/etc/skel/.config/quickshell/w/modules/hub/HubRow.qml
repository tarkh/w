// W Linux — Hub row.
// A general-purpose settings row shared by the Hub panels: a leading chrome icon +
// a label (with an optional muted sub-label) on the left, and a right side that is any
// combination of a read-only value text (status rows: About, AI), an action button
// (Update / Install), a "done" check glyph (an already-installed pack) and a second,
// DESTRUCTIVE action. Value + button coexist — e.g. "3 pending" beside an Update button.
// Purely presentational: it emits activated() / removeActivated() when its buttons are
// clicked and the owning panel actuates. Generalises the one-off "Connections…" link
// NetworkPanel built inline; unlike SelectRow it is for value/action rows, not
// multi-state dropdowns. Colors/motion/fonts from the shared singletons; the leading
// icon is a ChromeIcon (glyph, flat, one ink).
//
// ── The second action, and why it needs no second focus position ────────────────
// `actionText` and `done` are mutually exclusive (a pack is either installable or
// installed), but `removeText` coexists with BOTH: an installed pack shows its check
// AND a way to undo it. That is a second verb on one row, and the Hub already has an
// answer for that which costs the panel nothing — Enter/Space runs the row's primary
// action, HubNavKeys.del runs the destructive one (HotkeysPanel's custom/profile rows,
// AIProfilesPanel's profile header). So the panel's roving list stays a flat index over
// ROWS; there is no second focus slot to navigate into, and no arrow-key semantics to
// invent inside a row.
//
// The ring follows what Enter would hit, which is not always the primary: on a row with
// no primary button left (`done`), Enter is the destructive action, so the ring moves to
// it. Everything else stays marked by the row's own focus wash.
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
    property string removeText: ""       // non-empty → render a second, destructive button
    // enabled shadows QQuickItem.enabled by design — interaction is gated
    // manually below, native input-blocking is unused.
    // qmllint disable property-override
    property bool   enabled: true
    // qmllint enable property-override
    // Keyboard roving-focus indicator — same contract as Tile.focused/SelectRow.focused.
    property bool   focused: false

    signal activated()
    signal removeActivated()

    // Which button Enter would hit — and therefore which one wears the ring.
    readonly property bool hasAction: root.actionText.length > 0 && !root.done
    readonly property bool hasRemove: root.removeText.length > 0

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

    // Right-slot button. `danger` swaps the whole ink to dangerBorder (WPill's own
    // convention for a destructive control); `ring` is the roving-cursor mark, passed
    // in rather than read off root.focused because which button wears it depends on
    // what else the row is rendering.
    component ActionButton: Rectangle {
        id: btn

        property string label: ""
        property bool   danger: false
        property bool   ring: false

        signal clicked()

        readonly property color ink: btn.danger ? Colors.dangerBorder : Colors.text
        readonly property color outline: btn.danger ? Colors.dangerBorder : Colors.border

        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: btnLbl.implicitWidth + 24
        height: 30
        radius: Geometry.radiusSm
        color: (btnMa.containsMouse || btn.ring) && root.enabled ? Colors.hover : Colors.alpha(Colors.hover, 0)
        border.color: btn.ring && !btn.danger ? Colors.accentInk : btn.outline
        border.width: btn.ring ? 2 : HubConfig.border
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Text {
            id: btnLbl
            anchors.centerIn: parent
            text: btn.label
            color: btn.ink
            font.family: Fonts.family
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.enabled) btn.clicked()
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

            // Action button, and its destructive twin. One shape, because a 30px
            // neutral button beside a 26px accented WPill read as two unrelated
            // controls — this row's button is deliberately NOT a WPill (neutral ink on
            // Colors.border, not accentInk) and its second verb has to match it.
            ActionButton {
                visible: root.hasAction
                label: root.actionText
                ring: root.focused
                onClicked: root.activated()
            }

            ActionButton {
                visible: root.hasRemove
                label: root.removeText
                danger: true
                // Only when there is no primary left to carry it — see the header.
                ring: root.focused && !root.hasAction
                onClicked: root.removeActivated()
            }
        }
    }
}
