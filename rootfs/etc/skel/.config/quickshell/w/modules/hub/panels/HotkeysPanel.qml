// W Linux — Hub Hotkeys panel (Ф-B view/switch · Ф-C1 rebind · Ф-C2 custom · Ф-C3 profiles).
// The Hotkeys drill-in screen: the Hyprland keybindings as data. A fixed profile selector on
// top switches the active profile (built-in default / i3-vim or a user profile); the scrolling
// body lists custom actions, your saved profiles, then every rebindable action grouped by
// category with its effective chord (customised binds accented, clashing binds danger-flagged).
// It is a pure front-end over the user-space `w-hotkeys` CLI — no polkit, the session is the
// user's own — reading its porcelain contracts (profiles / catalog / custom) and mutating with
// use / set / reset / custom-add / custom-rm / profile-new / profile-rm (each live-reloads).
//
// C3 honest-dirty: `use <p>` writes the profile's whole diff into the fragment map, so a chord
// the profile itself provides reads as "override" in the catalog's source column. To tell a
// genuine user edit from a profile default, the catalog porcelain carries a 6th column — the
// active profile's baseline chord — and a row is `changed` only when effective ≠ baseline. Any
// changed row raises the "unsaved changes" banner (switching profiles would discard them):
// Save-as writes a user profile (profile-new --from current) and switches onto it; Discard-all
// reverts the map to the profile (reset --all).
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/HotkeysPanel.qml"}); as a subdir
// file it is not a module type, so the shared hub components (SelectRow, HubMenu, HubSection,
// HubRow) come in through `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // Full natural height (fixed selector/banner + gap + list) drives the Hub card morph; when
    // it exceeds the cap the Hub bounds the panel and the list scrolls internally. `+8` mirrors
    // the Flickable's own contentHeight padding below (focus-wash bleed slack, gotcha #6 — without
    // it `flick` is permanently 8px shorter than its own contentHeight). menuLayer.menuBottom grows
    // the card under the open profile dropdown when it would otherwise clip.
    implicitHeight: Math.max(topCol.implicitHeight + 12 + listCol.implicitHeight + 8, menuLayer.menuBottom)

    // Emitted when chord capture ends or a prompt closes: the Hub re-grabs keyboard focus on its
    // card so Esc / Backspace navigate again (during capture / a prompt we hold focus elsewhere).
    signal restoreFocus()
    // Up on the topmost roving position hands the cursor to the header's "?" button
    // (Hub.qml's focusHeaderHelp). A route with no `help` entry has no button and the
    // Hub answers false — the cursor simply stays where it is.
    signal focusHeader()


    // The shared pill (core/WPill.qml) with the Hub's outline width — used across
    // the banner and prompt forms. Was a file-local copy of the same Rectangle.
    component Pill: WPill { borderWidth: HubConfig.border }

    // ── Profiles (w-hotkeys profiles --porcelain: name⇥kind⇥active) ──────────────────
    property var    profileOptions: []   // [{id,label}] for the switch dropdown
    property var    userProfiles: []     // deletable user profile names
    property string activeProfile: "default"
    Process {
        id: profilesProc
        running: true
        command: ["w-hotkeys", "profiles", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const opts = [];
                const users = [];
                let active = "default";
                for (const line of (this.text || "").split("\n")) {
                    if (!line.trim()) continue;
                    const f = line.split("\t");
                    if (f.length < 1 || !f[0]) continue;
                    opts.push({ id: f[0], label: f[0] });
                    if (f[1] === "user") users.push(f[0]);
                    if (f[2] === "1") active = f[0];
                }
                root.profileOptions = opts;
                root.userProfiles = users;
                root.activeProfile = active;
            }
        }
    }

    // ── Catalog (token⇥category⇥default⇥chord⇥source⇥profile-baseline) ────────────────
    // Flattened into a display list: a section marker per new category, then one row per action.
    // `changed` = effective chord differs from the active profile's baseline (a genuine user
    // edit), NOT merely "in the fragment map" — see the file header.
    property var rows: []
    Process {
        id: catalogProc
        running: true
        command: ["w-hotkeys", "catalog", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let lastCat = "";
                for (const line of (this.text || "").split("\n")) {
                    if (!line.trim()) continue;
                    const f = line.split("\t");
                    if (f.length < 6) continue;
                    const cat = f[1];
                    if (cat !== lastCat) { out.push({ section: true, cat: cat }); lastCat = cat; }
                    // `cat` rides the action rows too: the "menu" category renders a second,
                    // muted chip with the chord's in-a-text-field form (see fieldChip below).
                    out.push({ section: false, token: f[0], cat: cat, chord: f[3], changed: f[3] !== f[5] });
                }
                root.rows = out;
            }
        }
    }

    // ── Custom actions (w-hotkeys custom --porcelain: chord⇥exec) ─────────────────────
    property var customActions: []   // [{chord,exec}]
    Process {
        id: customProc
        running: true
        command: ["w-hotkeys", "custom", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of (this.text || "").split("\n")) {
                    if (!line.trim()) continue;
                    const f = line.split("\t");
                    if (f.length < 2 || !f[0]) continue;
                    out.push({ chord: f[0], exec: f[1] });
                }
                root.customActions = out;
            }
        }
    }

    // Chords bound to >1 action ({chord: true}), over BOTH the token binds and custom actions.
    // Hyprland lets the LAST bind of a duplicated chord win, silently shadowing the others — a
    // real footgun (e.g. i3's close + kill both land on SUPER+SHIFT+Q, or a custom action
    // shadowing a real bind). Both sides of a clash are flagged (danger-coloured chip), since
    // highlighting only one would misread which bind actually fires.
    property var conflictChords: root.computeConflicts(root.rows, root.customActions)
    function computeConflicts(rws, customs) {
        const counts = {};
        for (const r of rws) if (r.section !== true && r.chord) counts[r.chord] = (counts[r.chord] || 0) + 1;
        for (const c of customs) if (c.chord) counts[c.chord] = (counts[c.chord] || 0) + 1;
        const conf = {};
        for (const k in counts) if (counts[k] > 1) conf[k] = true;
        return conf;
    }

    // Per-chord member labels ({chord: [action names]}, over tokens + custom execs) — the
    // data behind the conflict hover tooltip so a danger chip can name what else it clashes
    // with (Hyprland silently lets the last bind win, so knowing the other side matters).
    property var conflictMembers: root.computeConflictMembers(root.rows, root.customActions)
    function computeConflictMembers(rws, customs) {
        const groups = {};
        for (const r of rws) if (r.section !== true && r.chord) (groups[r.chord] = groups[r.chord] || []).push(root.labelFor(r.token));
        for (const c of customs) if (c.chord) (groups[c.chord] = groups[c.chord] || []).push(c.exec);
        return groups;
    }
    // "Also bound to: X, Y" for a chord, listing the other members (self excluded).
    function conflictText(chord, selfLabel) {
        const others = (root.conflictMembers[chord] || []).filter(x => x !== selfLabel);
        return Strings.t("hotkeys.alsoBound") + " " + others.join(", ");
    }

    // Any user edit pending against the active profile → the "unsaved changes" banner.
    readonly property bool dirty: {
        for (let i = 0; i < rows.length; i++) if (rows[i].section !== true && rows[i].changed) return true;
        return false;
    }

    // Built-in profile ids ("default" = catalog defaults, "i3-vim" = i3 legacy) — reserved,
    // cannot be saved onto or deleted. Profile ids are single lowercase words (a-z 0-9 -), so
    // they show verbatim; there is no display-name mapping.
    function isReserved(name) { return name === "default" || name === "i3-vim"; }
    // The active profile is a (rewritable) user profile → offer a plain "Save" that overwrites it.
    readonly property bool activeIsUser: activeProfile !== "" && !isReserved(activeProfile)

    // ── Mutations (all user-space; each CLI call live-reloads, then we re-probe) ──────
    // Switch profile. Re-probe both readers on exit — effective chords + the active marker changed.
    // These four can change a token's effective chord (profile switch / rebind / reset) —
    // menu_up/down/left/right included, so the Hub's own roving-nav resolver (HubNavKeys,
    // read by RootGrid/HubMenu/every other panel) is re-probed alongside the catalog list.
    Process {
        id: useProc
        onExited: { catalogProc.running = true; profilesProc.running = true; HubNavKeys.refresh(); }
    }
    function useProfile(name) { root.endCapture(); useProc.command = ["w-hotkeys", "use", name]; useProc.running = true; }

    Process { id: setProc;      onExited: { catalogProc.running = true; HubNavKeys.refresh(); } }
    Process { id: resetProc;    onExited: { catalogProc.running = true; HubNavKeys.refresh(); } }
    Process { id: resetAllProc; onExited: { catalogProc.running = true; HubNavKeys.refresh(); } }
    Process {
        id: saveProc                                  // profile-new --from current
        property string pendingName: ""
        onExited: (code) => { if (code === 0) root.useProfile(saveProc.pendingName); else catalogProc.running = true; }
    }
    Process { id: saveCurrentProc; onExited: { catalogProc.running = true; profilesProc.running = true; } }
    Process { id: delProfileProc; onExited: { profilesProc.running = true; catalogProc.running = true; HubNavKeys.refresh(); } }
    Process { id: customAddProc;  onExited: customProc.running = true }
    Process { id: customRmProc;   onExited: customProc.running = true }

    function resetToken(token)     { resetProc.command    = ["w-hotkeys", "reset", token]; resetProc.running = true; }
    function resetAll()            { resetAllProc.command = ["w-hotkeys", "reset", "--all"]; resetAllProc.running = true; }
    // Overwrite the active user profile with the current effective binds (profile-new mv's over
    // the existing file); baseline then equals effective, so the dirty banner clears. Built-in
    // profiles are never the target — the button is hidden unless activeIsUser.
    function saveCurrent()         { saveCurrentProc.command = ["w-hotkeys", "profile-new", activeProfile, "--from", "current"]; saveCurrentProc.running = true; }
    function deleteProfile(name)   { delProfileProc.command = ["w-hotkeys", "profile-rm", name]; delProfileProc.running = true; }
    function removeCustom(chord)   { customRmProc.command = ["w-hotkeys", "custom-rm", chord]; customRmProc.running = true; }
    function saveProfile(name)     {
        saveProc.pendingName = name;
        saveProc.command = ["w-hotkeys", "profile-new", name, "--from", "current"];
        saveProc.running = true;
        root.closePrompt();
    }
    function addCustom(chord, exec) {
        customAddProc.command = ["w-hotkeys", "custom-add", chord, exec];
        customAddProc.running = true;
        root.closePrompt();
    }

    // Human label for a token. Numbered-workspace tokens (ws_<n> / move_ws_<n>) resolve from a
    // template with %n% substituted; everything else is a plain hotkeys.<token> key.
    function labelFor(token) {
        let m = token.match(/^ws_(\d+)$/);
        if (m) return Strings.t("hotkeys.ws").replace("%n%", m[1]);
        m = token.match(/^move_ws_(\d+)$/);
        if (m) return Strings.t("hotkeys.move_ws").replace("%n%", m[1]);
        return Strings.t("hotkeys." + token);
    }

    // Second, muted chord shown on a `menu` row: the same action's form inside a panel
    // whose text field owns the keyboard (Launcher/Clipboard/Assistant/Layouts, the three
    // searchable pickers, the password prompt). There the bare chord would be typed into
    // the field instead of acting, so the whole set moves behind Ctrl — fixed, not a
    // setting, because Ctrl+<key> is the only prefix a text field provably never eats.
    // menu_delete additionally keeps the desktop-idiom Shift+Del alias. Rendering both
    // chords side by side is the point: a user should never have to derive the second one.
    // See core/HubNavKeys.qml's fieldAction() for the resolver these strings describe.
    function fieldChord(token, chord) {
        if (!chord) return "";
        const ctrl = "Ctrl + " + chord;
        return token === "menu_delete" ? "Shift+Del · " + ctrl : ctrl;
    }

    // ── Chord capture / rebind (C1) + capture-for-custom (C2) ────────────────────────
    // Rebinding is DATA: the GUI writes the chord via `w-hotkeys set <token> <chord>` and
    // re-probes. Clicking a chord chip arms capture for that token; captureItem grabs keyboard
    // focus and reads the next key press into a canonical chord. In captureCustom mode the same
    // machinery fills `customChord` for the add-action form instead of calling `set`.
    property string captureToken: ""    // armed token (or "__custom__" sentinel); "" = idle
    property bool   captureCustom: false
    property string customChord: ""     // captured chord for the pending custom action

    // Chord capture must suspend Hyprland's global binds, otherwise pressing an already-bound
    // combo (e.g. SUPER+Return) fires its dispatcher at the compositor and never reaches this
    // surface. Entering the empty `capture` submap makes every unbound key pass through to the
    // (keyboard-focused) Hub; endCapture always resets it. Lua-config dispatch form.
    Process { id: submapProc }
    function enterCaptureSubmap() { submapProc.command = ["hyprctl", "dispatch", 'hl.dsp.submap("capture")']; submapProc.running = true; }
    function exitCaptureSubmap()  { submapProc.command = ["hyprctl", "dispatch", 'hl.dsp.submap("reset")'];   submapProc.running = true; }

    function startCapture(token)  { root.captureCustom = false; root.captureToken = token; root.enterCaptureSubmap(); captureItem.forceActiveFocus(); }
    function startCaptureCustom() { root.captureCustom = true;  root.captureToken = "__custom__"; root.enterCaptureSubmap(); captureItem.forceActiveFocus(); }
    function endCapture() {
        if (!root.captureToken) return;
        root.exitCaptureSubmap();
        root.captureToken = "";
        root.captureCustom = false;
        // Return focus into the open custom form, else hand it back to the Hub for navigation.
        if (root.promptMode !== "") cmdField.input.forceActiveFocus();
        else root.restoreFocus();
    }
    function applyChord(token, chord) {
        setProc.command = ["w-hotkeys", "set", token, chord];
        setProc.running = true;
        root.endCapture();
    }

    // Map a Qt key event to a Hyprland keysym byte-identical to catalog.tokens ("A", "1",
    // "Return", "left", "F5", "semicolon"…). Returns "" for keys we won't bind (bare modifiers,
    // unmapped punctuation) so garbage never reaches `w-hotkeys set` / a custom action.
    readonly property var _keysyms: ({})   // filled in Component.onCompleted (Qt.Key_* consts)
    function keysym(ev) {
        const k = ev.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode("A".charCodeAt(0) + (k - Qt.Key_A));
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode("0".charCodeAt(0) + (k - Qt.Key_0));
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (1 + k - Qt.Key_F1);
        return root._keysyms[k] || "";
    }
    Component.onCompleted: {
        root._keysyms[Qt.Key_Return]    = "Return";
        root._keysyms[Qt.Key_Enter]     = "Return";      // keypad Enter
        root._keysyms[Qt.Key_Space]     = "Space";
        root._keysyms[Qt.Key_Tab]       = "Tab";
        // Backspace WITH a modifier is a real key (powermenu default is SUPER + Backspace); a
        // LONE Backspace is intercepted earlier as the unbind gesture, so it never reaches here.
        root._keysyms[Qt.Key_Backspace] = "Backspace";
        root._keysyms[Qt.Key_Left]      = "left";
        root._keysyms[Qt.Key_Right]     = "right";
        root._keysyms[Qt.Key_Up]        = "up";
        root._keysyms[Qt.Key_Down]      = "down";
        root._keysyms[Qt.Key_Home]      = "Home";
        root._keysyms[Qt.Key_End]       = "End";
        root._keysyms[Qt.Key_PageUp]    = "Prior";
        root._keysyms[Qt.Key_PageDown]  = "Next";
        root._keysyms[Qt.Key_Insert]    = "Insert";
        root._keysyms[Qt.Key_Delete]    = "Delete";
        root._keysyms[Qt.Key_Print]     = "Print";
        root._keysyms[Qt.Key_Semicolon] = "semicolon";
        root._keysyms[Qt.Key_Comma]     = "comma";
        root._keysyms[Qt.Key_Period]    = "period";
        root._keysyms[Qt.Key_Slash]     = "slash";
        root._keysyms[Qt.Key_Backslash] = "backslash";
        root._keysyms[Qt.Key_Minus]     = "minus";
        root._keysyms[Qt.Key_Equal]     = "equal";
        root._keysyms[Qt.Key_BracketLeft]  = "bracketleft";
        root._keysyms[Qt.Key_BracketRight] = "bracketright";
        root._keysyms[Qt.Key_Apostrophe]   = "apostrophe";
        root._keysyms[Qt.Key_QuoteLeft]    = "grave";
    }

    // Invisible focus sink: while armed it holds keyboard focus and turns the press into a chord.
    // Modifier order is canonical (SUPER, CTRL, SHIFT, ALT) to match the catalog so override /
    // default comparison stays byte-exact.
    Item {
        id: captureItem
        focus: false
        Keys.onPressed: (ev) => {
            if (!root.captureToken || ev.isAutoRepeat) { ev.accepted = true; return; }
            ev.accepted = true;
            if (ev.key === Qt.Key_Escape) { root.endCapture(); return; }
            if (!root.captureCustom && ev.key === Qt.Key_Backspace && ev.modifiers === Qt.NoModifier) {
                root.applyChord(root.captureToken, "");   // lone Backspace = unbind (token mode only)
                return;
            }
            const ks = root.keysym(ev);
            if (!ks) return;   // bare modifier or unmappable key: keep waiting
            const mods = [];
            if (ev.modifiers & Qt.MetaModifier)    mods.push("SUPER");
            if (ev.modifiers & Qt.ControlModifier) mods.push("CTRL");
            if (ev.modifiers & Qt.ShiftModifier)   mods.push("SHIFT");
            if (ev.modifiers & Qt.AltModifier)     mods.push("ALT");
            // menu_* actions are Quickshell-local and only ever resolve a bare key (see
            // HubNavKeys.keyFor()/w-hotkeys' menu_chord_valid — modifiers there would
            // silently never fire); keep waiting for a bare press instead of sending a
            // chord the backend would reject anyway.
            if (!root.captureCustom && root.captureToken.indexOf("menu_") === 0 && mods.length > 0) return;
            mods.push(ks);
            const chord = mods.join(" + ");
            if (root.captureCustom) { root.customChord = chord; root.endCapture(); }
            else                    root.applyChord(root.captureToken, chord);
        }
    }

    // ── Prompt plumbing (save-as name / custom-action add form) ──────────────────────
    property string promptMode: ""   // "" | "save" | "custom"
    function openSavePrompt()   {
        root.promptMode = "save"; root.promptFocusIndex = 0;
        nameField.input.clear(); nameField.input.forceActiveFocus();
    }
    function openCustomPrompt() {
        root.promptMode = "custom"; root.promptFocusIndex = 1;   // lands in the command field, capChip (0) reachable via Up
        root.customChord = ""; cmdField.input.clear(); cmdField.input.forceActiveFocus();
    }
    function closePrompt() {
        if (root.captureToken !== "") root.exitCaptureSubmap();   // cancelled mid-capture
        root.promptMode = "";
        root.promptFocusIndex = 0;
        root.captureToken = "";
        root.captureCustom = false;
        root.customChord = "";
        root.restoreFocus();
    }

    // ── Keyboard roving-focus (flat descriptor list — quickshell-hub.md's Ф-Keyboard
    // framework). Four independent async sources feed this panel (profileOptions/rows/
    // customActions/userProfiles all start empty and fill in via Process.onStreamFinished,
    // AFTER Component.onCompleted) — the same shape as AIProfilesPanel's gotcha #15
    // marker, so `focusedKey` (not a bare index) is used from the start rather than
    // retrofitted later. The list spans BOTH the fixed selector/banner above the
    // Flickable and the scrolling body below it, in visual top-to-bottom order, so
    // Up/Down flow naturally between the two regions; `fixed:true` entries are always
    // on-screen and skip scrollIntoView.
    function buildContent() {
        const arr = [];
        arr.push({ field: "profile", key: "profile", fixed: true });
        if (root.dirty) {
            if (root.activeIsUser) arr.push({ field: "save", key: "save", fixed: true });
            arr.push({ field: "saveAs", key: "saveAs", fixed: true });
            arr.push({ field: "discardAll", key: "discardAll", fixed: true });
        }
        for (const c of root.customActions)
            arr.push({ field: "customDel", key: "custom:" + c.chord, chord: c.chord });
        arr.push({ field: "addCustom", key: "addCustom" });
        for (const name of root.userProfiles)
            arr.push({ field: "profileDel", key: "userProfile:" + name, name: name });
        for (const r of root.rows)
            if (r.section !== true) arr.push({ field: "token", key: "token:" + r.token, token: r.token });
        return arr;
    }
    readonly property var contentDesc: root.buildContent()
    readonly property var contentIndexOf: {
        const m = {};
        for (let i = 0; i < root.contentDesc.length; i++) m[root.contentDesc[i].key] = i;
        return m;
    }
    // Only the rows living inside `flick` ever need scrolling into view — used by
    // scrollIntoView's true-edge-first check (gotcha #4) scoped to that sub-list.
    readonly property var flickDesc: root.contentDesc.filter((d) => !d.fixed)
    property int focusIndex: 0
    // Which descriptor focusIndex currently points at, by key — not just the numeric
    // clamp below (gotcha #15: rows can be spliced in BEFORE the cursor's current slot
    // once an async source resolves, e.g. the dirty banner appearing above the list).
    property string focusedKey: ""
    onContentDescChanged: {
        const at = root.contentIndexOf[root.focusedKey];
        root.focusIndex = at !== undefined ? at : Math.max(0, Math.min(root.focusIndex, root.contentDesc.length - 1));
        root.focusedKey = (root.contentDesc[root.focusIndex] || {}).key || "";
    }

    function customItemFor(chord) {
        for (let i = 0; i < root.customActions.length; i++)
            if (root.customActions[i].chord === chord) return customRepeater.itemAt(i);
        return null;
    }
    function userProfileItemFor(name) {
        for (let i = 0; i < root.userProfiles.length; i++)
            if (root.userProfiles[i] === name) return userProfileRepeater.itemAt(i);
        return null;
    }
    function tokenItemFor(token) {
        for (let i = 0; i < root.rows.length; i++)
            if (root.rows[i].section !== true && root.rows[i].token === token) return tokenRepeater.itemAt(i);
        return null;
    }
    function contentItemFor(d) {
        if (!d) return null;
        switch (d.field) {
        case "profile":    return profileRow;
        case "save":       return bannerSavePill;
        case "saveAs":     return bannerSaveAsPill;
        case "discardAll": return bannerDiscardPill;
        case "addCustom":  return addCustomRow;
        case "customDel":  return root.customItemFor(d.chord);
        case "profileDel": return root.userProfileItemFor(d.name);
        case "token":      return root.tokenItemFor(d.token);
        }
        return null;
    }
    // True-edge-first (gotcha #4): a plain "bring bounds into view" stops short of the
    // Flickable's own top/bottom bleed slack (gotcha #3's `+8`/`y:4` below).
    function scrollIntoView(i) {
        const d = root.contentDesc[i];
        if (!d || d.fixed) return;   // topCol rows are always on-screen, nothing to scroll
        const item = root.contentItemFor(d);
        if (!item) return;
        const flickIdx = root.flickDesc.indexOf(d);
        if (flickIdx === 0) { flick.contentY = 0; return; }
        if (flickIdx === root.flickDesc.length - 1) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }
    function focusRow(i) {
        root.focusIndex = Math.max(0, Math.min(i, root.contentDesc.length - 1));
        root.focusedKey = (root.contentDesc[root.focusIndex] || {}).key || "";
        root.scrollIntoView(root.focusIndex);
    }

    focus: true
    Keys.onPressed: (e) => {
        if (root.promptMode !== "") { root.handlePromptKey(e); return; }
        const cd = root.contentDesc;
        if (cd.length === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:
            if (root.focusIndex === 0) { root.focusHeader(); e.accepted = true; return; }
            root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.del: {
            const d = cd[root.focusIndex];
            // Mirrors the mouse's × exactly on both row kinds — that click removes with
            // no confirm step either, so keyboard doesn't invent a two-step arm/confirm
            // (gotcha #14 doesn't apply the way it does to AppearancePanel's tiles).
            if (d && d.field === "customDel") root.removeCustom(d.chord);
            else if (d && d.field === "profileDel") root.deleteProfile(d.name);
            e.accepted = true;
            return;
        }
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const d = cd[root.focusIndex];
            if (!d) { e.accepted = true; return; }
            switch (d.field) {
            // Mirrors SelectRow's own MouseArea gate (`onClicked: if (root.interactive)
            // root.activated()`) — calling the signal directly would otherwise bypass it
            // while the profile list is still loading (profileRow briefly disabled).
            case "profile":    if (profileRow.interactive) profileRow.activated(); break;
            case "save":       root.saveCurrent(); break;
            case "saveAs":     root.openSavePrompt(); break;
            case "discardAll": root.resetAll(); break;
            case "addCustom":  root.openCustomPrompt(); break;
            case "token": {
                // Shift+confirm reaches the reset ↺ (only meaningful once overridden);
                // plain confirm mirrors the chord chip's own click (arm capture) — no
                // new `menu` token needed (gotcha #13), same trick as every other panel's
                // second verb this session.
                if (e.modifiers & Qt.ShiftModifier) {
                    const row = root.rows.find((r) => r.section !== true && r.token === d.token);
                    if (row && row.changed) root.resetToken(d.token);
                } else {
                    root.startCapture(d.token);
                }
                break;
            }
            }
            e.accepted = true;
            return;
        }
        }
    }

    // ── Prompt-local roving (save-as name / custom-action form) — separate small list,
    // guarded ahead of the main switch above (root.promptMode !== ""). Escape/Backspace
    // close the prompt LOCALLY instead of bubbling to Hub.qml's card.back(), same shape
    // as every other panel's prompt/pendingDelete guard this session.
    property int promptFocusIndex: 0
    function promptMaxIndex() { return root.promptMode === "custom" ? 3 : 2; }
    function promptItemAt(i) {
        if (root.promptMode === "save") {
            if (i === 0) return nameField;
            if (i === 1) return savePromptSavePill;
            if (i === 2) return savePromptCancelPill;
        } else if (root.promptMode === "custom") {
            if (i === 0) return capChip;
            if (i === 1) return cmdField;
            if (i === 2) return customPromptAddPill;
            if (i === 3) return customPromptCancelPill;
        }
        return null;
    }
    function promptFocusRow(i) {
        root.promptFocusIndex = Math.max(0, Math.min(i, root.promptMaxIndex()));
        const it = root.promptItemAt(root.promptFocusIndex);
        if (it && it.input !== undefined) it.input.forceActiveFocus();
        else root.forceActiveFocus();   // real Qt focus back on root so Keys.onPressed keeps receiving events
    }
    function handlePromptKey(e) {
        if (e.key === HubNavKeys.back || e.key === Qt.Key_Escape || e.key === Qt.Key_Backspace) {
            root.closePrompt(); e.accepted = true; return;
        }
        switch (e.key) {
        case HubNavKeys.down:
        case HubNavKeys.right:
            root.promptFocusRow(root.promptFocusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:
        case HubNavKeys.left:
            root.promptFocusRow(root.promptFocusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            // capChip/nameField are handled directly (not real widgets with a `clicked`
            // signal, or submission needs the validity gate the field's own onAccepted
            // already carries) — everything else (Save/Cancel/Add pills) dispatches
            // generically, but only when actually enabled: `.clicked()` called on a
            // disabled WPill bypasses its own MouseArea gate entirely.
            if (root.promptMode === "custom" && root.promptFocusIndex === 0) {
                root.startCaptureCustom(); e.accepted = true; return;
            }
            if (root.promptMode === "save" && root.promptFocusIndex === 0) {
                if (savePromptCol.nameOk) root.saveProfile(nameField.text);
                e.accepted = true; return;
            }
            const it = root.promptItemAt(root.promptFocusIndex);
            if (it && it.clicked !== undefined && it.enabled !== false) it.clicked();
            e.accepted = true;
            return;
        }
        }
    }

    // ── Fixed selector + unsaved-changes banner (stay put while the list scrolls) ────
    Column {
        id: topCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 12

        HubSection { width: parent.width; text: Strings.t("hotkeys.profile") }
        SelectRow {
            id: profileRow
            width: parent.width
            icon: "preferences-desktop-keyboard-shortcuts"; glyph: String.fromCodePoint(0xf030c) // nf-md-keyboard
            label: Strings.t("hotkeys.profile")
            enabled: root.profileOptions.length > 0
            currentId: root.activeProfile
            options: root.profileOptions
            value: root.activeProfile || "—"
            focused: root.focusedKey === "profile"
            onActivated: menuLayer.openMenu(profileRow, root.profileOptions, root.activeProfile,
                                       (id) => root.useProfile(id))
        }
        // How-to for the (non-obvious) click-to-capture rebind affordance below.
        Text {
            width: parent.width
            text: Strings.t("hotkeys.rebind")
            color: Colors.muted
            font.family: Fonts.family
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        // Unsaved edits are ad-hoc overrides that `use <profile>` would discard — offer to save
        // them as a user profile (and switch onto it) or revert to the active profile.
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
                    text: Strings.t("hotkeys.unsaved")
                    color: Colors.accentInk
                    font.family: Fonts.family; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    width: parent.width
                    text: Strings.t("hotkeys.unsavedHint")
                    color: Colors.muted
                    font.family: Fonts.family; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    // Save to the current profile (only when it is a rewritable user profile).
                    Pill {
                        id: bannerSavePill
                        visible: root.activeIsUser
                        label: Strings.t("hotkeys.save")
                        focused: root.focusedKey === "save"
                        onClicked: root.saveCurrent()
                    }
                    Pill {
                        id: bannerSaveAsPill
                        label: Strings.t("hotkeys.saveAs")
                        focused: root.focusedKey === "saveAs"
                        onClicked: root.openSavePrompt()
                    }
                    Pill {
                        id: bannerDiscardPill
                        label: Strings.t("hotkeys.discardAll")
                        danger: true
                        focused: root.focusedKey === "discardAll"
                        onClicked: root.resetAll()
                    }
                }
            }
        }
    }

    // ── Scrolling body: custom actions · your profiles · categorised bindings ────────
    Flickable {
        id: flick
        anchors { top: topCol.bottom; topMargin: 12
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        // Extend into the card's right padding so the scrollbar pill sits near the window edge;
        // the content column insets the same amount, keeping its padding symmetric.
        anchors.rightMargin: -12
        // Mirrors every other panel's left-side bleed lane (gotcha #2): clip:true cuts
        // anything outside the Flickable's OWN rect, and each row's keyboard-focus wash
        // bleeds -8 past its own left edge — without this the bleed lands at negative x
        // and gets clipped to nothing. `listCol.x` insets the same 8 so visible content
        // doesn't shift; only the bleed lane grows.
        anchors.leftMargin: -8
        clip: true
        // +8 slack (4 at each end) for the first/last row's -4 top/bottom wash bleed to
        // scroll fully into view (gotcha #4) — via contentHeight+`listCol.y`, NOT
        // Flickable's own topMargin/bottomMargin (gotcha #3: that centers content when
        // content+margins fit the viewport, offsetting the resting contentY).
        contentHeight: listCol.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: listCol
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 8

            // ── Custom actions (C2) ──────────────────────────────────────────────
            HubSection { width: parent.width; text: Strings.t("hotkeys.custom") }
            Repeater {
                id: customRepeater
                model: root.customActions
                delegate: Item {
                    id: crow
                    required property var modelData
                    width: listCol.width
                    height: 30
                    readonly property bool conflict: modelData.chord !== "" && root.conflictChords[modelData.chord] === true

                    // Keyboard roving-focus wash — full-row bleed (gotcha #1: both
                    // horizontal AND vertical margins, or the wash visually "slips"
                    // against neighboring rows). The row's only real action is the ×
                    // (del) below — there is no body-click equivalent for confirm.
                    Rectangle {
                        anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                        radius: Geometry.radiusSm
                        visible: root.focusedKey === "custom:" + crow.modelData.chord
                        color: Colors.hover
                    }

                    Text {
                        anchors { left: parent.left; right: cDelBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: crow.modelData.exec
                        color: Colors.text
                        font.family: Fonts.family; font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                    Text {
                        id: cDelBtn
                        anchors { right: cChip.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: String.fromCodePoint(0xf0156)   // nf-md-close
                        font.family: Fonts.mono; font.pixelSize: 14
                        color: cDelMa.containsMouse ? Colors.dangerBorder : Colors.muted
                        MouseArea {
                            id: cDelMa
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeCustom(crow.modelData.chord)
                        }
                    }
                    Rectangle {
                        id: cChip
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: cChordLbl.implicitWidth + 16
                        height: 24
                        radius: Geometry.radiusSm
                        color: "transparent"
                        border.width: HubConfig.border
                        border.color: crow.conflict ? Colors.dangerBorder : Colors.accentInk
                        Text {
                            id: cChordLbl
                            anchors.centerIn: parent
                            text: crow.modelData.chord
                            color: crow.conflict ? Colors.dangerBorder : Colors.accentInk
                            font.family: Fonts.mono; font.pixelSize: 12
                        }
                        // Hover a clashing custom chip → name the other action(s) on this chord.
                        MouseArea {
                            id: cChipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            WToolTip {
                                visible: cChipMa.containsMouse && crow.conflict
                                text: crow.conflict ? root.conflictText(crow.modelData.chord, crow.modelData.exec) : ""
                            }
                        }
                    }
                }
            }
            HubRow {
                id: addCustomRow
                width: parent.width
                icon: "list-add"; glyph: String.fromCodePoint(0xf0417)   // nf-md-plus
                label: Strings.t("hotkeys.addCustom")
                actionText: Strings.t("hotkeys.add")
                focused: root.focusedKey === "addCustom"
                onActivated: root.openCustomPrompt()
            }

            // ── Your profiles (C3, delete) — only when you have any ──────────────
            Column {
                visible: root.userProfiles.length > 0
                width: parent.width
                spacing: 8
                HubSection { width: parent.width; text: Strings.t("hotkeys.userProfiles") }
                Repeater {
                    id: userProfileRepeater
                    model: root.userProfiles
                    delegate: Item {
                        id: prow
                        required property var modelData
                        width: listCol.width
                        height: 30

                        // Same wash convention as the custom-action rows above — the
                        // only real action here is the × (del) too.
                        Rectangle {
                            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                            radius: Geometry.radiusSm
                            visible: root.focusedKey === "userProfile:" + prow.modelData
                            color: Colors.hover
                        }

                        Text {
                            anchors { left: parent.left; right: pDelBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: prow.modelData + (prow.modelData === root.activeProfile ? "  •" : "")
                            color: prow.modelData === root.activeProfile ? Colors.accentInk : Colors.text
                            font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            id: pDelBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: String.fromCodePoint(0xf0156)   // nf-md-close
                            font.family: Fonts.mono; font.pixelSize: 14
                            color: pDelMa.containsMouse ? Colors.dangerBorder : Colors.muted
                            MouseArea {
                                id: pDelMa
                                anchors.fill: parent; anchors.margins: -4
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.deleteProfile(prow.modelData)
                            }
                        }
                    }
                }
            }

            // ── Rebindable actions, grouped by category ──────────────────────────
            Repeater {
                id: tokenRepeater
                model: root.rows
                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property bool isSection: modelData.section === true
                    width: listCol.width
                    implicitHeight: isSection ? sect.implicitHeight : 30
                    height: implicitHeight

                    // Category header. The "menu" category carries a note under it: its
                    // chords are the only ones that are NOT a compositor bind, and the
                    // Ctrl form they take inside a search field is the one rule about them
                    // a user cannot infer from the chip alone.
                    Column {
                        id: sect
                        visible: entry.isSection
                        width: parent.width
                        spacing: 4
                        HubSection {
                            width: parent.width
                            text: entry.isSection ? Strings.t("hotkeys.cat." + entry.modelData.cat) : ""
                        }
                        Text {
                            width: parent.width
                            visible: entry.isSection && entry.modelData.cat === "menu"
                            text: visible ? Strings.t("hotkeys.cat.menu.note") : ""
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Action row: label on the left; a reset ↺ (only when overridden) + the
                    // clickable chord chip on the right. Clicking the chip arms capture for this
                    // token (chip → "Press keys…", accented); the effective chord shows accented
                    // when it differs from the profile, muted "unbound" when "".
                    Item {
                        id: actionRow
                        visible: !entry.isSection
                        anchors.fill: parent

                        readonly property string token: entry.isSection ? "" : entry.modelData.token
                        readonly property bool changed: !entry.isSection && entry.modelData.changed
                        readonly property bool capturing: root.captureToken !== "" && root.captureToken === token && !root.captureCustom
                        readonly property bool unbound: !entry.isSection && entry.modelData.chord === ""
                        // Shares its (non-empty) chord with another action — the last-bound one
                        // wins in Hyprland, so flag both. Not while capturing (chord is in flux).
                        readonly property bool conflict: !entry.isSection && !capturing
                                                         && entry.modelData.chord !== ""
                                                         && root.conflictChords[entry.modelData.chord] === true

                        // Keyboard roving-focus wash — independent of the chip's own
                        // accent/danger/muted colouring (gotcha #5-adjacent: a row that's
                        // merely roving-focused but otherwise plain default would
                        // otherwise be indistinguishable from an unfocused one). Reads
                        // `entry.modelData.token` (not the bare `token` alias above) —
                        // every other nested reference to a per-row value in this delegate
                        // goes through an explicit path (`parent.parent.token`,
                        // `entry.modelData.token`), never a bare identifier.
                        Rectangle {
                            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                            radius: Geometry.radiusSm
                            visible: !entry.isSection && root.focusedKey === "token:" + entry.modelData.token
                            color: Colors.hover
                        }

                        Text {
                            anchors { left: parent.left; right: resetBtn.left; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            text: entry.isSection ? "" : root.labelFor(entry.modelData.token)
                            color: Colors.text
                            font.family: Fonts.family
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        // In-a-text-field form of a `menu` chord (Ctrl+…), muted and
                        // borderless so it reads as derived information next to the chip
                        // that is actually clickable. Hidden while capturing (the chord is
                        // in flux) and when unbound (there is nothing to prefix).
                        Text {
                            id: fieldChip
                            anchors { right: chip.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            visible: !entry.isSection && entry.modelData.cat === "menu"
                                     && !actionRow.capturing && !actionRow.unbound
                            text: visible ? root.fieldChord(entry.modelData.token, entry.modelData.chord) : ""
                            color: Colors.muted
                            font.family: Fonts.mono
                            font.pixelSize: 11
                        }

                        // Revert this action to the active profile's chord (only when overridden).
                        Text {
                            id: resetBtn
                            anchors { right: fieldChip.visible ? fieldChip.left : chip.left
                                      rightMargin: 8; verticalCenter: parent.verticalCenter }
                            visible: parent.changed
                            text: String.fromCodePoint(0xf0453)   // nf-md-restore
                            font.family: Fonts.mono
                            font.pixelSize: 14
                            color: resetMa.containsMouse ? Colors.accentInk : Colors.muted
                            MouseArea {
                                id: resetMa
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.resetToken(parent.parent.token)
                            }
                        }

                        Rectangle {
                            id: chip
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            // Chip accent priority: capture(accent) > conflict(danger) >
                            // override(accent) > default(muted). Conflict outranks override so a
                            // clashing override reads as a problem, not just a customisation.
                            readonly property bool active: parent.capturing || parent.changed
                            readonly property color hue: parent.conflict ? Colors.dangerBorder
                                                         : chip.active ? Colors.accentInk : Colors.border
                            width: chordLbl.implicitWidth + 16
                            height: 24
                            radius: Geometry.radiusSm
                            color: chipMa.containsMouse && !parent.capturing ? Colors.hover : Colors.alpha(Colors.hover, 0)
                            border.width: HubConfig.border
                            border.color: chip.hue
                            Text {
                                id: chordLbl
                                anchors.centerIn: parent
                                text: entry.isSection ? ""
                                      : parent.parent.capturing ? Strings.t("hotkeys.capturing")
                                      : parent.parent.unbound   ? Strings.t("hotkeys.unbound")
                                      : entry.modelData.chord
                                color: parent.parent.conflict ? Colors.dangerBorder
                                       : chip.active ? Colors.accentInk : Colors.muted
                                font.family: parent.parent.unbound ? Fonts.family : Fonts.mono
                                font.italic: parent.parent.unbound && !parent.parent.capturing
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.startCapture(entry.modelData.token)
                                // Hover a clashing chip → name the other action(s) on this chord.
                                WToolTip {
                                    visible: chipMa.containsMouse && actionRow.conflict
                                    text: actionRow.conflict
                                          ? root.conflictText(entry.modelData.chord, root.labelFor(entry.modelData.token)) : ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Dropdown overlay layer (above the rows) ─────────────────────────────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }

    // ── Prompt overlay layer (save-as name / custom-action form) ────────────────────
    Item {
        id: promptLayer
        anchors.fill: parent
        z: 101
        visible: root.promptMode !== ""

        // Click outside the card cancels.
        MouseArea { anchors.fill: parent; onClicked: root.closePrompt() }

        Rectangle {
            id: promptCard
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: parent.width - 24
            radius: Geometry.radiusSm
            color: Colors.surface
            border.width: HubConfig.border; border.color: Colors.border
            implicitHeight: promptCol.implicitHeight + 24
            // Swallow clicks so they don't fall through to the cancelling backdrop.
            MouseArea { anchors.fill: parent }

            Column {
                id: promptCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10

                // Save current edits as a user profile.
                Column {
                    id: savePromptCol
                    visible: root.promptMode === "save"
                    width: parent.width
                    spacing: 8
                    readonly property bool reserved: root.isReserved(nameField.text)
                    readonly property bool nameOk: /^[a-z0-9-]+$/.test(nameField.text) && !reserved
                    Text {
                        text: Strings.t("hotkeys.saveAs")
                        color: Colors.text; font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    WTextBox {
                        id: nameField
                        width: parent.width
                        placeholder: Strings.t("hotkeys.profileName")
                        onAccepted: if (parent.nameOk) root.saveProfile(text)
                        // Tab/Esc hand off to the prompt's own local roving list instead
                        // of typing a tab char or bubbling Esc up to Hub.back() — same
                        // reasoning as every field wrapper elsewhere in the Hub.
                        input.Keys.onTabPressed: root.promptFocusRow(1)
                        input.Keys.onEscapePressed: root.closePrompt()
                    }
                    Text {
                        width: parent.width
                        text: parent.reserved ? Strings.t("hotkeys.reserved") : Strings.t("hotkeys.nameHint")
                        color: parent.reserved ? Colors.dangerBorder : Colors.muted
                        font.family: Fonts.family; font.pixelSize: 11
                    }
                    Row {
                        spacing: 8
                        Pill {
                            id: savePromptSavePill
                            label: Strings.t("hotkeys.save")
                            enabled: parent.parent.nameOk
                            focused: root.promptMode === "save" && root.promptFocusIndex === 1
                            onClicked: root.saveProfile(nameField.text)
                        }
                        Pill {
                            id: savePromptCancelPill
                            label: Strings.t("hotkeys.cancel")
                            focused: root.promptMode === "save" && root.promptFocusIndex === 2
                            onClicked: root.closePrompt()
                        }
                    }
                }

                // Add a custom action: capture a chord, type a command.
                Column {
                    visible: root.promptMode === "custom"
                    width: parent.width
                    spacing: 8
                    Text {
                        text: Strings.t("hotkeys.addCustom")
                        color: Colors.text; font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Rectangle {
                        id: capChip
                        readonly property bool capturing: root.captureCustom && root.captureToken !== ""
                        // Roving cursor on this bespoke (non-WPill) button — same bespoke
                        // ring treatment as NetworkPanel's connBtn, since it carries no
                        // shared `focused` contract of its own.
                        readonly property bool roving: root.promptMode === "custom" && root.promptFocusIndex === 0 && !capChip.capturing
                        width: capChordLbl.implicitWidth + 20
                        height: 28
                        radius: Geometry.radiusSm
                        color: (capMa.containsMouse || capChip.roving) && !capChip.capturing ? Colors.hover : Colors.alpha(Colors.hover, 0)
                        border.width: (capChip.capturing || capChip.roving) ? 2 : HubConfig.border
                        border.color: (capChip.capturing || root.customChord !== "" || capChip.roving) ? Colors.accentInk : Colors.border
                        Text {
                            id: capChordLbl
                            anchors.centerIn: parent
                            text: capChip.capturing ? Strings.t("hotkeys.capturing")
                                  : root.customChord !== "" ? root.customChord
                                  : Strings.t("hotkeys.setChord")
                            color: (capChip.capturing || root.customChord !== "") ? Colors.accentInk : Colors.muted
                            font.family: root.customChord !== "" ? Fonts.mono : Fonts.family
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: capMa
                            anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.startCaptureCustom()
                        }
                    }
                    WTextBox {
                        id: cmdField
                        width: parent.width
                        placeholder: Strings.t("hotkeys.command")
                        input.Keys.onTabPressed: root.promptFocusRow(2)
                        input.Keys.onEscapePressed: root.closePrompt()
                    }
                    Row {
                        spacing: 8
                        Pill {
                            id: customPromptAddPill
                            label: Strings.t("hotkeys.add")
                            enabled: root.customChord !== "" && cmdField.text.trim() !== ""
                            focused: root.promptMode === "custom" && root.promptFocusIndex === 2
                            onClicked: root.addCustom(root.customChord, cmdField.text.trim())
                        }
                        Pill {
                            id: customPromptCancelPill
                            label: Strings.t("hotkeys.cancel")
                            focused: root.promptMode === "custom" && root.promptFocusIndex === 3
                            onClicked: root.closePrompt()
                        }
                    }
                }
            }
        }
    }
}
