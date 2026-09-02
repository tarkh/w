// W Linux — Hub system-language picker (Ф5, drilled from InputPanel).
// A searchable catalogue of the UTF-8 locales glibc supports (`w-locale list`).
// Picking one switches the system LANG via the privileged path — pkexec +
// com.w.hub.actuate, capability locale-set → `w-locale set` — handed to the Hub as
// runPrivileged, which suspends for the polkit prompt and restores on exit; on
// completion it pops back to the Input panel. The change applies only to sessions
// started afterwards, so this is a deliberate, prompted action (the Input panel
// carries the "log back in" hint).
//
// Fills the card height and scrolls internally; too large for the small HubMenu,
// hence a full drill-in screen. Loaded via HubRegistry; shared bits via qs.modules.hub.
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
    implicitHeight: 480

    // Anti-jitter state for hover-driven selection (see the delegate's MouseArea) — a
    // fresh Item per Loader-open (Hub routes reload the source each time), so this
    // starts null on every open without extra reset wiring.
    property var lastPointer: null

    // Privileged actuation + pop, both wired by the Hub.
    signal runPrivileged(var cmd, var onDone)
    signal navigateBack()

    property string query: ""
    property var locales: []                  // ["en_US.UTF-8", …]

    function filtered() {
        const q = root.query.trim().toLowerCase();
        if (!q) return root.locales;
        return root.locales.filter(l => l.toLowerCase().indexOf(q) >= 0);
    }
    readonly property var model: filtered()

    Process {
        id: localeList
        running: true
        command: ["w-locale", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of (this.text || "").split("\n")) { const t = line.trim(); if (t) out.push(t); }
                root.locales = out;
            }
        }
    }

    function pick(loc) {
        root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "locale-set", loc],
                           () => root.navigateBack());
    }

    Column {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            width: parent.width
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
                placeholderText: Strings.t("hub.searchLocale")
                placeholderTextColor: Colors.muted
                font.family: Fonts.family; font.pixelSize: 15
                selectionColor: Colors.accent; selectedTextColor: Colors.accentFg
                focus: true
                onTextChanged: { root.query = text; results.currentIndex = 0; }
                // Mode B: the search field owns the keyboard for as long as the picker is
                // open, so ↑↓/Enter stay bare and the profile set rides Ctrl (on i3-vim
                // physically Ctrl+j/Ctrl+k) — one resolver for every W palette, see
                // core/HubNavKeys.qml.
                Keys.onPressed: (e) => {
                    switch (HubNavKeys.fieldAction(e)) {
                    case "down": results.incrementCurrentIndex(); e.accepted = true; return;
                    case "up":   results.decrementCurrentIndex(); e.accepted = true; return;
                    case "confirm":
                        if (results.currentIndex >= 0 && results.currentIndex < results.count)
                            root.pick(results.model[results.currentIndex]);
                        e.accepted = true;
                        return;
                    // "back" is deliberately left unaccepted: popping a panel belongs to
                    // the Hub's card (Hub.qml), and letting the event bubble is what makes
                    // Escape and Ctrl+menu_back behave here exactly as everywhere else.
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
                height: 38

                readonly property bool current: ListView.isCurrentItem

                Text {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    text: dele.modelData
                    color: dele.current ? Colors.accentFg : Colors.text
                    font.family: Fonts.family; font.pixelSize: 14
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
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
                    onClicked: root.pick(dele.modelData)
                }
            }
        }
    }
}
