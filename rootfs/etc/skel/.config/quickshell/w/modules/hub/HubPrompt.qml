// W Linux — Hub modal prompt chrome.
// The card-over-the-panel surface every in-Hub modal shares: a tint over everything
// behind it, a centered surface card holding whatever the panel puts in, and an
// outside click that dismisses. It carries NO buttons and NO keyboard handling —
// those differ per modal (Hotkeys' save-as/custom forms drive their own local roving
// list, HubConfirm builds a fixed Cancel + action row), and a chrome component that
// guessed at them would be fought by both. Extracted from HotkeysPanel's inline
// promptLayer, which was the only modal in the Hub until Packs needed a second one.
//
// ── Why the tint is drawn HERE and not by the Hub ────────────────────────────────
// The obvious place for "dim the Hub while a modal is up" is Hub.qml, next to the
// card. It does not work: the Hub card's children are its swallow-MouseArea and one
// Column (header + body), and `z` only orders SIBLINGS — a scrim declared after that
// Column paints over the whole Column, modal included, because the modal lives deep
// inside it (panel → Loader → body → Column). Hoisting the modal itself up to Hub
// level is the other way out and is what WFilePicker does, but a panel's modal is
// full of panel-local ids (HotkeysPanel reaches nameField/capChip by id from
// promptItemAt()), and those do not cross a Loader boundary.
//
// So the scrim is a child of THIS component, drawn before the card, and is given the
// Hub card's own rectangle to cover — passed in as `surface`, not guessed. An earlier
// version instead over-reached its bounds by a large negative margin and leaned on
// Hub.qml's `clip: true` to cut it back. That is wrong in a way that only shows on a
// themed corner radius: Qt Quick's `clip` cuts to an item's BOUNDING RECTANGLE, never
// to its rounded shape, so the tint kept four square corners poking past the Hub's
// rounded ones. Taking the surface's geometry AND its radius is the fix; the big
// negative margin survives only as the fallback for a caller that passes no surface.
//
// Lives flat in modules/hub/ with the other shared Hub components, so panels (which
// sit in the panels/ subdir and are not module types) reach it via `import
// qs.modules.hub`, the same way they reach HubRow / HubSection / HubDropdown.
import QtQuick
import qs.core

Item {
    id: root

    // The panel owns this: the modal is up while it is true.
    property bool open: false
    // The Hub card this modal dims: Hub.qml hands it to the panel (panelLoader.onLoaded,
    // the same way navArgs is handed over), the panel forwards it here. Null is allowed
    // and falls back to covering everything in reach — correct on square corners, and
    // the reason this is a property rather than an assumption.
    property Item surface: null
    // Optional heading inside the card. Empty = no heading row, which is what a modal
    // with several mutually exclusive forms wants (each form titles itself).
    property string title: ""
    // Everything the panel declares inside a HubPrompt lands in the card's Column.
    default property alias content: promptCol.data

    // Outside click, or whatever else the panel routes here (Esc, a Cancel button).
    signal dismissed()

    // Lower edge of the card, in this item's coordinates — the panel adds it to its
    // own implicitHeight (`Math.max(col.implicitHeight + 8, prompt.contentBottom)`) so
    // the Hub card morphs tall enough to show a modal taller than the panel behind it.
    // Same contract as HubDropdown.menuBottom, and 0 when closed for the same reason.
    readonly property real contentBottom: root.open ? promptCard.y + promptCard.height + 8 : 0

    // Above HubDropdown's overlay (z: 100) — a dropdown left open behind a modal must
    // not float over it.
    z: 101

    // Opens the way every other W surface does, because it is one: the Hub card and the
    // launcher both fade their content over Motion.fast and scale the card 0.96 → 1 over
    // Motion.base, both on the shared bezier. The scale (on promptCard below) is the half
    // that actually reads as "a window opened" — a bare opacity ramp looks like the
    // rectangle simply blinking on, which is what this did before.
    //
    // Closing is instant, and that is deliberate rather than an omission: `visible` drops
    // with `open`, so the animations below run unseen on the way out. A visible outgoing
    // fade would show the card zip shut to its own padding, because a closing modal's
    // content is bound to the state that just went away (HotkeysPanel's forms and the AI
    // panel's are `visible: <mode> === …`). Reopening therefore starts from the settled
    // 0/0.96 and plays the entrance in full.
    visible: root.open
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.bezierCurve
        }
    }

    // ── Tint ─────────────────────────────────────────────────────────────────────
    // The Hub card's rectangle, in this item's coordinates, inset by the card's own
    // outline so the Hub keeps a crisp border instead of being painted over at the edge.
    //
    // The offset is summed along the parent chain rather than taken from mapToItem/
    // mapFromItem, and that is not a stylistic choice: those are opaque C++ calls, so a
    // binding built on one registers NO dependency on the geometry it read. Hub.qml puts
    // this modal's panel inside a Column, and a positioner assigns its child's y AFTER
    // the binding first evaluates — mapFromItem duly returned (0, 0) and the tint sat in
    // the panel's own corner forever, because nothing ever invalidated it (caught by a
    // probe against a mock of the Hub's nesting, not by any linter). Reading `.x`/`.y`
    // here registers each one, so layout settling re-runs this, and so does the card's
    // height morph.
    Rectangle {
        readonly property real inset: (root.surface && root.surface.border)
                                      ? root.surface.border.width : 0
        readonly property rect box: {
            const s = root.surface;
            let dx = 0, dy = 0, it = root;
            while (it && it !== s) { dx += it.x; dy += it.y; it = it.parent; }
            // No surface, or one that is not actually an ancestor: cover everything in
            // reach and let the Hub card's clip bound it. Square corners, but visible.
            if (!it) return Qt.rect(-4096, -4096, root.width + 8192, root.height + 8192);
            return Qt.rect(-dx + inset, -dy + inset,
                           s.width - 2 * inset, s.height - 2 * inset);
        }

        x: box.x
        y: box.y
        width: box.width
        height: box.height
        // Same corner as the surface it covers — the whole point of taking its geometry.
        radius: root.surface ? Math.max(0, root.surface.radius - inset) : 0
        // The theme's own overlay-scrim value. A modal sitting on an already translucent
        // card needs the full weight to separate from it; a fraction of it read as haze.
        color: Qt.rgba(0, 0, 0, Effects.scrimOpacity)

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissed()
        }
    }

    // ── Card ─────────────────────────────────────────────────────────────────────
    // Opaque on purpose: the Hub card behind it is translucent (Effects.surfaceOpacity
    // over the blurred backdrop), so a translucent modal of the same hue is exactly
    // what read as "blends into the panel" before the tint existed.
    Rectangle {
        id: promptCard
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: parent.width - 24
        radius: Geometry.radiusSm
        color: Colors.surface
        border.width: HubConfig.border
        border.color: Colors.border
        implicitHeight: promptCol.implicitHeight + 24

        // Top-pinned scale-in, exactly like the Hub card's own (Hub.qml) — the card grows
        // from its fixed top edge instead of from its middle, so the heading stays put.
        transformOrigin: Item.Top
        scale: root.open ? 1 : 0.96
        Behavior on scale {
            NumberAnimation {
                duration: Motion.base
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.bezierCurve
            }
        }

        // Swallow clicks so they don't fall through to the dismissing tint.
        MouseArea { anchors.fill: parent }

        Column {
            id: promptCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            Text {
                visible: root.title.length > 0
                width: parent.width
                text: root.title
                color: Colors.text
                font.family: Fonts.family
                font.pixelSize: 14
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
        }
    }
}
