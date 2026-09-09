// W Linux — Hub Power panel (Ф-power).
// The power-management drill-in: power profile (power-profiles-daemon), the machine
// mode (laptop|desktop) preset, battery charge limit + status, idle timers (lock /
// display / suspend, per AC and battery) and lid/power-button actions — a pure
// front-end over `w-power`. State is read in one shot from `w-power status
// --porcelain`; unprivileged changes (profile, idle timers) run w-power directly, and
// root-domain changes (mode, auto-switch, charge limit, lid, power key) are handed up
// to the Hub via runPrivileged (pkexec + com.w.hub.actuate cap `power-set`), which
// suspends for the polkit prompt and restores + refreshes on exit.
//
// Idle timers are a cascade, lock -> display -> suspend: each link's raw value is
// relative to the previous link firing (not to last activity), enforced by `w-power`'s
// `cascade_at()`. Rows are laid out in that order and each shows the effective absolute
// firing time (from the porcelain `*_AT` keys, already cascaded server-side) as its
// secondary label — this panel does no cascade arithmetic of its own.
//
// Laptop-only controls (auto profile-switch, battery, charge limit, per-battery idle
// timers, lid) show when the machine has a battery OR the user picked laptop mode, so a
// desktop stays lean and switching to laptop reveals the full set. Content scrolls in a
// Flickable; the row dropdown flips upward near the bottom so it never spills past the
// card. Loaded via HubRegistry as a subdir file → shared components via `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // Feeds the card morph; grow to the open (downward) menu's lower edge so it isn't clipped.
    // The +8 mirrors the Flickable's own contentHeight padding below (the focus-wash
    // bleed slack) — without it the card undershoots by exactly that much, so `flick`
    // (sized to this implicitHeight by Hub.qml) is permanently 8px shorter than its
    // own contentHeight and shows a phantom scroll even when the real content fits
    // comfortably under maxCardH (found via live QA on a short panel — InputPanel —
    // where it wasn't masked by genuine overflow the way it is here).
    implicitHeight: Math.max(col.implicitHeight + 8, menuLayer.menuBottom)

    // Up on the topmost roving position hands the cursor to the header's "?" button
    // (Hub.qml's focusHeaderHelp). A route with no `help` entry has no button and the
    // Hub answers false — the cursor simply stays where it is.
    signal focusHeader()

    signal runPrivileged(var cmd, var onDone)

    // ── Keyboard roving-focus (flat list, top→bottom, inside a Flickable) ───────────
    // Same compact-visible-list contract as RootGrid.visTiles: half these rows are
    // conditionally hidden (laptop-only / has-keyboard-light), and the Grid/Column
    // layout already skips them, so the roving order has to track `.visible` too.
    readonly property var focusables: [
        modeRow, profRow, autoRow, batteryRow, chargeRow,
        idleAcLock, idleAcDisplay, idleAcSuspend, idleAcKbd,
        idleBatLock, idleBatDisplay, idleBatSuspend, idleBatKbd,
        lidBatRow, lidAcRow, keyRow
    ]
    readonly property var visFocusables: root.focusables.filter((f) => f.visible)
    property int focusIndex: 0
    onVisFocusablesChanged: root.focusIndex = Math.max(0, Math.min(root.focusIndex, root.visFocusables.length - 1))
    // True while an IdleRow's minute field holds real Qt focus — Up/Down must move
    // the cursor/do nothing there, not steal the roving index (same reasoning as
    // NetworkPanel's hostField guard, generalized over every focusable that exposes
    // an `input`; SelectRow/HubRow don't, so `f.input` is `undefined` for them and
    // the `some()` predicate short-circuits false).
    readonly property bool editingText: root.visFocusables.some((f) => f.input !== undefined && f.input.activeFocus)

    function scrollIntoView(item) {
        if (!item) return;
        const vf = root.visFocusables;
        // The first/last row aren't at the true top/bottom of the Column — a
        // HubSection header sits above modeRow, and other sections/rows sit below
        // keyRow's neighbors — so "bring the row's own bounds into view" (the
        // general case below) would stop short of the panel's actual edge, leaving
        // the header or the trailing space unreachable. Reaching either end of the
        // roving list should reach the true scroll edge, matching what a mouse-drag
        // to the limit already does.
        if (item === vf[0]) { flick.contentY = 0; return; }
        if (item === vf[vf.length - 1]) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        // ±4 so a row's OWN focus-wash bleed (see SelectRow/HubRow) scrolls fully
        // into view too, not just the row's logical bounds.
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }
    function focusRow(i) {
        root.focusIndex = Math.max(0, Math.min(i, root.visFocusables.length - 1));
        root.scrollIntoView(root.visFocusables[root.focusIndex]);
    }

    focus: true
    Keys.onPressed: (e) => {
        if (root.editingText) return;
        const vf = root.visFocusables;
        if (vf.length === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:
            if (root.focusIndex === 0) { root.focusHeader(); e.accepted = true; return; }
            root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = vf[root.focusIndex];
            if (item.input !== undefined) item.input.forceActiveFocus();   // IdleRow: enter edit mode
            else if (item.activated !== undefined) item.activated();        // SelectRow / HubRow
            e.accepted = true;
            return;
        }
        }
    }

    // Idle-timer row: minutes field + Change button. A dropdown of preset minutes can't
    // represent a value set out-of-band (CLI `w-power idle`, AI tool, hand-edited user
    // conf) — it would silently snap to the nearest option. A free-form field always
    // shows the real value. Mirrors SystemPanel's log-retention row (same box+button
    // idiom); commits on Enter or the Change button, not on every keystroke.
    component IdleRow: Item {
        id: idleRow
        required property string glyph
        required property string label
        property string valueSec: "0"   // seconds; "0" = never
        property string atSec: "0"      // effective absolute firing time (cascaded), seconds; "0" = link off
        property bool locked: false     // fleet policy owns this timer (see SelectRow.locked)
        // Keyboard roving-focus indicator, same contract as Tile/SelectRow/HubRow —
        // set by the panel's roving index. Exposed `input` lets the panel forceActiveFocus()
        // straight into the field on Enter; `exitField()` is how the field hands
        // focus back on Tab/Esc (an inline `component` block cannot see the
        // enclosing file's `root` id, so it has to go out through a signal like
        // `apply` already does, not a direct `root.forceActiveFocus()` call).
        property bool focused: false
        // `property var`, not a third `alias` hop (WSettingsField.input is already a
        // two-step alias down to the real TextField) — qmllint's alias resolver doesn't
        // walk a third hop (see quickshell-hub.md's Ф-Keyboard gotcha #9, first caught on
        // NightLightSection's Repeater fields); a JS-expression `var` sidesteps it
        // entirely with the same runtime effect.
        property var input: idleField.input
        signal apply(int sec)
        signal exitField()

        width: parent.width
        implicitHeight: 38
        opacity: locked ? 0.45 : 1

        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: idleRow.focused && !idleField.input.activeFocus
            color: Colors.hover
        }

        readonly property int currentMin: Math.round(parseInt(idleRow.valueSec || "0") / 60)
        readonly property int atMin: Math.round(parseInt(idleRow.atSec || "0") / 60)

        Row {
            id: idleLeft
            anchors {
                left: parent.left
                right: idleField.left; rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 10
            ChromeIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: 22
                glyph: idleRow.glyph
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: idleRow.label
                    color: Colors.text
                    font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                }
                Text {
                    width: Math.max(0, idleLeft.width - 32)
                    text: idleRow.atMin > 0
                          ? (Strings.t("power.idleFires") + " " + idleRow.atMin + " " + Strings.t("power.min"))
                          : Strings.t("power.idleOff")
                    color: Colors.muted
                    font.family: Fonts.family; font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }
        WSettingsField {
            id: idleField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fixedWidth: 56
            numeric: true
            suffix: Strings.t("power.min")
            value: "" + idleRow.currentMin
            // A locked timer must not even accept typing: the setter would refuse,
            // and a field that takes input it cannot commit is worse than a dim one.
            validator: (text) => !idleRow.locked && /^[0-9]+$/.test(text)
            borderWidth: HubConfig.border
            onApplied: (text) => idleRow.apply(parseInt(text) * 60)
            input.Keys.onTabPressed: idleRow.exitField()
            input.Keys.onEscapePressed: idleRow.exitField()
        }

        // Hover-explainer for a locked timer. A SIBLING anchored over the field, never
        // a child of it: WSettingsField is a Row, and an `anchors.fill` child inside a
        // positioner both fights the layout and gets positioned as a real column — it
        // pushed the whole field off the card's right edge.
        MouseArea {
            id: lockMa
            // Mirrors idleField's own anchors rather than `anchors.fill: idleField`:
            // filling a component instance trips qmllint's type resolution.
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: idleField.width
            height: idleField.height
            enabled: idleRow.locked
            hoverEnabled: true
            WToolTip { text: Strings.t("hub.lockedByPolicy"); visible: lockMa.containsMouse }
        }
    }

    // ── State (one porcelain read) ─────────────────────────────────────────────────
    property string mode: ""
    property string source: "ac"
    property bool   hasBattery: false
    property bool   ppdAvail: false
    property string profile: ""
    property var    profiles: []          // what PPD offers HERE (porcelain PROFILES)
    property string autoProfile: "off"
    property string chargeLimit: "100"
    property string lidBattery: "ignore"
    property string lidAc: "ignore"
    property string powerKey: "menu"
    property var    idle: ({ ac: { display: "0", lock: "0", suspend: "0", kbdlight: "0", displayAt: "0", lockAt: "0", suspendAt: "0" },
                             bat: { display: "0", lock: "0", suspend: "0", kbdlight: "0", displayAt: "0", lockAt: "0", suspendAt: "0" } })
    // No keyboard backlight on this machine -> the rows would be dead controls.
    property bool   hasKbdlight: false
    property string batPct: ""
    property string batState: ""
    property string batHealth: ""

    // Show laptop-only controls when a battery exists or the user explicitly chose laptop.
    readonly property bool laptopControls: root.mode === "laptop" || root.hasBattery

    function reload() { statProc.running = false; statProc.running = true; }
    Process {
        id: statProc
        running: true
        command: ["w-power", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const line of (this.text || "").split("\n")) {
                    const m = line.match(/^([A-Z_]+)=(.*)$/);
                    if (m) kv[m[1]] = m[2];
                }
                root.mode = kv.MODE || "";
                root.source = kv.SOURCE || "ac";
                root.hasBattery = kv.HAS_BATTERY === "1";
                root.ppdAvail = kv.PPD_AVAIL === "1";
                root.profile = kv.PROFILE || "";
                // Straight from power-profiles-daemon: `performance` needs a platform
                // driver and is simply absent on a VM or a plain desktop.
                root.profiles = (kv.PROFILES || "").split(" ").filter(p => p.length > 0);
                root.autoProfile = kv.AUTO_PROFILE || "off";
                root.chargeLimit = kv.CHARGE_LIMIT || "100";
                root.lidBattery = kv.LID_ON_BATTERY || "ignore";
                root.lidAc = kv.LID_ON_AC || "ignore";
                root.powerKey = kv.POWER_KEY || "menu";
                root.idle = {
                    ac:  { display: kv.AC_DISPLAY || "0",  lock: kv.AC_LOCK || "0",  suspend: kv.AC_SUSPEND || "0",
                           kbdlight: kv.AC_KBDLIGHT || "0",
                           displayAt: kv.AC_DISPLAY_AT || "0",  lockAt: kv.AC_LOCK_AT || "0",  suspendAt: kv.AC_SUSPEND_AT || "0" },
                    bat: { display: kv.BAT_DISPLAY || "0", lock: kv.BAT_LOCK || "0", suspend: kv.BAT_SUSPEND || "0",
                           kbdlight: kv.BAT_KBDLIGHT || "0",
                           displayAt: kv.BAT_DISPLAY_AT || "0", lockAt: kv.BAT_LOCK_AT || "0", suspendAt: kv.BAT_SUSPEND_AT || "0" },
                };
                root.hasKbdlight = kv.HAS_KBDLIGHT === "1";
                root.batPct = kv.BAT_PCT || "";
                root.batState = kv.BAT_STATE || "";
                root.batHealth = kv.BAT_HEALTH || "";
            }
        }
    }

    // ── The layered-config declaration (w-conf.md) ─────────────────────────────────
    // Two facts this panel used to carry in its own head: WHO may set a key ("idle
    // timers need no root, the lid does") and whether a fleet policy has taken it
    // out of local hands. Both now come from the same schema/policy the reader
    // enforces, so the panel and the backend cannot drift: a knob re-scoped in
    // power.schema changes how the Hub routes it, without a QML edit.
    property var confScope: ({})        // KEY → system | user | both
    property var confLocked: ({})       // KEY → true when /etc/w/policy.d owns it
    Process {
        id: confProc
        running: true
        command: ["w-conf", "list", "power", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const scope = {}, locked = {};
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 5) continue;
                    scope[f[0]] = f[4];
                    if (f[3] === "locked") locked[f[0]] = true;
                }
                root.confScope = scope;
                root.confLocked = locked;
            }
        }
    }
    function isLocked(key) { return root.confLocked[key] === true; }
    function reloadAll() { root.reload(); confProc.running = false; confProc.running = true; }

    // Unprivileged actions (profile switch, idle timers) — run w-power directly, then reload.
    Process { id: userProc; onExited: root.reloadAll() }
    function userRun(cmd) { userProc.running = false; userProc.command = cmd; userProc.running = true; }
    function setPriv(key, val) {
        root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "power-set", key, val],
                           () => root.reloadAll());
    }
    // The idle cascade is the one place where the route is a real choice, and it
    // used to be folklore in this file ("timers need no root, the lid does"). Now
    // the schema decides: a user-scope key goes straight to w-power, and if it is
    // ever re-scoped to `system` the Hub escalates through the `power-set` cap
    // (which covers the cascade for exactly this reason) instead of failing.
    // The remaining knobs — mode, charge limit, lid, power key — write /etc and
    // are root-domain by construction, so they always take the privileged path.
    function setIdle(src, link, sec) {
        const key = (src === "ac" ? "AC_" : "BAT_") + link.toUpperCase();
        if (root.confScope[key] === "user") root.userRun(["w-power", "idle", src, link, "" + sec]);
        else root.setPriv("idle-" + src + "-" + link, "" + sec);
    }

    // ── Label helpers ──────────────────────────────────────────────────────────────
    function actLabel(id) { return Strings.t("power.act." + id); }
    function profLabel(id) { return id ? Strings.t("power.prof." + id) : "—"; }
    function modeLabel(id) { return id ? Strings.t("power.mode." + id) : "—"; }
    function onOffLabel(id) { return Strings.t("power." + id); }
    function actOptions(keys) { return keys.map(k => ({ id: k, label: actLabel(k) })); }

    // ── Layout (scrolls; menuLayer sits above it, sized to the viewport) ─────────────
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: -12                 // pill near the window edge; col insets the same
        // Mirrors the right-side scrollbar convention (quickshell-hub.md's "Соглашение
        // о позиции скроллбара"), just on the left: `clip:true` cuts anything outside
        // Flickable's OWN rect, and every row's keyboard-focus wash bleeds -8 past its
        // own left edge (SelectRow/HubRow/IdleRow) — without this, that bleed lands at
        // negative x and gets clipped to nothing. `col` insets the same 8 so visible
        // content doesn't shift; only the bleed lane grows.
        anchors.leftMargin: -8
        clip: true
        // 4px of slack at each end so the first/last row's keyboard-focus wash (its
        // -4 top/bottom bleed, see SelectRow/HubRow) has room to scroll into view —
        // NOT via Flickable's own topMargin/bottomMargin: those turned out to trigger
        // Qt Quick's "center content when it + margins fit the viewport" behavior,
        // which silently offset the RESTING scroll position to -4 instead of 0 (found
        // live via a headless probe tracing contentY — see dev-workflow.md's headless-
        // instance technique). Plain contentHeight+8 with `col` inset by 4 has no such
        // special-case: content still rests flush at contentY=0, only the reachable
        // range grows symmetrically.
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: col
            x: 8
            y: 4                                  // matching 4px reserved above (see contentHeight)
            width: flick.width - 12 - 8           // flick.width, NOT parent.width: a Flickable child's
            spacing: 12                          // parent is the internal contentItem (width unreliable)

            // Machine mode.
            HubSection { width: parent.width; text: Strings.t("power.machine") }
            SelectRow {
                id: modeRow
                width: parent.width
                icon: "computer"; glyph: String.fromCodePoint(0xf0379)   // nf-md-laptop
                label: Strings.t("power.modeLabel")
                currentId: root.mode
                value: root.modeLabel(root.mode)
                options: [{ id: "laptop", label: root.modeLabel("laptop") }, { id: "desktop", label: root.modeLabel("desktop") }]
                focused: root.focusIndex === root.visFocusables.indexOf(modeRow)
                onActivated: menuLayer.openMenu(modeRow, options, root.mode, (id) => root.setPriv("mode", id))
            }

            // Power profile + (laptop) auto-switch.
            HubSection { width: parent.width; text: Strings.t("power.profileSec") }
            SelectRow {
                id: profRow
                width: parent.width
                icon: "power-profile-balanced"; glyph: String.fromCodePoint(0xf0241)   // nf-md-flash
                label: Strings.t("power.profileLabel")
                enabled: root.ppdAvail && root.profiles.length > 0
                currentId: root.profile
                value: root.ppdAvail ? root.profLabel(root.profile) : "—"
                options: root.profiles.map(p => ({ id: p, label: root.profLabel(p) }))
                focused: root.focusIndex === root.visFocusables.indexOf(profRow)
                onActivated: menuLayer.openMenu(profRow, options, root.profile, (id) => root.userRun(["w-power", "profile", id]))
            }
            SelectRow {
                id: autoRow
                width: parent.width
                visible: root.laptopControls          // meaningless without a battery to switch on
                icon: "view-refresh"; glyph: String.fromCodePoint(0xf0450)   // nf-md-autorenew
                label: Strings.t("power.autoLabel")
                currentId: root.autoProfile
                value: root.onOffLabel(root.autoProfile)
                options: [{ id: "on", label: root.onOffLabel("on") }, { id: "off", label: root.onOffLabel("off") }]
                locked: root.isLocked("AUTO_PROFILE")
                lockedHint: Strings.t("hub.lockedByPolicy")
                focused: root.focusIndex === root.visFocusables.indexOf(autoRow)
                onActivated: menuLayer.openMenu(autoRow, options, root.autoProfile, (id) => root.setPriv("auto", id))
            }

            // Battery (laptop). Status row needs real battery data; charge limit shows in laptop mode.
            HubSection { width: parent.width; text: Strings.t("power.batterySec"); visible: root.laptopControls }
            HubRow {
                id: batteryRow
                width: parent.width
                visible: root.hasBattery
                icon: "battery"; glyph: String.fromCodePoint(0xf0079)   // nf-md-battery
                label: Strings.t("power.batteryStatus")
                value: root.batPct ? (root.batPct + "%  ·  " + (root.batState || "")
                        + (root.batHealth ? ("  ·  " + Strings.t("power.health") + " " + root.batHealth + "%") : "")) : "—"
                focused: root.focusIndex === root.visFocusables.indexOf(batteryRow)
            }
            SelectRow {
                id: chargeRow
                width: parent.width
                visible: root.laptopControls
                icon: "battery-charging"; glyph: String.fromCodePoint(0xf0e2c)   // nf-md-battery_heart
                label: Strings.t("power.chargeLabel")
                currentId: root.chargeLimit
                value: root.chargeLimit === "100" ? Strings.t("power.chargeFull") : (root.chargeLimit + "%")
                options: [{ id: "100", label: Strings.t("power.chargeFull") }, { id: "80", label: "80%" }]
                locked: root.isLocked("CHARGE_LIMIT")
                lockedHint: Strings.t("hub.lockedByPolicy")
                focused: root.focusIndex === root.visFocusables.indexOf(chargeRow)
                onActivated: menuLayer.openMenu(chargeRow, options, root.chargeLimit, (id) => root.setPriv("charge-limit", id))
            }

            // Idle timers — on AC (always relevant). Cascade order: lock -> display -> suspend.
            HubSection { width: parent.width; text: Strings.t("power.idleAc") }
            IdleRow {
                id: idleAcLock
                glyph: String.fromCodePoint(0xf033e)
                label: Strings.t("power.lockT")
                valueSec: root.idle.ac.lock
                atSec: root.idle.ac.lockAt
                locked: root.isLocked("AC_LOCK")
                focused: root.focusIndex === root.visFocusables.indexOf(idleAcLock)
                onApply: (sec) => root.setIdle("ac", "lock", sec)
                onExitField: root.forceActiveFocus()
            }
            IdleRow {
                id: idleAcDisplay
                glyph: String.fromCodePoint(0xf0379)
                label: Strings.t("power.display")
                valueSec: root.idle.ac.display
                atSec: root.idle.ac.displayAt
                locked: root.isLocked("AC_DISPLAY")
                focused: root.focusIndex === root.visFocusables.indexOf(idleAcDisplay)
                onApply: (sec) => root.setIdle("ac", "display", sec)
                onExitField: root.forceActiveFocus()
            }
            IdleRow {
                id: idleAcSuspend
                glyph: String.fromCodePoint(0xf04b2)   // nf-md-power_sleep
                label: Strings.t("power.suspendT")
                valueSec: root.idle.ac.suspend
                atSec: root.idle.ac.suspendAt
                locked: root.isLocked("AC_SUSPEND")
                focused: root.focusIndex === root.visFocusables.indexOf(idleAcSuspend)
                onApply: (sec) => root.setIdle("ac", "suspend", sec)
                onExitField: root.forceActiveFocus()
            }
            // Not a cascade link: its own timer from last activity, so atSec is
            // simply its own value. Hidden on machines with no keyboard light.
            IdleRow {
                id: idleAcKbd
                visible: root.hasKbdlight
                glyph: String.fromCodePoint(0xf030c)   // nf-md-keyboard
                label: Strings.t("power.kbdOff")
                valueSec: root.idle.ac.kbdlight
                atSec: root.idle.ac.kbdlight
                locked: root.isLocked("AC_KBDLIGHT")
                focused: root.focusIndex === root.visFocusables.indexOf(idleAcKbd)
                onApply: (sec) => root.setIdle("ac", "kbdlight", sec)
                onExitField: root.forceActiveFocus()
            }

            // Idle timers — on battery (laptop). Same cascade order.
            HubSection { width: parent.width; text: Strings.t("power.idleBattery"); visible: root.laptopControls }
            IdleRow {
                id: idleBatLock
                visible: root.laptopControls
                glyph: String.fromCodePoint(0xf033e)
                label: Strings.t("power.lockT")
                valueSec: root.idle.bat.lock
                atSec: root.idle.bat.lockAt
                locked: root.isLocked("BAT_LOCK")
                focused: root.focusIndex === root.visFocusables.indexOf(idleBatLock)
                onApply: (sec) => root.setIdle("bat", "lock", sec)
                onExitField: root.forceActiveFocus()
            }
            IdleRow {
                id: idleBatDisplay
                visible: root.laptopControls
                glyph: String.fromCodePoint(0xf0379)
                label: Strings.t("power.display")
                valueSec: root.idle.bat.display
                atSec: root.idle.bat.displayAt
                locked: root.isLocked("BAT_DISPLAY")
                focused: root.focusIndex === root.visFocusables.indexOf(idleBatDisplay)
                onApply: (sec) => root.setIdle("bat", "display", sec)
                onExitField: root.forceActiveFocus()
            }
            IdleRow {
                id: idleBatSuspend
                visible: root.laptopControls
                glyph: String.fromCodePoint(0xf04b2)
                label: Strings.t("power.suspendT")
                valueSec: root.idle.bat.suspend
                atSec: root.idle.bat.suspendAt
                locked: root.isLocked("BAT_SUSPEND")
                focused: root.focusIndex === root.visFocusables.indexOf(idleBatSuspend)
                onApply: (sec) => root.setIdle("bat", "suspend", sec)
                onExitField: root.forceActiveFocus()
            }
            IdleRow {
                id: idleBatKbd
                visible: root.laptopControls && root.hasKbdlight
                glyph: String.fromCodePoint(0xf030c)
                label: Strings.t("power.kbdOff")
                valueSec: root.idle.bat.kbdlight
                atSec: root.idle.bat.kbdlight
                locked: root.isLocked("BAT_KBDLIGHT")
                focused: root.focusIndex === root.visFocusables.indexOf(idleBatKbd)
                onApply: (sec) => root.setIdle("bat", "kbdlight", sec)
                onExitField: root.forceActiveFocus()
            }

            // Lid actions (laptop).
            HubSection { width: parent.width; text: Strings.t("power.lidSec"); visible: root.laptopControls }
            SelectRow {
                id: lidBatRow
                width: parent.width; visible: root.laptopControls
                icon: "computer"; glyph: String.fromCodePoint(0xf0379)
                label: Strings.t("power.lidBattery")
                currentId: root.lidBattery
                value: root.actLabel(root.lidBattery)
                options: root.actOptions(["suspend", "lock", "ignore"])
                locked: root.isLocked("LID_ON_BATTERY")
                lockedHint: Strings.t("hub.lockedByPolicy")
                focused: root.focusIndex === root.visFocusables.indexOf(lidBatRow)
                onActivated: menuLayer.openMenu(lidBatRow, options, root.lidBattery, (id) => root.setPriv("lid-battery", id))
            }
            SelectRow {
                id: lidAcRow
                width: parent.width; visible: root.laptopControls
                icon: "computer"; glyph: String.fromCodePoint(0xf0379)
                label: Strings.t("power.lidAc")
                currentId: root.lidAc
                value: root.actLabel(root.lidAc)
                options: root.actOptions(["suspend", "lock", "ignore"])
                locked: root.isLocked("LID_ON_AC")
                lockedHint: Strings.t("hub.lockedByPolicy")
                focused: root.focusIndex === root.visFocusables.indexOf(lidAcRow)
                onActivated: menuLayer.openMenu(lidAcRow, options, root.lidAc, (id) => root.setPriv("lid-ac", id))
            }

            // Power button (always).
            HubSection { width: parent.width; text: Strings.t("power.buttonSec") }
            SelectRow {
                id: keyRow
                width: parent.width
                icon: "system-shutdown"; glyph: String.fromCodePoint(0xf0425)   // nf-md-power
                label: Strings.t("power.keyLabel")
                currentId: root.powerKey
                value: root.actLabel(root.powerKey)
                options: root.actOptions(["menu", "suspend", "poweroff", "ignore"])
                locked: root.isLocked("POWER_KEY")
                lockedHint: Strings.t("hub.lockedByPolicy")
                focused: root.focusIndex === root.visFocusables.indexOf(keyRow)
                onActivated: menuLayer.openMenu(keyRow, options, root.powerKey, (id) => root.setPriv("power-key", id))
            }
        }
    }

    // ── Dropdown overlay layer (above the content; sized to the viewport) ─────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; flipUp: true; returnFocusTo: root }
}
