// W Linux — Hub System panel (Ф4).
// The System drill-in screen: a read-and-act front-end over the W maintenance tools —
// About (os-release version + update channel), Updates (pending package count + a pending
// reboot flag from w-update, plus, on an edge system, the w-sync behind-count) and Logs
// (retention policy + journal usage). Packs and AI were promoted out to their own
// root-level Hub tiles/panels (panels/PacksPanel.qml, panels/AIProfilesPanel.qml).
//
// Execution model (agreed Ф4): the long-running operations — w-update and w-sync update —
// do NOT use the Hub's runPrivileged/suspend bracket (that hides the Hub and blocks with
// no progress for the whole download). They open in a terminal with live output and close
// the Hub, the same way the root grid's Updates tile already does. Sync additionally runs
// its terminal command through pkexec + the sync-update capability, so it works for every
// admin instead of only the checkout's owner (see the row itself).
//
// It is a pure front-end: state is read cheaply (FileView on os-release / update.conf /
// the updates + sync status JSON) and nothing here carries system logic of its own.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/SystemPanel.qml"}); as a subdir
// file it is not a module type, so the shared hub components (HubRow, HubSection) come in
// through `import qs.modules.hub`. Scrolls with the shared WScrollBar if it overflows.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // Content-driven height so the Hub card morphs to it (capped + scrolled by the Hub).
    // +8 mirrors the Flickable's contentHeight padding below (focus-wash bleed slack) —
    // without it `flick` is permanently 8px shorter than its own contentHeight and
    // shows a phantom scroll even when content fits comfortably under maxCardH.
    // Max with the dropdown's lower edge so an open session-mode menu grows the card
    // instead of being clipped (0 while closed or flipped up) — DisplaysPanel contract.
    implicitHeight: Math.max(col.implicitHeight + 8, sessMenu.menuBottom)

    // Open a long-running maintenance command in a terminal and close the Hub, so its
    // progress is visible instead of blocking a hidden popup.
    function runTerm(cmd) { Quickshell.execDetached(cmd); Overlays.close("hub"); }

    // Drill into a deeper Hub route (the system-language / locale picker).
    signal navigate(var route)

    // Privileged actions handed up to the Hub (suspend for the polkit prompt, restore +
    // refresh on exit) — used by the Logs retention control. Wired generically in Hub.qml.
    signal runPrivileged(var cmd, var onDone)

    // ── Keyboard roving-focus (flat list, top→bottom, inside a Flickable) ───────────
    // Same compact-visible-list contract as PowerPanel: syncRow is edge-only, so the
    // Column already skips it when hidden and the roving order has to match.
    readonly property var focusables: [verRow, channelRow, localeRow, updRow, syncRow, vacuumRow, retRow,
                                      sessModeRow, sessLayoutsRow, sessAutoRow]
    readonly property var visFocusables: root.focusables.filter((f) => f.visible)
    property int focusIndex: 0
    onVisFocusablesChanged: root.focusIndex = Math.max(0, Math.min(root.focusIndex, root.visFocusables.length - 1))

    function scrollIntoView(item) {
        if (!item) return;
        const vf = root.visFocusables;
        // Reaching either end of the roving list should reach the true scroll edge
        // (a HubSection header sits above the first row) — same reasoning as
        // PowerPanel.scrollIntoView.
        if (item === vf[0]) { flick.contentY = 0; return; }
        if (item === vf[vf.length - 1]) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }
    function focusRow(i) {
        root.focusIndex = Math.max(0, Math.min(i, root.visFocusables.length - 1));
        root.scrollIntoView(root.visFocusables[root.focusIndex]);
    }

    focus: true
    Keys.onPressed: (e) => {
        // A text field may hold real Qt focus and just not consume this key — let it
        // bubble here unhandled rather than steal the roving cursor mid-edit (same
        // guard as NetworkPanel's hostField). Both editable fields on this panel
        // qualify; missing one means typing in it silently moves the roving cursor.
        if (retField.input.activeFocus || sessAutoField.input.activeFocus) return;
        const vf = root.visFocusables;
        if (vf.length === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:   root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = vf[root.focusIndex];
            if (item === retRow) retField.input.forceActiveFocus();          // enter edit mode
            else if (item === sessAutoRow) sessAutoField.input.forceActiveFocus();
            else if (item.activated !== undefined) item.activated();
            e.accepted = true;
            return;
        }
        }
    }

    // ── System language (/etc/locale.conf) ───────────────────────────────────────
    property string lang: ""
    FileView {
        path: "/etc/locale.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const m = (text() || "").match(/^LANG=([^\s#]+)/m); root.lang = m ? m[1].replace(/"/g, "") : ""; }
    }

    // ── About: os-release version + update channel ───────────────────────────────────
    // IMAGE_VERSION is the release (a git tag); W_BUILD_DATE is the day this image was
    // assembled, and is empty unless the system came from a stamped ISO. BUILD_ID is
    // deliberately not shown: it is the constant "rolling" and carries no information
    // a user of a rolling distro does not already have.
    property string osVersion: ""
    property string osBuildDate: ""
    readonly property string versionText:
        osVersion ? (osBuildDate ? osVersion + " (" + osBuildDate + ")" : osVersion) : "—"
    FileView {
        path: "/etc/os-release"
        onLoaded: {
            const t = text() || "";
            const v = t.match(/^IMAGE_VERSION=([^\s#]+)/m);  root.osVersion   = v ? v[1].replace(/"/g, "") : "";
            const d = t.match(/^W_BUILD_DATE=([^\s#]+)/m);   root.osBuildDate = d ? d[1].replace(/"/g, "") : "";
        }
    }

    property string channel: "stable"
    readonly property bool isEdge: channel === "edge"
    FileView {
        path: "/etc/w/update.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = (text() || "").match(/^CHANNEL=([^\s#]+)/m);
            root.channel = m ? m[1] : "stable";
        }
    }

    // ── Updates (w-update) ───────────────────────────────────────────────────────────
    property int updRepo: 0
    property int updAur: 0
    property bool rebootPending: false
    readonly property int updCount: updRepo + updAur
    FileView {
        id: updFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/w/updates.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text() || "{}");
                root.updRepo = d.repo || 0; root.updAur = d.aur || 0;
                root.rebootPending = d.rebootPending === true;
            } catch (e) { root.updRepo = 0; root.updAur = 0; root.rebootPending = false; }
        }
    }

    // ── Sync (w-sync) — edge only ────────────────────────────────────────────────────
    // behind < 0 means w-sync could NOT determine the count (network or git — see its
    // `err` field). It must never render as "up to date": not knowing is a warning,
    // not good news. -1 is also the default, so a missing/unreadable state file says
    // "unknown" rather than lying by omission.
    // The state is MACHINE-WIDE (absolute path, not XDG): the checkout is one shared
    // object, so its status is one answer for every user of this machine. It is
    // written by the checkout's owner (or root) and world-readable.
    property int syncBehind: -1
    property string syncRef: ""
    FileView {
        id: syncFile
        path: "/var/lib/w/state/sync.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text() || "{}");
                root.syncBehind = (typeof d.behind === "number") ? d.behind : -1;
                root.syncRef = d.ref || "";
            } catch (e) { root.syncBehind = -1; root.syncRef = ""; }
        }
    }

    // Both state files above are written ATOMICALLY (mktemp + mv -f, by w-sync and
    // w-update): every write lands a NEW inode on the path, so the watch established
    // on the old one dies with it and the panel would keep showing the first number
    // it ever read until the shell restarts. Atomicity is not negotiable — the sync
    // file is machine-wide and read by every user's Hub, so a half-written JSON is
    // exactly the bug `mv` prevents. So `watchChanges` gets a reload timer beside it,
    // the same pairing the bar's blocks/Updates.qml already documents.
    //
    // It ticks only while the Hub is on screen: a panel is destroyed when its route
    // changes, but a Hub CLOSED on this route keeps it alive (Hub.qml deliberately
    // does not reset the nav stack on hide), and polling a hidden popup is waste.
    // `Overlays.current` is the deterministic signal for that — not Item.visible,
    // whose meaning inside an unmapped PanelWindow we would rather not depend on.
    // triggeredOnStart also makes every re-open re-read immediately.
    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: Overlays.current === "hub"
        onTriggered: { syncFile.reload(); updFile.reload(); }
    }

    // ── Logs (w-logs status) — retention policy + journal usage ───────────────────────
    // Read once (no live watch: a refresh mid-typing would clobber the days field). Re-read
    // explicitly after a privileged change via runPrivileged's onDone.
    property int logDays: 0
    property string logJournalUsage: ""
    Process {
        id: logStat
        running: true
        command: ["w-logs", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text || "";
                const d = t.match(/^Policy\s*:\s*keep\s+(\d+)\s+day/m);      root.logDays = d ? parseInt(d[1]) : 0;
                const u = t.match(/^\s*disk usage\s*:\s*(.+?)\s*$/m);         root.logJournalUsage = u ? u[1] : "";
            }
        }
    }
    function reloadLogs() { logStat.running = false; logStat.running = true; }

    // ── Session memory (w-session status) ─────────────────────────────────────────────
    // Two reads, the same pair every user-scope panel uses: the tool's own porcelain for
    // the values, and `w-conf list --porcelain` for which keys a fleet policy has taken
    // out of local hands. Read once and re-read on our own setter's exit — a live watch
    // would clobber the autosave field mid-typing, exactly as it would the log days.
    property string sessMode: "off"
    property int    sessAutosave: 60
    property int    sessSnapWindows: 0
    property int    sessLayouts: 0
    Process {
        id: sessStat
        running: true
        command: ["w-session", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length >= 2) kv[f[0]] = f[1];
                }
                root.sessMode = kv.MODE || "off";
                root.sessAutosave = parseInt(kv.AUTOSAVE_SEC || "60");
                root.sessSnapWindows = parseInt(kv.SNAPSHOT_WINDOWS || "0");
            }
        }
    }
    // How many named layouts exist. Counted from the CLI's own porcelain rather than
    // by listing a directory, so the Hub agrees with the panel about what a layout is
    // (a file that fails to parse is not one).
    Process {
        id: sessLay
        running: true
        command: ["w-session", "layout", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessLayouts = (this.text || "").split("\n").filter((l) => l.length > 0).length;
            }
        }
    }
    property var sessLocked: ({})
    Process {
        id: sessConf
        running: true
        command: ["w-conf", "list", "session", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const locked = {};
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length >= 5 && f[3] === "locked") locked[f[0]] = true;
                }
                root.sessLocked = locked;
            }
        }
    }
    function reloadSession() {
        sessStat.running = false; sessStat.running = true;
        sessConf.running = false; sessConf.running = true;
        sessLay.running = false; sessLay.running = true;
    }
    // Unprivileged setter: every key here is user-scope, so this is a plain Process and
    // not the Hub's runPrivileged bracket — there is no polkit prompt to suspend for.
    Process { id: sessSet; onExited: root.reloadSession() }
    function runSession(cmd) { sessSet.running = false; sessSet.command = cmd; sessSet.running = true; }

    function sessModeLabel(id) { return id ? Strings.t("sess.mode." + id) : "—"; }
    readonly property var sessModeOptions: [
        { id: "off",     label: Strings.t("sess.mode.off") },
        { id: "save",    label: Strings.t("sess.mode.save") },
        { id: "restore", label: Strings.t("sess.mode.restore") },
    ]

    // ── Layout ───────────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        // Extend into the card's right padding so the scrollbar pill sits near the window
        // edge; the content column insets the same amount, keeping its padding symmetric.
        anchors.rightMargin: -12
        // Mirrors PowerPanel's left-side convention: every row's keyboard-focus wash
        // bleeds -8 past its own left edge, so the Flickable's own clip rect has to
        // grow left by the same amount (col insets by 8 so visible content doesn't
        // shift — only the bleed lane grows).
        anchors.leftMargin: -8
        clip: true
        // 4px slack at each end so the first/last row's focus wash (-4 top/bottom
        // bleed) has room to scroll into view. NOT via Flickable.topMargin/
        // bottomMargin — that triggers Qt Quick's content-centering and offsets the
        // resting scroll position (see quickshell-hub.md's Ф-Keyboard gotcha #3).
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 12

            // About.
            HubSection { width: parent.width; text: Strings.t("hub.about") }
            HubRow {
                id: verRow
                width: parent.width
                icon: "help-about"; glyph: String.fromCodePoint(0xf02fc)   // nf-md-information_outline
                label: Strings.t("hub.version")
                value: root.versionText
                focused: root.focusIndex === root.visFocusables.indexOf(verRow)
            }
            HubRow {
                id: channelRow
                width: parent.width
                icon: "preferences-system"; glyph: String.fromCodePoint(0xf062c)  // nf-md-source_branch
                label: Strings.t("hub.channel")
                value: Strings.t("hub.channel." + (root.isEdge ? "edge" : "stable"))
                focused: root.focusIndex === root.visFocusables.indexOf(channelRow)
            }

            // System language (locale). The switch is privileged (w-locale via the
            // polkit path in the picker) and applies only after the next login.
            HubSection { width: parent.width; text: Strings.t("hub.language") }
            HubRow {
                id: localeRow
                width: parent.width
                icon: "preferences-desktop-locale"; glyph: String.fromCodePoint(0xf05ca) // nf-md-translate
                label: Strings.t("hub.locale")
                sublabel: Strings.t("hub.localeHint")
                value: root.lang || "—"
                actionText: Strings.t("hub.change")
                focused: root.focusIndex === root.visFocusables.indexOf(localeRow)
                onActivated: root.navigate("system.locale")
            }

            // Updates.
            HubSection { width: parent.width; text: Strings.t("hub.updates") }
            HubRow {
                id: updRow
                width: parent.width
                icon: "system-software-update"; glyph: String.fromCodePoint(0xf01da)  // nf-md-download
                label: Strings.t("hub.pending")
                value: root.rebootPending
                       ? Strings.t("hub.rebootNeeded")
                       : (root.updCount > 0 ? root.updCount + " " + Strings.t("hub.pendingUnit")
                                            : Strings.t("hub.upToDate"))
                valueColor: root.rebootPending ? Colors.accentInk : Colors.muted
                actionText: Strings.t("hub.updateNow")
                focused: root.focusIndex === root.visFocusables.indexOf(updRow)
                onActivated: root.runTerm(Term.exec(["w-update"]))
            }
            HubRow {
                id: syncRow
                visible: root.isEdge
                width: parent.width
                icon: "emblem-synchronizing"; glyph: String.fromCodePoint(0xf04e6)   // nf-md-sync
                label: Strings.t("hub.sync")
                focused: root.focusIndex === root.visFocusables.indexOf(syncRow)
                sublabel: root.syncRef
                value: root.syncBehind < 0
                       ? Strings.t("hub.syncUnknown")
                       : (root.syncBehind > 0
                          ? root.syncBehind + " " + Strings.t("hub.behind")
                          : Strings.t("hub.upToDate"))
                valueColor: root.syncBehind < 0 ? Colors.dangerBorder
                            : (root.syncBehind > 0 ? Colors.accentInk : Colors.muted)
                actionText: Strings.t("hub.syncNow")
                // Privileged path, not a plain `w-sync update`: the checkout belongs to
                // ONE user, so running as whoever is sitting at the session only worked
                // for its owner (a second admin — entitled to update the machine, and
                // able to via the AI path — hit "run w-sync as that user, or via sudo").
                // pkexec + the sync-update capability gives every admin the same prompt,
                // and a non-admin one an admin can unlock (com.w.hub.actuate = auth_admin;
                // see update-system.md stage 2). The terminal stays — Ф4's hybrid model is
                // about the operation being long, not about who runs it — and `interactive`
                // keeps w-sync's own commit-list confirmation and reboot question, which
                // the argument-less capability (the AI's non-interactive path) skips.
                onActivated: root.runTerm(Term.exec(
                    ["pkexec", "/usr/lib/w/w-hub-actuate", "sync-update", "interactive"]))
            }

            // Logs — one retention policy governs the journal, /var/log (logrotate) and
            // /var/log/w (tmpfiles). The days field + Change is privileged (logs-retention
            // cap → w-hub-actuate → polkit); Vacuum trims the journal to that window now.
            HubSection { width: parent.width; text: Strings.t("hub.logs") }
            HubRow {
                id: vacuumRow
                width: parent.width
                icon: "text-x-generic"; glyph: String.fromCodePoint(0xf0e9a)   // nf-md-math_log
                label: Strings.t("hub.journalUsage")
                value: root.logJournalUsage || "—"
                actionText: root.logDays > 0 ? Strings.t("hub.vacuumNow") : ""
                focused: root.focusIndex === root.visFocusables.indexOf(vacuumRow)
                onActivated: root.runPrivileged(
                    ["pkexec", "/usr/lib/w/w-hub-actuate", "logs-vacuum", "time", root.logDays + "d"],
                    () => root.reloadLogs())
            }
            // Retention editor — same left icon+label / right-slot geometry as HubRow
            // (which can't host a TextField), so it aligns with every other System row.
            // Right side is WSettingsField (see [[quickshell-widgets]]) — the same box+
            // Change idiom as Network's Hostname / Energy's idle timeout, now including
            // its own 1-3650 day range validator.
            Item {
                id: retRow
                width: parent.width
                implicitHeight: Math.max(38, retLeft.implicitHeight + 8)

                Rectangle {
                    anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                    radius: Geometry.radiusSm
                    visible: root.focusIndex === root.visFocusables.indexOf(retRow) && !retField.input.activeFocus
                    color: Colors.hover
                }

                // Left: brand-shaded icon + label / sublabel (mirrors HubRow).
                Row {
                    id: retLeft
                    anchors {
                        left: parent.left
                        right: retField.left; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 10
                    ChromeIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 22
                        glyph: String.fromCodePoint(0xf0292)   // nf-md-history
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: Strings.t("hub.retention")
                            color: Colors.text
                            font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                        }
                        Text {
                            width: Math.max(0, retLeft.width - 32)
                            text: Strings.t("hub.retentionHint")
                            color: Colors.muted
                            font.family: Fonts.family; font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                // Right: field + "days" + Change, anchored to the row's right edge so the
                // button aligns with the value/action slot of the other rows.
                WSettingsField {
                    id: retField
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    fixedWidth: 64
                    numeric: true
                    suffix: Strings.t("hub.days")
                    value: root.logDays > 0 ? "" + root.logDays : ""
                    validator: (text) => /^[0-9]+$/.test(text) && parseInt(text) >= 1 && parseInt(text) <= 3650
                    borderWidth: HubConfig.border
                    onApplied: (text) => root.runPrivileged(
                        ["pkexec", "/usr/lib/w/w-hub-actuate", "logs-retention", text],
                        () => root.reloadLogs())
                    // Tab/Esc hand focus back to the row roving-nav instead of typing a
                    // tab char or bubbling Esc up to Hub.back() (see NetworkPanel.hostField).
                    input.Keys.onTabPressed: root.forceActiveFocus()
                    input.Keys.onEscapePressed: root.forceActiveFocus()
                }
            }

            // Session memory — which windows were open, where, and whether they
            // come back at the next login. Every key of this subsystem is
            // user-scope (session.schema), so unlike Logs above there is no
            // pkexec anywhere here: the rows call `w-session` directly, the way
            // NightLightSection calls `w-nightlight`. A control is disabled only
            // when a fleet policy has locked the key.
            HubSection { width: parent.width; text: Strings.t("hub.session") }
            Text {
                width: parent.width
                text: Strings.t("sess.hint")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            SelectRow {
                id: sessModeRow
                width: parent.width
                icon: "preferences-desktop"; glyph: Glyphs.sessionRestore
                label: Strings.t("sess.modeLabel")
                currentId: root.sessMode
                value: root.sessModeLabel(root.sessMode)
                options: root.sessModeOptions
                locked: root.sessLocked["MODE"] === true
                lockedHint: Strings.t("hub.lockedByPolicy")
                focused: root.focusIndex === root.visFocusables.indexOf(sessModeRow)
                onActivated: sessMenu.openMenu(sessModeRow, options, root.sessMode,
                                               (id) => root.runSession(["w-session", "mode", id]))
            }
            // What is stored right now — a fact, not a control. Acting on the
            // snapshot by hand (save it, open it, throw it away, keep several
            // under names) is the layouts panel's job, not a settings screen's:
            // the Hub answers "is this on and how often". A save button here
            // would also be redundant with the automatic one, which already runs
            // on every graceful logout.
            HubRow {
                id: sessSavedRow
                width: parent.width
                visible: root.sessMode !== "off"
                icon: "document-save"; glyph: String.fromCodePoint(0xf0193)   // nf-md-content_save
                label: Strings.t("sess.saved")
                value: root.sessSnapWindows > 0
                       ? root.sessSnapWindows + " " + Strings.t("sess.windows")
                       : Strings.t("sess.savedNone")
            }
            // The named layouts, and the way to reach them. Shown whatever the mode
            // is — saving a layout by hand is not gated on the automatic memory
            // being switched on, so a row that vanished with MODE=off would be
            // telling the user something that is not true.
            HubRow {
                id: sessLayoutsRow
                width: parent.width
                icon: "preferences-system-windows"; glyph: Glyphs.layoutAll
                label: Strings.t("sess.layouts")
                value: root.sessLayouts > 0 ? root.sessLayouts + "" : Strings.t("sess.layoutsNone")
                actionText: Strings.t("sess.openLayouts")
                focused: root.visFocusables[root.focusIndex] === sessLayoutsRow
                // Toggling the popup replaces the Hub in Overlays (one modal at a
                // time), so the Hub is closed by the act of opening the panel.
                onActivated: Hyprland.dispatch('hl.dsp.global("quickshell:layouts")')
            }
            // Autosave floor. Same left-icon / right-field geometry as the log
            // retention editor above, so the two line up.
            Item {
                id: sessAutoRow
                width: parent.width
                visible: root.sessMode !== "off"
                implicitHeight: Math.max(38, sessAutoLeft.implicitHeight + 8)

                Rectangle {
                    anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                    radius: Geometry.radiusSm
                    visible: root.focusIndex === root.visFocusables.indexOf(sessAutoRow) && !sessAutoField.input.activeFocus
                    color: Colors.hover
                }

                Row {
                    id: sessAutoLeft
                    anchors {
                        left: parent.left
                        right: sessAutoField.left; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 10
                    ChromeIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 22
                        glyph: String.fromCodePoint(0xf0954)   // nf-md-timer_outline
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: Strings.t("sess.autosave")
                            color: Colors.text
                            font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                        }
                        Text {
                            width: Math.max(0, sessAutoLeft.width - 32)
                            text: Strings.t("sess.autosaveHint")
                            color: Colors.muted
                            font.family: Fonts.family; font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                WSettingsField {
                    id: sessAutoField
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    fixedWidth: 64
                    numeric: true
                    suffix: Strings.t("sess.seconds")
                    // The validator refuses while the key is policy-locked, so a
                    // locked field cannot even accept input — the same treatment
                    // PowerPanel's idle field gives a locked value.
                    enabled: root.sessLocked["AUTOSAVE_SEC"] !== true
                    value: "" + root.sessAutosave
                    validator: (text) => root.sessLocked["AUTOSAVE_SEC"] !== true
                               && /^[0-9]+$/.test(text)
                               && parseInt(text) >= 0 && parseInt(text) <= 86400
                    borderWidth: HubConfig.border
                    onApplied: (text) => root.runSession(["w-session", "autosave", text])
                    input.Keys.onTabPressed: root.forceActiveFocus()
                    input.Keys.onEscapePressed: root.forceActiveFocus()
                }
            }
        }
    }

    // The panel's single dropdown overlay (only the session mode row needs one).
    // Declared last so it paints above the Flickable; `flipUp` because the row
    // sits at the very bottom of a long panel, where growing downward would push
    // the menu past the card's ceiling.
    HubDropdown { id: sessMenu; anchors.fill: parent; flipUp: true; returnFocusTo: root }
}
