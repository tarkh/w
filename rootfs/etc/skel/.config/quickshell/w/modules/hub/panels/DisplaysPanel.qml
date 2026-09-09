// W Linux — Hub Displays panel (Этап 3 session tab + Ф5 login-screen tab of the monitor plan
// + the night-light scope).
// A segmented switch (Session | Login screen | Night light) at the top picks what is being
// edited. The first two are two configs behind ONE row layout: the row/dropdown markup below
// is shared verbatim, only the data source and what a mutation does differ. The third shares
// nothing with them and lives in its own file (NightLightSection.qml, see below).
//
// Session scope: one section per live output (from `hyprctl monitors all`, via `w-monitor
// list --porcelain`) with the five contracted settings (mode/scale/rotation/position/
// enabled) plus which output is primary — a pure front-end over `w-monitor`, no direct
// Lua/JSON edits. State is two porcelain reads: `list` for live mode/scale/transform/
// enabled/focused per output, `status` for the saved fragment rule (position — `list`
// carries no auto-* semantics — and primary), plus a sequential per-output `modes` fetch
// feeding the Resolution/Refresh dropdowns (one shared Process walking the output list, not
// a fan-out — this panel rarely sees more than a handful of heads). Every mutation is a
// tracked `w-monitor` Process; on exit the panel re-probes all three sources.
//
// Login-screen scope: root-owned config, no live compositor to mutate against (the greeter
// exits once a session starts), so edits are STAGED locally (`stagedCfg`/`stagedPrimary`)
// against a baseline read from `w-monitor greeter status --porcelain` — same "changed =
// effective ≠ baseline" honesty as HotkeysPanel.qml's profile-dirty banner, not "touched".
// A dirty diff raises an unsaved-changes banner (Apply / Discard); Apply sends the WHOLE
// output set as one `pkexec …  monitor-greeter apply <spec>...` call via `runPrivileged`
// (Hub.qml suspends for the single polkit prompt, restores, and the panel re-probes the
// greeter baseline — which also clears `stagedCfg` back in sync). "Copy from session" and
// "Reset" are independent one-shot privileged actions, not gated on the dirty banner. An
// output with no saved greeter rule seeds `stagedCfg` from its live mode/scale/transform
// (concrete values) rather than the "preferred"/"auto" symbolic defaults `monitors.lua`
// itself would use — there is no live compositor here to resolve "preferred" against, and
// the physical display is the same hardware as the session, so its current live mode is the
// best available guess until the user (or `greeter sync`) sets a real one.
//
// Night-light scope: a front-end over `w-nightlight` (blue-light filter, hyprsunset).
// It has no outputs, no staging and no polkit — every key is user-scope — so it is a
// sibling file loaded on demand rather than more markup here, and it borrows only this
// panel's dropdown overlay. See NightLightSection.qml and w-nightlight.md.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/DisplaysPanel.qml"}); as a
// subdir file it is not a module type, so shared hub components come in via `import
// qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // topCol (fixed: scope switch + login-screen hint/actions/banner) + col (scrolling
    // per-output rows) drive the Hub card morph together; the dropdown can still grow it
    // further (menuLayer.menuBottom) — same contract as NetworkPanel/InputPanel
    // (flipUp:false: this panel is short enough to just grow downward).
    // +8 mirrors the Flickable's own contentHeight padding below (focus-wash bleed
    // slack, quickshell-hub.md gotcha 6) — without it `flick` is permanently 8px
    // shorter than its own contentHeight and shows a phantom scroll even when the
    // real content fits comfortably under maxCardH.
    implicitHeight: Math.max(topCol.implicitHeight + 12 + col.implicitHeight + 8, menuLayer.menuBottom)

    // Privileged actuation for the login-screen scope: handed up to the Hub, which
    // suspends for the polkit prompt and restores + refreshes on exit (same contract as
    // NetworkPanel.qml).
    // Up on the topmost roving position hands the cursor to the header's "?" button
    // (Hub.qml's focusHeaderHelp). A route with no `help` entry has no button and the
    // Hub answers false — the cursor simply stays where it is.
    signal focusHeader()

    signal runPrivileged(var cmd, var onDone)

    // The shared pill (core/WPill.qml) with the Hub's outline width — used for the
    // scope switch (`active` = filled current segment) and the login-screen
    // actions/banner. Was a file-local copy of the same Rectangle.
    component Pill: WPill { borderWidth: HubConfig.border }

    // ── Keyboard roving-focus (three regions: scope pills → greeter action pills →
    // the scrolling per-output/night rows) ─────────────────────────────────────────
    // "actions" only exists while scope === "greeter" — moveDown/moveUp skip it
    // otherwise (same "scope switch reshapes what's below it" idea as
    // AppearancePanel's tab region, just three fixed regions in a fixed order
    // instead of a general chain). "content" is a flat computed list (buildContent())
    // whose shape depends entirely on scope: per-output field rows for session/
    // greeter — built from root.outputs, whose length varies with the machine's
    // monitor count, so positional descriptors are used instead of a fixed id list
    // (same reasoning as InputPanel's ring) — or night-light's own conditionally-
    // visible fields for night, physically rendered by the sibling
    // NightLightSection.qml. DisplaysPanel stays the SOLE owner of the roving index
    // across that Loader boundary — see contentIndexOf and nightLoader's Binding
    // below — the child only ever reads `focusedField` back and exposes
    // rowItem()/activateField()/focusFieldInput() for this panel to drive it.
    property string focusRegion: "scope"   // "scope" | "actions" | "content"
    property int focusIdx: 0
    readonly property int scopeIdx: ["session", "greeter", "night"].indexOf(root.scope)
    readonly property string nightMode: nightLoader.item ? nightLoader.item.mode : "off"

    readonly property var fieldRowProp: ({ primary: "header", res: "resRow", freq: "freqRow", scale: "scaleRow",
                                            rot: "rotRow", pos: "posRow", enabled: "enRow", reset: "resetBtn" })
    function buildContent() {
        if (root.scope === "night") {
            const arr = [{ kind: "night", field: "mode", key: "night:mode" }];
            if (root.nightMode !== "off") arr.push({ kind: "night", field: "temp", key: "night:temp" });
            if (root.nightMode === "schedule") {
                arr.push({ kind: "night", field: "day",   key: "night:day" });
                arr.push({ kind: "night", field: "ramp",  key: "night:ramp" });
                arr.push({ kind: "night", field: "start", key: "night:start" });
                arr.push({ kind: "night", field: "end",   key: "night:end" });
            }
            return arr;
        }
        const arr = [];
        for (let i = 0; i < root.outputs.length; i++) {
            const fields = ["primary", "res", "freq", "scale", "rot"];
            if (root.outputs.length >= 2) fields.push("pos", "enabled");
            if (root.scope === "session") fields.push("reset");
            for (const f of fields)
                arr.push({ kind: "row", section: i, rowProp: root.fieldRowProp[f], key: "row:" + i + ":" + f });
        }
        return arr;
    }
    readonly property var contentDesc: root.buildContent()
    // Same "index-of" idiom as PowerPanel's visFocusables.indexOf(namedId), just
    // keyed by a computed string since the per-output rows have no fixed ids.
    readonly property var contentIndexOf: {
        const m = {};
        for (let i = 0; i < root.contentDesc.length; i++) m[root.contentDesc[i].key] = i;
        return m;
    }
    onContentDescChanged: if (root.focusRegion === "content")
        root.focusIdx = Math.max(0, Math.min(root.focusIdx, root.contentDesc.length - 1))
    onDirtyChanged: if (root.focusRegion === "actions")
        root.focusIdx = Math.max(0, Math.min(root.focusIdx, (root.dirty ? 4 : 2) - 1))

    function contentItemFor(d) {
        if (!d) return null;
        if (d.kind === "night") return nightLoader.item ? nightLoader.item.rowItem(d.field) : null;
        const sect = outputRepeater.itemAt(d.section);
        return sect ? sect[d.rowProp] : null;
    }
    // Same true-edge-first reasoning as InputPanel/PowerPanel.scrollIntoView — a
    // HubSection header or the greeter hint sits above the first row, so "row 0 is
    // in the viewport" and "we scrolled all the way up" are different conditions.
    function scrollContentIntoView() {
        const item = root.contentItemFor(root.contentDesc[root.focusIdx]);
        if (!item) return;
        if (root.focusIdx === 0) { flick.contentY = 0; return; }
        if (root.focusIdx === root.contentDesc.length - 1) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }

    function moveH(delta) {
        if (root.focusRegion === "scope") {
            const i = Math.max(0, Math.min(2, root.scopeIdx + delta));
            root.scope = ["session", "greeter", "night"][i];
            root.focusIdx = i;
            return;
        }
        if (root.focusRegion === "actions") {
            const n = root.dirty ? 4 : 2;
            root.focusIdx = Math.max(0, Math.min(n - 1, root.focusIdx + delta));
        }
    }
    function moveDown() {
        if (root.focusRegion === "scope") {
            root.focusRegion = root.scope === "greeter" ? "actions" : "content";
            root.focusIdx = 0;
            return;
        }
        if (root.focusRegion === "actions") { root.focusRegion = "content"; root.focusIdx = 0; return; }
        root.focusIdx = Math.min(root.focusIdx + 1, Math.max(0, root.contentDesc.length - 1));
        root.scrollContentIntoView();
    }
    function moveUp() {
        if (root.focusRegion === "scope") { root.focusHeader(); return; }
        if (root.focusRegion === "actions") { root.focusRegion = "scope"; root.focusIdx = root.scopeIdx; return; }
        if (root.focusIdx > 0) { root.focusIdx--; root.scrollContentIntoView(); return; }
        if (root.scope === "greeter") { root.focusRegion = "actions"; root.focusIdx = 0; }
        else { root.focusRegion = "scope"; root.focusIdx = root.scopeIdx; }
    }

    // True while a night-light text field (temp/day/ramp/start/end) holds real Qt
    // focus — same guard reasoning as PowerPanel.editingText, forwarded across the
    // Loader boundary since the fields physically live in NightLightSection.
    readonly property bool editingText: root.scope === "night" && nightLoader.item
                                         && nightLoader.item.editingText === true

    focus: true
    Keys.onPressed: (e) => {
        if (root.editingText) return;
        switch (e.key) {
        case HubNavKeys.down: root.moveDown(); e.accepted = true; return;
        case HubNavKeys.up:   root.moveUp();   e.accepted = true; return;
        case HubNavKeys.left:  root.moveH(-1); e.accepted = true; return;
        case HubNavKeys.right: root.moveH(1);  e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            if (root.focusRegion === "actions") {
                const acts = root.dirty ? ["copy", "reset", "apply", "discard"] : ["copy", "reset"];
                switch (acts[root.focusIdx]) {
                case "copy": root.copyFromSession(); break;
                case "reset": root.resetGreeter(); break;
                case "apply": root.applyGreeter(); break;
                case "discard": root.discardStaged(); break;
                }
                e.accepted = true; return;
            }
            if (root.focusRegion === "content") {
                const d = root.contentDesc[root.focusIdx];
                if (d) {
                    if (d.kind === "night") {
                        if (nightLoader.item) {
                            if (d.field === "mode") nightLoader.item.activateField("mode");
                            else nightLoader.item.focusFieldInput(d.field);
                        }
                    } else {
                        const item = root.contentItemFor(d);
                        if (item && item.activated !== undefined) item.activated();
                        else if (item && item.clicked !== undefined) item.clicked();
                    }
                }
            }
            e.accepted = true;
            return;
        }
        }
    }

    // Which config the rows below reflect. "session" = today's live/`w-monitor` behaviour;
    // "greeter" = staged edits against the login-screen config (see file header);
    // "night" = the night-light settings, which have no per-output rows at all and are
    // rendered entirely by NightLightSection.qml (the Repeater's model goes empty).
    property string scope: "session"

    // Per-tab documentation for the header's "?" (contract in HubRegistry): the login
    // screen is a separate config with its own staging rules, and the night light is a
    // different subsystem entirely — one anchor cannot cover all three.
    readonly property var help: {
        switch (root.scope) {
        case "greeter": return { page: "guide/displays.md", anchor: "the-login-screen-has-its-own-layout" };
        case "night":   return { page: "guide/displays.md", anchor: "night-light" };
        }
        return { page: "guide/displays.md", anchor: "the-monitor-layout" };
    }

    // ── Session state (list + status porcelain reads) ──────────────────────────────
    property var liveRows: []        // [{name,desc,mode,scale,transform,enabled,focused}]
    property string primary: ""
    property var rules: ({})         // name -> {mode,scale,transform,position,disabled}
    property var modesByOutput: ({}) // name -> [{full,wh,hz}]
    property var modesQueue: []
    property int modesQueueIdx: 0

    // ── Login-screen state (staged) ─────────────────────────────────────────────────
    // `greeterRules`/`greeterPrimary` = the last-read committed baseline (`w-monitor
    // greeter status`). `stagedCfg` is a SPARSE overlay — only outputs the user actually
    // touched since the last commit carry an entry; an untouched output reads straight
    // through to the baseline (see greeterEffectiveRule), so a fresh commit (apply/sync/
    // reset) clears the dirty banner by simply emptying the overlay, no full re-clone
    // needed and no load-order race against `liveRows`.
    property var greeterRules: ({})      // name -> {mode,scale,transform,position,disabled}
    property string greeterPrimary: ""
    property var stagedCfg: ({})         // name -> {mode,scale,transform,position,disabled}
    property string stagedPrimary: ""

    // Default for an output with no saved greeter rule yet: seed from its own live values
    // rather than monitors.lua's "preferred"/"auto" symbols — there is no live compositor
    // here to resolve those against, and the physical display is the same hardware as the
    // session, so its current live mode is the best available guess (see file header).
    function liveDefaultRule(name) {
        for (const row of root.liveRows) {
            if (row.name === name) return { mode: row.mode, scale: row.scale, transform: row.transform, position: "auto", disabled: "false" };
        }
        return { mode: "preferred", scale: "auto", transform: "0", position: "auto", disabled: "false" };
    }
    function greeterBaselineRule(name)  { return root.greeterRules[name] || root.liveDefaultRule(name); }
    function greeterEffectiveRule(name) { return root.stagedCfg[name] || root.greeterBaselineRule(name); }
    function liveModeFor(name) {
        for (const row of root.liveRows) if (row.name === name) return row.mode;
        return "";
    }

    readonly property var outputs: {
        const arr = [];
        for (const row of root.liveRows) {
            if (root.scope === "session") {
                const rule = root.rules[row.name] || null;
                arr.push({
                    name: row.name, desc: row.desc, mode: row.mode, scale: row.scale,
                    transform: row.transform, enabled: row.enabled === "1",
                    position: rule ? rule.position : "auto",
                });
            } else {
                const s = root.greeterEffectiveRule(row.name);
                arr.push({
                    name: row.name, desc: row.desc, mode: s.mode, scale: s.scale,
                    transform: s.transform, enabled: s.disabled !== "true",
                    position: s.position,
                });
            }
        }
        return arr;
    }
    readonly property string effectivePrimary: root.scope === "session" ? root.primary : root.stagedPrimary
    readonly property int enabledCount: root.outputs.filter(o => o.enabled).length

    // A genuine staged edit against the greeter baseline (field-by-field, not "has an
    // overlay entry" — see stagedCfg's comment above) — same honesty contract as
    // HotkeysPanel.qml's profile-dirty banner.
    readonly property bool dirty: {
        if (root.scope !== "greeter") return false;
        if (root.stagedPrimary !== root.greeterPrimary) return true;
        for (const row of root.liveRows) {
            const s = root.greeterEffectiveRule(row.name);
            const b = root.greeterBaselineRule(row.name);
            if (s.mode !== b.mode || s.scale !== b.scale || s.transform !== b.transform
                || s.position !== b.position || s.disabled !== b.disabled) return true;
        }
        return false;
    }

    function reload() {
        listProc.running = false; listProc.running = true;
        statusProc.running = false; statusProc.running = true;
    }
    // Only the three privileged actions (and the initial load) touch the greeter reader —
    // NOT session-scope reload() — so an in-progress staged edit on the login-screen tab
    // survives the user tweaking session settings on the other tab.
    function reloadGreeter() { greeterStatusProc.running = false; greeterStatusProc.running = true; }

    // ── Staging / mutation dispatch ─────────────────────────────────────────────────
    // Session scope mutates `w-monitor` live and re-probes; greeter scope only updates the
    // local overlay (see stagedCfg) — nothing is written until "Apply".
    function applyOrStage(name, field, cliCmd, value) {
        if (root.scope === "session") root.mutate(cliCmd);
        else root.stageField(name, field, value);
    }
    function stageField(name, field, value) {
        const cur = Object.assign({}, root.greeterEffectiveRule(name));
        cur[field] = value;
        const cfg = Object.assign({}, root.stagedCfg);
        cfg[name] = cur;
        root.stagedCfg = cfg;
    }
    // Same failsafe parity as `w-monitor greeter primary`: force-enable the new primary so
    // primary and disabled never drift apart.
    function stagePrimary(name) {
        root.stagedPrimary = name;
        root.stageField(name, "disabled", "false");
    }
    function discardStaged() { root.stagedCfg = {}; root.stagedPrimary = root.greeterPrimary; }

    function transformIdxFromDeg(deg) { return ({ "0": "0", "90": "1", "180": "2", "270": "3" })[deg] || "0"; }
    function placeWordToPos(word) { return ({ "right": "auto-right", "left": "auto-left", "above": "auto-up", "below": "auto-down" })[word] || "auto"; }
    function posWordOrAuto(pos)   { return ({ "auto-right": "right", "auto-left": "left", "auto-up": "above", "auto-down": "below", "auto": "auto" })[pos] || "auto"; }

    // One spec per live output — `greeter apply` REPLACES the whole ruleset atomically, so
    // every known output needs an entry even if the user only touched one. The staged
    // primary rides along as a third on/off/primary state — "primary" implies on and is
    // what `cmd_greeter_apply` writes to $GREETER_STATE — so a primary change reaches the
    // greeter in the SAME single pkexec call as the rest of the tab, one prompt.
    function specForOutput(name) {
        const s = root.greeterEffectiveRule(name);
        const onoff = (root.stagedPrimary !== "" && name === root.stagedPrimary) ? "primary"
                      : (s.disabled === "true" ? "off" : "on");
        return name + ":" + s.mode + ":" + s.scale + ":" + root.transformDeg(s.transform) + ":"
             + root.posWordOrAuto(s.position) + ":" + onoff;
    }
    function applyGreeter() {
        const specs = root.liveRows.map(r => root.specForOutput(r.name));
        root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "monitor-greeter", "apply", ...specs],
                           () => root.reloadGreeter());
    }
    function copyFromSession() {
        root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "monitor-greeter", "sync"], () => root.reloadGreeter());
    }
    function resetGreeter() {
        root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "monitor-greeter", "reset"], () => root.reloadGreeter());
    }

    Process {
        id: listProc
        running: true
        command: ["w-monitor", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                for (const line of (this.text || "").split("\n")) {
                    if (!line.trim()) continue;
                    const f = line.split("\t");
                    if (f.length < 9) continue;
                    rows.push({ name: f[0], desc: f[1], mode: f[2], scale: f[3],
                                transform: f[4], enabled: f[6] });
                }
                root.liveRows = rows;
                root.modesQueue = rows.map(r => r.name);
                root.modesQueueIdx = 0;
                root.modesByOutput = {};
                root.fetchNextModes();
            }
        }
    }
    Process {
        id: statusProc
        running: true
        command: ["w-monitor", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                let primary = ""; const rules = {};
                for (const line of (this.text || "").split("\n")) {
                    if (line.startsWith("primary=")) { primary = line.slice(8); continue; }
                    if (!line.startsWith("rule=")) continue;
                    const f = line.slice(5).split("\t");
                    if (f.length < 6) continue;
                    rules[f[0]] = { mode: f[1], scale: f[2], transform: f[3], position: f[4], disabled: f[5] };
                }
                root.primary = primary;
                root.rules = rules;
            }
        }
    }
    // The login-screen baseline. Runs independently of listProc/statusProc (see reload()'s
    // comment) — its own reload only fires at mount and after apply/sync/reset succeed,
    // each of which clears the staged overlay by emptying it (greeterEffectiveRule then
    // reads straight through to the freshly-committed rules).
    Process {
        id: greeterStatusProc
        running: true
        command: ["w-monitor", "greeter", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                let primary = ""; const rules = {};
                for (const line of (this.text || "").split("\n")) {
                    if (line.startsWith("primary=")) { primary = line.slice(8); continue; }
                    if (!line.startsWith("rule=")) continue;
                    const f = line.slice(5).split("\t");
                    if (f.length < 6) continue;
                    rules[f[0]] = { mode: f[1], scale: f[2], transform: f[3], position: f[4],
                                     disabled: f[5] === "1" ? "true" : "false" };
                }
                root.greeterPrimary = primary;
                root.greeterRules = rules;
                root.stagedPrimary = primary;
                root.stagedCfg = {};
            }
        }
    }
    // Modes are fetched one output at a time through one shared Process — simpler and
    // deterministic than an instantiator fan-out for a panel that rarely has more than a
    // couple of heads.
    Process {
        id: modesProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = root.modesQueue[root.modesQueueIdx];
                const rows = [];
                for (const line of (this.text || "").split("\n")) {
                    if (!line.trim()) continue;
                    const f = line.split("\t");
                    if (f.length < 3) continue;
                    rows.push({ full: f[0], wh: f[1], hz: f[2] });
                }
                const mb = Object.assign({}, root.modesByOutput);
                mb[name] = rows;
                root.modesByOutput = mb;
            }
        }
        onExited: { root.modesQueueIdx++; root.fetchNextModes(); }
    }
    function fetchNextModes() {
        if (root.modesQueueIdx >= root.modesQueue.length) return;
        modesProc.command = ["w-monitor", "modes", root.modesQueue[root.modesQueueIdx], "--porcelain"];
        modesProc.running = true;
    }

    // Mutations — unprivileged, the Hyprland session is the user's own.
    Process { id: mutateProc; onExited: root.reload() }
    function mutate(cmd) { mutateProc.running = false; mutateProc.command = cmd; mutateProc.running = true; }

    // ── Helpers ──────────────────────────────────────────────────────────────────
    function currentWH(mode) { return (mode || "").split("@")[0] || ""; }
    function currentHz(mode) { const p = (mode || "").split("@"); return p[1] || ""; }
    function resOptions(modes) {
        const seen = {}; const out = [];
        for (const m of modes) { if (seen[m.wh]) continue; seen[m.wh] = true; out.push({ id: m.wh, label: m.wh }); }
        return out;
    }
    function freqOptions(modes, wh) {
        const seen = {}; const out = [];
        for (const m of modes) {
            if (m.wh !== wh || seen[m.hz]) continue;
            seen[m.hz] = true; out.push({ id: m.hz, label: m.hz + " Hz" });
        }
        return out;
    }
    // Modes are sorted by area desc, then Hz desc (w-monitor contract) — same-WH entries
    // are contiguous, so the first match is the highest refresh rate for that resolution.
    function bestHzFor(modes, wh) { for (const m of modes) if (m.wh === wh) return m.hz; return ""; }

    readonly property var scalePresets: ["auto", "1", "1.25", "1.5", "1.75", "2"]
    // Mirrors w-monitor's own scale-validity check (integral logical pixels).
    function scaleValid(widthPx, scaleId) {
        if (scaleId === "auto" || !widthPx) return true;
        const s = parseFloat(scaleId);
        if (!s) return true;
        const l = widthPx / s;
        return Math.abs(l - Math.round(l)) < 0.001;
    }
    function scaleOptions(widthPx) {
        return root.scalePresets.map(id => {
            const label = id === "auto" ? Strings.t("disp.scaleAuto") : id;
            const invalid = !root.scaleValid(widthPx, id);
            return { id: id, label: invalid ? (label + " (" + Strings.t("disp.scaleInvalid") + ")") : label };
        });
    }
    function scaleCurrentId(scaleStr) {
        if (scaleStr === "auto") return "auto";
        const f = parseFloat(scaleStr);
        for (const p of root.scalePresets) { if (p !== "auto" && Math.abs(parseFloat(p) - f) < 0.001) return p; }
        return "";
    }
    function scaleValueText(scaleStr) {
        if (scaleStr === "auto") return Strings.t("disp.scaleAuto");
        return "" + (Math.round(parseFloat(scaleStr) * 100) / 100);
    }

    readonly property var rotationOptions: [
        { id: "0", label: "0°" }, { id: "90", label: "90°" },
        { id: "180", label: "180°" }, { id: "270", label: "270°" },
    ]
    function transformDeg(t) { return ["0", "90", "180", "270"][parseInt(t) || 0] || "0"; }

    readonly property var placeOptions: [
        { id: "right", label: Strings.t("disp.place.right") }, { id: "left", label: Strings.t("disp.place.left") },
        { id: "above", label: Strings.t("disp.place.above") }, { id: "below", label: Strings.t("disp.place.below") },
    ]
    function posId(pos) {
        return ({ "auto-right": "right", "auto-left": "left", "auto-up": "above", "auto-down": "below" })[pos] || "";
    }
    function posValue(pos) { const id = root.posId(pos); return id ? Strings.t("disp.place." + id) : "—"; }

    readonly property var onOffOptions: [
        { id: "on", label: Strings.t("disp.on") }, { id: "off", label: Strings.t("disp.off") },
    ]

    // ── Fixed header: scope switch + login-screen hint/actions/banner ────────────────
    Column {
        id: topCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 12

        Row {
            spacing: 8
            Pill {
                label: Strings.t("disp.scope.session"); active: root.scope === "session"
                focused: root.focusRegion === "scope" && root.focusIdx === 0
                onClicked: { root.scope = "session"; root.focusRegion = "scope"; root.focusIdx = 0; }
            }
            Pill {
                label: Strings.t("disp.scope.greeter"); active: root.scope === "greeter"
                focused: root.focusRegion === "scope" && root.focusIdx === 1
                onClicked: { root.scope = "greeter"; root.focusRegion = "scope"; root.focusIdx = 1; }
            }
            // Not a third config scope but a third thing you do to a display, and the
            // switch is already the panel's idiom for "which of these am I editing".
            // Leaving the segment drops any live temperature preview (see nl.dropPreview).
            Pill {
                label: Strings.t("disp.scope.night")
                active: root.scope === "night"
                focused: root.focusRegion === "scope" && root.focusIdx === 2
                onClicked: { root.scope = "night"; root.focusRegion = "scope"; root.focusIdx = 2; }
            }
        }

        Column {
            visible: root.scope === "greeter"
            width: parent.width
            spacing: 10

            Text {
                width: parent.width
                text: Strings.t("disp.loginHint")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Row {
                spacing: 8
                Pill {
                    label: Strings.t("disp.copyFromSession")
                    focused: root.focusRegion === "actions" && root.focusIdx === 0
                    onClicked: root.copyFromSession()
                }
                Pill {
                    label: Strings.t("disp.resetAll"); danger: true
                    focused: root.focusRegion === "actions" && root.focusIdx === 1
                    onClicked: root.resetGreeter()
                }
            }

            // Unsaved staged edits — same "changed = effective ≠ baseline" honesty and
            // Save/Discard-style UX as HotkeysPanel.qml's profile-dirty banner.
            Rectangle {
                visible: root.dirty
                width: parent.width
                radius: Geometry.radiusSm
                color: Colors.inputBg
                border.width: HubConfig.border; border.color: Colors.accentInk
                implicitHeight: bannerCol.implicitHeight + 16
                Column {
                    id: bannerCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6
                    Text {
                        text: Strings.t("disp.unsaved")
                        color: Colors.accentInk
                        font.family: Fonts.family; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        text: Strings.t("disp.unsavedHint")
                        color: Colors.muted
                        font.family: Fonts.family; font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: 8
                        Pill {
                            label: Strings.t("disp.apply")
                            focused: root.focusRegion === "actions" && root.focusIdx === 2
                            onClicked: root.applyGreeter()
                        }
                        Pill {
                            label: Strings.t("disp.discard"); danger: true
                            focused: root.focusRegion === "actions" && root.focusIdx === 3
                            onClicked: root.discardStaged()
                        }
                    }
                }
            }
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { top: topCol.bottom; topMargin: 12
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        // Extend into the card's right padding so the scrollbar pill sits near the window
        // edge; the content column insets the same amount (see quickshell-hub.md, E=12).
        anchors.rightMargin: -12
        // Extends the clip rect into the card's left padding so a row's own -8
        // focus-wash bleed (SelectRow/HubRow) doesn't get cut off — Column.x below
        // compensates so the visible content itself doesn't shift (quickshell-hub.md
        // Ф-Keyboard gotcha 2).
        anchors.leftMargin: -8
        clip: true
        // +8 slack (2×4 bleed) for the first/last row's focus wash, via Column.y
        // below — NOT Flickable.topMargin/bottomMargin (gotcha 3, a documented trap).
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}
        // An open dropdown's position is computed once, at click time — it doesn't track
        // the row if the section is scrolled afterward. Closing on scroll (same effect as
        // an outside click) is simpler and more robust than chasing the row's position
        // through the Flickable's live transform.
        onContentYChanged: if (menuLayer.menuOpen) menuLayer.closeMenu()

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 20

            // Night light: a sibling file rather than more markup here — it shares no
            // state with the output rows (no outputs, no staging, no polkit) and this
            // panel is long enough already. `active` unloads it on scope change, which
            // is what fires its Component.onDestruction → `preview reset`, so an
            // unkept temperature never survives leaving the segment.
            Loader {
                id: nightLoader
                width: col.width
                active: root.scope === "night"
                visible: active
                source: "NightLightSection.qml"
                onLoaded: item.menuLayer = menuLayer
            }
            // DisplaysPanel stays the sole owner of the roving index (see the
            // framework comment above `focusRegion`) — the loaded section only
            // reads back which of its own fields is currently focused.
            Binding {
                target: nightLoader.item
                property: "focusedField"
                value: (root.scope === "night" && root.focusRegion === "content" && root.contentDesc[root.focusIdx])
                       ? root.contentDesc[root.focusIdx].field : ""
                when: nightLoader.status === Loader.Ready
            }
            // Tab/Esc out of a night-light text field hands real Qt focus back here,
            // same "child signals, panel calls forceActiveFocus()" contract as
            // PowerPanel's IdleRow.exitField().
            Connections {
                target: nightLoader.item
                function onRequestFocusReturn() { root.forceActiveFocus(); }
            }

            Repeater {
                id: outputRepeater
                // The night scope has no per-output rows; an empty model is cheaper and
                // clearer than wrapping every section in a visibility gate.
                model: root.scope === "night" ? [] : root.outputs
                Column {
                    id: sect
                    required property var modelData
                    required property int index
                    // Exposes this delegate's rows to DisplaysPanel's roving-focus
                    // dispatch (outputRepeater.itemAt(i).<alias>) — an id declared
                    // inside a delegate isn't visible from outside it without an alias.
                    property alias header: headerRow
                    property alias resRow: resRow
                    property alias freqRow: freqRow
                    property alias scaleRow: scaleRow
                    property alias rotRow: rotRow
                    property alias posRow: posRow
                    property alias enRow: enRow
                    property alias resetBtn: resetBtn
                    width: col.width
                    spacing: 10

                    readonly property var modes: root.modesByOutput[sect.modelData.name] || []
                    readonly property bool isPrimary: sect.modelData.name === root.effectivePrimary
                    // A greeter rule can carry a literal "preferred" mode (e.g. after
                    // "Copy from session" of a rule that was never pinned to a concrete
                    // resolution) — there's no live compositor here to resolve it, so fall
                    // back to the live output's current mode for display purposes only
                    // (same physical hardware as the session).
                    readonly property string _dispMode: sect.modelData.mode === "preferred"
                                                          ? root.liveModeFor(sect.modelData.name) : sect.modelData.mode
                    readonly property string wh: root.currentWH(sect._dispMode)
                    readonly property string hz: root.currentHz(sect._dispMode)

                    // ── Section header: name + summary, click/Enter = make primary ──
                    Item {
                        id: headerRow
                        width: parent.width
                        height: 40
                        // Same activated()-signal contract as SelectRow/HubRow/WButton —
                        // DisplaysPanel's generic Confirm dispatch (contentItemFor +
                        // `item.activated()`) reaches this row with no special-casing.
                        signal activated()
                        onActivated: if (!sect.isPrimary) {
                            if (root.scope === "session") root.mutate(["w-monitor", "primary", sect.modelData.name]);
                            else root.stagePrimary(sect.modelData.name);
                        }
                        readonly property bool rovingFocused: root.focusRegion === "content"
                            && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":primary"]

                        Rectangle {
                            anchors.fill: parent
                            radius: Geometry.radiusSm
                            color: (headerMa.containsMouse || headerRow.rovingFocused) && !sect.isPrimary
                                   ? Colors.hover : Colors.alpha(Colors.hover, 0)
                            border.width: headerRow.rovingFocused ? HubConfig.border : 0
                            border.color: Colors.accentInk
                        }
                        MouseArea {
                            id: headerMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: sect.isPrimary ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: headerRow.activated()
                        }
                        Row {
                            anchors { left: parent.left; leftMargin: 8
                                      right: badge.visible ? badge.left : parent.right; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            spacing: 10
                            ChromeIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 22
                                icon: "video-display"; glyph: String.fromCodePoint(0xf0379)   // nf-md-monitor
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: sect.modelData.name
                                    color: Colors.text
                                    font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.DemiBold
                                }
                                Text {
                                    text: (sect.modelData.desc || "—") + "  ·  "
                                          + (sect.modelData.mode === "preferred" ? (sect.wh + "@" + sect.hz) : sect.modelData.mode)
                                          + "  ·  ×" + root.scaleValueText(sect.modelData.scale)
                                    color: Colors.muted
                                    font.family: Fonts.family; font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Rectangle {
                            id: badge
                            visible: sect.isPrimary
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: badgeLbl.implicitWidth + 14
                            height: 20
                            radius: Geometry.radiusSm
                            color: "transparent"
                            border.width: HubConfig.border; border.color: Colors.accentInk
                            Text {
                                id: badgeLbl
                                anchors.centerIn: parent
                                text: Strings.t("disp.primary")
                                color: Colors.accentInk
                                font.family: Fonts.family; font.pixelSize: 10; font.weight: Font.Medium
                            }
                        }
                    }

                    SelectRow {
                        id: resRow
                        width: parent.width
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":res"]
                        glyph: String.fromCodePoint(0xf0a24)   // nf-md-aspect_ratio
                        label: Strings.t("disp.resolution")
                        currentId: sect.wh
                        value: sect.wh
                        options: root.resOptions(sect.modes)
                        onActivated: menuLayer.openMenu(resRow, options, currentId, (id) => {
                            const hz = root.bestHzFor(sect.modes, id);
                            const val = hz ? (id + "@" + hz) : id;
                            root.applyOrStage(sect.modelData.name, "mode", ["w-monitor", "mode", sect.modelData.name, val], val);
                        })
                    }
                    SelectRow {
                        id: freqRow
                        width: parent.width
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":freq"]
                        icon: "view-refresh"; glyph: String.fromCodePoint(0xf006a)   // nf-md-autorenew
                        label: Strings.t("disp.refresh")
                        currentId: sect.hz
                        value: sect.hz + " Hz"
                        options: root.freqOptions(sect.modes, sect.wh)
                        onActivated: menuLayer.openMenu(freqRow, options, currentId, (id) => {
                            const val = sect.wh + "@" + id;
                            root.applyOrStage(sect.modelData.name, "mode", ["w-monitor", "mode", sect.modelData.name, val], val);
                        })
                    }
                    SelectRow {
                        id: scaleRow
                        width: parent.width
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":scale"]
                        icon: "zoom-in"; glyph: String.fromCodePoint(0xf034b)   // nf-md-magnify_plus
                        label: Strings.t("disp.scale")
                        currentId: root.scaleCurrentId(sect.modelData.scale)
                        value: root.scaleValueText(sect.modelData.scale)
                        options: root.scaleOptions(parseInt(sect.wh.split("x")[0]) || 0)
                        onActivated: menuLayer.openMenu(scaleRow, options, currentId, (id) =>
                            root.applyOrStage(sect.modelData.name, "scale", ["w-monitor", "scale", sect.modelData.name, id], id))
                    }
                    SelectRow {
                        id: rotRow
                        width: parent.width
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":rot"]
                        icon: "object-rotate-right"; glyph: String.fromCodePoint(0xf0467)   // nf-md-rotate_right
                        label: Strings.t("disp.rotation")
                        currentId: root.transformDeg(sect.modelData.transform)
                        value: root.transformDeg(sect.modelData.transform) + "°"
                        options: root.rotationOptions
                        onActivated: menuLayer.openMenu(rotRow, options, currentId, (id) =>
                            root.applyOrStage(sect.modelData.name, "transform", ["w-monitor", "transform", sect.modelData.name, id],
                                               root.transformIdxFromDeg(id)))
                    }
                    SelectRow {
                        id: posRow
                        width: parent.width
                        visible: root.outputs.length >= 2
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":pos"]
                        glyph: String.fromCodePoint(0xf0616)   // nf-md-arrow_expand
                        label: Strings.t("disp.place")
                        currentId: root.posId(sect.modelData.position)
                        value: root.posValue(sect.modelData.position)
                        options: root.placeOptions
                        onActivated: menuLayer.openMenu(posRow, options, currentId, (id) =>
                            root.applyOrStage(sect.modelData.name, "position", ["w-monitor", "place", sect.modelData.name, id],
                                               root.placeWordToPos(id)))
                    }
                    SelectRow {
                        id: enRow
                        width: parent.width
                        visible: root.outputs.length >= 2
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":enabled"]
                        // Failsafe (mirrored server-side in `w-monitor disable`/`primary`): the
                        // primary output can never be turned off, and greys out here rather than
                        // just erroring on click — the CLI is the source of truth, this only
                        // reflects the invariant it enforces.
                        enabled: !sect.isPrimary && !(sect.modelData.enabled && root.enabledCount <= 1)
                        icon: "system-shutdown"; glyph: String.fromCodePoint(0xf0425)   // nf-md-power
                        label: Strings.t("disp.enabled")
                        currentId: sect.modelData.enabled ? "on" : "off"
                        value: sect.modelData.enabled ? Strings.t("disp.on") : Strings.t("disp.off")
                        options: root.onOffOptions
                        onActivated: menuLayer.openMenu(enRow, options, currentId, (id) =>
                            root.applyOrStage(sect.modelData.name, "disabled",
                                               ["w-monitor", id === "on" ? "enable" : "disable", sect.modelData.name],
                                               id === "on" ? "false" : "true"))
                    }
                    Text {
                        width: parent.width
                        visible: enRow.visible && !enRow.enabled
                        text: sect.isPrimary ? Strings.t("disp.primaryLocked") : Strings.t("disp.lastOutput")
                        color: Colors.muted
                        font.family: Fonts.family; font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    // No per-output reset in the greeter scope — only the whole-config
                    // "Сбросить" action above (`w-monitor greeter reset` has no per-output
                    // form).
                    WButton {
                        id: resetBtn
                        visible: root.scope === "session"
                        label: Strings.t("disp.reset")
                        focused: root.focusRegion === "content" && root.focusIdx === root.contentIndexOf["row:" + sect.index + ":reset"]
                        onClicked: root.mutate(["w-monitor", "reset", sect.modelData.name])
                    }
                }
            }
        }
    }

    // ── Dropdown overlay layer (above the content; sized to the viewport) ─────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }
}
