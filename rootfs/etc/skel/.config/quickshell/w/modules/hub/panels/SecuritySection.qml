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
// The second control is the kernel hardening profile (w-kernel harden), and it is the
// opposite kind of action: renaming three sysctl drop-ins, one `sysctl --system`, a
// cmdline edit and a bootloader regen — seconds, no stdin, nothing to watch. So it goes
// through the Hub's runPrivileged bracket (suspend for the polkit prompt, restore, then
// re-read), the same idiom as the Date & Time section's NTP toggle. The two idioms
// sitting side by side in one section is the rule working, not an inconsistency: the
// choice is about how long the operation takes and whether it needs a pty, never about
// which panel it lives on.
//
// This was a root-level Hub panel of its own until the menu reorganisation: one control
// is too thin for a root tile, and Secure Boot is the System screen's business in every
// reference settings app. The TAB used to be gated on /etc/default/limine — correct
// while it held Secure Boot alone, wrong the moment hardening arrived: hardening is
// bootloader-independent, and the gate would have hidden it from every plain GRUB
// install. The flag is now handed down from SystemPanel and drops only the Secure Boot
// rows (a structural absence of the backend, not a firmware limitation — that case the
// row grays out with a hint instead).
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

    // Whether this machine has the Limine/Secure Boot backend at all — pushed down by
    // SystemPanel, which owns the probe (see the header).
    property bool limineAvailable: false

    // Instant privileged actuation handed up to the Hub (suspend for the polkit prompt,
    // restore, re-read on exit). Re-emitted by SystemPanel: the Hub's Connections sees
    // only the top-level panel, never a signal from inside a nested Loader.
    signal runPrivileged(var cmd, var onDone)

    // ── Remote control surface (roving index lives in SystemPanel) ──────────────────
    // Field names: "sb" (the Secure Boot switch), "finish" (the pending TPM2 re-seal,
    // present only while one is owed) and "harden" (the hardening profile). SystemPanel
    // reads `fields` to build its content descriptor list, so a row appearing or
    // disappearing — with the backend, or with a pending re-seal — reshapes the roving
    // order for free. The hardening row is last and unconditional: it is the only one
    // that exists on every install.
    property string focusedField: ""
    readonly property var fields: (root.limineAvailable
                                   ? (root.tpmPending !== "no" ? ["sb", "finish"] : ["sb"])
                                   : []).concat(["harden"])
    function rowItem(field) {
        if (field === "sb") return sbRow;
        if (field === "finish") return finishRow;
        if (field === "harden") return hardenRow;
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
        // Only where there is a backend to ask: on a plain GRUB install the Secure Boot
        // rows are absent, so the probe would be pure waste. limineAvailable arrives
        // asynchronously from SystemPanel, which is what starts this.
        running: root.limineAvailable
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

    // ── Hardening state (w-kernel harden status --porcelain) ────────────────────────
    // Unprivileged, and re-read explicitly after our own setter exits (runPrivileged's
    // onDone) rather than watched: nothing else changes the profile while the panel is
    // up. `pending` is the configured cmdline disagreeing with /proc/cmdline — the boot
    // half of the profile only lands on the next boot, and `off` additionally leaves
    // already-applied sysctl values in the running kernel, which the hint says out loud.
    property string hardenState: ""      // "on" | "off" | "mixed" | "" (not read yet)
    property bool   hardenPending: false
    readonly property var hardenOptions: [
        { id: "off", label: Strings.t("hub.harden.off") },
        { id: "on",  label: Strings.t("hub.harden.on") },
    ]
    Process {
        id: hardenRead
        running: true
        command: ["w-kernel", "harden", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").filter(l => l.length > 0);
                const f = lines.length >= 2 ? lines[1].split("\t") : [];
                root.hardenState = f[0] || "";
                root.hardenPending = (f[1] || "no") === "yes";
            }
        }
    }
    function reloadHarden() { hardenRead.running = false; hardenRead.running = true; }

    // ── Layout ─────────────────────────────────────────────────────────────────────
    spacing: 12

    HubSection {
        width: parent.width
        visible: root.limineAvailable
        text: Strings.t("hub.secureBoot")
    }
    SelectRow {
        id: sbRow
        width: parent.width
        visible: root.limineAvailable
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
        visible: root.limineAvailable
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
        visible: root.limineAvailable && root.tpmPending !== "no"
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

    // ── Kernel hardening (w-kernel harden) ─────────────────────────────────────────
    HubSection { width: parent.width; text: Strings.t("hub.harden") }
    SelectRow {
        id: hardenRow
        width: parent.width
        icon: "security-medium"; glyph: String.fromCodePoint(0xf0297)   // nf-md-lock_outline
        label: Strings.t("hub.hardenLabel")
        enabled: root.hardenState !== ""
        // "mixed" is a real state, not a rounding error: the sysctl drop-ins and the
        // boot cmdline are two halves that can be toggled apart (a hand-edited drop-in,
        // or — until this was made bootloader-aware — an install that wrote its cmdline
        // where its loader never looked). Rendering it as "off" would be a lie the user
        // could act on. currentId stays empty then, so the menu marks nothing as current.
        currentId: root.hardenState === "mixed" ? "" : root.hardenState
        options: root.hardenOptions
        value: root.hardenState ? Strings.t("hub.harden." + root.hardenState) : "—"
        focused: root.focusedField === "harden"
        onActivated: if (root.menuLayer) root.menuLayer.openMenu(hardenRow, root.hardenOptions,
                                                                root.hardenState, (id) => {
            root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "kernel-harden", id],
                               () => root.reloadHarden());
        })
    }
    Text {
        width: parent.width
        text: Strings.t("hub.hardenHint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    // Deliberately a line of text and not a HubRow: unlike the Secure Boot one above,
    // this pending step has no action to offer — the cmdline half simply takes effect
    // at the next boot — so giving it a focusable row would put a dead stop in the
    // keyboard roving order.
    Text {
        width: parent.width
        visible: root.hardenPending
        text: Strings.t("hub.hardenReboot")
        color: Colors.accentInk
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
