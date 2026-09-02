// W Linux — shared compact pill button (26px), the Hub's second button size next
// to WButton's 30px settings-field size.
//
// Why it is shared: this exact Rectangle+Text+MouseArea was copy-pasted into four
// panels (AppearancePanel tabs, ThemeCreatePanel contrast segments, DisplaysPanel
// scope switch + actions, HotkeysPanel and AIProfilesPanel prompt forms), each
// with a comment saying "no shared type exists yet". They then drifted, and when
// light themes arrived every copy had to be found again to fix the same bug. This
// is that shared type; the union of what the four copies did is below.
//
// ── The state contract every W control follows ────────────────────────────────
//   rest      outline + label in INK (accentInk), fill fully transparent
//   hover     Colors.hover wash behind the same ink
//   active    accent FILL with accentFg on top; the outline joins the fill so the
//             pill reads as one solid block (same convention as Tile/HubMenu)
//   flat      a chip that stays muted (border/text) until `selected` accents it
//   danger    the whole ink swaps to dangerBorder
//   disabled  opacity 0.4, no interaction
//
// Two rules in there are load-bearing and are the reason light themes were broken:
//   • INK ≠ FILL. `Colors.accent` is a container pigment — it is *supposed* to sit
//     close to the surface, so it can never be an outline or a label. Anything
//     drawn ON the card uses `Colors.accentInk`, which the theme engine holds at
//     4.5:1 against it.
//   • The rest state is the hover colour at alpha 0, NEVER the literal
//     "transparent" — that is rgba(0,0,0,0), and ColorAnimation interpolates the
//     channels straight, so fading from it drags the fill through grey/black.
//
// `enabled` shadows QQuickItem.enabled by design (same idiom as HubRow/Tile/
// WButton) — interaction is gated manually below, native input-blocking unused.
import QtQuick
import qs.core

Rectangle {
    id: root

    property string label: ""
    property bool active: false      // filled: the current segment of a switch
    property bool danger: false      // destructive action
    property bool flat: false        // muted chip until `selected`
    property bool selected: false    // only meaningful with `flat`
    property int borderWidth: Geometry.border
    // qmllint disable property-override
    property bool enabled: true
    // qmllint enable property-override
    // Keyboard roving-focus indicator — same contract as Tile.focused. A segmented
    // WPill row (tabs, contrast picker) is navigated ←/→ by the owning panel, which
    // sets this on the segment currently under the keyboard cursor.
    property bool focused: false

    signal clicked()

    // A flat chip is muted until picked; every other pill is accented at rest.
    readonly property bool accented: !root.flat || root.selected
    readonly property color ink: root.danger ? Colors.dangerBorder
                                 : (root.accented ? Colors.accentInk : Colors.text)
    readonly property color outline: root.danger ? Colors.dangerBorder
                                     : (root.accented ? Colors.accentInk : Colors.border)

    implicitWidth: pillTxt.implicitWidth + 20
    implicitHeight: 26
    radius: Geometry.radiusSm
    opacity: root.enabled ? 1 : 0.4

    // Keyboard focus on an ACTIVE pill (the current tab/segment) would otherwise be
    // invisible: `active` already owns the accent fill, so the ring below is
    // suppressed there on purpose (see the comment under it), leaving color with
    // nothing left to say "the roving cursor is ALSO here, not just this segment is
    // selected". A small scale-lift reuses the hover-lift idiom already established
    // for theme tiles (AppearancePanel's ThemeTile) and reads regardless of `active`.
    scale: root.focused ? 1.08 : 1
    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    color: root.active ? Colors.accent
           : ((ma.containsMouse || root.focused) && root.enabled ? Colors.hover : Colors.alpha(Colors.hover, 0))
    border.width: root.focused && !root.active ? 2 : root.borderWidth
    // On the filled state the outline joins the fill: a ring in a different tone
    // would turn a solid segment into a two-colour badge.
    border.color: root.active ? Colors.accent : root.outline

    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: pillTxt
        anchors.centerIn: parent
        text: root.label
        color: root.active ? Colors.accentFg : root.ink
        font.family: Fonts.family
        font.pixelSize: 12
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
}
