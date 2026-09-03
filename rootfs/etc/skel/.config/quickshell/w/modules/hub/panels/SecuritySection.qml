// W Linux — Hub Security section (the System panel's "Security" tab).
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
// This was a root-level Hub panel of its own until the menu reorganisation: one control
// is too thin for a root tile, and Secure Boot is the System screen's business in every
// reference settings app. The whole TAB is gated on /etc/default/limine by SystemPanel
// (a plain GRUB install has no w-secureboot backend at all — a structural absence, not
// a firmware limitation), which is why nothing here re-checks for it.
//
// Keyboard roving-focus is owned by SystemPanel, not this file — the same contract
// NightLightSection has with DisplaysPanel: this renders whichever field it is told
// through `focusedField` and exposes fields/rowItem()/activateField() for the parent
// to drive, instead of keeping a second copy of the roving state.
//
// Loaded by SystemPanel (Loader{source:"SecuritySection.qml"}); as a subdir file it is
// not a module type, so the shared hub components (SelectRow, HubSection, HubRow) come
// in through `import qs.modules.hub`.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Column {
    id: root

    // SystemPanel's HubDropdown — one overlay per panel, shared so an open menu here
    // closes the same way it does over the General tab's session-mode row.
    property var menuLayer: null

    // ── Remote control surface (roving index lives in SystemPanel) ──────────────────
    // Field names: "sb" (the Secure Boot switch) and "finish" (the pending TPM2 re-seal,
    // present only while one is owed). SystemPanel reads `fields` to build its content
    // descriptor list, so a row appearing/disappearing reshapes the roving order for free.
    property string focusedField: ""
    readonly property var fields: root.tpmPending !== "no" ? ["sb", "finish"] : ["sb"]
    function rowItem(field) {
        if (field === "sb") return sbRow;
        if (field === "finish") return finishRow;
        return null;
    }
    function activateField(field) {
        const it = root.rowItem(field);
        if (it && it.activated !== undefined) it.activated();
    }

    // Open a privileged, interactive command in a terminal and close the Hub, so the
    // disk-passphrase prompt lands on a real pty instead of a hidden popup.
    function runTerm(cmd) { Quickshell.execDetached(cmd); Overlays.close("hub"); }

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
        focused: root.focusedField === "sb"
        onActivated: if (root.menuLayer) root.menuLayer.openMenu(sbRow, root.sbOptions, root.sbCurrentId, (id) => {
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
        focused: root.focusedField === "finish"
        onActivated: {
            if (root.tpmPending !== "ready") return;
            root.runTerm(Term.exec(["pkexec", "/usr/lib/w/w-hub-actuate", "secureboot", "on"]))
        }
    }
}
