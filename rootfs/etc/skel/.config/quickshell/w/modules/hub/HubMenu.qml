// W Linux — Hub dropdown menu.
// A small floating options list for a multi-state setting (DNS mode, firewall zone): a
// rounded surface of rows, the current one accent-highlighted with a check glyph. Data-
// driven (`model` = [{ id, label }]) so a setting can grow options without UI changes.
// Hosted inside the Hub card's overlay layer (RootGrid positions it under the SelectRow's
// value button) — no separate window, so it never fights the Hub's keyboard grab. Emits
// picked(id) on selection. Colors/motion/fonts from the shared singletons.
//
// `maxContentHeight` (set by HubDropdown when a long list wouldn't otherwise fit before
// the panel's ceiling) caps the menu's height and scrolls its rows internally instead of
// growing past it — the default -1 keeps today's grow-to-fit behavior unchanged for every
// short dropdown in the Hub.
import QtQuick
import QtQuick.Controls
import qs.core

Rectangle {
    id: root

    property var model: []          // [{ id, label }]
    property string current: ""
    property real maxContentHeight: -1
    // Keyboard cursor over the option list — independent of `current` (the actually
    // picked value): seeded to the current selection on open so arrow keys start
    // from "where you are", not always row 0.
    property int highlightedIndex: -1

    signal picked(string id)
    // Esc while the menu holds focus: HubDropdown closes it and returns focus to
    // the row that opened it, instead of the key bubbling up to Hub's Esc/Backspace
    // (which would navigate the Hub itself back a level).
    signal closeRequested()

    function seedHighlight() {
        const i = (root.model || []).findIndex((o) => String(o.id) === root.current);
        root.highlightedIndex = i >= 0 ? i : 0;
    }
    // Keep the keyboard cursor's row inside the scrollable viewport — without this,
    // arrow-navigating past the visible slice of a capped/scrolling menu (see
    // `maxContentHeight` above) would move the selection invisibly.
    function scrollIntoView() {
        if (!root.scrollable) return;
        const rowY = root.highlightedIndex * root.rowH;
        if (rowY < menuFlick.contentY) menuFlick.contentY = rowY;
        else if (rowY + root.rowH > menuFlick.contentY + menuFlick.height)
            menuFlick.contentY = rowY + root.rowH - menuFlick.height;
    }

    focus: true
    Keys.onPressed: (e) => {
        const n = (root.model || []).length;
        if (n === 0) return;
        switch (e.key) {
        case HubNavKeys.down:
            root.highlightedIndex = Math.min(n - 1, root.highlightedIndex + 1);
            root.scrollIntoView(); e.accepted = true; return;
        case HubNavKeys.up:
            root.highlightedIndex = Math.max(0, root.highlightedIndex - 1);
            root.scrollIntoView(); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.picked(String(root.model[root.highlightedIndex].id));
            e.accepted = true; return;
        case HubNavKeys.back:
            root.closeRequested(); e.accepted = true; return;
        }
    }

    readonly property int rowH: 34
    readonly property int padV: 6
    // Breathing space between the widest label and the (right-pinned) check column, so the box
    // never hugs its longest option. Universal for every Hub dropdown.
    readonly property int padR: 30

    // Deterministic content width: measure the widest label with the row font, then add
    // left pad(12) + gap(padR) + check(14) + right margin(12). We can't lean on the Column's
    // implicitWidth — the rows bind their width back to it, so that path is circular and Qt
    // collapses it to the floor (fine for short options, too narrow for a long one like
    // "Super+Space"). A small floor keeps a 1–2 char option from looking cramped.
    TextMetrics { id: metric; font.family: Fonts.family; font.pixelSize: 13 }
    property int contentW: 96
    function recomputeWidth() {
        let w = 0;
        const m = root.model || [];
        for (let i = 0; i < m.length; i++) { metric.text = String(m[i].label); w = Math.max(w, metric.advanceWidth); }
        root.contentW = Math.max(96, Math.ceil(w) + 12 + root.padR + 14 + 12);
    }
    onModelChanged: recomputeWidth()

    readonly property real naturalHeight: menuCol.implicitHeight + root.padV * 2
    readonly property bool scrollable: root.maxContentHeight > 0 && root.naturalHeight > root.maxContentHeight

    width: root.contentW
    height: root.scrollable ? root.maxContentHeight : root.naturalHeight
    radius: Geometry.radiusSm
    color: Colors.surface
    border.color: Colors.border
    border.width: Geometry.border

    // Entrance: quick fade (position is owned by the parent Loader).
    opacity: 0
    Component.onCompleted: { recomputeWidth(); root.seedHighlight(); appear.start(); }
    NumberAnimation { id: appear; target: root; property: "opacity"; to: 1; duration: Motion.fast }

    Flickable {
        id: menuFlick
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                  topMargin: root.padV; bottomMargin: root.padV }
        clip: true
        // Off unconditionally: the MouseArea below drives contentY on wheel, and the
        // WScrollBar handle drags contentY independently of this flag — nothing here needs
        // Flickable's own touch/mouse-drag-to-pan or built-in wheel response, and leaving
        // either on would compete with that MouseArea for the same wheel events (or leave
        // ambiguous which of the two actually stops the event reaching the page beneath).
        interactive: false
        contentHeight: menuCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar { visible: root.scrollable }

        Column {
            id: menuCol
            width: menuFlick.width

            Repeater {
                model: root.model
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: menuCol.width
                    height: root.rowH

                    readonly property bool isCurrent: String(modelData.id) === root.current
                    readonly property bool isHighlighted: row.index === root.highlightedIndex

                    Rectangle {
                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                        radius: Geometry.radiusSm
                        color: row.isCurrent ? Colors.accent
                               : ((ma.containsMouse || row.isHighlighted) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Text {
                        id: lbl
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: row.modelData.label
                        color: row.isCurrent ? Colors.accentFg : Colors.text
                        font.family: Fonts.family
                        font.pixelSize: 13
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        visible: row.isCurrent
                        text: String.fromCodePoint(0xf012c)   // nf-md-check
                        font.family: Fonts.mono
                        font.pixelSize: 13
                        color: Colors.accentFg
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.picked(String(row.modelData.id))
                    }
                }
            }
        }
    }

    // Wheel over the popup must never leak to whatever sits underneath it — the Hub card
    // is a sibling overlay, not an ancestor of the panel's own Flickable, and Qt Quick
    // resolves an unhandled wheel event by offering it to the next item down the FULL
    // on-screen stack (not just up this item's own parent chain), so an unaccepted event
    // here really does reach the page below and scroll it. A plain MouseArea reliably
    // blocks that cascade — it's the same mechanism HubDropdown's own "click outside
    // closes" area already relies on — where a newer WheelHandler was tried and did not
    // (this replaced it). `acceptedButtons: NoButton` + `hoverEnabled: false` make it
    // transparent to everything except wheel, so row clicks/hover underneath are
    // untouched; declaring it last (topmost) puts it first in line for the event.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            if (root.scrollable) {
                const maxY = Math.max(0, menuFlick.contentHeight - menuFlick.height);
                menuFlick.contentY = Math.max(0, Math.min(maxY,
                    menuFlick.contentY - (wheel.angleDelta.y / 120) * root.rowH));
            }
            wheel.accepted = true;
        }
    }
}
