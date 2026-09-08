// W Linux — Hub Rollback section (the System panel's "Rollback" tab).
// A front-end over `w-rollback`: what the system is currently booted from, and
// the snapper snapshots it can roll back to. The tab is unconditional — both
// boot paths (plain/GRUB and encrypted/Limine) carry the snapper configs — so
// unlike Security there is no backend gate.
//
// The snapshot LIST is a privileged read (`snapper list` answers "No
// permissions" to an ordinary user), and it is read exactly once per tab
// entry: the Loader recreates this section on every switch to the tab, and
// creation starts `pkexec … snapshot-list`, whose polkit prompt is the w-authd
// card. The call runs as this section's own tracked Process — the Hub's
// runPrivileged bracket has no stdout capture — with the same suspend bracket
// held here: Overlays.suspended = true before the spawn, false on exit. The
// auth card drives the same flag while it is up and clears it when it closes;
// both paths converge on the Hub being visible again.
//
// Starting a rollback is NOT done here. `w-rollback launch <n>` is the single
// definition of "start a rollback from a graphical surface" — the snapshot
// notice's button and the AI's rollback tool call the same thing — and it
// keeps the escalation in front of the person who answers for the result: it
// opens the terminal, the pkexec prompt lands there, and the confirmation and
// the reboot question live on a real pty. This section only detaches it and
// closes the Hub, the idiom SecuritySection uses for its terminal operations.
//
// Keyboard roving-focus is owned by SystemPanel, not this file — the same
// contract NightLightSection has with DisplaysPanel: this renders whichever
// field it is told through `focusedField` and exposes fields/rowItem()/
// activateField() for the parent to drive. The field set is dynamic (empty
// while the privileged read is in flight, one field per snapshot after it, a
// Retry row when it failed) — the async-appearing-list case the panel's
// focus-index clamp already covers.
//
// Loaded by SystemPanel (Loader{source:"RollbackSection.qml"}); as a subdir
// file it is not a module type, so the shared hub components (HubSection,
// HubRow) come in through `import qs.modules.hub`.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub

