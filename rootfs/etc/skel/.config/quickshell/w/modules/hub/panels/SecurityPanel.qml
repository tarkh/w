// W Linux — Hub Security panel (root-level tile).
// A thin front-end over `w-secureboot`: one control, Secure Boot on/off, plus the
// firmware status it reads from. State comes from `w-secureboot status --porcelain`
// (unprivileged — sbctl needs no root to read EFI variables), a one-shot Process on
// open, no live watch (nothing else changes it while the panel is up).
//
// Enrolling/de-enrolling is NOT a `runPrivileged`/suspend action (that hides the Hub
// and blocks with no progress) — it needs a live pty besides: `w-secureboot enable`
// re-seals the LUKS TPM2 auto-unlock to the new boot chain (`w-crypt enroll-tpm`/
// `reenroll-tpm`), which asks for the disk passphrase once; `disable` removes that
// factor first so the passphrase prompt returns at boot. So this opens in a terminal
// through the `secureboot` capability (pkexec + w-hub-actuate) and closes the Hub —
// the same idiom SystemPanel uses for `sync-update interactive`.
//
// A firmware that doesn't expose Secure Boot EFI variables at all (legacy boot, or a
// non-secboot VM firmware) reports `state=unsupported`: the row locks instead of
// hiding, so the panel says why instead of just not being there — `SelectRow.locked`
// is the same mechanism NetworkPanel uses for a site-policy-owned key.
//
// A 4th "on" also carries a `tpm_pending` flag: PCR7 (what the LUKS TPM2 auto-unlock
// is sealed to) is measured by the firmware/bootloader at boot and does not change
// while the OS is running, so `w-secureboot enable` cannot enroll the SB keys AND
// re-seal TPM2 in the same session — it enrolls, then asks for a reboot before it can
// finish. `reboot_needed` vs `ready` (has the required reboot happened, keyed off the
// boot ID) decides whether the extra row below is a plain note or a clickable action.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/SecurityPanel.qml"}); as a
// subdir file it is not a module type, so the shared hub components (SelectRow,
// HubSection, HubRow) come in through `import qs.modules.hub`.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    implicitHeight: Math.max(col.implicitHeight, menuLayer.menuBottom)

    // Open a privileged, interactive command in a terminal and close the Hub, so the
    // disk-passphrase prompt lands on a real pty instead of a hidden popup.
    function runTerm(cmd) { Quickshell.execDetached(cmd); Overlays.close("hub"); }

    // ── Keyboard roving-focus (short fixed list, no Flickable — never scrolls) ──────
    // finishRow is edge-only (visible only while a TPM2 re-seal is pending), so the
    // roving order has to skip it the same way the Column already does.
    readonly property var focusables: [sbRow, finishRow]
    readonly property var visFocusables: root.focusables.filter((f) => f.visible)
    property int focusIndex: 0
    onVisFocusablesChanged: root.focusIndex = Math.max(0, Math.min(root.focusIndex, root.visFocusables.length - 1))

    focus: true
    Keys.onPressed: (e) => {
        const vf = root.visFocusables;
        if (vf.length === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusIndex = Math.min(root.focusIndex + 1, vf.length - 1); e.accepted = true; return;
        case HubNavKeys.up:   root.focusIndex = Math.max(root.focusIndex - 1, 0);              e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = vf[root.focusIndex];
            if (item.activated !== undefined) item.activated();
            e.accepted = true;
            return;
        }
        }
    }

    // ── Secure Boot state (w-secureboot status --porcelain) ─────────────────────────
    property string sbState: ""   // "on" | "off" | "unsupported" | "" (not read yet)
    property string tpmPending: "no"   // "no" | "reboot_needed" | "ready"
    readonly property bool sbUnsupported: root.sbState === "unsupported"
    readonly property bool sbAvailable: root.sbState === "on" || root.sbState === "off"
    readonly property string sbCurrentId: root.sbAvailable ? root.sbState : "off"
    readonly property var sbOptions: [
        { id: "off", label: Strings.t("hub.secureBoot.off") },
        { id: "on",  label: Strings.t("hub.secureBoot.on") },
    ]
    Process {
        id: sbRead
        running: true
        command: ["w-secureboot", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Header row + one data row; skip the header, split the rest on tabs.
                const lines = (this.text || "").split("\n").filter(l => l.length > 0);
                const f = lines.length >= 2 ? lines[1].split("\t") : [];
                root.sbState = f[0] || "";
                root.tpmPending = f[3] || "no";
            }
        }
    }

    // ── Layout ─────────────────────────────────────────────────────────────────────
    Column {
        id: col
        width: parent.width
        spacing: 12

        HubSection { width: parent.width; text: Strings.t("hub.secureBoot") }
        SelectRow {
            id: sbRow
            width: parent.width
            icon: "security-high"; glyph: String.fromCodePoint(0xf0498)   // nf-md-shield
            label: Strings.t("hub.secureBoot")
            enabled: root.sbState !== ""
            locked: root.sbUnsupported
            lockedHint: Strings.t("hub.secureBootUnsupportedHint")
            currentId: root.sbCurrentId
            options: root.sbOptions
            value: root.sbUnsupported ? Strings.t("hub.secureBootUnsupported")
                   : (root.sbAvailable ? Strings.t("hub.secureBoot." + root.sbCurrentId) : "—")
            focused: root.focusIndex === root.visFocusables.indexOf(sbRow)
            onActivated: menuLayer.openMenu(sbRow, root.sbOptions, root.sbCurrentId, (id) => {
                root.runTerm(Term.exec(["pkexec", "/usr/lib/w/w-hub-actuate", "secureboot", id]))
            })
        }
        Text {
            width: parent.width
            text: Strings.t("hub.secureBootHint")
            color: Colors.muted
            font.family: Fonts.family; font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        // PCR7 (what TPM2 disk auto-unlock is sealed to) only updates on an actual
        // reboot, so a fresh enrollment cannot finish sealing it in the same session —
        // this row makes that pending step visible instead of the toggle silently
        // reading "On" while the disk still asks for its passphrase at every boot.
        HubRow {
            id: finishRow
            width: parent.width
            visible: root.tpmPending !== "no"
            icon: "view-refresh"; glyph: String.fromCodePoint(0xf0450)   // nf-md-restart
            label: Strings.t("hub.secureBoot.finishTitle")
            sublabel: root.tpmPending === "reboot_needed"
                      ? Strings.t("hub.secureBoot.pendingReboot")
                      : Strings.t("hub.secureBoot.pendingReady")
            actionText: root.tpmPending === "ready" ? Strings.t("hub.secureBoot.finish") : ""
            focused: root.focusIndex === root.visFocusables.indexOf(finishRow)
            onActivated: {
                if (root.tpmPending !== "ready") return;
                root.runTerm(Term.exec(["pkexec", "/usr/lib/w/w-hub-actuate", "secureboot", "on"]))
            }
        }
    }

    // ── Dropdown overlay layer (above the rows) ────────────────────────────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }
}
