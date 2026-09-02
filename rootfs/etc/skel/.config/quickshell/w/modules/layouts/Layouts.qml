// W Linux — the layouts panel.
// A name field, two Save buttons and a list of what has been saved, over the same
// tinted, compositor-blurred backdrop as the Launcher and the Clipboard viewer.
// Toggled by a Hyprland global shortcut (SUPER+O).
//
// EVERY VERB IS `w-session`, and this file holds no policy of its own. What a layout
// contains, which windows a scope covers, how windows are closed before one is
// applied and how many would close — all of that is answered by the CLI, because the
// Hub, the AI and a terminal have to get the same answer as this panel. See
// w-session.md.
//
//   list    `w-session layout list --porcelain`  → slug \t scope \t windows \t at \t name
//   save    `w-session layout save <name> [--workspace]`
//   apply   `w-session layout apply <slug>`      (detaches itself — see below)
//   delete  `w-session layout delete <slug>`
//
// Two rows of the list are not layouts:
//   • "Last session" — the automatic snapshot (`w-session status --porcelain`). It is
//     pinned first because it is what MODE=save exists for: recording without
//     reopening at login, and reopening from here when the user asks. Without this
//     row that mode has no entry point outside a terminal.
//
// APPLYING CLOSES THIS PANEL FIRST, and that is not tidiness. A layer surface with
// exclusive keyboard focus sits over the save dialogs the close is about to raise —
// which is precisely the hyprshutdown failure W refuses to ship. `w-session layout
// apply` also detaches itself, so nothing here has to stay alive to see it through.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import qs.core

