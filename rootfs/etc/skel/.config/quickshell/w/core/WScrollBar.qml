// W Linux — shared themed scrollbar.
// One scroll indicator for every scrollable surface in the shell (Hub / launcher /
// clipboard …) so they read as one system. Attach to any Flickable-derived view:
//   ListView  { ScrollBar.vertical: WScrollBar {} }
//   GridView  { ScrollBar.vertical: WScrollBar {} }
//   Flickable { ScrollBar.vertical: WScrollBar {} }
// A thin rounded pill on the trailing edge: shown only when content overflows
// (AsNeeded), fades in while scrolling/hovered and out when idle, accent on press.
// Colors/Motion come from the shared singletons.
import QtQuick
import QtQuick.Controls
import qs.core

ScrollBar {
    id: root
    // Only present when the content actually overflows the viewport.
    policy: ScrollBar.AsNeeded
    // The pill hugs the trailing edge (small right padding). To keep it off the content
    // AND close to the window edge, the host view extends into its container's right
    // padding (anchors.rightMargin: -N) while the inner content insets the same N — so the
    // content padding stays symmetric and the pill lands in the freed lane near the edge.
    leftPadding: 4
    rightPadding: 2
    topPadding: 2
    bottomPadding: 2
    implicitWidth: 10

    contentItem: Rectangle {
        implicitWidth: 4
        radius: width / 2
        color: root.pressed ? Colors.accentInk
             : (root.hovered ? Colors.text : Colors.muted)
        // Visible only while the view is active (scrolling) or the bar is hovered;
        // otherwise it fades away so the surface stays clean.
        opacity: (root.active || root.hovered) ? (root.pressed || root.hovered ? 0.9 : 0.5) : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    // No track — the pill floats over the content edge.
    background: null
}
