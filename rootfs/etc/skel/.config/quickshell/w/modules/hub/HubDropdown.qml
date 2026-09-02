// W Linux — Hub dropdown plumbing + overlay, shared by every panel with a SelectRow.
// Owns the single-menu-at-a-time state machine (open/current/pick-callback/position) and
// hosts the actual overlay (outside-click-to-close + a HubMenu Loader anchored under the
// row's value button). A panel drops one of these in as `menuLayer` and calls
// `menuLayer.openMenu(row, opts, current, onPick)` from each SelectRow's onActivated —
// no more per-panel copy of this math. `flipUp` opts into the PowerPanel-style behavior:
// flip the menu above the row when it would spill past the layer's bottom edge and there
// is room above; panels that don't care leave it false and always grow via `menuBottom`
// (0 when closed or flipped up) — same contract every panel already had, just shared.
//
// A long option list (Displays' resolution dropdown) can be taller than ANY available
// space below a row, even the topmost one — flipping direction doesn't help, there's
// simply nowhere for it to fully fit. `fitDownward()` caps such a menu at the room left
// before the panel's hard ceiling and tells HubMenu to scroll internally instead
// (`maxContentHeight`), rather than growing past the card and getting clipped.
import QtQuick
import qs.core

Item {
    id: root

    // PowerPanel-style: flip the menu upward near the bottom instead of growing the card.
    property bool flipUp: false
    // Where keyboard focus goes back to when the menu closes (Esc / pick / outside
    // click) — the panel's own roving-nav root, so its Keys.onPressed catches arrows
    // again instead of the key silently going nowhere. null = panel hasn't opted in
    // (mouse-only panel, unchanged behavior).
    property Item returnFocusTo: null

    property bool   menuOpen: false
    property var    menuOpts: []
    property string menuCurrent: ""
    property var    menuOnPick: null
    property var    menuOwner: null
    property real   menuRight: 0
    property real   menuTop: 0
    property real   menuBottom: 0   // downward menu's lower edge (grows the card); 0 = closed/flipped up
    property real   menuMaxH: -1    // -1 = unconstrained; >0 = HubMenu must cap+scroll to this

    // Every drilled-in panel shares the same hard viewport ceiling (Hub.qml: maxCardH(560)
    // − chrome(84) = 476, documented in quickshell-hub.md as a cross-panel constant) — a
    // FIXED bound, not the panel's current (possibly still-small, pre-growth) height, which
    // would make a short panel's small dropdown cap prematurely before the card has had a
    // chance to grow to fit it.
    readonly property int panelCeiling: 476
    readonly property int menuGap: 8      // breathing room before the panel's bottom edge
    readonly property int menuMinH: 80    // floor so a capped menu never squashes to near-nothing

    z: 100
    visible: root.menuOpen

    // How much of `natural` fits below `topY` before the panel's hard ceiling.
    // Returns {shown, maxH}: maxH -1 = fits naturally (no scroll needed), otherwise the
    // capped height HubMenu must scroll within.
    function fitDownward(topY, natural) {
        const avail = Math.max(root.menuMinH, root.panelCeiling - topY - root.menuGap);
        if (natural <= avail) return { shown: natural, maxH: -1 };
        return { shown: avail, maxH: avail };
    }

    function openMenu(row, opts, current, onPick) {
        const a = row.anchorItem;
        const below = a.mapToItem(root, a.width, a.height + 4);
        // Whole-pixel anchor: a fractional origin makes the menu border render subpixel-
        // blurred and shimmer as rows repaint on hover.
        root.menuRight = Math.round(below.x);
        const natural = opts.length * 34 + 12;

        if (root.flipUp) {
            const topAnchor = a.mapToItem(root, a.width, 0);
            // Flip up when the menu would spill past the visible layer bottom and there is room above.
            if (below.y + natural > root.height && topAnchor.y - 4 - natural >= 0) {
                root.menuTop = Math.round(topAnchor.y - 4 - natural);
                root.menuBottom = 0;                        // upward: fits within current bounds
                root.menuMaxH = -1;
            } else {
                root.menuTop = Math.round(below.y);
                const fit = root.fitDownward(root.menuTop, natural);
                root.menuMaxH = fit.maxH;
                root.menuBottom = root.menuTop + fit.shown + root.menuGap;
            }
        } else {
            root.menuTop = Math.round(below.y);
            const fit = root.fitDownward(root.menuTop, natural);
            root.menuMaxH = fit.maxH;
            root.menuBottom = root.menuTop + fit.shown + root.menuGap;
        }

        root.menuOpts = opts;
        root.menuCurrent = current;
        root.menuOnPick = onPick;
        root.menuOwner = row;
        row.menuOpen = true;
        root.menuOpen = true;
    }
    function closeMenu() {
        if (root.menuOwner) root.menuOwner.menuOpen = false;
        root.menuOwner = null;
        root.menuOnPick = null;
        root.menuOpen = false;
        root.menuBottom = 0;
        root.menuMaxH = -1;
        if (root.returnFocusTo) root.returnFocusTo.forceActiveFocus();
    }
    function pickMenu(id) {
        const cb = root.menuOnPick;
        root.closeMenu();
        if (cb) cb(id);
    }

    MouseArea { anchors.fill: parent; onClicked: root.closeMenu() }

    Loader {
        id: menuLoader
        active: root.menuOpen
        // Right-aligned to the button, whole-pixel (see openMenu).
        x: Math.round(root.menuRight - (item ? item.width : 0))
        y: root.menuTop
        sourceComponent: HubMenu {
            model: root.menuOpts
            current: root.menuCurrent
            maxContentHeight: root.menuMaxH
            onPicked: (id) => root.pickMenu(id)
            onCloseRequested: root.closeMenu()
        }
        // Grab keyboard focus the moment the menu appears, so arrow keys navigate its
        // options instead of the row that opened it. `active` toggles false→true on
        // every open (the item is destroyed on close, not just hidden), so onLoaded
        // fires each time — no separate "reopen" hook needed.
        onLoaded: if (item) item.forceActiveFocus()
    }
}