Column {
    id: root

    // SystemPanel's roving cursor, pushed through a Binding: the focused
    // field's name, or "" when the cursor sits elsewhere.
    property string focusedField: ""

    // ── Remote control surface (roving index lives in SystemPanel) ─────────────────
    // "snap<N>" per snapshot row, "retry" while the privileged read has failed.
    // The booted-from row is a fact, not a control, and stays out of the roving
    // list — the same reason sessSavedRow is not in SystemPanel's focusables.
    readonly property var fields: root.loadFailed ? ["retry"]
        : root.snaps.map((s) => "snap" + s.number)
    function rowItem(field) {
        if (field === "retry") return retryRow;
        for (let i = 0; i < root.snaps.length; i++)
            if ("snap" + root.snaps[i].number === field) return snapRep.itemAt(i);
        return null;
    }
    function activateField(field) {
        const it = root.rowItem(field);
        if (it && it.activated !== undefined) it.activated();
    }

    // Start a rollback to this snapshot and close the Hub: the terminal, the
    // auth prompt and the confirmation all belong to w-rollback launch — on
    // the Limine path the snapshot number is picked inside the vendor tool,
    // which the terminal helpfully restates.
    function restoreSnapshot(number) {
        Quickshell.execDetached(["w-rollback", "launch", String(number)]);
        Overlays.close("hub");
    }

    // ── Booted-from state (w-rollback status --porcelain) ───────────────────────────
    // Unprivileged — the boot path is a file test and the booted snapshot comes
    // from /proc/cmdline. Read once on open; nothing changes it while the panel
    // is up (if the answer changes, the machine rebooted, and so did this panel).
    property string bootedSnap: ""        // non-empty → running from that snapshot
    Process {
        id: statusRead
        running: true
        command: ["w-rollback", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("=");
                    if (f[0] === "booted_snapshot") root.bootedSnap = f[1] || "";
                }
            }
        }
    }

    // ── Snapshot list (w-rollback list --porcelain, as root) ────────────────────────
    // One privileged read per tab entry — see the header. Parse and failure live
    // on different signals, so the pair is order-independent: stdout collects
    // first and fills `snaps`, the exit resets the suspend bracket and only then
    // decides between empty (a healthy system with no snapshots) and failed.
    property var snaps: []   // [{ number, type, pre, date, description }]
    property bool loading: false
    property bool loadFailed: false
    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                // number TAB type TAB paired-pre TAB date TAB description; snapshot #0
                // was left out by the CLI. Type/pairing is how one finds "the snapshot
                // taken right before that update" — the usual thing to look for.
                const rows = [];
                for (const line of (this.text || "").split("\n")) {
                    if (!line.length) continue;
                    const f = line.split("\t");
                    if (f.length >= 5)
                        rows.push({ number: parseInt(f[0]), type: f[1], pre: f[2],
                                    date: f[3], description: f[4] });
                }
                if (rows.length) { root.snaps = rows; root.loadFailed = false; }
            }
        }
        onExited: (code) => {
            root.loading = false;
            Overlays.suspended = false;
            if (root.snaps.length === 0 && code !== 0) root.loadFailed = true;
        }
    }
    function loadList() {
        root.snaps = [];
        root.loadFailed = false;
        root.loading = true;
        Overlays.suspended = true;
        listProc.running = false;
        listProc.command = ["pkexec", "/usr/lib/w/w-hub-actuate", "snapshot-list"];
        listProc.running = true;
    }
    Component.onCompleted: root.loadList()
    // Insurance against a stuck-hidden Hub: the exit bracket above is the normal
    // path, but a section destroyed with the read in flight (Hub torn down some
    // other way) never reaches onExited. Gated on OUR read — the auth card owns
    // the flag while it is up, and this must not fight it.
    Component.onDestruction: if (root.loading) Overlays.suspended = false

    // ── Layout ─────────────────────────────────────────────────────────────────────
    spacing: 12

    // The correct rollback process, up top where the user lands first.
    Text {
        width: parent.width
        text: Strings.t("hub.rollbackHint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    HubSection { width: parent.width; text: Strings.t("hub.rollbackState") }
    HubRow {
        width: parent.width
        icon: "computer"; glyph: String.fromCodePoint(0xf035b)   // nf-md-memory
        label: Strings.t("hub.rollbackBooted")
        value: root.bootedSnap !== ""
               ? Strings.t("hub.rollbackBootedSnapshot").replace("%n%", root.bootedSnap)
               : Strings.t("hub.rollbackBootedNormal")
        sublabel: root.bootedSnap !== "" ? Strings.t("hub.rollbackBootedSnapshotHint") : ""
    }

    HubSection { width: parent.width; text: Strings.t("hub.rollbackSnapshots") }

    Text {
        width: parent.width
        visible: root.loading && !root.loadFailed
        text: Strings.t("hub.rollbackLoading")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 12
    }
    Text {
        width: parent.width
        visible: !root.loading && root.snaps.length === 0 && !root.loadFailed
        text: Strings.t("hub.rollbackEmpty")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 12
    }

    Repeater {
        id: snapRep
        model: root.snaps
        HubRow {
            required property var modelData
            width: root.width
            icon: "document-revert"; glyph: String.fromCodePoint(0xf0292)   // nf-md-history
            // "pre"/"post" are snapper's own terms, kept untranslated; a post row
            // also names the pre snapshot it belongs to (the pair one rolls to
            // after trying the post, or back out of).
            label: modelData.type === "pre" ? "#" + modelData.number + " (" + Strings.t("hub.rollback.pre") + ")"
                 : modelData.type === "post" ? "#" + modelData.number + " ("
                                               + Strings.t("hub.rollback.postOf").replace("%p%", modelData.pre || "?") + ")"
                 : "#" + modelData.number
            sublabel: modelData.date + (modelData.description.length ? " · " + modelData.description : "")
            actionText: Strings.t("hub.rollbackRestore")
            // Inline "snap" + number rather than a per-delegate field property —
            // the focused binding is read per row and must not drift (Ф-Keyboard
            // gotcha #16 class).
            focused: root.focusedField === ("snap" + modelData.number)
            onActivated: root.restoreSnapshot(modelData.number)
        }
    }

    // The one recovery path when the privileged read did not complete (prompt
    // dismissed, or the call refused) — a focusable row, since it has a verb.
    HubRow {
        id: retryRow
        width: parent.width
        visible: root.loadFailed
        icon: "view-refresh"; glyph: String.fromCodePoint(0xf0450)   // nf-md-restart
        label: Strings.t("hub.rollbackLoadFail")
        sublabel: Strings.t("hub.rollbackLoadFailHint")
        actionText: Strings.t("hub.rollbackRetry")
        focused: root.focusedField === "retry"
        onActivated: root.loadList()
    }
}
