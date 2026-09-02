// W Linux — Hub Packs panel (root-level, promoted out of System).
// A read-and-act front-end over the w-pack bundle catalogue: one row per bundle, in
// one of three states, because a bundle has two layers and only naming the missing
// one is honest:
//   installed   machine layer present AND set up for this account -> a check
//   machine     on the machine, but NOT set up for me -> "Set up" (no sudo: it only
//               writes my own home, so no polkit and no admin needed)
//   absent      not on the machine at all -> "Install" (sudo, in a terminal)
// The middle state is the whole point of the panel's rewrite: it used to render as a
// plain "installed" check for a second account that had none of the bundle's tools.
//
// Long-running installs open in a terminal with live output and close the Hub (same
// pattern as Updates/Sync on the System panel) rather than the runPrivileged/suspend
// bracket, which hides the Hub and blocks with no progress for the whole download.
//
// State is read cheaply: a one-shot `w-pack list --porcelain` probe on open, no live
// watch. Porcelain rather than the human table: the states are now a real contract
// (name TAB machine TAB user TAB desc) and parsing the pretty output with a regex was
// one padding change away from breaking.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/PacksPanel.qml"}); as a
// subdir file it is not a module type, so the shared hub components (HubRow,
// HubSection) come in through `import qs.modules.hub`. Scrolls with the shared
// WScrollBar if it overflows.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub

Item {
    id: root
    // +8 mirrors the Flickable's contentHeight bleed below (focus-wash slack) — see
    // quickshell-hub.md's Ф-Keyboard gotcha #6 (InputPanel is the reference).
    implicitHeight: col.implicitHeight + 8

    // Open a long-running maintenance command in a terminal and close the Hub, so its
    // progress is visible instead of blocking a hidden popup.
    function runTerm(cmd) { Quickshell.execDetached(cmd); Overlays.close("hub"); }

    // ── Keyboard roving-focus (flat list, top→bottom, inside a Flickable) ───────────
    // The bundle count is runtime-variable (w-pack list --porcelain), so the roving
    // cursor is a plain linear index over the Repeater's own `index`, not an array of
    // item ids — same idiom as InputPanel's layout ring.
    readonly property int focusCount: packs.count
    property int focusIndex: 0
    onFocusCountChanged: root.focusIndex = Math.max(0, Math.min(root.focusIndex, root.focusCount - 1))

    function focusItem(i) { return packsRepeater.itemAt(i); }
    function scrollIntoView(i) {
        const item = root.focusItem(i);
        if (!item) return;
        // Reaching either end of the roving list should reach the true scroll edge
        // (a HubSection-less flat list, but the same reasoning as InputPanel/
        // PowerPanel — "row visible in viewport" and "scrolled to the true edge"
        // are not the same condition with the usual nudge-into-view math).
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
        if (root.focusCount === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:   root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = root.focusItem(root.focusIndex);
            if (item) item.activated();
            e.accepted = true;
            return;
        }
        }
    }

    // ── Packs (w-pack list --porcelain) — catalogue read once on open ────────────────
    ListModel { id: packs }
    Process {
        id: packList
        running: true
        command: ["w-pack", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                packs.clear();
                // <name> TAB <machine:yes|no> TAB <user:yes|no|n/a> TAB <description>
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 4) continue;
                    // "n/a" = the bundle has no per-user layer, so being on the machine
                    // is the whole story and nobody should be nagged to set it up.
                    const ready = f[1] === "yes" && f[2] !== "no";
                    packs.append({ pname: f[0], pdesc: f[3].trim(),
                                   onMachine: f[1] === "yes", installed: ready });
                }
            }
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        // Extend into the card's right padding so the scrollbar pill sits near the window
        // edge; the content column insets the same amount, keeping its padding symmetric.
        anchors.rightMargin: -12
        // Widen the clip rect leftward into the card's own padding — HubRow's -8 focus
        // wash would otherwise clip against Flickable's clip rect (Ф-Keyboard gotcha #2).
        anchors.leftMargin: -8
        clip: true
        // 4px slack at each end for the first/last row's focus wash — NOT via
        // Flickable.topMargin/bottomMargin (Ф-Keyboard gotcha #3, see quickshell-hub.md).
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 12

            // One row per bundle. Ready shows a check; otherwise the button says which
            // of the two layers is missing and runs exactly the command for it:
            //   not on the machine -> `sudo w-pack install <b>` (packages, root)
            //   on it but not mine -> `w-pack setup <b>`, deliberately WITHOUT sudo —
            //     it writes only this account's home, so a non-admin can do it too.
            // Both go through a terminal so a long download stays visible.
            Repeater {
                id: packsRepeater
                model: packs
                HubRow {
                    required property int index
                    required property string pname
                    required property string pdesc
                    required property bool onMachine
                    required property bool installed
                    width: col.width
                    icon: "package-x-generic"; glyph: String.fromCodePoint(0xf03d3)  // nf-md-package_variant
                    label: pname
                    sublabel: installed || !onMachine ? pdesc : Strings.t("hub.packs.notSetUp")
                    done: installed
                    actionText: installed ? ""
                              : onMachine ? Strings.t("hub.packs.setUp")
                                          : Strings.t("hub.install")
                    focused: root.focusIndex === index
                    onActivated: root.runTerm(onMachine
                        ? Term.exec(["w-pack", "setup", pname])
                        : Term.exec(["sudo", "w-pack", "install", pname]))
                }
            }
        }
    }
}