Scope {
    id: root

    readonly property bool active: Overlays.current === "layouts"
    // Shown = open AND not suspended (stepped aside for a higher-priority modal),
    // the same contract as the Hub and the Clipboard viewer.
    readonly property bool shown: root.active && !Overlays.suspended

    // Rows: [{ slug, scope, windows, savedAt, name }]. `scope` is "layout" or
    // "workspace" for saved ones and "session" for the pinned automatic snapshot,
    // whose slug is empty — that is what tells apply() to call `restore` instead.
    property var entries: []
    property int sessionWindows: 0

    // Last pointer position in SCENE coords: hover-selects only on real mouse
    // movement, so rows scrolling under a still cursor do not hijack the selection.
    // Same guard as the Launcher and the Clipboard viewer.
    property var lastPointer: null

    // ── The keyboard cursor ─────────────────────────────────────────────────────
    // The name field holds real Qt focus the whole time the panel is open, because
    // the panel's first job is typing a name. So "where the keyboard cursor is" is a
    // property here rather than actual focus, and the two zones it moves between —
    // the Save buttons and the list — draw themselves accordingly. That is the same
    // split the Hub uses (a roving index plus a `focused` outline), applied to a
    // modal palette instead of a settings screen.
    //
    // WHICH KEYS, AND WHY TWO SETS. Bare arrows always work: they cannot be typed
    // into a field, so nothing is taken away from anyone. The profile-aware set is
    // Ctrl + the `menu_*` chord — because `i3-vim` puts navigation on HJKL, and a
    // bare H in a field is the letter H, not a movement. Ctrl+letter never types.
    // This is exactly the pairing the Hub's own search fields use (see
    // TimezonePicker/LocalePicker/KeyboardPicker), so one habit covers all of them.
    property string focusZone: "list"    // "list" | "buttons"
    property int buttonIndex: 0          // 0 = save layout, 1 = save workspace

    function moveDown() {
        if (root.focusZone === "buttons") { root.focusZone = "list"; return; }
        list.incrementCurrentIndex();
    }

    function moveUp() {
        if (root.focusZone === "buttons") return;      // the buttons are the top row
        if (list.currentIndex <= 0) { root.focusZone = "buttons"; return; }
        list.decrementCurrentIndex();
    }

    // Left/Right are only intercepted while the cursor is on the buttons. In the list
    // zone they stay what they are in any text field — caret movement — because that
    // is where the user is actually typing.
    function moveSide(delta) {
        if (root.focusZone !== "buttons") return false;
        root.buttonIndex = root.buttonIndex === 0 ? 1 : 0;
        return true;
    }

    function activate() {
        if (root.focusZone === "buttons") root.save(root.buttonIndex === 0 ? "layout" : "workspace");
        else root.apply(list.model[list.currentIndex]);
    }

    readonly property int cardW: Overlays.cardWidth
    readonly property int rowH: 44
    readonly property int maxCardH: 520
    // Top-pinned as if the card were this tall, so the name field lands on the exact
    // screen Y as the Launcher's search box — they read as one centre.
    readonly property int pinRef: 480
    // margins(12+12) + name field(48) + buttons(30) + footer(18) + spacing×3(36) = 156
    readonly property int chrome: 156

    // bind = SUPER, O, global, quickshell:layouts
    GlobalShortcut {
        appid: "quickshell"
        name: "layouts"
        onPressed: {
            if (LayoutsConfig.enabled) Overlays.toggle("layouts");
            else Overlays.close("layouts");
        }
    }

    // ── Reading what is saved ───────────────────────────────────────────────────
    Process {
        id: listProc
        command: ["w-session", "layout", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of (this.text || "").split("\n")) {
                    if (line.length === 0) continue;
                    const f = line.split("\t");
                    if (f.length < 5) continue;
                    out.push({ slug: f[0], scope: f[1], windows: parseInt(f[2]) || 0,
                               savedAt: parseInt(f[3]) || 0, name: f.slice(4).join("\t") });
                }
                root.entries = out;
                list.currentIndex = 0;
            }
        }
    }

    // The pinned "Last session" row's window count. `w-session status --porcelain`
    // is asked rather than the snapshot file being read here: the count it reports
    // is what the restore would actually reopen, filters and all.
    Process {
        id: statusProc
        command: ["w-session", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /^SNAPSHOT_WINDOWS\t(\d+)$/m.exec(this.text || "");
                root.sessionWindows = m ? parseInt(m[1]) : 0;
            }
        }
    }

    // Saves and deletes; the list is re-read on exit so the view stays honest.
    //
    // THE REFUSAL IS SHOWN. `w-session layout save` can legitimately say no — most
    // often "no windows here that can be reopened", which is what "Save workspace"
    // on an empty workspace means — and a button that answers a refusal by doing
    // nothing at all is indistinguishable from a broken button. So stderr is read
    // and put where the user is already looking, and the typed name is kept rather
    // than cleared, because they will want to try it again somewhere else.
    property string notice: ""
    Process {
        id: mutateProc
        property string pendingName: ""
        stderr: StdioCollector { id: mutateErr }
        onExited: (code) => {
            root.notice = code === 0 ? ""
                : (mutateErr.text || "").trim().replace(/^w-session:\s*/, "").split("\n")[0];
            if (code === 0 && mutateProc.pendingName !== "") name.text = "";
            mutateProc.pendingName = "";
            root.reload();
        }
    }

    function reload() {
        listProc.running = true;
        statusProc.running = true;
    }

    // Rows = the pinned session (only when it holds something) + saved layouts,
    // filtered by whatever has been typed into the name field. Referencing
    // name.text and root.entries is what makes `model: root.view()` reactive.
    function view() {
        const rows = [];
        if (root.sessionWindows > 0)
            rows.push({ slug: "", scope: "session", windows: root.sessionWindows,
                        savedAt: 0, name: Strings.t("layouts.lastSession") });
        for (const e of root.entries) rows.push(e);
        const q = name.text.trim().toLowerCase();
        if (q === "") return rows;
        return rows.filter(r => r.name.toLowerCase().indexOf(q) >= 0);
    }

    function badge(scope) {
        if (scope === "workspace") return Strings.t("layouts.badgeWorkspace");
        if (scope === "session")   return Strings.t("layouts.badgeSession");
        return Strings.t("layouts.badgeLayout");
    }

    function save(scope) {
        const n = name.text.trim();
        if (n === "") return;
        root.notice = "";
        mutateProc.pendingName = n;      // cleared from the field only if the save took
        mutateProc.command = scope === "workspace"
            ? ["w-session", "layout", "save", n, "--workspace"]
            : ["w-session", "layout", "save", n];
        mutateProc.running = true;
    }

    function remove(entry) {
        if (!entry || entry.scope === "session") return;   // the snapshot is not ours to delete
        root.notice = "";
        mutateProc.command = ["w-session", "layout", "delete", entry.slug];
        mutateProc.running = true;
    }

    // ── Applying ────────────────────────────────────────────────────────────────
    // Ask first, but only when there is something to lose. The count comes from the
    // CLI — `--dry-run` on the very command that is about to run — so the question
    // is asked about exactly what the answer will act on, and a scope that closes
    // nothing (an empty workspace) is applied straight away instead of demanding a
    // confirmation for a no-op.
    property var pending: null

    Process {
        id: countProc
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt((this.text || "").trim()) || 0;
                if (n > 0) root.confirm(n);
                else root.run(root.pending);
            }
        }
    }

    function apply(entry) {
        if (!entry) return;
        root.pending = entry;
        countProc.command = entry.slug === ""
            ? ["w-session", "close", "--dry-run"]
            : ["w-session", "layout", "apply", entry.slug, "--dry-run"];
        countProc.running = true;
    }

    function confirm(count) {
        const entry = root.pending;
        // openInfobox replaces this panel in Overlays — one modal at a time — so the
        // panel is already gone by the time anything closes, which is the point.
        Overlays.openInfobox({
            glyph: entry.scope === "workspace" ? Glyphs.layoutWorkspace : Glyphs.layoutAll,
            title: Strings.t("layouts.confirmTitle").replace("%1", entry.name),
            bodyMarkdown: Strings.t("layouts.confirmBody"),
            // Infobox lays its action row out RightToLeft, so array index 0 renders
            // RIGHTMOST and is where the keyboard cursor starts. The confirming
            // action goes there: it is the one the user just asked for by picking a
            // row, and the guard that actually protects unsaved work is downstream
            // (every window is asked to close, and cancelling any of those dialogs
            // abandons the whole apply). Esc cancels from here.
            actions: [
                { label: Strings.t("layouts.confirmOpen"), primary: true,
                  exec: function() { root.run(entry); } },
                { label: Strings.t("layouts.confirmCancel"), exec: function() { root.pending = null; } },
            ],
        });
    }

    function run(entry) {
        root.pending = null;
        if (!entry) return;
        Overlays.close("layouts");
        Overlays.close("infobox");
        // Detached on purpose: `w-session layout apply` re-execs itself into its own
        // session anyway (it closes the terminal it is typed in), and the shell must
        // not hold a handle on something that outlives this surface.
        Quickshell.execDetached(entry.slug === ""
            ? ["w-session", "restore"]
            : ["w-session", "layout", "apply", entry.slug]);
    }

    PanelWindow {
        id: win

        visible: root.shown || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:layouts"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                root.reload();
                // The active hotkeys profile can change while the shell runs, so the
                // menu chords are re-probed per open — the same thing Hub.qml does.
                HubNavKeys.refresh();
                list.currentIndex = 0;
                root.focusZone = "list";
                root.buttonIndex = 0;
                root.notice = "";
                root.lastPointer = null;
                name.input.forceActiveFocus();
            } else if (!root.active) {
                name.text = "";     // reset on a real close, not on a suspend
            }
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Click outside the card to dismiss. Tint + blur come from the shared
            // Backdrop surface, so this layer is input-only.
            MouseArea { anchors.fill: parent; onClicked: Overlays.close("layouts") }

            Rectangle {
                id: card
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - root.pinRef) / 2)
                width: root.cardW
                height: Math.min(root.maxCardH, root.chrome + Math.max(1, list.count) * root.rowH)
                radius: Geometry.radius
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: LayoutsConfig.border
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                transformOrigin: Item.Top
                scale: root.shown ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // ── Name field ────────────────────────────────────────────
                    // Doubles as the list filter: with a name typed it narrows the
                    // rows, which is also how you find the row you are about to
                    // overwrite by saving under its name again.
                    WQueryField {
                        id: name
                        width: parent.width
                        placeholder: Strings.t("layouts.namePlaceholder")

                        onTextChanged: { list.currentIndex = 0; root.notice = ""; }

                        // Bare ←/→ are this panel's own addition, not part of the shared
                        // palette contract: the resolver never claims them (in a one-line
                        // field they belong to the text cursor), and here moveSide()
                        // declines whenever the zone can't move — handing the keystroke
                        // back to the cursor untouched.
                        input.Keys.onLeftPressed: (e) => { e.accepted = root.moveSide(-1); }
                        input.Keys.onRightPressed: (e) => { e.accepted = root.moveSide(1); }

                        // Everything else goes through the shared mode-B resolver: bare
                        // ↑↓/Enter/Esc are already taken above, so what this adds is the
                        // Shift+Del/Shift+Backspace removal aliases and Ctrl+<profile
                        // chord> for the whole set — identical in every W palette, see
                        // core/HubNavKeys.qml for why Ctrl is what makes it safe.
                        input.Keys.onPressed: (e) => {
                            switch (HubNavKeys.fieldAction(e)) {
                            case "down":    root.moveDown(); e.accepted = true; return;
                            case "up":      root.moveUp(); e.accepted = true; return;
                            case "left":    e.accepted = root.moveSide(-1); return;
                            case "right":   e.accepted = root.moveSide(1); return;
                            case "confirm": root.activate(); e.accepted = true; return;
                            case "back":    Overlays.close("layouts"); e.accepted = true; return;
                            case "delete":
                                if (root.focusZone === "list") root.remove(list.model[list.currentIndex]);
                                e.accepted = true;
                                return;
                            }
                        }
                    }

                    // ── The two Save buttons ──────────────────────────────────
                    Row {
                        id: saveRow
                        width: parent.width
                        height: 30
                        spacing: 8

                        WButton {
                            label: Strings.t("layouts.saveLayout")
                            enabled: name.text.trim().length > 0
                            focused: root.focusZone === "buttons" && root.buttonIndex === 0
                            onClicked: root.save("layout")
                        }
                        WButton {
                            label: Strings.t("layouts.saveWorkspace")
                            enabled: name.text.trim().length > 0
                            focused: root.focusZone === "buttons" && root.buttonIndex === 1
                            onClicked: root.save("workspace")
                        }
                    }

                    // ── Saved layouts ─────────────────────────────────────────
                    ListView {
                        id: list
                        // Extend into the card's right padding so the shared
                        // scrollbar sits near the window edge; delegates inset the
                        // same 8 back, so rows do not move.
                        width: parent.width + 8
                        height: parent.height - name.height - saveRow.height
                                - footer.height - parent.spacing * 3
                        clip: true
                        model: root.view()
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false

                        ScrollBar.vertical: WScrollBar {}

                        highlightMoveDuration: Motion.fast
                        highlightResizeDuration: 0
                        highlightFollowsCurrentItem: true
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: height
                        // One selection, two meanings: accent while the keyboard
                        // cursor is in the list, a muted wash while it is up on the
                        // buttons. Without that the row would keep shouting "you are
                        // here" from a zone the keys no longer reach.
                        highlight: Rectangle {
                            radius: Geometry.radiusSm
                            color: root.focusZone === "list" ? Colors.accent : Colors.hover
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: Strings.t("layouts.empty")
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 15
                        }

                        delegate: Item {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: ListView.view.width - 8
                            height: root.rowH

                            readonly property bool current: ListView.isCurrentItem
                            // Selected AND under the keyboard cursor: only then does
                            // the row carry the accent foreground, which has to track
                            // the highlight fill above or it loses its contrast.
                            readonly property bool onCursor: rowItem.current && root.focusZone === "list"

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.modelData.scope === "workspace"
                                        ? Glyphs.layoutWorkspace
                                        : (rowItem.modelData.scope === "session"
                                           ? Glyphs.sessionRestore : Glyphs.layoutAll)
                                    font.family: Fonts.mono
                                    font.pixelSize: 16
                                    color: rowItem.onCursor ? Colors.accentFg : Colors.muted
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.modelData.name
                                    color: rowItem.onCursor ? Colors.accentFg : Colors.text
                                    font.family: Fonts.family
                                    font.pixelSize: 15
                                    elide: Text.ElideRight
                                    width: Math.max(0, rowItem.width - 300)
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                            }

                            // Badge + window count + remove, right-aligned: what the
                            // row IS, how big it is, and the way to drop it.
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                WPill {
                                    anchors.verticalCenter: parent.verticalCenter
                                    flat: true
                                    label: root.badge(rowItem.modelData.scope)
                                    // A badge is a label, not a control: clicking it
                                    // must do what clicking the row does.
                                    onClicked: root.apply(rowItem.modelData)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.modelData.windows + " " + Strings.t("layouts.windows")
                                    color: rowItem.onCursor ? Colors.accentFg : Colors.muted
                                    font.family: Fonts.mono
                                    font.pixelSize: 11
                                    font.features: ({ "tnum": 1 })
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                Text {
                                    id: delBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    // The pinned session row has nothing to delete —
                                    // but it stays in the layout, invisible, because a
                                    // Row skips `visible:false` children entirely and
                                    // that pulled its badge and count flush against the
                                    // card edge while every other row was inset by this
                                    // glyph. Held open by opacity, not visibility, so
                                    // the right-hand column lines up down the list.
                                    readonly property bool removable: rowItem.modelData.scope !== "session"
                                    text: String.fromCodePoint(0xf0156)   // md-close (verified in the font)
                                    font.family: Fonts.mono
                                    font.pixelSize: 16
                                    color: delArea.containsMouse ? Colors.dangerBorder
                                        : (rowItem.onCursor ? Colors.accentFg : Colors.muted)
                                    opacity: (delBtn.removable && (rowItem.current || rowHover.containsMouse)) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                    MouseArea {
                                        id: delArea
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: delBtn.removable
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (delBtn.removable) root.remove(rowItem.modelData)
                                    }
                                }
                            }

                            MouseArea {
                                id: rowHover
                                anchors.fill: parent
                                anchors.rightMargin: 30   // leave the ✕ its own area
                                hoverEnabled: true
                                onPositionChanged: (mouse) => {
                                    const p = rowItem.mapToItem(null, mouse.x, mouse.y);
                                    if (root.lastPointer === null) { root.lastPointer = p; return; }
                                    if (Math.abs(p.x - root.lastPointer.x) + Math.abs(p.y - root.lastPointer.y) < 2)
                                        return;
                                    root.lastPointer = p;
                                    list.currentIndex = rowItem.index;
                                    // Touching a row IS moving the cursor into the
                                    // list — otherwise the pointer would select a row
                                    // that the keys, still up on the buttons, cannot act on.
                                    root.focusZone = "list";
                                }
                                onClicked: root.apply(rowItem.modelData)
                            }
                        }
                    }

                    // ── Footer hints ──────────────────────────────────────────
                    Item {
                        id: footer
                        width: parent.width
                        height: 18

                        Text {
                            anchors.left: parent.left
                            anchors.right: countText.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.notice !== "" ? root.notice : Strings.t("layouts.hints")
                            color: root.notice !== "" ? Colors.dangerBorder : Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Text {
                            id: countText
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: list.count > 0
                            text: list.count + ""
                            color: Colors.muted
                            font.family: Fonts.mono
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }

            // Topmost of all: no hover highlight while the cursor is hidden, so the
            // keyboard selection is the only mark on screen (see core/HoverGate).
            HoverGate { anchors.fill: parent }
        }
    }
}
