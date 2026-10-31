// W Linux — Hub Security section (the System panel's "Security" tab).
// Three disk/boot controls on an encrypted (Limine) install — Secure Boot, automatic
// disk unlock (TPM2) and the recovery key — plus the kernel hardening profile, which
// exists on every install.
//
// ── Secure Boot is a walk-through, not a switch ──────────────────────────────────
// "Secure Boot on" is two things in two places: W's chain (sbctl keys, W's key in
// MokList or the firmware, a signed Limine carrying its config hash) and the
// firmware's switch. The firmware switch alone does not make W boot — W must be ready
// first; and turning it off goes the other way round (with factory keys W boots only
// through shim, so the firmware goes first). Between them sit reboots and, for shim,
// a MokManager visit. So the row shows where the machine is (from `w-secureboot status
// --porcelain`, unprivileged) and a line naming the next step, and its menu offers only
// the actions that make sense from there — prepare, reboot, reboot into the firmware
// setup, finish, retry a lost key request, turn off in W. The state lives in the
// system across the reboots; the row only reads it back.
//
// ── Automatic unlock and the recovery key are their own rows ─────────────────────
// TPM2 is sealed to PCR7, which only tells W's boot chain from a stranger's USB stick
// while Secure Boot is enforced — so the TPM row stays locked until then, and Secure
// Boot never enrolls TPM2 by itself (w-secureboot only re-seals an existing seal). A
// laptop is told that TPM-only unlock boots a stolen laptop up to the login screen and
// offered TPM2 + PIN instead. Turning Secure Boot off removes TPM2 (w-secureboot
// disable), which the Secure Boot hint says out loud.
//
// Both rows read `w-crypt status --porcelain`, which needs root (the LUKS header is
// root-only). That read is privileged the way the Rollback tab's snapshot list is: one
// `pkexec … crypt-status` per tab entry, as this section's own tracked Process, inside
// the Overlays.suspended bracket. Cancelling the prompt leaves the Secure Boot and
// hardening rows working; the two disk rows say so and retry on activation.
//
// ── Two execution idioms side by side ────────────────────────────────────────────
// Everything that asks for the disk passphrase, a new PIN, or prints a MokManager code
// or a recovery key runs in a terminal that stays open (Term.execHold — the output IS
// the point) and closes the Hub. Removing the TPM2 seal asks nothing: it goes through
// this section's privileged Process and updates the row from its exit code instead of
// a second prompt for a re-read. Hardening is instant actuation through the Hub's
// runPrivileged bracket, the same idiom as the Date & Time section's NTP toggle.
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
    // SystemPanel, which owns the probe. Without it only the hardening row exists.
    property bool limineAvailable: false

    // Instant privileged actuation handed up to the Hub (suspend for the polkit prompt,
    // restore, re-read on exit). Re-emitted by SystemPanel: the Hub's Connections sees
    // only the top-level panel, never a signal from inside a nested Loader.
    signal runPrivileged(var cmd, var onDone)

    // ── Remote control surface (roving index lives in SystemPanel) ──────────────────
    property string focusedField: ""
    readonly property var fields: (root.limineAvailable ? ["sb", "tpm", "recovery"] : []).concat(["harden"])
    function rowItem(field) {
        if (field === "sb") return sbRow;
        if (field === "tpm") return tpmRow;
        if (field === "recovery") return recRow;
        if (field === "harden") return hardenRow;
        return null;
    }
    function activateField(field) {
        const it = root.rowItem(field);
        if (it && it.activated !== undefined) it.activated();
    }

    // A privileged, interactive command in a terminal that stays open, then close the Hub.
    function runTerm(argv) {
        Quickshell.execDetached(Term.execHold(["pkexec", "/usr/lib/w/w-hub-actuate"].concat(argv)));
        Overlays.close("hub");
    }
    function sessionExit(action) { Quickshell.execDetached(["w-session-exit", action]); Overlays.close("hub"); }

    // ── Secure Boot state (w-secureboot status --porcelain) ─────────────────────────
    property string sbState: ""        // "on" | "off" | "unsupported" | "" (not read yet)
    property string sbFirmware: ""     // "yes" | "no" — the firmware enforces Secure Boot
    property string sbSetup: ""        // "yes" — the firmware is in Setup Mode
    property string tpmPending: "no"   // "no" | "reboot_needed" | "ready"
    property string sbMode: "none"     // "own" | "shim" | "none" — who trusts W's key
    property string sbMok: "na"        // "yes" | "no" | "unknown" | "na" — W's key in MokList
    readonly property bool sbUnsupported: root.sbState === "unsupported"
    // The one state in which PCR7 tells W's boot chain from anyone else's.
    readonly property bool sbEnforced: root.sbState === "on" && root.sbFirmware === "yes" && root.tpmPending === "no"
    Process {
        id: sbRead
        // limineAvailable arrives asynchronously from SystemPanel, which starts this.
        running: root.limineAvailable
        command: ["w-secureboot", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Header row + one data row; skip the header, split the rest on tabs.
                const lines = (this.text || "").split("\n").filter(l => l.length > 0);
                const f = lines.length >= 2 ? lines[1].split("\t") : [];
                root.sbState = f[0] || "";
                root.sbFirmware = f[1] || "";
                root.sbSetup = f[2] || "";
                root.tpmPending = f[3] || "no";
                root.sbMode = f[4] || "none";
                root.sbMok = f[6] || "na";
            }
        }
    }

    // Can logind reboot straight into the firmware setup (OsIndications)? Unprivileged.
    property bool canFirmwareSetup: false
    Process {
        running: root.limineAvailable
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "CanRebootToFirmwareSetup"]
        stdout: StdioCollector { onStreamFinished: root.canFirmwareSetup = (this.text || "").trim() === "s \"yes\"" }
    }

    // Where the walk-through stands: the row's value, the next-step line, the menu.
    readonly property var sbPlan: {
        const modeName = Strings.t("hub.secureBoot.mode." + root.sbMode);
        const fw = root.canFirmwareSetup ? ["firmware"] : [];
        if (root.sbState === "off")
            return { value: Strings.t("hub.secureBoot.off"),
                     step: Strings.t(root.sbSetup === "yes" ? "hub.secureBoot.step.prepareOwn" : "hub.secureBoot.step.prepare"),
                     actions: ["prepare"] };
        if (root.sbState !== "on") return { value: "—", step: "", actions: [] };
        const prepared = Strings.t("hub.secureBoot.prepared") + " · " + modeName;
        if (root.tpmPending === "reboot_needed")
            return { value: prepared,
                     step: Strings.t(root.sbMode === "shim" ? "hub.secureBoot.step.rebootMok" : "hub.secureBoot.step.reboot"),
                     actions: ["reboot", "disable"] };
        if (root.sbMode === "shim" && root.sbMok === "no")
            return { value: prepared, step: Strings.t("hub.secureBoot.step.mokLost"), actions: ["retry", "disable"] };
        if (root.sbFirmware !== "yes")
            return { value: prepared, step: Strings.t("hub.secureBoot.step.firmwareOn"), actions: fw.concat(["disable"]) };
        if (root.tpmPending === "ready")
            return { value: prepared, step: Strings.t("hub.secureBoot.step.finish"), actions: ["finish"] };
        // On. shim: W boots only through shim while the firmware enforces its factory
        // keys, so turning off starts in the firmware (w-secureboot disable refuses).
        return { value: Strings.t("hub.secureBoot.on") + " · " + modeName,
                 step: root.sbMode === "shim" ? Strings.t("hub.secureBoot.step.offShim") : "",
                 actions: root.sbMode === "shim" ? fw : ["disable"] };
    }
    readonly property var sbOptions: root.sbPlan.actions.map((a) => ({ id: a, label: Strings.t("hub.secureBoot.act." + a) }))
    function sbAct(a) {
        if (a === "prepare" || a === "finish" || a === "retry") root.runTerm(["secureboot", "on"]);
        else if (a === "disable") root.runTerm(["secureboot", "off"]);
        else if (a === "reboot") root.sessionExit("reboot");
        else if (a === "firmware") root.sessionExit("firmware");
    }

    // ── Disk unlock factors (pkexec … crypt-status → w-crypt status --porcelain) ────
    property string cryptRead: ""     // "" (reading) | "ok" | "failed"
    property bool   tpmDevice: false
    property string tpm2: "none"      // "none" | "tpm" | "pin"
    property string reseal: "no"      // "no" | "pending" | "stale" | "unknown"
    property bool   recoveryKey: false
    property bool   privBusy: false   // our own pkexec is up (owns Overlays.suspended)
    property bool   portable: false   // laptop/convertible/tablet — TPM-only warning, PIN first
    Process {
        id: cryptProc
        property string op: ""        // "read" | "off"
        stdout: StdioCollector {
            onStreamFinished: {
                if (cryptProc.op !== "read") return;
                const lines = (this.text || "").split("\n").filter(l => l.length > 0);
                const f = lines.length >= 2 ? lines[1].split("\t") : [];
                if (f.length < 6) return;
                root.tpmDevice = f[1] === "yes";
                root.tpm2 = f[2];
                root.recoveryKey = f[4] === "yes";
                root.reseal = f[5];
                root.cryptRead = "ok";
            }
        }
        onExited: (code) => {
            root.privBusy = false;
            Overlays.suspended = false;
            if (cryptProc.op === "read" && root.cryptRead !== "ok") root.cryptRead = "failed";
            if (cryptProc.op === "off" && code === 0) { root.tpm2 = "none"; root.reseal = "no"; }
        }
    }
    function cryptRun(op, argv) {
        root.privBusy = true;
        Overlays.suspended = true;
        cryptProc.running = false;
        cryptProc.op = op;
        cryptProc.command = ["pkexec", "/usr/lib/w/w-hub-actuate"].concat(argv);
        cryptProc.running = true;
    }
    function loadCrypt() { root.cryptRead = ""; root.cryptRun("read", ["crypt-status"]); }
    // limineAvailable is pushed in by SystemPanel's Binding after creation, so its one
    // false → true change is the tab entry — exactly one prompt per entry.
    onLimineAvailableChanged: if (root.limineAvailable) root.loadCrypt()
    // A section destroyed with our prompt up never reaches onExited — don't leave the
    // Hub hidden. Gated on OUR process: the auth card owns the flag while it is up.
    Component.onDestruction: if (root.privBusy) Overlays.suspended = false
    Process {
        running: root.limineAvailable
        command: ["hostnamectl", "chassis"]
        stdout: StdioCollector {
            onStreamFinished: root.portable = ["laptop", "convertible", "tablet", "handset"].indexOf((this.text || "").trim()) >= 0
        }
    }

    readonly property bool tpmLocked: root.cryptRead === "ok"
                                      && (!root.tpmDevice || (root.tpm2 === "none" && !root.sbEnforced))
    // Without Secure Boot enforced only the ways back are offered for an existing seal
    // (one made from the CLI with --no-secureboot, or by an unattended install).
    readonly property var tpmOptions: {
        let o = [{ id: "none", label: Strings.t("hub.tpm.none") }];
        if (root.sbEnforced) {
            const tpm = { id: "tpm", label: Strings.t("hub.tpm.tpm") };
            const pin = { id: "pin", label: Strings.t(root.portable ? "hub.tpm.pinRecommended" : "hub.tpm.pin") };
            o = o.concat(root.portable ? [pin, tpm] : [tpm, pin]);
        }
        if (root.tpm2 !== "none") o.push({ id: "reseal", label: Strings.t("hub.tpm.reseal") });
        return o;
    }
    function tpmAct(id) {
        if (id === root.tpm2) return;
        if (id === "none") root.cryptRun("off", ["crypt", "tpm-off"]);
        else if (id === "tpm") root.runTerm(["crypt", "tpm-on"]);
        else if (id === "pin") root.runTerm(["crypt", "tpm-pin"]);
        else if (id === "reseal") root.runTerm(["crypt", "tpm-reseal"]);
    }
    readonly property string cryptValueFallback: root.cryptRead === "failed" ? Strings.t("hub.crypt.noAccess")
                                                 : root.cryptRead === "" ? "…" : ""

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
        enabled: root.sbState !== "" && root.sbOptions.length > 0
        locked: root.sbUnsupported
        lockedHint: Strings.t("hub.secureBootUnsupportedHint")
        currentId: ""
        options: root.sbOptions
        value: root.sbUnsupported ? Strings.t("hub.secureBootUnsupported") : root.sbPlan.value
        focused: root.focusedField === "sb"
        onActivated: if (root.menuLayer && sbRow.interactive)
            root.menuLayer.openMenu(sbRow, root.sbOptions, "", (id) => root.sbAct(id))
    }
    // The next step, in accent ink — what the row's menu is about to do, or what has to
    // happen outside W (a reboot, the blue MokManager screen, the firmware setup).
    Text {
        width: parent.width
        visible: root.limineAvailable && !root.sbUnsupported && root.sbPlan.step !== ""
        text: root.sbPlan.step
        color: Colors.accentInk
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    Text {
        width: parent.width
        visible: root.limineAvailable
        text: Strings.t("hub.secureBootHint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // ── Disk unlock ────────────────────────────────────────────────────────────────
    HubSection {
        width: parent.width
        visible: root.limineAvailable
        text: Strings.t("hub.crypt")
    }
    SelectRow {
        id: tpmRow
        width: parent.width
        visible: root.limineAvailable
        icon: "security-medium"; glyph: String.fromCodePoint(0xf061a)   // nf-md-chip
        label: Strings.t("hub.tpm")
        enabled: root.cryptRead !== ""
        locked: root.tpmLocked
        lockedHint: Strings.t(root.tpmDevice ? "hub.tpm.needSecureBoot" : "hub.tpm.noDevice")
        currentId: root.tpm2
        options: root.tpmOptions
        value: root.cryptValueFallback
               || (!root.tpmDevice ? Strings.t("hub.tpm.noDeviceShort") : Strings.t("hub.tpm.value." + root.tpm2))
        focused: root.focusedField === "tpm"
        onActivated: {
            if (root.cryptRead === "failed") { root.loadCrypt(); return; }
            if (root.menuLayer && tpmRow.interactive)
                root.menuLayer.openMenu(tpmRow, root.tpmOptions, root.tpm2, (id) => root.tpmAct(id));
        }
    }
    Text {
        width: parent.width
        visible: root.limineAvailable && root.cryptRead === "ok" && (root.reseal === "stale" || root.reseal === "pending")
        text: Strings.t("hub.tpm.reseal." + root.reseal)
        color: Colors.accentInk
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    Text {
        width: parent.width
        visible: root.limineAvailable
        text: Strings.t("hub.tpmHint") + (root.portable ? " " + Strings.t("hub.tpmHintLaptop") : "")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    HubRow {
        id: recRow
        width: parent.width
        visible: root.limineAvailable
        icon: "dialog-password"; glyph: String.fromCodePoint(0xf087e)   // nf-md-lifebuoy
        label: Strings.t("hub.recovery")
        sublabel: Strings.t("hub.recoveryHint")
        value: root.cryptValueFallback || Strings.t(root.recoveryKey ? "hub.recovery.yes" : "hub.recovery.no")
        actionText: root.cryptRead === "ok" ? Strings.t(root.recoveryKey ? "hub.recovery.replace" : "hub.recovery.add")
                    : root.cryptRead === "failed" ? Strings.t("hub.crypt.retry") : ""
        focused: root.focusedField === "recovery"
        onActivated: {
            if (root.cryptRead === "failed") root.loadCrypt();
            else if (root.cryptRead === "ok") root.runTerm(["crypt", root.recoveryKey ? "recovery-replace" : "recovery-add"]);
        }
    }

    // ── Kernel hardening (w-kernel harden) ─────────────────────────────────────────
    property string hardenState: ""      // "on" | "off" | "mixed" | "" (not read yet)
    property bool   hardenPending: false
    readonly property var hardenOptions: [
        { id: "off", label: Strings.t("hub.harden.off") },
        { id: "on",  label: Strings.t("hub.harden.on") },
    ]
    // Unprivileged, and re-read explicitly after our own setter exits (runPrivileged's
    // onDone) rather than watched: nothing else changes the profile while the panel is
    // up. `pending` is the configured cmdline disagreeing with /proc/cmdline — the boot
    // half of the profile only lands on the next boot, and `off` additionally leaves
    // already-applied sysctl values in the running kernel, which the hint says out loud.
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
    // Deliberately a line of text and not a HubRow: this pending step has no action to
    // offer — the cmdline half simply takes effect at the next boot — so giving it a
    // focusable row would put a dead stop in the keyboard roving order.
    Text {
        width: parent.width
        visible: root.hardenPending
        text: Strings.t("hub.hardenReboot")
        color: Colors.accentInk
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
