// W Linux — Hub Input panel (Ф5 keyboard + the pointer segments).
// A segmented switch (Keyboard | Mouse | Touchpad) at the top picks what is being
// edited; the Touchpad segment only exists on a machine that has one (`w-pointer
// status`'s touchpad_present, answered by udev — so it is honest even before the
// device is known to Hyprland by name).
//
// Keyboard segment: the live XKB layout ring (kb_layout + kb_variant) — rows list the
// ring's layouts by full human name including variant ("Russian (Macintosh)") via the
// shared Xkb registry, with the active one highlighted (Hyprland `activelayout`, the
// same live source as the bar block), each row removable, an "Add language…" drill-in
// to the searchable picker, the XKB group-toggle preset dropdown, plus key auto-repeat
// and NumLock. Backend: user-space `w-keyboard`.
//
// Mouse / Touchpad segments: a pure front-end over `w-pointer` (speed, acceleration,
// scrolling, tap/click behaviour, drag modes and the workspace-swipe gesture). Their
// rows are data-driven (`settingRows`) rather than 20 hand-written blocks — one
// descriptor list, one delegate that renders either a dropdown row or a slider row.
// Touchpad speed / acceleration / on-off are per-DEVICE settings in Hyprland (there is
// no input.touchpad key for them), so they need the touchpad's device name: the panel
// runs `w-pointer detect` once when the segment is first opened without one, and hides
// those three rows while the name is still unknown.
//
// Neither backend is privileged — the Hyprland session is the user's own, so there is
// no polkit anywhere here. (The system language / locale lives in the System panel: it
// is system-wide and relogin-gated.)
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/InputPanel.qml"}); as a
// subdir file it is not a module type, so the shared hub components come in through
// `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // topCol (fixed: segment switch) + col (scrolling rows), with the dropdown able to
    // grow the card further (menuLayer.menuBottom) — same contract as DisplaysPanel.
    // +8 mirrors the Flickable's contentHeight padding below (focus-wash bleed slack,
    // quickshell-hub.md gotcha 6).
    implicitHeight: Math.max(topCol.implicitHeight + 12 + col.implicitHeight + 8, menuLayer.menuBottom)

    // Drill into a deeper Hub route (the layout picker).
    signal navigate(var route)

    component Pill: WPill { borderWidth: HubConfig.border }

    // ── Backing state ────────────────────────────────────────────────────────────
    property string scope: "keyboard"          // keyboard | mouse | touchpad

    // Keyboard ring (authoritative: w-keyboard status)
    property var    codes: []                  // ordered layout codes, e.g. ["us","ru"]
    property var    variants: []               // parallel variant per slot ("" | "mac" …)
    property string layoutFull: ""             // active layout's full XKB name
    property string toggleId: "grp:alt_shift_toggle"
    property int    repeatRate: 25
    property int    repeatDelay: 600
    property bool   numlock: false
    readonly property string activeCode: Xkb.codeOf(layoutFull)

    // Pointer config (authoritative: w-pointer status --porcelain), key → raw value
    // exactly as the CLI stores it ("0.3" / "true" / "adaptive"), so a dropdown option
    // id and a `w-pointer set` argument are the same string.
    property var    ptr: ({})
    property bool   touchpadPresent: false
    property var    touchpadDevices: []
    readonly property bool padsKnown: root.touchpadDevices.length > 0
    function pv(key, fallback) { const v = root.ptr[key]; return v === undefined ? fallback : v; }
    function pnum(key, fallback) { const v = parseFloat(root.pv(key, "")); return isNaN(v) ? fallback : v; }

    // Display order is alphabetical and STABLE across a default change — `codes[0]`
    // (the ring order w-keyboard persists) still names the default, but its row doesn't
    // jump to the top when it changes (found in live QA: reordering the whole list made
    // the change easy to miss).
    readonly property var sortedCodes: { const a = root.codes.slice(); a.sort(); return a; }
    // `variants` is parallel to `codes` (ring order), not `sortedCodes`.
    function variantFor(code) { const i = root.codes.indexOf(code); return i >= 0 ? root.variants[i] : ""; }

    // ── Option sets ──────────────────────────────────────────────────────────────
    readonly property var onOff: [
        { id: "true",  label: Strings.t("ptr.on") },
        { id: "false", label: Strings.t("ptr.off") }
    ]
    readonly property var accelOpts: [
        { id: "adaptive", label: Strings.t("ptr.accel.adaptive") },
        { id: "flat",     label: Strings.t("ptr.accel.flat") }
    ]
    readonly property var tapMapOpts: [
        { id: "lrm", label: Strings.t("ptr.tapMap.lrm") },
        { id: "lmr", label: Strings.t("ptr.tapMap.lmr") }
    ]
    readonly property var clickOpts: [
        { id: "false", label: Strings.t("ptr.click.areas") },
        { id: "true",  label: Strings.t("ptr.click.fingers") }
    ]
    readonly property var dragLockOpts: [
        { id: "0", label: Strings.t("ptr.off") },
        { id: "1", label: Strings.t("ptr.dragLock.timeout") },
        { id: "2", label: Strings.t("ptr.dragLock.sticky") }
    ]
    readonly property var drag3fgOpts: [
        { id: "0", label: Strings.t("ptr.off") },
        { id: "1", label: Strings.t("ptr.fingers3") },
        { id: "2", label: Strings.t("ptr.fingers4") }
    ]
    readonly property var swipeOpts: [
        { id: "0", label: Strings.t("ptr.off") },
        { id: "3", label: Strings.t("ptr.fingers3") },
        { id: "4", label: Strings.t("ptr.fingers4") }
    ]
    // Curated common layout-switch presets. `warn` = i18n key for a caveat shown under
    // the row (empty = none). The switch key lives at the XKB level (kb_options), NOT as
    // a Hyprland bind — pure modifier combos can't be expressed as a bind, so it gets a
    // dropdown here rather than the Hotkeys rebind machinery.
    readonly property var togglePresets: [
        { id: "grp:alt_shift_toggle",  label: Strings.t("kbtoggle.alt_shift"),  warn: "" },
        { id: "grp:ctrl_shift_toggle", label: Strings.t("kbtoggle.ctrl_shift"), warn: "" },
        { id: "grp:toggle",            label: Strings.t("kbtoggle.ralt"),       warn: "kbtoggle.warnRalt" },
        { id: "grp:shifts_toggle",     label: Strings.t("kbtoggle.shifts"),     warn: "" },
        { id: "grp:ctrl_space_toggle", label: Strings.t("kbtoggle.ctrl_space"), warn: "kbtoggle.warnCtrlSpace" },
        { id: "grp:win_space_toggle",  label: Strings.t("kbtoggle.win_space"),  warn: "kbtoggle.warnWinSpace" }
    ]
    function toggleLabel(id) {
        for (const p of root.togglePresets) if (p.id === id) return p.label;
        return id;   // an out-of-catalog toggle: show its raw id rather than nothing
    }
    readonly property string toggleWarn: {
        for (const p of root.togglePresets) if (p.id === root.toggleId) return p.warn;
        return "";
    }
    function labelOf(options, id) {
        for (const o of options) if (o.id === id) return o.label;
        return id;
    }

    // ── Pointer rows (data-driven) ───────────────────────────────────────────────
    // One descriptor per rendered row; `section` rows are headers and are skipped by
    // the roving cursor. Keys are the `w-pointer` keys verbatim, so a pick or a slider
    // release is `w-pointer set <key> <value>` with no translation table.
    readonly property var settingRows: {
        if (root.scope === "mouse") {
            return [
                { kind: "section", key: "m.sec1", label: Strings.t("ptr.secSpeed") },
                { kind: "slider", key: "mouse.sensitivity", label: Strings.t("ptr.speed"),
                  from: -1, to: 1, step: 0.1, decimals: 1, suffix: "" },
                { kind: "select", key: "mouse.accel_profile", label: Strings.t("ptr.accel"), options: root.accelOpts },
                { kind: "select", key: "mouse.natural_scroll", label: Strings.t("ptr.naturalScroll"), options: root.onOff },
                { kind: "slider", key: "mouse.scroll_factor", label: Strings.t("ptr.scrollSpeed"),
                  from: 0.2, to: 3, step: 0.05, decimals: 2, suffix: "×" },
                { kind: "section", key: "m.sec2", label: Strings.t("ptr.secButtons") },
                { kind: "select", key: "mouse.left_handed", label: Strings.t("ptr.leftHanded"), options: root.onOff },
                { kind: "section", key: "m.sec3", label: Strings.t("ptr.secCursor") },
                { kind: "entry", key: "cursor.system_timeout", label: Strings.t("ptr.cursorSystem"),
                  suffix: "s", hint: Strings.t("ptr.cursorSystemHint") },
                { kind: "entry", key: "cursor.menu_timeout", label: Strings.t("ptr.cursorMenu"),
                  suffix: "s", hint: Strings.t("ptr.cursorMenuHint") }
            ];
        }
        if (root.scope !== "touchpad") return [];
        const arr = [{ kind: "section", key: "t.sec1", label: Strings.t("ptr.secSpeed") }];
        // Speed / acceleration / on-off are per-device rules — they can only be written
        // once the touchpad's Hyprland name is known (see the file header).
        if (root.padsKnown) {
            arr.push({ kind: "select", key: "touchpad.enabled", label: Strings.t("ptr.tpEnabled"), options: root.onOff });
            arr.push({ kind: "slider", key: "touchpad.sensitivity", label: Strings.t("ptr.speed"),
                       from: -1, to: 1, step: 0.1, decimals: 1, suffix: "" });
            arr.push({ kind: "select", key: "touchpad.accel_profile", label: Strings.t("ptr.accel"), options: root.accelOpts });
        }
        arr.push({ kind: "select", key: "touchpad.natural_scroll", label: Strings.t("ptr.naturalScroll"), options: root.onOff });
        arr.push({ kind: "slider", key: "touchpad.scroll_factor", label: Strings.t("ptr.scrollSpeed"),
                   from: 0.2, to: 3, step: 0.05, decimals: 2, suffix: "×" });
        arr.push({ kind: "select", key: "touchpad.disable_while_typing", label: Strings.t("ptr.dwt"), options: root.onOff });
        arr.push({ kind: "section", key: "t.sec2", label: Strings.t("ptr.secTaps") });
        arr.push({ kind: "select", key: "touchpad.tap_to_click", label: Strings.t("ptr.tapToClick"), options: root.onOff });
        arr.push({ kind: "select", key: "touchpad.tap_button_map", label: Strings.t("ptr.tapMap"), options: root.tapMapOpts });
        arr.push({ kind: "select", key: "touchpad.clickfinger_behavior", label: Strings.t("ptr.click"), options: root.clickOpts });
        arr.push({ kind: "select", key: "touchpad.middle_button_emulation", label: Strings.t("ptr.middleEmu"), options: root.onOff });
        arr.push({ kind: "section", key: "t.sec3", label: Strings.t("ptr.secDrag") });
        arr.push({ kind: "select", key: "touchpad.tap_and_drag", label: Strings.t("ptr.tapDrag"), options: root.onOff });
        arr.push({ kind: "select", key: "touchpad.drag_lock", label: Strings.t("ptr.dragLock"), options: root.dragLockOpts });
        arr.push({ kind: "select", key: "touchpad.drag_3fg", label: Strings.t("ptr.drag3fg"), options: root.drag3fgOpts });
        arr.push({ kind: "section", key: "t.sec4", label: Strings.t("ptr.secGestures") });
        arr.push({ kind: "select", key: "gestures.workspace_fingers", label: Strings.t("ptr.wsSwipe"), options: root.swipeOpts });
        if (root.pv("gestures.workspace_fingers", "3") !== "0") {
            arr.push({ kind: "select", key: "gestures.swipe_invert", label: Strings.t("ptr.swipeNatural"), options: root.onOff });
            arr.push({ kind: "select", key: "gestures.swipe_create_new", label: Strings.t("ptr.swipeCreate"), options: root.onOff });
        }
        return arr;
    }

    // ── Keyboard roving-focus (two regions: segment pills → the scrolling rows) ───
    // The content list is rebuilt from whatever the current segment shows, and its
    // shape depends on data that arrives AFTER the first frame (both CLI round-trips)
    // — so the cursor is stored as a descriptor KEY, not a bare index: a row appearing
    // above the focused one must not silently move the highlight (quickshell-hub.md
    // gotcha 15). Sections are headers and never enter the list.
    property string focusRegion: "scope"      // "scope" | "content"
    property int scopeIdx: 0
    property string focusKey: ""

    readonly property var scopes: root.touchpadPresent ? ["keyboard", "mouse", "touchpad"] : ["keyboard", "mouse"]

    function buildContent() {
        const arr = [];
        if (root.scope === "keyboard") {
            for (let i = 0; i < root.sortedCodes.length; i++)
                arr.push({ kind: "layout", key: "kbd.layout:" + root.sortedCodes[i], idx: i, code: root.sortedCodes[i] });
            arr.push({ kind: "nav",    key: "kbd.add" });
            arr.push({ kind: "select", key: "kbd.toggle" });
            arr.push({ kind: "slider", key: "kbd.rate" });
            arr.push({ kind: "slider", key: "kbd.delay" });
            arr.push({ kind: "select", key: "kbd.numlock" });
            return arr;
        }
        for (let i = 0; i < root.settingRows.length; i++) {
            const r = root.settingRows[i];
            if (r.kind === "section") continue;
            arr.push({ kind: r.kind, key: r.key, row: i });
        }
        return arr;
    }
    readonly property var contentDesc: root.buildContent()
    readonly property int focusIdx: {
        for (let i = 0; i < root.contentDesc.length; i++)
            if (root.contentDesc[i].key === root.focusKey) return i;
        return -1;
    }
    // The focused row vanished (a layout removed, a segment switched, a conditional row
    // folded away) — fall back to the first row rather than leaving a dangling key.
    onContentDescChanged: if (root.focusRegion === "content" && root.focusIdx < 0)
        root.focusKey = root.contentDesc.length > 0 ? root.contentDesc[0].key : ""

    // True while an EntryRow's field holds real Qt focus — Up/Down/Left/Right must
    // navigate the text cursor, not steal the roving highlight (same guard as
    // PowerPanel's editingText over its IdleRow fields).
    readonly property bool editingText: root.contentDesc.some((d) => {
        if (d.kind !== "entry") return false;
        const item = root.focusItem(d);
        return !!(item && item.input !== undefined && item.input.activeFocus);
    })

    function focusItem(d) {
        if (!d) return null;
        if (d.kind === "layout") return layoutRepeater.itemAt(d.idx);
        switch (d.key) {
        case "kbd.add":     return addRow;
        case "kbd.toggle":  return toggleRow;
        case "kbd.rate":    return rateRow;
        case "kbd.delay":   return delayRow;
        case "kbd.numlock": return numlockRow;
        }
        return settingRepeater.itemAt(d.row);
    }
    // Reaching either end of the roving list should reach the true scroll edge — a
    // HubSection header sits above the first row, so "row 0 is in the viewport" and "we
    // scrolled all the way up" are different conditions (gotcha 4).
    function scrollIntoView() {
        const item = root.focusItem(root.contentDesc[root.focusIdx]);
        if (!item) return;
        if (root.focusIdx === 0) { flick.contentY = 0; return; }
        if (root.focusIdx === root.contentDesc.length - 1) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }
    function focusRow(i) {
        if (root.contentDesc.length === 0) return;
        const n = Math.max(0, Math.min(i, root.contentDesc.length - 1));
        root.focusKey = root.contentDesc[n].key;
        root.scrollIntoView();
    }
    function setScope(name) {
        if (root.scope === name) return;
        root.scope = name;
        root.scopeIdx = Math.max(0, root.scopes.indexOf(name));
        root.focusKey = "";
        flick.contentY = 0;
        if (name === "touchpad") root.ensureDetected();
    }
    function moveH(delta) {
        if (root.focusRegion === "scope") {
            const i = Math.max(0, Math.min(root.scopes.length - 1, root.scopeIdx + delta));
            root.scopeIdx = i;
            root.setScope(root.scopes[i]);
            return;
        }
        // In the content region ←/→ belong to the focused slider (the only control
        // with a continuous value); dropdown rows ignore them.
        const d = root.contentDesc[root.focusIdx];
        if (!d || d.kind !== "slider") return;
        const item = root.focusItem(d);
        if (!item) return;
        if (delta > 0) item.stepUp(); else item.stepDown();
    }
    function moveDown() {
        if (root.focusRegion === "scope") {
            root.focusRegion = "content";
            root.focusRow(0);
            return;
        }
        root.focusRow(root.focusIdx + 1);
    }
    function moveUp() {
        if (root.focusRegion === "scope") return;
        if (root.focusIdx > 0) { root.focusRow(root.focusIdx - 1); return; }
        root.focusRegion = "scope";
        root.scopeIdx = Math.max(0, root.scopes.indexOf(root.scope));
    }

    focus: true
    Keys.onPressed: (e) => {
        // An entry field holds real Qt focus — let it keep arrow/Enter/Space for
        // text editing instead of stealing the roving cursor mid-edit (same guard
        // as PowerPanel's IdleRow / SystemPanel's retRow).
        if (root.editingText) return;
        switch (e.key) {
        case HubNavKeys.down:  root.moveDown(); e.accepted = true; return;
        case HubNavKeys.up:    root.moveUp();   e.accepted = true; return;
        case HubNavKeys.left:  root.moveH(-1);  e.accepted = true; return;
        case HubNavKeys.right: root.moveH(1);   e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            if (root.focusRegion === "scope") { e.accepted = true; return; }
            const d = root.contentDesc[root.focusIdx];
            if (d) {
                if (d.kind === "layout") {
                    if (d.code !== root.codes[0]) root.setDefault(d.code);   // mirrors row click
                } else if (d.kind === "nav") {
                    root.navigate("input.kbd");
                } else if (d.kind === "select") {
                    const item = root.focusItem(d);
                    if (item) item.activated();
                } else if (d.kind === "entry") {
                    // Enter on the row focuses the field (a second Enter commits).
                    const item = root.focusItem(d);
                    if (item) item.focusEntry();
                }
            }
            e.accepted = true;
            return;
        }
        // Removes the focused layout — mirrors the row's own × button, only meaningful
        // on a layout row and only when it isn't the last one. The physical key is the
        // `menu_delete` token (default Delete, i3-vim X), same single-key-per-profile
        // contract as the roving arrows above.
        case HubNavKeys.del: {
            const d = root.contentDesc[root.focusIdx];
            if (d && d.kind === "layout" && root.codes.length > 1) root.removeLayout(d.code);
            e.accepted = true;
            return;
        }
        }
    }

    // ── Backend: keyboard ────────────────────────────────────────────────────────
    function probeRing() { statusProc.running = true; }

    Process {
        id: statusProc
        running: true
        command: ["w-keyboard", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text || "";
                const lay = (t.match(/^layout=(.*)$/m) || [])[1] || "";
                const vr  = (t.match(/^variant=(.*)$/m) || [])[1] || "";
                const opt = (t.match(/^options=(.*)$/m) || [])[1] || "";
                root.codes = lay.split(",").map(s => s.trim()).filter(s => s.length > 0);
                root.variants = vr.split(",");
                const m = opt.match(/grp:[a-z0-9_]+/);
                root.toggleId = m ? m[0] : "grp:alt_shift_toggle";
                root.repeatRate  = parseInt((t.match(/^repeat_rate=(.*)$/m)  || [])[1] || "25", 10);
                root.repeatDelay = parseInt((t.match(/^repeat_delay=(.*)$/m) || [])[1] || "600", 10);
                root.numlock = ((t.match(/^numlock=(.*)$/m) || [])[1] || "false") === "true";
            }
        }
    }

    // Initial active layout (before the first activelayout event fires).
    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text || "{}");
                    const kbs = d.keyboards || [];
                    const kb = kbs.find(k => k.main) || kbs[0];
                    if (kb && root.layoutFull === "") root.layoutFull = kb.active_keymap || "";
                } catch (e) { /* keep default */ }
            }
        }
    }

    // Live active layout (key-combo toggle or a switch): keep the highlight in sync.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const parts = (event.data || "").split(","); parts.shift();
            root.layoutFull = parts.join(",");
        }
    }

    // One tracked process for every w-keyboard mutation (they are mutually exclusive in
    // practice — a click, then a re-probe on exit).
    Process { id: kbdProc; onExited: root.probeRing() }
    function runKbd(args) { kbdProc.command = args; kbdProc.running = true; }
    function removeLayout(code) { root.runKbd(["w-keyboard", "remove", code]); }
    function setDefault(code)   { root.runKbd(["w-keyboard", "set-default", code]); }
    function setToggle(id)      { root.runKbd(["w-keyboard", "set-toggle", id]); }
    function setRepeat(rate, delay) { root.runKbd(["w-keyboard", "set-repeat", String(rate), String(delay)]); }
    function setNumlock(v)      { root.runKbd(["w-keyboard", "set-numlock", v === "true" ? "on" : "off"]); }

    // ── Backend: pointer ─────────────────────────────────────────────────────────
    function probePointer() { ptrProc.running = true; }

    Process {
        id: ptrProc
        running: true
        command: ["w-pointer", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                let present = false;
                let devs = [];
                for (const line of (this.text || "").split("\n")) {
                    const i = line.indexOf("=");
                    if (i <= 0) continue;
                    const k = line.slice(0, i), v = line.slice(i + 1);
                    if (k === "touchpad_present") present = (v === "yes");
                    else if (k === "touchpad_devices") devs = v.split(",").filter(s => s.length > 0);
                    else map[k] = v;
                }
                root.ptr = map;
                root.touchpadPresent = present;
                root.touchpadDevices = devs;
                // The segment can disappear under us (a hot-unplugged USB touchpad).
                if (!present && root.scope === "touchpad") root.setScope("mouse");
            }
        }
    }

    // A touchpad Hyprland doesn't have a name for yet can't get its per-device rules,
    // so the first visit to the segment resolves it. One shot per panel lifetime: a
    // detect that found nothing (an odd device udev flags but Hyprland doesn't list)
    // must not re-run on every visit.
    property bool detectTried: false
    function ensureDetected() {
        if (root.detectTried || root.padsKnown || !root.touchpadPresent) return;
        root.detectTried = true;
        detectProc.running = true;
    }
    Process { id: detectProc; command: ["w-pointer", "detect"]; onExited: root.probePointer() }

    // Pointer mutations are chatty (a slider commits on every release), so they queue:
    // reassigning `command` while a Process is running would drop the earlier call.
    property var setQueue: []
    Process {
        id: setProc
        onExited: {
            if (root.setQueue.length > 0) {
                const next = root.setQueue.shift();
                root.setQueue = root.setQueue;      // keep the binding honest
                setProc.command = next;
                setProc.running = true;
            } else {
                root.probePointer();
            }
        }
    }
    function setPointer(key, value) {
        // Optimistic local update: the row shows the new value immediately, and the
        // re-probe after the queue drains reconciles it with what the CLI stored.
        const m = Object.assign({}, root.ptr);
        m[key] = String(value);
        root.ptr = m;
        const cmd = ["w-pointer", "set", key, String(value)];
        if (setProc.running) root.setQueue = root.setQueue.concat([cmd]);
        else { setProc.command = cmd; setProc.running = true; }
    }

    // ── Row components ───────────────────────────────────────────────────────────
    // A slider row: label, slider, value readout. Shared by the pointer segments and
    // the keyboard's auto-repeat rows, so the geometry is declared once.
    component SliderRow: Item {
        id: sr
        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 1
        property real stepSize: 0
        property int decimals: 1
        property string suffix: ""
        property bool focused: false
        signal moved(real v)
        signal committed(real v)

        function stepUp()   { slider.stepUp(); }
        function stepDown() { slider.stepDown(); }

        height: 30

        // Full-row wash, bleeding on all four sides (gotcha 1) — the same contract as
        // SelectRow/HubRow so a focused slider row reads like any other focused row.
        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: sr.focused
            color: Colors.hover
        }

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.max(0, parent.width - 260)
            text: sr.label
            color: Colors.text
            font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            id: valTxt
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 52
            horizontalAlignment: Text.AlignRight
            text: sr.value.toFixed(sr.decimals) + sr.suffix
            color: Colors.muted
            font.family: Fonts.family; font.pixelSize: 12
            font.features: ({ "tnum": 1 })
        }
        WSlider {
            id: slider
            anchors { right: valTxt.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 190
            from: sr.from; to: sr.to; stepSize: sr.stepSize
            value: sr.value
            focused: sr.focused
            // Keyboard stepping walks the value; only the last step of a burst is worth
            // a CLI round-trip.
            commitDelay: 350
            onMoved: (v) => sr.moved(v)
            onCommitted: (v) => sr.committed(v)
        }
    }

    // An entry row: label (+ optional muted sublabel) on the left, a numeric text
    // box + unit suffix + Change button on the right. Mirrors the retention row in
    // SystemPanel's Logs section and PowerPanel's idle-timer row — the canonical
    // WSettingsField idiom (box + gated Change). The sublabel sits in the label's
    // own Column, anchored to the field's left edge, so a wrapped description never
    // runs under the input or the next row. Commits on Enter or the Change button,
    // only when the text both differs from `value` and parses as a number in range
    // (the border turns danger-red otherwise; the CLI re-validates anyway). Used
    // for the cursor idle timeouts, which are free-form seconds (0.1 precision)
    // rather than slider-scale.
    component EntryRow: Item {
        id: er
        property string label: ""
        property string hint: ""
        property string value: ""
        property string suffix: ""
        property bool focused: false
        signal committed(string v)
        signal exitField()
        // Exposed so the panel's roving-nav can forceActiveFocus() straight into
        // the field on Enter (a second Enter commits via WSettingsField), and wire
        // Tab/Esc to hand focus back out — same shape as PowerPanel's IdleRow.
        property var input: field.input

        function beginEdit() { field.input.forceActiveFocus(); field.input.selectAll(); }

        // Grows to fit a wrapped sublabel; 38 is the minimum so a hint-less row
        // still reads at the same scale as the retention row it mirrors.
        implicitHeight: Math.max(38, leftCol.implicitHeight + 8)
        height: implicitHeight

        // Full-row wash, same contract as SliderRow / SelectRow — hidden while the
        // field itself holds real Qt focus (its own accent border is the indicator
        // then, mirroring SystemPanel's retRow / PowerPanel's idleRow).
        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: er.focused && !field.input.activeFocus
            color: Colors.hover
        }

        Column {
            id: leftCol
            anchors {
                left: parent.left
                right: field.left; rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 2
            Text {
                width: leftCol.width
                text: er.label
                color: Colors.text
                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                visible: er.hint !== ""
                width: leftCol.width
                text: er.hint
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
        // Right slot — WSettingsField (box + Change button), the canonical idiom
        // shared with SystemPanel's log-retention / PowerPanel's idle-timer rows.
        // Commits on Enter or the Change button (gated on dirty + valid), not on
        // every keystroke or focus loss; Tab/Esc hand focus back to the roving-nav.
        WSettingsField {
            id: field
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fixedWidth: 90
            numeric: true
            placeholder: "0"
            suffix: er.suffix
            value: er.value
            validator: (text) => {
                const t = text.trim();
                if (t === "") return true;
                if (!/^\d+(\.\d+)?$/.test(t)) return false;
                const n = parseFloat(t);
                return !isNaN(n) && n >= 0 && n <= 3600;
            }
            borderWidth: HubConfig.border
            onApplied: (text) => er.committed(text)
            input.Keys.onTabPressed: er.exitField()
            input.Keys.onEscapePressed: er.exitField()
        }
    }

    // ── Fixed header: segment switch ─────────────────────────────────────────────
    Column {
        id: topCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 12

        Row {
            spacing: 8
            Pill {
                label: Strings.t("ptr.tab.keyboard"); active: root.scope === "keyboard"
                focused: root.focusRegion === "scope" && root.scopeIdx === 0
                onClicked: { root.focusRegion = "scope"; root.scopeIdx = 0; root.setScope("keyboard"); }
            }
            Pill {
                label: Strings.t("ptr.tab.mouse"); active: root.scope === "mouse"
                focused: root.focusRegion === "scope" && root.scopeIdx === 1
                onClicked: { root.focusRegion = "scope"; root.scopeIdx = 1; root.setScope("mouse"); }
            }
            // Only on a machine that has one — udev answers this even before Hyprland
            // knows the device by name.
            Pill {
                visible: root.touchpadPresent
                label: Strings.t("ptr.tab.touchpad"); active: root.scope === "touchpad"
                focused: root.focusRegion === "scope" && root.scopeIdx === 2
                onClicked: { root.focusRegion = "scope"; root.scopeIdx = 2; root.setScope("touchpad"); }
            }
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { top: topCol.bottom; topMargin: 12
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        // Extend into the card's right padding so the scrollbar pill sits near the window
        // edge; the content column insets the same amount, keeping its padding symmetric.
        anchors.rightMargin: -12
        // Extends the clip rect into the card's left padding so a row's own -8 focus-wash
        // bleed isn't cut off; Column.x compensates (gotcha 2).
        anchors.leftMargin: -8
        clip: true
        // 4px slack at each end for the first/last row's focus wash, via Column.y — NOT
        // Flickable.topMargin/bottomMargin (gotcha 3, a documented trap).
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}
        // An open dropdown's position is computed once, at click time — closing it on
        // scroll is simpler than chasing the row through the Flickable's transform.
        onContentYChanged: if (menuLayer.menuOpen) menuLayer.closeMenu()

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 12

            // ── Keyboard segment ──────────────────────────────────────────────────
            Column {
                visible: root.scope === "keyboard"
                width: parent.width
                spacing: 12

                HubSection { width: parent.width; text: Strings.t("hub.layouts") }

                Repeater {
                    id: layoutRepeater
                    // Alphabetical + stable across a default change (see root.sortedCodes)
                    // — only the "default" badge moves, never the row order.
                    model: root.scope === "keyboard" ? root.sortedCodes : []
                    Item {
                        id: lrow
                        required property string modelData
                        required property int index
                        readonly property bool active: lrow.modelData === root.activeCode
                        readonly property bool focused: root.focusRegion === "content"
                                                        && root.focusKey === "kbd.layout:" + lrow.modelData
                        // The ring's actual front slot (kb_layout[0]) names the default —
                        // NOT this row's position, which is alphabetical.
                        readonly property bool isDefault: lrow.modelData === root.codes[0]
                        width: col.width
                        height: 38

                        Rectangle {
                            anchors.fill: parent
                            radius: Geometry.radiusSm
                            color: lrow.active ? Colors.selection
                                   : ((rowMa.containsMouse || lrow.focused) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                            // Keyboard focus reuses the same accent ring as `active` — the
                            // Hub-wide convention.
                            border.width: (lrow.active || lrow.focused) ? HubConfig.border : 0
                            border.color: Colors.accentInk
                        }

                        // Click the row (anywhere but the × / badge) → make it the default.
                        MouseArea {
                            id: rowMa
                            anchors { left: parent.left; right: rmBtn.left; top: parent.top; bottom: parent.bottom }
                            hoverEnabled: true
                            cursorShape: lrow.isDefault ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!lrow.isDefault) root.setDefault(lrow.modelData)
                        }

                        Row {
                            anchors { left: parent.left; leftMargin: 8
                                      right: defBadge.visible ? defBadge.left : rmBtn.left; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            spacing: 10
                            ChromeIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 22
                                icon: "input-keyboard"; glyph: String.fromCodePoint(0xf030c) // nf-md-keyboard
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: lrow.modelData.toUpperCase()
                                color: Colors.text
                                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - 200)
                                // Full name incl. variant, e.g. "Russian (Macintosh)".
                                text: Xkb.label(lrow.modelData, root.variantFor(lrow.modelData))
                                color: Colors.muted
                                font.family: Fonts.family; font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        // "default" badge on the login-default layout (ring index 0).
                        Rectangle {
                            id: defBadge
                            visible: lrow.isDefault
                            anchors { right: rmBtn.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: defBadgeLbl.implicitWidth + 14
                            height: 20
                            radius: Geometry.radiusSm
                            color: "transparent"
                            border.width: HubConfig.border; border.color: Colors.accentInk
                            Text {
                                id: defBadgeLbl
                                anchors.centerIn: parent
                                text: Strings.t("hub.default")
                                color: Colors.accentInk
                                font.family: Fonts.family; font.pixelSize: 10; font.weight: Font.Medium
                            }
                        }

                        // Remove (×) — disabled when it is the last remaining layout.
                        Rectangle {
                            id: rmBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 30; height: 30; radius: Geometry.radiusSm
                            readonly property bool canRemove: root.codes.length > 1
                            color: rmMa.containsMouse && rmBtn.canRemove ? Colors.hover : Colors.alpha(Colors.hover, 0)
                            opacity: rmBtn.canRemove ? 1 : 0.35
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xf0156)   // nf-md-close
                                font.family: Fonts.mono; font.pixelSize: 15; color: Colors.muted
                            }
                            MouseArea {
                                id: rmMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: rmBtn.canRemove ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (rmBtn.canRemove) root.removeLayout(lrow.modelData)
                            }
                        }
                    }
                }

                // Add language → the searchable layout picker.
                HubRow {
                    id: addRow
                    width: parent.width
                    icon: "list-add"; glyph: String.fromCodePoint(0xf0417)   // nf-md-plus
                    label: Strings.t("hub.addLanguage")
                    actionText: Strings.t("hub.choose")
                    focused: root.focusRegion === "content" && root.focusKey === "kbd.add"
                    onActivated: root.navigate("input.kbd")
                }

                // ── Layout-switch key (only meaningful with more than one layout) ──
                HubSection { width: parent.width; text: Strings.t("hub.layoutToggle") }
                SelectRow {
                    id: toggleRow
                    width: parent.width
                    focused: root.focusRegion === "content" && root.focusKey === "kbd.toggle"
                    icon: "preferences-desktop-keyboard"; glyph: String.fromCodePoint(0xf030c) // nf-md-keyboard
                    label: Strings.t("hub.switchKey")
                    currentId: root.toggleId
                    options: root.togglePresets
                    value: root.toggleLabel(root.toggleId)
                    onActivated: menuLayer.openMenu(toggleRow, root.togglePresets, root.toggleId,
                                                    (id) => root.setToggle(id))
                }
                // Caveat for a problematic toggle (e.g. Ctrl+Space / Super+Space).
                Text {
                    width: parent.width
                    visible: root.toggleWarn !== ""
                    text: root.toggleWarn !== "" ? Strings.t(root.toggleWarn) : ""
                    color: Colors.dangerBorder
                    font.family: Fonts.family; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                // ── Typing ────────────────────────────────────────────────────────
                HubSection { width: parent.width; text: Strings.t("ptr.secTyping") }
                SliderRow {
                    id: rateRow
                    width: parent.width
                    label: Strings.t("ptr.repeatRate")
                    from: 5; to: 60; stepSize: 1; decimals: 0; suffix: "/s"
                    value: root.repeatRate
                    focused: root.focusRegion === "content" && root.focusKey === "kbd.rate"
                    onMoved: (v) => root.repeatRate = Math.round(v)
                    onCommitted: (v) => root.setRepeat(Math.round(v), root.repeatDelay)
                }
                SliderRow {
                    id: delayRow
                    width: parent.width
                    label: Strings.t("ptr.repeatDelay")
                    from: 150; to: 1200; stepSize: 25; decimals: 0; suffix: " ms"
                    value: root.repeatDelay
                    focused: root.focusRegion === "content" && root.focusKey === "kbd.delay"
                    onMoved: (v) => root.repeatDelay = Math.round(v)
                    onCommitted: (v) => root.setRepeat(root.repeatRate, Math.round(v))
                }
                SelectRow {
                    id: numlockRow
                    width: parent.width
                    focused: root.focusRegion === "content" && root.focusKey === "kbd.numlock"
                    icon: "input-keyboard"; glyph: String.fromCodePoint(0xf030c) // nf-md-keyboard
                    label: Strings.t("ptr.numlock")
                    currentId: root.numlock ? "true" : "false"
                    options: root.onOff
                    value: root.labelOf(root.onOff, root.numlock ? "true" : "false")
                    onActivated: menuLayer.openMenu(numlockRow, root.onOff, root.numlock ? "true" : "false",
                                                    (id) => root.setNumlock(id))
                }
            }

            // ── Pointer segments (data-driven rows) ───────────────────────────────
            Repeater {
                id: settingRepeater
                model: root.settingRows
                Item {
                    id: prow
                    required property var modelData
                    required property int index
                    width: col.width
                    // A section header is a label, not a row: no wash, no focus, its own
                    // height. Sliders/selects are 30px control rows. An entry row sizes
                    // itself (it carries a sublabel and may wrap), so it reports its own
                    // implicitHeight once the Loader is ready.
                    height: prow.modelData.kind === "section" ? sectionHdr.implicitHeight + 8
                         : (prow.modelData.kind === "entry"
                              ? (entryLoader.item ? entryLoader.item.implicitHeight : 38)
                              : 30)

                    // Per-row properties are always read through an explicit path
                    // (`prow.modelData.x`) — a bare identifier inside a Repeater delegate
                    // silently resolved to the SAME value on every row once already
                    // (quickshell-hub.md gotcha 16).
                    readonly property bool isFocused: root.focusRegion === "content"
                                                      && root.focusKey === prow.modelData.key

                    function activated() { if (selectLoader.item) selectLoader.item.activated(); }
                    function stepUp()    { if (sliderLoader.item) sliderLoader.item.stepUp(); }
                    function stepDown()  { if (sliderLoader.item) sliderLoader.item.stepDown(); }
                    function focusEntry() { if (entryLoader.item) entryLoader.item.beginEdit(); }
                    // Exposed so the panel's roving-nav can detect an entry being
                    // edited (editingText guard) — same shape as PowerPanel's
                    // IdleRow exposing `input` to its visFocusables.some() check.
                    readonly property var input: entryLoader.active && entryLoader.item ? entryLoader.item.input : undefined

                    HubSection {
                        id: sectionHdr
                        visible: prow.modelData.kind === "section"
                        width: parent.width
                        text: prow.modelData.kind === "section" ? prow.modelData.label : ""
                    }

                    Loader {
                        id: selectLoader
                        active: prow.modelData.kind === "select"
                        anchors.fill: parent
                        // No width here: a Loader with a size resizes its item, and a
                        // second binding on top of that would fight it.
                        sourceComponent: SelectRow {
                            id: selRow
                            focused: prow.isFocused
                            label: prow.modelData.label
                            options: prow.modelData.options
                            currentId: root.pv(prow.modelData.key, "")
                            value: root.labelOf(prow.modelData.options, root.pv(prow.modelData.key, ""))
                            // openMenu() needs the ROW (it reads anchorItem and sets
                            // menuOpen on it), not the delegate wrapping it.
                            onActivated: menuLayer.openMenu(selRow, prow.modelData.options,
                                                            root.pv(prow.modelData.key, ""),
                                                            (id) => root.setPointer(prow.modelData.key, id))
                        }
                    }

                    Loader {
                        id: sliderLoader
                        active: prow.modelData.kind === "slider"
                        anchors.fill: parent
                        sourceComponent: SliderRow {
                            focused: prow.isFocused
                            label: prow.modelData.label
                            from: prow.modelData.from; to: prow.modelData.to
                            stepSize: prow.modelData.step; decimals: prow.modelData.decimals
                            suffix: prow.modelData.suffix
                            value: root.pnum(prow.modelData.key, 0)
                            // Dragging only repaints (the optimistic map update); the CLI
                            // is called once the value is final.
                            onMoved: (v) => {
                                const m = Object.assign({}, root.ptr);
                                m[prow.modelData.key] = String(v);
                                root.ptr = m;
                            }
                            onCommitted: (v) => root.setPointer(prow.modelData.key, v)
                        }
                    }

                    Loader {
                        id: entryLoader
                        active: prow.modelData.kind === "entry"
                        anchors.fill: parent
                        sourceComponent: EntryRow {
                            focused: prow.isFocused
                            label: prow.modelData.label
                            hint: prow.modelData.hint !== undefined ? prow.modelData.hint : ""
                            suffix: prow.modelData.suffix
                            value: root.pv(prow.modelData.key, "")
                            onCommitted: (v) => root.setPointer(prow.modelData.key, v)
                            onExitField: root.forceActiveFocus()
                        }
                    }
                }
            }

            // Shown while the touchpad exists but Hyprland hasn't named it yet: speed,
            // acceleration and the on/off switch are per-device rules and stay hidden.
            Text {
                width: parent.width
                visible: root.scope === "touchpad" && !root.padsKnown
                text: Strings.t("ptr.deviceUnknown")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Dropdown overlay layer (above the content) ───────────────────────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }
}
