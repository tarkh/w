// W Linux — Hub System panel (Ф4).
// The System drill-in screen, in three tabs:
//   • General  — a read-and-act front-end over the W maintenance tools: About (os-release
//     version + update channel), the system language, Updates (pending package count + a
//     pending reboot flag from w-update, plus, on an edge system, the w-sync behind-count),
//     Logs (retention policy + journal usage) and Session memory.
//   • Date & Time — DateTimeSection.qml, a sibling file (timezone + NTP, over w-time).
//   • Security    — SecuritySection.qml, a sibling file (Secure Boot, over w-secureboot).
// Both were root-level Hub tiles of their own until the menu reorganisation; each is one
// short topic that reference settings apps file under System, and neither earns a tile in
// a 16-slot root grid. The Security tab exists only where its backend does (see
// limineAvailable below). Packs and AI went the other way — promoted OUT to their own
// root-level tiles/panels (panels/PacksPanel.qml, panels/AIProfilesPanel.qml).
//
// This panel is the SOLE owner of the roving-focus index across both Loader boundaries
// (the DisplaysPanel/NightLightSection contract): the sections render whichever field
// they are told through `focusedField` and expose fields/rowItem()/activateField() for
// this file to drive. Their signals are re-emitted here too — the Hub wires a panel's
// optional signals with `Connections { target: panelLoader.item }`, which sees only the
// TOP-level panel, so a signal from inside a nested Loader would never reach it.
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
    // Max with the dropdown's lower edge so an open menu grows the card instead of being
    // clipped (0 while closed or flipped up) — DisplaysPanel contract. The fixed tab row
    // sits above the Flickable and is not part of its scrolled content, so it is added
    // here the same way DisplaysPanel/InputPanel add theirs.
    implicitHeight: Math.max(topCol.implicitHeight + 12 + col.implicitHeight + 8,
                             menuLayer.menuBottom)

    // Open a long-running maintenance command in a terminal and close the Hub, so its
    // progress is visible instead of blocking a hidden popup.
    function runTerm(cmd) { Quickshell.execDetached(cmd); Overlays.close("hub"); }

    // Drill into a deeper Hub route (the system-language / timezone pickers). Also
    // re-emitted on behalf of the Date & Time section (see the header note).
    signal navigate(var route)

    // Privileged actions handed up to the Hub (suspend for the polkit prompt, restore +
    // refresh on exit) — used by the Logs retention control and, re-emitted, by the
    // Date & Time section. Wired generically in Hub.qml.
    signal runPrivileged(var cmd, var onDone)

    // The shared pill (core/WPill.qml) carrying the Hub's configured outline width —
    // the tab switch, same idiom as AppearancePanel/DisplaysPanel/InputPanel.
    component Pill: WPill { borderWidth: HubConfig.border }

    // ── Tabs ────────────────────────────────────────────────────────────────────────
    property string tab: "general"          // "general" | "datetime" | "security"

    // Secure Boot only exists on the encrypted+Limine install path (sbctl/tpm2-tools are
    // installed there and nowhere else, see package-limine.md) — a plain GRUB system has
    // no w-secureboot backend to front at all. This gate used to hide the whole Security
    // TAB, which was wrong once the tab stopped being about Secure Boot alone: kernel
    // hardening is bootloader-independent and would have been unreachable on every plain
    // install. So the tab is unconditional now and the flag is handed to the section,
    // which drops just the one row it governs. It is a structural absence, not a
    // firmware limitation (that case the section grays out instead).
    property bool limineAvailable: false
    FileView {
        path: "/etc/default/limine"
        onLoaded: root.limineAvailable = true
        onLoadFailed: root.limineAvailable = false
    }

    readonly property var tabs: ["general", "datetime", "security"]
    readonly property int tabIdx: Math.max(0, root.tabs.indexOf(root.tab))
    function setTab(name) {
        if (root.tab === name) return;
        root.tab = name;
        root.focusIdx = 0;
        flick.contentY = 0;
    }

    // ── Keyboard roving-focus (two regions: the tab pills → the scrolling rows) ──────
    // "content" is a flat computed list whose shape depends on the tab: on General the
    // panel's own rows (as Items, the compact-visible-list contract PowerPanel uses —
    // syncRow/sessAutoRow are conditional, so the Column already skips them and the
    // roving order has to match); on the other two the field names the loaded section
    // reports through its `fields` property. Descriptors carry either an `item` (General)
    // or a `field` (a section), never both, which is what tells the two apart below.
    property string focusRegion: "tab"      // "tab" | "content"
    property int focusIdx: 0

    readonly property var focusables: [verRow, channelRow, kernelRow, kernelRebootRow,
                                      localeRow, updRow, syncRow, vacuumRow, retRow,
                                      sessModeRow, sessLayoutsRow, sessAutoRow]
    readonly property var visFocusables: root.focusables.filter((f) => f.visible)

    function sectionItem() {
        if (root.tab === "datetime") return dtLoader.item;
        if (root.tab === "security") return secLoader.item;
        return null;
    }
    function buildContent() {
        if (root.tab === "general") return root.visFocusables.map((it) => ({ item: it, field: "" }));
        const sec = root.sectionItem();
        return sec ? sec.fields.map((f) => ({ item: null, field: f })) : [];
    }
    readonly property var contentDesc: root.buildContent()
    onContentDescChanged: if (root.focusRegion === "content")
        root.focusIdx = Math.max(0, Math.min(root.focusIdx, root.contentDesc.length - 1))

    // What the rows bind their own `focused` to. Two shapes because the General rows are
    // real Items here while a section's rows live behind a Loader and are addressed by
    // name; `focusedField` is pushed across that boundary by the Bindings below.
    readonly property var focusedRow: (root.tab === "general" && root.focusRegion === "content"
                                       && root.contentDesc[root.focusIdx])
                                      ? root.contentDesc[root.focusIdx].item : null
    readonly property string focusedField: (root.tab !== "general" && root.focusRegion === "content"
                                            && root.contentDesc[root.focusIdx])
                                           ? root.contentDesc[root.focusIdx].field : ""

    function contentItemFor(d) {
        if (!d) return null;
        if (d.item) return d.item;
        const sec = root.sectionItem();
        return sec ? sec.rowItem(d.field) : null;
    }
    function scrollIntoView() {
        const item = root.contentItemFor(root.contentDesc[root.focusIdx]);
        if (!item) return;
        // Reaching either end of the roving list should reach the true scroll edge
        // (a HubSection header sits above the first row) — same reasoning as
        // PowerPanel.scrollIntoView.
        if (root.focusIdx === 0) { flick.contentY = 0; return; }
        if (root.focusIdx === root.contentDesc.length - 1) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }

    function moveH(delta) {
        // ←/→ belong to the tab row; no row on any tab has a continuous value to step.
        if (root.focusRegion !== "tab") return;
        const i = Math.max(0, Math.min(root.tabs.length - 1, root.tabIdx + delta));
        root.setTab(root.tabs[i]);
    }
    function moveDown() {
        if (root.focusRegion === "tab") {
            root.focusRegion = "content";
            root.focusIdx = 0;
            root.scrollIntoView();
            return;
        }
        root.focusIdx = Math.min(root.focusIdx + 1, Math.max(0, root.contentDesc.length - 1));
        root.scrollIntoView();
    }
    function moveUp() {
        if (root.focusRegion === "tab") return;
        if (root.focusIdx > 0) { root.focusIdx--; root.scrollIntoView(); return; }
        root.focusRegion = "tab";
    }

    focus: true
    Keys.onPressed: (e) => {
        // A text field may hold real Qt focus and just not consume this key — let it
        // bubble here unhandled rather than steal the roving cursor mid-edit (same
        // guard as NetworkPanel's hostField). Both editable fields live on the General
        // tab; neither section carries one, so this guard covers the whole panel.
        if (retField.input.activeFocus || sessAutoField.input.activeFocus) return;
        switch (e.key) {
        case HubNavKeys.down:  root.moveDown(); e.accepted = true; return;
        case HubNavKeys.up:    root.moveUp();   e.accepted = true; return;
        case HubNavKeys.left:  root.moveH(-1);  e.accepted = true; return;
        case HubNavKeys.right: root.moveH(1);   e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            if (root.focusRegion === "tab") { e.accepted = true; return; }
            const d = root.contentDesc[root.focusIdx];
            if (d) {
                if (d.item) {
                    if (d.item === retRow) retField.input.forceActiveFocus();          // enter edit mode
                    else if (d.item === sessAutoRow) sessAutoField.input.forceActiveFocus();
                    else if (d.item.activated !== undefined) d.item.activated();
                } else {
                    const sec = root.sectionItem();
                    if (sec) sec.activateField(d.field);
                }
            }
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

    // ── Kernel (w-kernel list --porcelain) ───────────────────────────────────────────
    // Read once on open (a one-shot Process, like the logs and session readers): the
    // only thing that changes this while the panel is up is the switch itself, and that
    // closes the Hub. `default` is what boots next, `running` is what is loaded now —
    // they disagree exactly between a switch and its reboot, which is the one state the
    // panel must not render as simply "LTS" and leave at that.
    property string kernelDefault: ""
    property string kernelRunning: ""
    property var    kernelRows: []       // [{ id, installed }] in the tool's own order
    readonly property bool kernelRebootOwed: root.kernelDefault !== "" && root.kernelRunning !== ""
                                             && root.kernelDefault !== root.kernelRunning
    function kernelLabel(id) { return id ? Strings.t("hub.kernel." + id) : "—"; }
    // A kernel that is not installed yet is still offered — choosing it is how you
    // install it — but it says so, because that choice costs a download and a DKMS
    // rebuild while an installed one is an instant, offline repin of the boot default.
    readonly property var kernelOptions: root.kernelRows.map((k) => ({
        id: k.id,
        label: k.installed ? root.kernelLabel(k.id)
                           : root.kernelLabel(k.id) + " — " + Strings.t("hub.kernelNotInstalled")
    }))
    Process {
        id: kernelStat
        running: true
        command: ["w-kernel", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Header row + one row per kernel: name pkg version installed default running
                const rows = [];
                let def = "", run = "";
                const lines = (this.text || "").split("\n").filter((l) => l.length > 0);
                for (let i = 1; i < lines.length; i++) {
                    const f = lines[i].split("\t");
                    if (f.length < 6) continue;
                    rows.push({ id: f[0], installed: f[3] === "yes" });
                    if (f[4] === "yes") def = f[0];
                    if (f[5] === "yes") run = f[0];
                }
                root.kernelRows = rows; root.kernelDefault = def; root.kernelRunning = run;
            }
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

    // ── Fixed header: tab switch ─────────────────────────────────────────────────────
    // Outside the Flickable so it stays put while a long tab scrolls under it (same
    // placement as DisplaysPanel's scope switch and InputPanel's device switch).
    Column {
        id: topCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 12

        Row {
            spacing: 8
            Pill {
                label: Strings.t("sys.tab.general"); active: root.tab === "general"
                focused: root.focusRegion === "tab" && root.tabIdx === 0
                onClicked: { root.focusRegion = "tab"; root.setTab("general"); }
            }
            Pill {
                label: Strings.t("hub.datetime"); active: root.tab === "datetime"
                focused: root.focusRegion === "tab" && root.tabIdx === 1
                onClicked: { root.focusRegion = "tab"; root.setTab("datetime"); }
            }
            Pill {
                label: Strings.t("hub.security"); active: root.tab === "security"
                focused: root.focusRegion === "tab" && root.tabIdx === 2
                onClicked: { root.focusRegion = "tab"; root.setTab("security"); }
            }
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors {
            top: topCol.bottom; topMargin: 12
            left: parent.left; right: parent.right; bottom: parent.bottom
        }
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

            // ── Tab: General ────────────────────────────────────────────────────
            // Hidden (not unloaded) on the other tabs: these rows are cheap and already
            // built, and their FileView/Process readers are the panel's live state.
            Column {
                id: genCol
                width: parent.width
                visible: root.tab === "general"
                spacing: 12

                // About.
                HubSection { width: parent.width; text: Strings.t("hub.about") }
                HubRow {
                    id: verRow
                    width: parent.width
                    icon: "help-about"; glyph: String.fromCodePoint(0xf02fc)   // nf-md-information_outline
                    label: Strings.t("hub.version")
                    value: root.versionText
                    focused: root.focusedRow === verRow
                }
                HubRow {
                    id: channelRow
                    width: parent.width
                    icon: "preferences-system"; glyph: String.fromCodePoint(0xf062c)  // nf-md-source_branch
                    label: Strings.t("hub.channel")
                    value: Strings.t("hub.channel." + (root.isEdge ? "edge" : "stable"))
                    focused: root.focusedRow === channelRow
                }

                // Kernel. Switching INSTALLS the chosen kernel and its paired headers and
                // every DKMS module rebuilds behind them — long, network-bound, and its
                // output is where a DKMS module with no patch for the new series says so.
                // That is a terminal operation (Ф4's hybrid model), not a runPrivileged
                // one, and the Hub closes behind it exactly as it does for Sync.
                // Nothing is ever uninstalled: every installed kernel stays a bootable
                // menu entry, which is what makes a bad kernel one reboot away from being
                // escaped — offline, with no download, on a machine whose network driver
                // is the thing that broke. `w-kernel remove` is the deliberate way back
                // and is CLI-only on purpose; reclaiming space is not a settings-screen
                // gesture, and the ESP it would reclaim is self-limiting anyway.
                HubSection { width: parent.width; text: Strings.t("hub.kernel") }
                SelectRow {
                    id: kernelRow
                    width: parent.width
                    icon: "computer"; glyph: String.fromCodePoint(0xf035b)   // nf-md-memory
                    label: Strings.t("hub.kernelLabel")
                    enabled: root.kernelRows.length > 0
                    currentId: root.kernelDefault
                    options: root.kernelOptions
                    value: root.kernelLabel(root.kernelDefault)
                    focused: root.focusedRow === kernelRow
                    onActivated: menuLayer.openMenu(kernelRow, root.kernelOptions, root.kernelDefault, (id) => {
                        if (id === root.kernelDefault) return;
                        root.runTerm(Term.exec(["pkexec", "/usr/lib/w/w-hub-actuate", "kernel-set", id]));
                    })
                }
                Text {
                    width: parent.width
                    text: Strings.t("hub.kernelHint")
                    color: Colors.muted
                    font.family: Fonts.family; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                // The switch is a boot-time choice: it is complete only after a reboot,
                // and until then the row above would otherwise read "LTS" on a machine
                // still running Zen. The bar says the same thing with its reboot glyph
                // (w-update's reboot_pending now covers a pending kernel switch too);
                // this is the place that can also act on it. Rebooting is unprivileged
                // and belongs to the user's own session — w-session-exit asks every
                // window to close first, so an editor with unsaved work still gets a
                // reachable dialog (and cancelling one calls the reboot off). That is
                // why it is not a prompt at the end of the root-owned terminal: under
                // pkexec there is no user session to hand the graceful path to.
                HubRow {
                    id: kernelRebootRow
                    width: parent.width
                    visible: root.kernelRebootOwed
                    icon: "view-refresh"; glyph: String.fromCodePoint(0xf0450)   // nf-md-restart
                    label: Strings.t("hub.kernelRebootTitle")
                    sublabel: Strings.t("hub.kernelRunningNow") + ": " + root.kernelLabel(root.kernelRunning)
                    actionText: Strings.t("hub.rebootNow")
                    focused: root.focusedRow === kernelRebootRow
                    onActivated: {
                        Session.exiting = true;
                        Quickshell.execDetached(["w-session-exit", "reboot"]);
                        Overlays.close("hub");
                    }
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
                    focused: root.focusedRow === localeRow
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
                    focused: root.focusedRow === updRow
                    onActivated: root.runTerm(Term.exec(["w-update"]))
                }
                HubRow {
                    id: syncRow
                    visible: root.isEdge
                    width: parent.width
                    icon: "emblem-synchronizing"; glyph: String.fromCodePoint(0xf04e6)   // nf-md-sync
                    label: Strings.t("hub.sync")
                    focused: root.focusedRow === syncRow
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
                    focused: root.focusedRow === vacuumRow
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
                        visible: root.focusedRow === retRow && !retField.input.activeFocus
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
                    focused: root.focusedRow === sessModeRow
                    onActivated: menuLayer.openMenu(sessModeRow, options, root.sessMode,
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
                    focused: root.focusedRow === sessLayoutsRow
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
                        visible: root.focusedRow === sessAutoRow && !sessAutoField.input.activeFocus
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

            // ── Tab: Date & Time ────────────────────────────────────────────────
            // A sibling file rather than more markup here: it shares no state with the
            // rows above and this panel is long enough already. `active` unloads it on
            // tab change, so its 1 s clock ticker does not run while another tab is up.
            Loader {
                id: dtLoader
                width: col.width
                active: root.tab === "datetime"
                visible: active
                source: "DateTimeSection.qml"
                onLoaded: item.menuLayer = menuLayer
            }
            Binding {
                target: dtLoader.item
                property: "focusedField"
                value: root.focusedField
                when: dtLoader.status === Loader.Ready
            }
            // The Hub's own Connections watches only the top-level panel, so the
            // section's signals are re-emitted from here (see the file header).
            Connections {
                target: dtLoader.item
                function onNavigate(route) { root.navigate(route); }
                function onRunPrivileged(cmd, onDone) { root.runPrivileged(cmd, onDone); }
            }

            // ── Tab: Security ───────────────────────────────────────────────────
            // Secure Boot enrolling opens a terminal and closes the Hub on its own; the
            // hardening toggle is instant actuation and comes back up as runPrivileged.
            Loader {
                id: secLoader
                width: col.width
                active: root.tab === "security"
                visible: active
                source: "SecuritySection.qml"
                onLoaded: item.menuLayer = menuLayer
            }
            Binding {
                target: secLoader.item
                property: "focusedField"
                value: root.focusedField
                when: secLoader.status === Loader.Ready
            }
            // Pushed rather than probed a second time inside the section: the FileView
            // resolves asynchronously, and this way the tab that owns the flag stays the
            // one place that decides what "this machine has a Limine backend" means.
            Binding {
                target: secLoader.item
                property: "limineAvailable"
                value: root.limineAvailable
                when: secLoader.status === Loader.Ready
            }
            Connections {
                target: secLoader.item
                function onRunPrivileged(cmd, onDone) { root.runPrivileged(cmd, onDone); }
            }
        }
    }

    // The panel's single dropdown overlay, shared by all three tabs (one overlay per
    // panel — the DisplaysPanel/NightLightSection contract, so a menu opened from a
    // section closes exactly like one opened over a General row). Declared last so it
    // paints above the Flickable; `flipUp` because the session-mode row sits at the very
    // bottom of a long tab, where growing downward would push the menu past the card's
    // ceiling — it only ever flips when a menu would actually spill, so the sections'
    // near-the-top rows still grow the card the way they always did.
    HubDropdown { id: menuLayer; anchors.fill: parent; flipUp: true; returnFocusTo: root }
}
