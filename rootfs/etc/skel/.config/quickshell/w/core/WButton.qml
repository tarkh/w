// W Linux — shared outline action button.
// One button shape for Hub settings-fields: accent border by default, "danger" tone for
// destructive actions (Remove), opacity-gated by `enabled` — the same hand-rolled
// Rectangle+MouseArea shape that used to live inline in NetworkPanel/PowerPanel (the
// "Change" button) and AIProfilesPanel (Save/Remove), now shared so all three read as
// one control. `enabled` shadows QQuickItem.enabled by design (same idiom as
// HubRow/Tile/Pill) — interaction is gated manually below, native input-blocking unused.
// Sized to match SelectRow's dropdown "value ▾" button (30px, same +24 width padding) —
// the dropdown rows are the reference size in the Hub, so a settings-field's Change/
// Save/Remove button reads at the same scale as the dropdowns right above it.
import QtQuick
import qs.core

Rectangle {
    id: root

    property string label: ""
    property string tone: "accent"        // "accent" | "danger"
    property int borderWidth: Geometry.border
    // qmllint disable property-override
    property bool enabled: true
    // qmllint enable property-override
    // Keyboard roving-focus indicator — same contract as Tile.focused.
    property bool focused: false

    signal clicked()

    // INK, not the fill accent — see WPill for the whole state contract. Using
    // Colors.accent here is what made every outline button in the Hub vanish on a
    // light theme (1.10:1 against the card).
    readonly property color toneColor: root.tone === "danger" ? Colors.dangerBorder : Colors.accentInk

    implicitWidth: labelText.implicitWidth + 24
    implicitHeight: 30
    radius: Geometry.radiusSm
    opacity: root.enabled ? 1 : 0.4
    // Rest = the hover colour at alpha 0, never "transparent" (which is black at
    // alpha 0 and drags the fade through grey).
    color: (ma.containsMouse || root.focused) && root.enabled ? Colors.hover : Colors.alpha(Colors.hover, 0)
    border.width: root.focused ? 2 : root.borderWidth
    border.color: root.toneColor
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: root.toneColor
        font.family: Fonts.family; font.pixelSize: 13; font.weight: Font.Medium
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
}
