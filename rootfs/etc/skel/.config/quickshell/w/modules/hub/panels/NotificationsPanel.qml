// W Linux — Hub Notifications panel (Ф-notifications).
// The notification drill-in: Do Not Disturb (with quick deadlines), per-app mute,
// popup behaviour (timeouts / stack cap / OSD) and the history of what arrived —
// a pure front-end over `w-notify`.
//
// Unlike PowerPanel there is NO porcelain read: every value the panel shows already
// lives in the NotifConfig singleton, which watches the very same files w-notify
// writes, so the UI re-renders the moment the CLI, a hotkey or the AI changes
// anything — and the panel never has to poll or re-read after its own writes.
// Mutations still go through `w-notify` (never a direct JSON write from QML): one
// writer per file is what keeps the CLI, the bar block and this panel from racing.
//
// History is read straight from the state file rather than shelling out — the
// notification daemon that writes it lives in this same process, so a FileView watch
// is both cheaper and more immediate than `w-notify history`. Entries are records,
// not live notifications: their actions died with the popup, so rows are read-only
// by design (see quickshell-notifications.md).
//
// Loaded via HubRegistry as a subdir file → shared components via `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.notifications
import qs.modules.shading

Item {
    id: root
    // +8 mirrors the Flickable's own contentHeight padding below (focus-wash bleed
    // slack) — see quickshell-hub.md's Ф-Keyboard gotcha #6.
    implicitHeight: Math.max(col.implicitHeight + 8, menuLayer.menuBottom)

    // ── Backend (every mutation goes through the CLI) ───────────────────────────────
    Process { id: proc }
    function run(cmd) { proc.running = false; proc.command = cmd; proc.running = true; }

    // ── History (written by modules/notifications/Notifications.qml) ────────────────
    property var history: []

    FileView {
        id: histFile
        path: NotifConfig.historyPath
        watchChanges: true
        printErrors: false          // absent until the first notification is recorded
        onFileChanged: reload()
        onLoaded: {
            try {
                const a = JSON.parse(histFile.text() || "[]");
                root.history = Array.isArray(a) ? a : [];
            } catch (e) {
                root.history = [];
            }
        }
    }

    readonly property int historyShown: 30

    // Apps worth offering a mute switch for: everything seen recently, plus everything
    // already muted (so an app can be un-muted after it went quiet and aged out).
    readonly property var apps: {
        const idx = {};
        const out = [];
        for (let i = 0; i < root.history.length; i++) {
            const name = root.history[i].app || "";
            if (name.length === 0) continue;
            const key = name.toLowerCase();
            if (idx[key] === undefined) { idx[key] = out.length; out.push({ name: name, count: 1 }); }
            else out[idx[key]].count++;
        }
        for (let j = 0; j < NotifConfig.mutedApps.length; j++) {
            const m = "" + NotifConfig.mutedApps[j];
            if (idx[m.toLowerCase()] === undefined) { idx[m.toLowerCase()] = out.length; out.push({ name: m, count: 0 }); }
        }
        out.sort((a, b) => b.count - a.count);
        return out.slice(0, 12);
    }

    // ── Keyboard roving-focus (fixed rows → variable app-mute Repeater → one
    // conditional trailing row) ─────────────────────────────────────────────────
    // History rows are excluded entirely — HistoryRow has no MouseArea/action
    // (checklist's grep-for-MouseArea audit, gotcha #10), so they are simply never
    // part of this list. The app-mute Repeater's count varies with `root.apps`
    // (0–12), same InputPanel idiom as the keyboard-layout ring: a plain linear
    // index over fixed-before + Repeater + fixed-after, rather than Displays' named
    // descriptors (nothing here needs a name-keyed lookup across a Loader boundary).
    readonly property var fixedBefore: [dndRow, dnd30Btn, dnd1hBtn, dndMorningBtn, critRow, fsRow,
                                         toLow, toNormal, toCrit, toMax, osdRow, testBtn]
    readonly property bool hasClear: root.history.length > 0
    readonly property int focusCount: root.fixedBefore.length + root.apps.length + (root.hasClear ? 1 : 0)
    property int focusIndex: 0
    onFocusCountChanged: root.focusIndex = Math.max(0, Math.min(root.focusIndex, root.focusCount - 1))

    function focusItem(i) {
        const nb = root.fixedBefore.length;
        if (i < nb) return root.fixedBefore[i];
        if (i < nb + root.apps.length) return muteRepeater.itemAt(i - nb);
        return clearBtn;
    }
    // True while a TimeoutRow's seconds field holds real Qt focus — Up/Down must
    // move the cursor there, not steal the roving index (same reasoning as
    // PowerPanel.editingText).
    readonly property bool editingText: root.fixedBefore.some((f) => f.input !== undefined && f.input.activeFocus)

    function scrollIntoView(i) {
        const item = root.focusItem(i);
        if (!item) return;
        // True-edge-first — a HubSection header sits above the first row (same
        // reasoning as InputPanel/PowerPanel.scrollIntoView).
        if (i === 0) { flick.contentY = 0; return; }
        if (i === root.focusCount - 1) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }
    function focusRow(i) {
        root.focusIndex = Math.max(0, Math.min(i, root.focusCount - 1));
        root.scrollIntoView(root.focusIndex);
    }

    focus: true
    Keys.onPressed: (e) => {
        if (root.editingText) return;
        if (root.focusCount === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:   root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = root.focusItem(root.focusIndex);
            if (!item) { e.accepted = true; return; }
            if (item.input !== undefined) item.input.forceActiveFocus();
            else if (item.activated !== undefined) item.activated();
            else if (item.clicked !== undefined) item.clicked();
            e.accepted = true;
            return;
        }
        }
    }

    // ── Label helpers ──────────────────────────────────────────────────────────────
    function onOffLabel(on) { return Strings.t(on ? "notif.on" : "notif.off"); }
    function onOffOptions() {
        return [{ id: "on", label: Strings.t("notif.on") }, { id: "off", label: Strings.t("notif.off") }];
    }

    // DND summary: plain on/off, or the deadline it lapses at.
    readonly property string dndValue: {
        if (!NotifConfig.dndActive) return Strings.t("notif.off");
        if (NotifConfig.dndUntil > 0)
            return Strings.t("notif.until") + " " + Qt.formatTime(new Date(NotifConfig.dndUntil * 1000), "HH:mm");
        return Strings.t("notif.on");
    }

    function stamp(ts) {
        const d = new Date(ts * 1000);
        const now = new Date();
        const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth()
            && d.getDate() === now.getDate();
        return sameDay ? Qt.formatTime(d, "HH:mm") : Qt.formatDateTime(d, "dd.MM HH:mm");
    }

    // ── Row components ─────────────────────────────────────────────────────────────
    // Timeout row: seconds field + apply. Milliseconds are the config's unit but a
    // person thinks in seconds, so the field converts; 0 keeps its "never" meaning.
    component TimeoutRow: Item {
        id: toRow
        required property string glyph
        required property string label
        property int valueMs: 0
        // Keyboard roving-focus indicator, same contract as Tile/SelectRow/HubRow —
        // set by the panel's roving index. `exitField()` mirrors IdleRow: an inline
        // `component` block cannot see the enclosing file's `root` id, so handing
        // focus back to the panel on Tab/Esc has to go out through a signal.
        property bool focused: false
        // NOT `property alias`: WSettingsField.input is already a 2-hop alias onto
        // WTextBox's own TextField, and a 3rd alias hop on top of that is exactly
        // qmllint's unresolved-alias case (quickshell-hub.md's Ф-Keyboard gotcha
        // #9 — same root as the pre-existing PowerPanel.qml finding, not to be
        // multiplied). `var` is a plain binding to the same constant Item
        // reference and behaves identically at runtime.
        property var input: toField.input
        signal apply(int ms)
        signal exitField()

        width: parent.width
        implicitHeight: 38

        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: toRow.focused && !toField.input.activeFocus
            color: Colors.hover
        }

        Row {
            id: toLeft
            anchors {
                left: parent.left
                right: toField.left; rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 10
            ChromeIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: 22
                glyph: toRow.glyph
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: toRow.label
                    color: Colors.text
                    font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                }
                Text {
                    width: Math.max(0, toLeft.width - 32)
                    text: toRow.valueMs > 0 ? "" : Strings.t("notif.never")
                    visible: text.length > 0
                    color: Colors.muted
                    font.family: Fonts.family; font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }
        WSettingsField {
            id: toField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fixedWidth: 56
            numeric: true
            suffix: Strings.t("notif.sec")
            value: "" + Math.round(toRow.valueMs / 1000)
            validator: (text) => /^[0-9]+$/.test(text)
            borderWidth: HubConfig.border
            onApplied: (text) => toRow.apply(parseInt(text) * 1000)
            input.Keys.onTabPressed: toRow.exitField()
            input.Keys.onEscapePressed: toRow.exitField()
        }
    }

    // History entry: a record, not a live notification — no click target on purpose.
    component HistoryRow: Item {
        id: hRow
        required property var entry

        width: parent.width
        implicitHeight: 40

        readonly property bool critical: (hRow.entry.urgency || "") === "critical"

        Text {
            id: hTime
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            text: root.stamp(hRow.entry.ts || 0)
            color: Colors.muted
            font.family: Fonts.family; font.pixelSize: 12
        }
        Column {
            anchors {
                left: hTime.right; leftMargin: 8
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 2
            Text {
                width: parent.width
                text: hRow.entry.summary || ""
                color: hRow.critical ? Colors.dangerBorder : Colors.text
                font.family: Fonts.family; font.pixelSize: 13
                font.weight: hRow.critical ? Font.Medium : Font.Normal
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                width: parent.width
                // The dot marks what DND or a mute kept off the screen — the whole point
                // of recording suppressed alerts is being able to see them here later.
                text: (hRow.entry.suppressed ? "· " : "") + (hRow.entry.app || "")
                      + ((hRow.entry.body || "").length > 0 ? "  —  " + hRow.entry.body : "")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // ── Layout (scrolls; same bleed/scroll contract as PowerPanel/InputPanel —
    // quickshell-hub.md's Ф-Keyboard checklist item 7, NOT Flickable.topMargin/
    // bottomMargin, see gotcha #3) ───────────────────────────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: -12                 // pill near the window edge; col insets the same
        anchors.leftMargin: -8                    // room for rows' -8 left focus-wash bleed
        clip: true
        contentHeight: col.implicitHeight + 8     // 4px slack at each end for the wash bleed
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 12

            // ── Do Not Disturb ──────────────────────────────────────────────────
            HubSection { width: parent.width; text: Strings.t("notif.dndSec") }
            SelectRow {
                id: dndRow
                width: parent.width
                icon: "notification-disabled"; glyph: String.fromCodePoint(0xf009e)   // nf-md-bell_off
                label: Strings.t("notif.dndLabel")
                currentId: NotifConfig.dndActive ? "on" : "off"
                value: root.dndValue
                options: root.onOffOptions()
                focused: root.focusIndex === root.fixedBefore.indexOf(dndRow)
                onActivated: menuLayer.openMenu(dndRow, options, dndRow.currentId,
                                                (id) => root.run(["w-notify", "dnd", id]))
            }

            // Quick deadlines — the common shapes of "not now" without opening a menu.
            Row {
                width: parent.width
                spacing: 8
                WButton {
                    id: dnd30Btn
                    label: Strings.t("notif.for30m")
                    focused: root.focusIndex === root.fixedBefore.indexOf(dnd30Btn)
                    onClicked: root.run(["w-notify", "dnd", "for", "30m"])
                }
                WButton {
                    id: dnd1hBtn
                    label: Strings.t("notif.for1h")
                    focused: root.focusIndex === root.fixedBefore.indexOf(dnd1hBtn)
                    onClicked: root.run(["w-notify", "dnd", "for", "1h"])
                }
                WButton {
                    id: dndMorningBtn
                    label: Strings.t("notif.untilMorning")
                    focused: root.focusIndex === root.fixedBefore.indexOf(dndMorningBtn)
                    onClicked: root.run(["w-notify", "dnd", "until", "08:00"])
                }
            }

            SelectRow {
                id: critRow
                width: parent.width
                icon: "dialog-warning"; glyph: String.fromCodePoint(0xf0026)   // nf-md-alert
                label: Strings.t("notif.allowCritical")
                currentId: NotifConfig.dndAllowCritical ? "on" : "off"
                value: root.onOffLabel(NotifConfig.dndAllowCritical)
                options: root.onOffOptions()
                focused: root.focusIndex === root.fixedBefore.indexOf(critRow)
                onActivated: menuLayer.openMenu(critRow, options, critRow.currentId,
                                                (id) => root.run(["w-notify", "dnd", "critical", id]))
            }
            SelectRow {
                id: fsRow
                width: parent.width
                icon: "view-fullscreen"; glyph: String.fromCodePoint(0xf0293)   // nf-md-fullscreen
                label: Strings.t("notif.autoFullscreen")
                currentId: NotifConfig.dndAutoFullscreen ? "on" : "off"
                value: root.onOffLabel(NotifConfig.dndAutoFullscreen)
                options: root.onOffOptions()
                focused: root.focusIndex === root.fixedBefore.indexOf(fsRow)
                onActivated: menuLayer.openMenu(fsRow, options, fsRow.currentId,
                                                (id) => root.run(["w-notify", "dnd", "fullscreen", id]))
            }

            // ── Popup behaviour ─────────────────────────────────────────────────
            HubSection { width: parent.width; text: Strings.t("notif.behaviourSec") }
            TimeoutRow {
                id: toLow
                glyph: String.fromCodePoint(0xf0176)   // nf-md-arrow_down
                label: Strings.t("notif.timeoutLow")
                valueMs: NotifConfig.timeoutLow
                focused: root.focusIndex === root.fixedBefore.indexOf(toLow)
                onApply: (ms) => root.run(["w-notify", "timeout", "low", "" + ms])
                onExitField: root.forceActiveFocus()
            }
            TimeoutRow {
                id: toNormal
                glyph: String.fromCodePoint(0xf009e)   // nf-md-bell
                label: Strings.t("notif.timeoutNormal")
                valueMs: NotifConfig.timeoutNormal
                focused: root.focusIndex === root.fixedBefore.indexOf(toNormal)
                onApply: (ms) => root.run(["w-notify", "timeout", "normal", "" + ms])
                onExitField: root.forceActiveFocus()
            }
            TimeoutRow {
                id: toCrit
                glyph: String.fromCodePoint(0xf0026)   // nf-md-alert
                label: Strings.t("notif.timeoutCritical")
                valueMs: NotifConfig.timeoutCritical
                focused: root.focusIndex === root.fixedBefore.indexOf(toCrit)
                onApply: (ms) => root.run(["w-notify", "timeout", "critical", "" + ms])
                onExitField: root.forceActiveFocus()
            }
            TimeoutRow {
                id: toMax
                glyph: String.fromCodePoint(0xf0d8f)   // nf-md-layers
                label: Strings.t("notif.maxVisible")
                valueMs: NotifConfig.maxVisible * 1000     // the row's field works in seconds
                focused: root.focusIndex === root.fixedBefore.indexOf(toMax)
                onApply: (ms) => root.run(["w-notify", "max", "" + Math.max(1, Math.round(ms / 1000))])
                onExitField: root.forceActiveFocus()
            }
            SelectRow {
                id: osdRow
                width: parent.width
                icon: "audio-volume-high"; glyph: String.fromCodePoint(0xf057e)   // nf-md-volume_high
                label: Strings.t("notif.osd")
                currentId: NotifConfig.enableOsd ? "on" : "off"
                value: root.onOffLabel(NotifConfig.enableOsd)
                options: root.onOffOptions()
                focused: root.focusIndex === root.fixedBefore.indexOf(osdRow)
                onActivated: menuLayer.openMenu(osdRow, options, osdRow.currentId,
                                                (id) => root.run(["w-notify", "osd", id]))
            }
            WButton {
                id: testBtn
                label: Strings.t("notif.test")
                focused: root.focusIndex === root.fixedBefore.indexOf(testBtn)
                onClicked: root.run(["w-notify", "send", Strings.t("notif.testTitle"), Strings.t("notif.testBody")])
            }

            // ── Per-app mute ────────────────────────────────────────────────────
            HubSection {
                width: parent.width
                text: Strings.t("notif.appsSec")
                visible: root.apps.length > 0
            }
            Repeater {
                id: muteRepeater
                model: root.apps
                HubRow {
                    id: muteRow
                    required property var modelData
                    required property int index
                    width: col.width
                    readonly property bool muted: NotifConfig.isMuted(modelData.name)
                    icon: ""; glyph: String.fromCodePoint(muted ? 0xf009b : 0xf009e)
                    label: modelData.name
                    value: modelData.count > 0 ? ("" + modelData.count) : ""
                    actionText: Strings.t(muted ? "notif.unmute" : "notif.mute")
                    focused: root.focusIndex === root.fixedBefore.length + muteRow.index
                    onActivated: root.run(["w-notify", muted ? "unmute" : "mute", modelData.name])
                }
            }

            // ── History ─────────────────────────────────────────────────────────
            HubSection { width: parent.width; text: Strings.t("notif.historySec") }
            Text {
                width: parent.width
                visible: root.history.length === 0
                text: Strings.t("notif.historyEmpty")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 12
            }
            WButton {
                id: clearBtn
                visible: root.hasClear
                label: Strings.t("notif.clear")
                tone: "danger"
                focused: root.hasClear && root.focusIndex === root.fixedBefore.length + root.apps.length
                onClicked: root.run(["w-notify", "history", "clear"])
            }
            Repeater {
                model: root.history.slice(0, root.historyShown)
                HistoryRow {
                    required property var modelData
                    width: col.width
                    entry: modelData
                }
            }
        }
    }

    HubDropdown { id: menuLayer; anchors.fill: parent; flipUp: true; returnFocusTo: root }
}
