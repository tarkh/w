// W Linux — Hub keyboard layout picker (Ф5, drilled from InputPanel).
// A searchable, two-stage catalogue for "Add language": stage 1 picks an XKB layout
// (all ~99 from `w-keyboard list`), stage 2 optionally picks a variant of it (from
// `w-keyboard variants <code>`, with "Default" first); a layout with no variants is
// added straight away. The pick runs `w-keyboard add <code[:variant]>` — user-space,
// applied live + persisted — and pops back to the Input panel on completion.
//
// The card is short and its dropdown-free, so the picker fills the card height and
// scrolls internally (WScrollBar). Search filters the current stage by code or name.
// The catalogue is too large for the small HubMenu, hence a full drill-in screen.
// Loaded via HubRegistry (Loader{source}); shared hub bits via `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub

// FocusScope (not a plain Item): Hub.qml's focusContent() calls forceActiveFocus() on
// the loaded panel root, and only a FocusScope cascades that down to `search` (which
// carries `focus: true`) — a plain Item would take the active focus itself and leave
// the TextField, and therefore typing/arrow keys, dead until a manual mouse click.
FocusScope {
    id: root
    // Fill the card (capped by the Hub's maxCardH) so the list gets a real viewport.
    implicitHeight: 480

    // Anti-jitter state for hover-driven selection (see the delegate's MouseArea) — a
    // fresh Item per Loader-open (Hub routes reload the source each time), so this
    // starts null on every open without extra reset wiring.
    property var lastPointer: null

    // Pop back to the Input panel (wired by the Hub).
    signal navigateBack()

    property string stage: "layouts"        // "layouts" | "variants"
    property string pendingCode: ""          // layout chosen in stage 1
    property string query: ""

    property var layouts: []                 // [{ code, desc }]
    property var variants: []                // [{ id, desc }]  (id "" = default)

    // Filter the active stage's list by the search query (code or description).
    function filtered() {
        const q = root.query.trim().toLowerCase();
        const src = root.stage === "layouts"
            ? root.layouts.map(l => ({ id: l.code, code: l.code, desc: l.desc }))
            : root.variants.map(v => ({ id: v.id, code: v.id || "—", desc: v.desc }));
        if (!q) return src;
        return src.filter(o => o.code.toLowerCase().indexOf(q) >= 0
                            || o.desc.toLowerCase().indexOf(q) >= 0);
    }
    readonly property var model: filtered()

    // ── Catalogue reads ──────────────────────────────────────────────────────────
    Process {
        id: layoutList
        running: true
        command: ["w-keyboard", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of (this.text || "").split("\n")) {
                    const t = line.split("\t");
                    if (t.length >= 2 && t[0]) out.push({ code: t[0], desc: t[1] });
                }
                root.layouts = out;
            }
        }
    }
    Process {
        id: variantList
        stdout: StdioCollector {
            onStreamFinished: {
                const real = [];
                for (const line of (this.text || "").split("\n")) {
                    const t = line.split("\t");
                    if (t.length >= 2 && t[0]) real.push({ id: t[0], desc: t[1] });
                }
                // No variants → add the plain layout straight away; otherwise offer them
                // (with "Default" first) in stage 2.
                if (real.length === 0) { root.commit(""); return; }
                root.variants = [{ id: "", desc: Strings.t("hub.defaultVariant") }].concat(real);
                root.stage = "variants";
                root.query = "";
                results.currentIndex = 0;
            }
        }
    }

    // ── Commit (add) — tracked so we pop only once it is applied + persisted ──────
    Process { id: addProc; onExited: root.navigateBack() }
    function commit(variant) {
        addProc.command = ["w-keyboard", "add", root.pendingCode + (variant ? ":" + variant : "")];
        addProc.running = true;
    }

    // Stage-1 pick: fetch variants (→ stage 2) or add immediately if the layout has none.
    function pickLayout(code) {
        root.pendingCode = code;
        variantList.command = ["w-keyboard", "variants", code, "--porcelain"];
        variantList.running = true;
        // If the layout has no variants the Process finishes with an empty list; the
        // "Default"-only stage still shows, letting the user confirm the plain layout.
    }

    // Stage 2 → stage 1, shared by the mouse "‹" and the Esc key.
    function stepBack() {
        root.stage = "layouts";
        root.query = "";
        results.currentIndex = 0;
    }

    // ── UI ───────────────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        spacing: 10

        // Search + optional in-picker back (stage 2 → stage 1). The Hub's Esc/‹ pops
        // the whole picker; this local ‹ steps back one stage without leaving.
        Row {
            width: parent.width
            spacing: 8
            Item {
                width: stageBack.visible ? 24 : 0
                height: 40
                Text {
                    id: stageBack
                    anchors.centerIn: parent
                    visible: root.stage === "variants"
                    text: "‹"
                    color: sbMa.containsMouse ? Colors.accentInk : Colors.muted
                    font.family: Fonts.family; font.pixelSize: 22
                    MouseArea {
                        id: sbMa
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.stepBack()
                    }
                }
            }
            Rectangle {
                width: parent.width - (stageBack.visible ? 32 : 0)
                height: 40
                radius: Geometry.radiusSm
                color: Colors.inputBg
                TextField {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                    color: Colors.text
                    placeholderText: root.stage === "layouts"
                        ? Strings.t("hub.searchLanguage") : Strings.t("hub.searchVariant")
                    placeholderTextColor: Colors.muted
                    font.family: Fonts.family; font.pixelSize: 15
                    selectionColor: Colors.accent; selectedTextColor: Colors.accentFg
                    focus: true
                    onTextChanged: { root.query = text; results.currentIndex = 0; }
                    // Mode B: the search field owns the keyboard for as long as the picker
                    // is open, so ↑↓/Enter stay bare and the profile set rides Ctrl (on
                    // i3-vim physically Ctrl+j/Ctrl+k) — one resolver for every W palette,
                    // see core/HubNavKeys.qml.
                    Keys.onPressed: (e) => {
                        switch (HubNavKeys.fieldAction(e)) {
                        case "down": results.incrementCurrentIndex(); e.accepted = true; return;
                        case "up":   results.decrementCurrentIndex(); e.accepted = true; return;
                        case "confirm":
                            if (results.currentIndex >= 0 && results.currentIndex < results.count)
                                results.itemAtIndex(results.currentIndex).activate();
                            e.accepted = true;
                            return;
                        // Stage 2 → stage 1 without leaving the picker; on stage 1 the
                        // event is left unaccepted so it bubbles to the Hub's card
                        // (Hub.qml) and pops back to Input, as in the other two pickers.
                        case "back":
                            if (root.stage === "variants") { root.stepBack(); e.accepted = true; }
                            return;
                        }
                    }
                }
            }
        }

        ListView {
            id: results
            // Extend into the card's right padding (margin 16 → pill ~4px from the edge);
            // delegates inset the same 12 so rows stay put and only the shared scrollbar
            // moves near the window edge.
            width: parent.width + 12
            height: parent.height - 50
            clip: true
            model: root.model
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            ScrollBar.vertical: WScrollBar {}

            // Single sliding selection — doubles as the keyboard cursor and the mouse-
            // hover state (see the delegate's MouseArea), same convention as Launcher/
            // Clipboard: one state, not a separate hover wash plus a roving cursor.
            highlightMoveDuration: Motion.fast
            highlightResizeDuration: 0
            highlightFollowsCurrentItem: true
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            highlight: Rectangle {
                radius: Geometry.radiusSm
                color: Colors.accent
            }

            delegate: Item {
                id: dele
                required property var modelData
                required property int index
                width: results.width - 12   // inset the view's gutter extension
                height: 40

                readonly property bool current: ListView.isCurrentItem

                function activate() {
                    if (root.stage === "layouts") root.pickLayout(dele.modelData.id);
                    else root.commit(dele.modelData.id);
                }
                Row {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        text: dele.modelData.code.toUpperCase()
                        color: dele.current ? Colors.accentFg : Colors.text
                        font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 54
                        text: dele.modelData.desc
                        color: dele.current ? Colors.accentFg : Colors.muted
                        font.family: Fonts.family; font.pixelSize: 13
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }
                MouseArea {
                    id: deMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: (mouse) => {
                        const p = dele.mapToItem(null, mouse.x, mouse.y);
                        if (root.lastPointer === null) { root.lastPointer = p; return; }
                        if (Math.abs(p.x - root.lastPointer.x) + Math.abs(p.y - root.lastPointer.y) < 2)
                            return;
                        root.lastPointer = p;
                        results.currentIndex = dele.index;
                    }
                    onClicked: dele.activate()
                }
            }
        }
    }
}
