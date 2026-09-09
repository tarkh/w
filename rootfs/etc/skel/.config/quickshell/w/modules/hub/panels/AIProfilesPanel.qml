// W Linux — Hub AI profiles panel (Ф6; root-level Hub tile, robot glyph).
// A full front-end over `w-ai profile {list,new,show,use,rm,field}`: one profile per
// row (name + active check), tapping an inactive row activates it (`profile use`,
// same "tap = apply" idiom as the locale/keyboard pickers); tapping the chevron (or
// an already-active row) expands an inline field editor below it — HOST/PROVIDER/
// MODE/MCP_PROFILE as SelectRow dropdowns, MODEL/OLLAMA_HOST as WSettingsField (box +
// gated Change button, same idiom as Network's Hostname / Energy's idle timeout) — each
// committed via `w-ai profile field <name> <KEY> <value>`. The provider key (and the
// Web-search Brave key further down) are WSecretField (masked box + Save/Remove). A
// trailing row opens a small prompt to create a new profile (blank or copied from
// an existing one).
//
// Which options each of those dropdowns offers is NOT written here: one probe of
// `w-ai host list --porcelain` carries the host contract (hosts/<n>/host.conf), so
// the HOST list, the per-host PROVIDER list (`subscription` vs an API provider for
// a CLI that owns its login), whether MODEL is mandatory, and the install/sign-in
// row all follow from it — a host added as a new hosts/<n>/ directory shows up
// here with no change to this file. See w-ai.md / ai-integration.md §4.
//
// User-scope only — profiles live under ~/.config/w/ai/profiles/, no polkit is
// involved anywhere on this screen (installing or signing in to a provider CLI is
// per-user too, so those hand off to a terminal without sudo).
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/AIProfilesPanel.qml"});
// as a subdir file it is not a module type, so the shared hub components (HubRow,
// HubSection, SelectRow, HubMenu) come in through `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // Up on the topmost roving position hands the cursor to the header's "?" button
    // (Hub.qml's focusHeaderHelp). A route with no `help` entry has no button and the
    // Hub answers false — the cursor simply stays where it is.
    signal focusHeader()

    // While the new-profile prompt is open, grow to its lower edge (mirrors Input's
    // "Switch key" menu-growth trick) so the card expands under the prompt instead of
    // clipping it — the prompt's own implicitHeight already accounts for the wrapped
    // "based on" chip row, so this reads it directly rather than precomputing a formula.
    // +8 mirrors the Flickable's own contentHeight padding below (focus-wash bleed
    // slack, quickshell-hub.md Ф-Keyboard gotcha #6) — without it `flick` is
    // permanently 8px shorter than its own contentHeight. menuLayer.menuBottom grows
    // the card under an open downward dropdown (0 when closed/flipped up).
    implicitHeight: Math.max(col.implicitHeight + 8, menuLayer.menuBottom,
                              root.promptOpen ? 8 + promptCard.implicitHeight : 0)

    // The shared pill (core/WPill.qml) with the Hub's outline width — Use/Delete/
    // Create/Cancel, plus the flat "based on" chips (`flat`+`selected`). Was a
    // file-local copy of the same Rectangle.
    component Pill: WPill { borderWidth: HubConfig.border }

    // ── Profile list (w-ai profile list: "name" / "name (active)" / "name (active, modified since)") ──
    property var profiles: []   // [{name, active, modified}]
    function parseList(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const t = line.trim();
            if (!t) continue;
            const m = t.match(/^(\S+)(?:\s+\(active(, modified since)?\))?$/);
            if (!m) continue;
            out.push({ name: m[1], active: t.indexOf("(active") >= 0, modified: !!m[2] });
        }
        return out;
    }
    function reload() { listProc.running = true; }
    Process {
        id: listProc
        command: ["w-ai", "profile", "list"]
        stdout: StdioCollector { onStreamFinished: root.profiles = root.parseList(this.text || "") }
    }
    Component.onCompleted: { root.reload(); root.reloadKeys(); root.reloadHosts(); root.reloadFeatures(); }

    // ── Expanded profile's fields (w-ai profile show <n>) ────────────────────────────
    property string expanded: ""   // "" = nothing expanded
    readonly property var fieldKeys: ["HOST", "PROVIDER", "MODEL", "MODE", "OLLAMA_HOST", "MCP_PROFILE"]
    property var fields: ({ HOST: "", PROVIDER: "", MODEL: "", MODE: "", OLLAMA_HOST: "", MCP_PROFILE: "" })
    function parseShow(text) {
        const f = {};
        for (const k of root.fieldKeys) {
            const m = text.match(new RegExp("^#?" + k + "=(.*)$", "m"));
            f[k] = m ? m[1].trim() : "";
        }
        return f;
    }
    function toggleExpand(name) {
        if (root.expanded === name) { root.expanded = ""; return; }
        root.expanded = name;
        root.keyError = false;
        root.reloadKeys();
        root.reloadHosts();   // an install/login done since the last open changes the state row
        showProc.command = ["w-ai", "profile", "show", name];
        showProc.running = true;
    }
    Process {
        id: showProc
        stdout: StdioCollector { onStreamFinished: root.fields = root.parseShow(this.text || "") }
    }

    // A field change applies immediately (optimistic) and re-lists so the active
    // profile's "(active, modified since)" badge reflects a hand-edit right away.
    function setField(key, value) {
        const upd = {}; upd[key] = value;
        root.fields = Object.assign({}, root.fields, upd);
        fieldProc.command = ["w-ai", "profile", "field", root.expanded, key, value];
        fieldProc.running = true;
    }
    Process { id: fieldProc; onExited: root.reload() }

    function useProfile(name) { useProc.command = ["w-ai", "profile", "use", name]; useProc.running = true; }
    Process { id: useProc; onExited: root.reload() }

    function removeProfile(name) {
        if (root.expanded === name) root.expanded = "";
        rmProc.command = ["w-ai", "profile", "rm", name];
        rmProc.running = true;
    }
    Process { id: rmProc; onExited: root.reload() }

    // ── Provider API keys (gnome-keyring via `w-ai key`) ─────────────────────────────
    // Keys are provider-scoped and global (attribute w-ai-provider=<provider>), shared
    // by every profile/host that uses that provider — NOT stored per-profile. keyStatus
    // maps provider → present(bool), parsed from `w-ai key list` ("  <provider>
    // present|-"). The secret itself never enters this UI on read — only its presence.
    property var keyStatus: ({})   // { openrouter: true, anthropic: false, … }
    property bool keyBusy: false
    property bool keyError: false
    // Mirrors effective_provider() in w-ai: a host with a closed AUTH_MODES list keeps
    // PROVIDER only when it names one of them, else falls back to the first — so a
    // claude profile inheriting PROVIDER=openrouter from a goose one reads as
    // "subscription", exactly as the launcher would treat it.
    function effectiveProvider(host, provider) {
        const modes = root.hostInfo(host).authModes;
        if (!modes || modes.length === 0) return provider || "";
        return modes.indexOf(provider) >= 0 ? provider : modes[0];
    }
    // `w-ai key list` prints exactly the providers whose catalog entry declares an env
    // var — ollama and `subscription` are omitted because they hold no key. So mere
    // membership in keyStatus is the answer, and this stays free of provider names.
    function providerNeedsKey(p) { return p !== "" && root.keyStatus[p] !== undefined; }
    function reloadKeys() { keyListProc.running = true; }
    Process {
        id: keyListProc
        command: ["w-ai", "key", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of (this.text || "").split("\n")) {
                    const t = line.match(/^\s*(\S+)\s+(present|-)\s*$/);
                    if (t) m[t[1]] = (t[2] === "present");
                }
                root.keyStatus = m;
            }
        }
    }

    // Save a key by piping it to `w-ai key set <provider>` over stdin (secret-tool reads
    // until EOF; closing stdin after the write signals it). The key rides the pipe, never
    // an argv/log/disk. No trailing newline — secret-tool would store it as part of the key.
    Process {
        id: saveKeyProc
        property string pending: ""
        onStarted: { write(saveKeyProc.pending); saveKeyProc.pending = ""; stdinEnabled = false; }
        onExited: (code) => { root.keyBusy = false; root.keyError = (code !== 0); root.reloadKeys(); }
    }
    function saveKey(provider, key) {
        const k = key.trim();
        if (k === "") return;
        root.keyError = false; root.keyBusy = true;
        saveKeyProc.pending = k;
        saveKeyProc.stdinEnabled = true;
        saveKeyProc.command = ["w-ai", "key", "set", provider];
        saveKeyProc.running = true;
    }
    Process { id: rmKeyProc; onExited: root.reloadKeys() }
    function removeKey(provider) {
        rmKeyProc.command = ["w-ai", "key", "rm", provider];
        rmKeyProc.running = true;
    }

    // ── Advanced features (ai-extra pack, Ф4 — GUI mirror of `w-ai features`) ───────
    // One-shot porcelain probe on open (same idiom as profiles/keys above). Gate on
    // featuresLoaded so the grey/live branch doesn't flash before the first probe
    // returns. `feat(key, fallback)` gives every row a safe default while loading or
    // when a key is simply absent from the porcelain output.
    property var features: ({})
    property bool featuresLoaded: false
    function feat(key, fallback) {
        return root.features[key] || { state: fallback || "off", detail: "" };
    }
    function reloadFeatures() { featuresProc.running = true; }
    Process {
        id: featuresProc
        command: ["w-ai", "features", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const line of (this.text || "").split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 3) continue;
                    out[parts[0]] = { state: parts[1], detail: parts[2] };
                }
                root.features = out;
                root.featuresLoaded = true;
            }
        }
    }
    function setFeature(key, value) {
        featureSetProc.command = ["w-ai", "features", "set", key, value];
        featureSetProc.running = true;
    }
    Process { id: featureSetProc; onExited: root.reloadFeatures() }

    // Nothing from the pack is present at all → one collapsed CTA instead of four
    // individually-explained disabled rows. Partial installs fall through to the
    // live branch, where each row reflects its own dependency.
    readonly property bool advNoneInstalled:
        root.feat("ollama").detail === "service=not-installed"
        && root.feat("ddgs").state !== "on"
        && root.feat("trafilatura").state !== "on"

    readonly property var searchOptions: [
        { id: "auto",  label: Strings.t("hub.aiAdvSearch.auto") },
        { id: "ddgs",  label: Strings.t("hub.aiAdvSearch.ddgs") },
        { id: "brave", label: Strings.t("hub.aiAdvSearch.brave") },
        { id: "off",   label: Strings.t("hub.aiAdvSearch.off") },
    ]
    readonly property var embedOptions: [
        { id: "off",    label: Strings.t("hub.aiAdvEmbed.off") },
        { id: "ollama", label: Strings.t("hub.aiAdvEmbed.ollama") },
    ]
    function localModelsValue() {
        const o = root.feat("ollama");
        let s = o.detail === "service=not-installed" ? Strings.t("hub.aiAdvOllamaMissing")
              : o.state === "on" ? Strings.t("hub.aiAdvOllamaActive")
              : Strings.t("hub.aiAdvOllamaInactive");
        if (o.state === "on")
            s += ", " + (root.feat("embed_model").state === "on"
                         ? Strings.t("hub.aiAdvModelReady") : Strings.t("hub.aiAdvModelNotReady"));
        return s;
    }

    // ── New-profile prompt ────────────────────────────────────────────────────────
    property bool promptOpen: false
    property string newFrom: ""       // "" = blank template
    property string pendingNewName: ""
    function openPrompt() {
        root.promptOpen = true; root.newFrom = ""; root.promptFocusIndex = 0;
        nameField.input.clear(); nameField.input.forceActiveFocus();
    }
    function closePrompt() { root.promptOpen = false; }
    function createProfile(name) {
        root.pendingNewName = name;
        const args = ["profile", "new", name];
        if (root.newFrom !== "") args.push("--from", root.newFrom);
        newProc.command = ["w-ai"].concat(args);
        newProc.running = true;
    }
    Process {
        id: newProc
        onExited: {
            root.closePrompt();
            root.reload();
            root.toggleExpand(root.pendingNewName);
        }
    }

    // ── Host contract (`w-ai host list --porcelain`) ────────────────────────────────
    // One probe describes the whole host layer: which hosts exist, whether each
    // binary is installed and signed in, which PROVIDER values each accepts, and
    // whether it needs a MODEL. Everything below is derived from it, so a host added
    // as a new /usr/share/w/ai/hosts/<n>/ directory appears here with no QML change.
    // Line: <name>\t<bin>\t<state>\t<auth_modes>\t<needs_model>\t<capabilities>\t<active|->
    property var hosts: ({})   // { claude: {bin, state, authModes:[], needsModel, caps} }
    property bool hostsLoaded: false
    function reloadHosts() { hostsProc.running = true; }
    Process {
        id: hostsProc
        command: ["w-ai", "host", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of (this.text || "").split("\n")) {
                    const c = line.split("\t");
                    if (c.length < 6 || !c[0]) continue;
                    m[c[0]] = {
                        bin: c[1], state: c[2],
                        authModes: c[3] ? c[3].split(/\s+/).filter(s => s) : [],
                        needsModel: c[4] === "yes", caps: c[5],
                    };
                }
                root.hosts = m;
                root.hostsLoaded = true;
            }
        }
    }
    function hostInfo(h) { return root.hosts[h] || { bin: h, state: "", authModes: [], needsModel: true, caps: "" }; }

    readonly property var hostOptions: {
        const out = [];
        for (const h of Object.keys(root.hosts).sort()) out.push({ id: h, label: h });
        // Before the probe resolves, offer at least the configured host so the
        // dropdown is never empty on first paint (gotcha #15: async content).
        if (out.length === 0 && root.fields.HOST) out.push({ id: root.fields.HOST, label: root.fields.HOST });
        return out;
    }

    // The catalog, used for hosts whose AUTH_MODES is open (goose). `subscription`
    // is not a vendor — it is the auth mode of a CLI that owns its own login, and
    // only hosts that declare it in AUTH_MODES ever offer it.
    readonly property var providerCatalog: [
        { id: "openrouter", label: "openrouter" }, { id: "anthropic", label: "anthropic" },
        { id: "openai", label: "openai" }, { id: "google", label: "google" }, { id: "ollama", label: "ollama" },
    ]
    // What the expanded profile's PROVIDER dropdown offers: the host's closed list
    // when it declares one (claude -> subscription|anthropic, local -> ollama),
    // otherwise the whole catalog.
    readonly property var providerOptions: {
        const modes = root.hostInfo(root.fields.HOST).authModes;
        if (!modes || modes.length === 0) return root.providerCatalog;
        return modes.map(m => ({ id: m, label: m === "subscription" ? Strings.t("hub.aiAuthSubscription") : m }));
    }
    readonly property var modeOptions: [
        { id: "auto", label: Strings.t("hub.aiMode.auto") },
        { id: "smart_approve", label: Strings.t("hub.aiMode.smart_approve") },
        { id: "approve", label: Strings.t("hub.aiMode.approve") },
        { id: "chat", label: Strings.t("hub.aiMode.chat") },
    ]
    readonly property var mcpOptions: [
        { id: "", label: Strings.t("hub.aiMcp.auto") },
        { id: "full", label: Strings.t("hub.aiMcp.full") },
        { id: "minimal", label: Strings.t("hub.aiMcp.minimal") },
    ]
    function labelOf(opts, id) { for (const o of opts) if (o.id === id) return o.label; return id || "—"; }

    // ── Keyboard roving-focus (flat descriptor list, ThemeCreatePanel's idiom) ──────
    // Three independent sources of async/variable content in one list — the profile
    // Repeater loads asynchronously and varies in length (listProc), each expanded
    // profile's field set varies (keyCol/OLLAMA_HOST/Use-pill conditionally visible),
    // and the whole Advanced section appears only after featuresProc resolves and then
    // branches its own row set (advNoneInstalled) — a fixed id array (PowerPanel) or a
    // single Repeater-linear index (InputPanel) can't describe this alone, and the
    // async-appears-after-first-render shape is exactly quickshell-hub.md's Ф-Keyboard
    // gotcha #15 marker, so this uses `focusedKey` (not a bare index) from the start
    // rather than retrofitting it later.
    function buildContent() {
        const arr = [];
        for (const p of root.profiles) {
            const pfx = "profile:" + p.name + ":";
            arr.push({ field: "header", key: pfx + "header", name: p.name });
            if (root.expanded === p.name) {
                arr.push({ field: "host", key: pfx + "host", name: p.name });
                // Mirrors hostStateRow.visible — the install/login row only exists
                // while the host CLI is missing or signed out.
                const hstate = root.hostInfo(root.fields.HOST).state;
                if (root.hostsLoaded && (hstate === "absent" || hstate === "not-logged-in"))
                    arr.push({ field: "hostState", key: pfx + "hostState", name: p.name });
                arr.push({ field: "prov", key: pfx + "prov", name: p.name });
                const prov = root.effectiveProvider(root.fields.HOST, root.fields.PROVIDER);
                if (root.providerNeedsKey(prov)) arr.push({ field: "key", key: pfx + "key", name: p.name });
                arr.push({ field: "mode", key: pfx + "mode", name: p.name });
                arr.push({ field: "mcp", key: pfx + "mcp", name: p.name });
                arr.push({ field: "model", key: pfx + "model", name: p.name });
                if (prov === "ollama")
                    arr.push({ field: "ollama", key: pfx + "ollama", name: p.name });
                if (!p.active) arr.push({ field: "use", key: pfx + "use", name: p.name });
            }
        }
        arr.push({ field: "newProfile", key: "newProfile" });
        if (root.featuresLoaded) {
            if (root.advNoneInstalled) {
                arr.push({ field: "installPack", key: "installPack" });
            } else {
                arr.push({ field: "search", key: "search" });
                if (root.feat("W_AI_SEARCH_PROVIDER", "auto").state === "brave")
                    arr.push({ field: "braveKey", key: "braveKey" });
                arr.push({ field: "embed", key: "embed" });
            }
        }
        return arr;
    }
    readonly property var contentDesc: root.buildContent()
    readonly property var contentIndexOf: {
        const m = {};
        for (let i = 0; i < root.contentDesc.length; i++) m[root.contentDesc[i].key] = i;
        return m;
    }
    property int focusIndex: 0
    // Which descriptor focusIndex currently points at, by key — not just the numeric
    // clamp below. See gotcha #15: profiles/features load after the first render, so
    // rows can be spliced in BEFORE the cursor's current slot.
    property string focusedKey: ""
    onContentDescChanged: {
        const at = root.contentIndexOf[root.focusedKey];
        root.focusIndex = at !== undefined ? at : Math.max(0, Math.min(root.focusIndex, root.contentDesc.length - 1));
        root.focusedKey = (root.contentDesc[root.focusIndex] || {}).key || "";
    }

    function profileItemFor(name) {
        for (let i = 0; i < root.profiles.length; i++) if (root.profiles[i].name === name) return profileRepeater.itemAt(i);
        return null;
    }
    function contentItemFor(d) {
        if (!d) return null;
        switch (d.field) {
        case "newProfile":  return newProfileRow;
        case "installPack": return installRow;
        case "search":      return searchRow;
        case "braveKey":    return braveKeyField;
        case "embed":       return embedRow;
        }
        const item = root.profileItemFor(d.name);
        if (!item) return null;
        switch (d.field) {
        case "header":    return item.headRow;
        case "host":      return item.hostRow;
        case "hostState": return item.hostStateRow;
        case "prov":      return item.provRow;
        case "key":    return item.keyField;
        case "mode":   return item.modeRow;
        case "mcp":    return item.mcpRow;
        case "model":  return item.modelField;
        case "ollama": return item.ollamaField;
        case "use":    return item.usePill;
        }
        return null;
    }
    // True-edge-first, same as ThemeCreatePanel/PowerPanel — a HubSection-less list
    // here, but the first/last row still carry the Flickable's own top/bottom bleed
    // slack (gotcha #4), so a plain "bring bounds into view" would stop short of it.
    function scrollIntoView(i) {
        const item = root.contentItemFor(root.contentDesc[i]);
        if (!item) return;
        if (i === 0) { flick.contentY = 0; return; }
        if (i === root.contentDesc.length - 1) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); return; }
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y - 4 < flick.contentY) flick.contentY = p.y - 4;
        else if (p.y + item.height + 4 > flick.contentY + flick.height) flick.contentY = p.y + item.height + 4 - flick.height;
    }
    function focusRow(i) {
        root.focusIndex = Math.max(0, Math.min(i, root.contentDesc.length - 1));
        root.focusedKey = (root.contentDesc[root.focusIndex] || {}).key || "";
        root.scrollIntoView(root.focusIndex);
    }
    // Up/Down must move the cursor inside whatever field is currently open, not steal
    // the roving index — only the item at focusIndex can ever hold real activeFocus
    // (every field's Tab/Esc hands it straight back to root, see the field wrappers
    // below), so checking just that one item is enough (unlike PowerPanel's `.some()`
    // over every focusable, needed there only because it has many candidates at once).
    readonly property bool editingText: {
        const item = root.contentItemFor(root.contentDesc[root.focusIndex]);
        return !!(item && item.input !== undefined && item.input.activeFocus);
    }

    // ── New-profile prompt: separate local roving list (nameField → "based on" pills
    // → Create/Cancel), guarded ahead of the main switch below — same shape as
    // AppearancePanel's pendingDelete-armed guard hijacking Escape/Backspace locally
    // instead of the panel's usual meaning.
    property int promptFocusIndex: 0
    readonly property int promptTailStart: root.profiles.length > 0 ? 2 + root.profiles.length : 1
    readonly property int promptMaxIndex: root.promptTailStart + 1
    function promptFocusRow(i) {
        root.promptFocusIndex = Math.max(0, Math.min(i, root.promptMaxIndex));
        if (root.promptFocusIndex === 0) nameField.input.forceActiveFocus();
        else root.forceActiveFocus();   // real Qt focus back on root so its Keys.onPressed keeps receiving events
    }
    function handlePromptKey(e) {
        // Backspace closes the prompt too (not just Escape) — same reasoning as
        // AppearancePanel's pendingDelete guard: without intercepting it here, the
        // fixed "back" alias bubbles to Hub.qml's card and pops the WHOLE panel
        // while the prompt is still visually open on top of it.
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
            if (root.promptFocusIndex === 0) { if (promptCol.nameOk) root.createProfile(nameField.text); }
            else {
                const it = root.promptItemAt(root.promptFocusIndex);
                if (it && it.clicked !== undefined) it.clicked();
            }
            e.accepted = true;
            return;
        }
        }
    }
    function promptItemAt(i) {
        if (i === 0) return nameField;
        if (i === root.promptTailStart) return createPill;
        if (i === root.promptTailStart + 1) return cancelPill;
        if (root.profiles.length > 0 && i === 1) return blankPill;
        if (root.profiles.length > 0 && i > 1 && i < root.promptTailStart) return basedOnRepeater.itemAt(i - 2);
        return null;
    }

    focus: true
    Keys.onPressed: (e) => {
        if (root.promptOpen) { root.handlePromptKey(e); return; }
        if (root.editingText) return;
        const cd = root.contentDesc;
        if (cd.length === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:
            if (root.focusIndex === 0) { root.focusHeader(); e.accepted = true; return; }
            root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.del: {
            const d = cd[root.focusIndex];
            // Mirrors the mouse's × exactly — that click removes the profile with no
            // confirm step either, so keyboard doesn't invent a two-step arm/confirm
            // gotcha #14 doesn't apply here the way it does to AppearancePanel's tiles.
            if (d && d.field === "header") root.removeProfile(d.name);
            e.accepted = true;
            return;
        }
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const d = cd[root.focusIndex];
            if (!d) { e.accepted = true; return; }
            const item = root.contentItemFor(d);
            if (d.field === "header") {
                const p = root.profiles.find(x => x.name === d.name);
                if (p) {
                    // Shift+confirm reaches the chevron's route (expand/collapse
                    // regardless of active state) — plain confirm mirrors the row's
                    // own body-click (activate if inactive, toggle if active). No new
                    // `menu` token needed (gotcha #13), same trick as AppearancePanel's
                    // Shift+confirm→edit route.
                    if (e.modifiers & Qt.ShiftModifier) root.toggleExpand(d.name);
                    else if (p.active) root.toggleExpand(d.name);
                    else root.useProfile(d.name);
                }
            } else if (d.field === "key" || d.field === "braveKey") {
                // Shift+confirm removes the stored key (mirrors the field's own Remove
                // button) when one is present; plain confirm focuses the box to type a
                // new one — same second-verb trick as the header above.
                if ((e.modifiers & Qt.ShiftModifier) && item && item.hasKey) {
                    root.removeKey(d.field === "braveKey" ? "brave" : root.effectiveProvider(root.fields.HOST, root.fields.PROVIDER));
                } else if (item) {
                    item.input.forceActiveFocus();
                }
            } else if (item && item.input !== undefined) {
                item.input.forceActiveFocus();
            } else if (item && item.activated !== undefined) {
                item.activated();
            } else if (item && item.clicked !== undefined) {
                item.clicked();
            }
            e.accepted = true;
            return;
        }
        }
    }

    // ── Layout ─────────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: -12
        // Mirrors PowerPanel's left-side bleed lane (quickshell-hub.md gotcha #2):
        // clip:true cuts anything outside Flickable's OWN rect, and every row's
        // keyboard-focus wash bleeds -8 past its own left edge — without this, that
        // bleed lands at negative x and gets clipped to nothing. `col` insets the
        // same 8 so visible content doesn't shift; only the bleed lane grows.
        anchors.leftMargin: -8
        clip: true
        // +8 slack at each end for the first/last row's -4 top/bottom wash bleed to
        // scroll fully into view (gotcha #4) — via contentHeight+`col.y`, NOT
        // Flickable's own topMargin/bottomMargin (gotcha #3: that centers content
        // when content+margins fit the viewport, offsetting the resting contentY).
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 10

            Repeater {
                id: profileRepeater
                model: root.profiles
                delegate: Column {
                    id: prow
                    required property var modelData
                    readonly property bool isActive: modelData.active
                    readonly property bool isExpanded: root.expanded === modelData.name
                    function fkey(field) { return "profile:" + modelData.name + ":" + field; }
                    property alias headRow: head
                    property alias hostRow: hostRow
                    property alias hostStateRow: hostStateRow
                    property alias provRow: provRow
                    property alias keyField: keyField
                    property alias modeRow: modeRow
                    property alias mcpRow: mcpRow
                    property alias modelField: modelField
                    property alias ollamaField: ollamaField
                    property alias usePill: usePill
                    width: col.width
                    spacing: 8

                    // Collapsed row: name + check(active) + chevron(expand) + ×(delete).
                    Item {
                        id: head
                        width: parent.width
                        height: 38

                        // Keyboard roving-focus wash — full-row bleed (gotcha #1: both
                        // horizontal AND vertical margins, not just horizontal, or the
                        // wash visually "slips" against neighboring rows).
                        Rectangle {
                            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                            radius: Geometry.radiusSm
                            visible: root.focusedKey === prow.fkey("header")
                            color: Colors.hover
                        }

                        Row {
                            anchors { left: parent.left; right: rightRow.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            ChromeIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 22
                                icon: "system-users"; glyph: String.fromCodePoint(0xf06a9)  // nf-md-robot
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: prow.modelData.name
                                color: Colors.text
                                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                            }
                            Text {
                                visible: prow.modelData.active && prow.modelData.modified
                                anchors.verticalCenter: parent.verticalCenter
                                text: Strings.t("hub.aiModified")
                                color: Colors.muted
                                font.family: Fonts.family; font.pixelSize: 11
                            }
                        }

                        Row {
                            id: rightRow
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 2

                            Text {
                                visible: prow.isActive
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(0xf05e0)   // nf-md-check_circle
                                font.family: Fonts.mono; font.pixelSize: 16
                                color: Colors.accentInk
                            }
                            // Fixed 32x32 hit targets (not just the glyph's own bounds) so the
                            // chevron/× are easy to hit without landing on the row's own
                            // activate-tap area — the miss the icon-only hit box invited.
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32; height: 32
                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xf0140)   // nf-md-chevron_down
                                    font.family: Fonts.mono; font.pixelSize: 16
                                    color: chevMa.containsMouse ? Colors.text : Colors.muted
                                    rotation: prow.isExpanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: Motion.fast } }
                                }
                                MouseArea {
                                    id: chevMa
                                    anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleExpand(prow.modelData.name)
                                }
                            }
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32; height: 32
                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xf0156)   // nf-md-close
                                    font.family: Fonts.mono; font.pixelSize: 16
                                    color: delMa.containsMouse ? Colors.dangerBorder : Colors.muted
                                }
                                MouseArea {
                                    id: delMa
                                    anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeProfile(prow.modelData.name)
                                }
                            }
                        }

                        MouseArea {
                            anchors { left: parent.left; right: rightRow.left; top: parent.top; bottom: parent.bottom }
                            cursorShape: Qt.PointingHandCursor
                            onClicked: prow.isActive ? root.toggleExpand(prow.modelData.name)
                                                      : root.useProfile(prow.modelData.name)
                        }
                    }

                    // Expanded field editor.
                    Column {
                        visible: prow.isExpanded
                        width: parent.width
                        spacing: 10
                        leftPadding: 32

                        SelectRow {
                            id: hostRow
                            width: parent.width - 32
                            label: Strings.t("hub.aiHost")
                            currentId: root.fields.HOST
                            options: root.hostOptions
                            value: root.labelOf(root.hostOptions, root.fields.HOST)
                            focused: root.focusedKey === prow.fkey("host")
                            onActivated: menuLayer.openMenu(hostRow, root.hostOptions, root.fields.HOST,
                                                        (id) => root.setField("HOST", id))
                        }

                        // The host's CLI, shown only while it needs something: not
                        // installed, or installed but not signed in. Both fixes are
                        // interactive (a vendor installer, a browser login), so they
                        // hand off to a terminal exactly like the ai-extra Install row
                        // below — with no sudo, since a provider CLI is per-user.
                        HubRow {
                            id: hostStateRow
                            readonly property var info: root.hostInfo(root.fields.HOST)
                            readonly property bool absent: info.state === "absent"
                            width: parent.width - 32
                            visible: root.hostsLoaded && (absent || info.state === "not-logged-in")
                            icon: "system-software-install"; glyph: String.fromCodePoint(0xf03d3)
                            label: info.bin
                            sublabel: absent ? Strings.t("hub.aiHostAbsent") : Strings.t("hub.aiHostNotLoggedIn")
                            actionText: absent ? Strings.t("hub.install") : Strings.t("hub.aiHostLogin")
                            focused: root.focusedKey === prow.fkey("hostState")
                            onActivated: {
                                Quickshell.execDetached(Term.exec(["w-ai", "host",
                                    hostStateRow.absent ? "install" : "login", root.fields.HOST]));
                                Overlays.close("hub");
                            }
                        }

                        // PROVIDER doubles as the auth mode: for a host with a closed
                        // AUTH_MODES list it offers `subscription` (the CLI's own login,
                        // no key) vs the API provider. Displayed through
                        // effectiveProvider so a value inherited from another host reads
                        // as what the launcher would actually use, not as a stale id.
                        SelectRow {
                            id: provRow
                            readonly property string prov: root.effectiveProvider(root.fields.HOST, root.fields.PROVIDER)
                            width: parent.width - 32
                            label: Strings.t("hub.aiProvider")
                            currentId: prov
                            options: root.providerOptions
                            value: root.labelOf(root.providerOptions, prov)
                            focused: root.focusedKey === prow.fkey("prov")
                            onActivated: menuLayer.openMenu(provRow, root.providerOptions, provRow.prov,
                                                        (id) => root.setField("PROVIDER", id))
                        }

                        // Provider API key — contextual on the effective provider (host +
                        // PROVIDER). Hidden when no key is needed (ollama/local). The status
                        // (present/missing) reflects the shared keyring, not this profile.
                        Column {
                            id: keyCol
                            width: parent.width - 32
                            spacing: 6
                            readonly property string prov: root.effectiveProvider(root.fields.HOST, root.fields.PROVIDER)
                            readonly property bool hasKey: root.keyStatus[prov] === true
                            visible: root.providerNeedsKey(prov)

                            Row {
                                spacing: 6
                                Text {
                                    text: Strings.t("hub.aiKey")
                                    color: Colors.muted; font.family: Fonts.family; font.pixelSize: 11
                                }
                                Text {
                                    text: keyCol.hasKey ? ("✓ " + Strings.t("hub.aiKeySet")) : Strings.t("hub.aiKeyMissing")
                                    color: keyCol.hasKey ? Colors.accentInk : Colors.muted
                                    font.family: Fonts.family; font.pixelSize: 11
                                }
                            }

                            // Wrapped (not a bare WSecretField) so the roving cursor has
                            // something to highlight while parked here but not yet
                            // editing — WSecretField carries no `focused` prop of its
                            // own, same reasoning as NetworkPanel's hostRow wrapper.
                            Item {
                                id: keyFieldRow
                                width: parent.width
                                implicitHeight: keyField.implicitHeight
                                Rectangle {
                                    anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                                    radius: Geometry.radiusSm
                                    visible: root.focusedKey === prow.fkey("key") && !keyField.input.activeFocus
                                    color: Colors.hover
                                }
                                WSecretField {
                                    id: keyField
                                    width: parent.width
                                    placeholder: Strings.t("hub.aiKeyPlaceholder")
                                    hasKey: keyCol.hasKey
                                    busy: root.keyBusy
                                    onSave: (text) => root.saveKey(keyCol.prov, text)
                                    onRemove: root.removeKey(keyCol.prov)
                                    // Tab/Esc hand focus back to the row roving-nav instead
                                    // of typing a tab char or bubbling Esc to Hub.back().
                                    input.Keys.onTabPressed: root.forceActiveFocus()
                                    input.Keys.onEscapePressed: root.forceActiveFocus()
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.keyError ? Strings.t("hub.aiKeyError") : Strings.t("hub.aiKeyShared")
                                color: root.keyError ? Colors.dangerBorder : Colors.muted
                                font.family: Fonts.family; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        SelectRow {
                            id: modeRow
                            width: parent.width - 32
                            label: Strings.t("hub.aiMode")
                            currentId: root.fields.MODE
                            options: root.modeOptions
                            value: root.labelOf(root.modeOptions, root.fields.MODE)
                            focused: root.focusedKey === prow.fkey("mode")
                            onActivated: menuLayer.openMenu(modeRow, root.modeOptions, root.fields.MODE,
                                                        (id) => root.setField("MODE", id))
                        }
                        SelectRow {
                            id: mcpRow
                            width: parent.width - 32
                            label: Strings.t("hub.aiMcpProfile")
                            currentId: root.fields.MCP_PROFILE
                            options: root.mcpOptions
                            value: root.labelOf(root.mcpOptions, root.fields.MCP_PROFILE)
                            focused: root.focusedKey === prow.fkey("mcp")
                            onActivated: menuLayer.openMenu(mcpRow, root.mcpOptions, root.fields.MCP_PROFILE,
                                                        (id) => root.setField("MCP_PROFILE", id))
                        }

                        // Free-text fields — box + Change button, same gated-apply idiom as
                        // Network's Hostname / Energy's idle timeout (WSettingsField).
                        // Wrapped the same way as the provider key above — WSettingsField
                        // carries no `focused` prop either.
                        Column {
                            width: parent.width - 32
                            spacing: 4
                            // Mandatory for goose (W never runs `goose configure`, so
                            // GOOSE_MODEL is its only source); optional for a CLI that
                            // picks its own model in-session — there an empty value is
                            // the norm and filling it in pins the model instead.
                            Text {
                                text: Strings.t("hub.aiModel")
                                     + (root.hostInfo(root.fields.HOST).needsModel ? "" : "  " + Strings.t("hub.aiModelOptional"))
                                color: Colors.muted; font.family: Fonts.family; font.pixelSize: 11
                            }
                            Item {
                                width: parent.width
                                implicitHeight: modelField.implicitHeight
                                Rectangle {
                                    anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                                    radius: Geometry.radiusSm
                                    visible: root.focusedKey === prow.fkey("model") && !modelField.input.activeFocus
                                    color: Colors.hover
                                }
                                WSettingsField {
                                    id: modelField
                                    width: parent.width
                                    value: root.fields.MODEL
                                    onApplied: (text) => root.setField("MODEL", text)
                                    input.Keys.onTabPressed: root.forceActiveFocus()
                                    input.Keys.onEscapePressed: root.forceActiveFocus()
                                }
                            }
                        }
                        Column {
                            width: parent.width - 32
                            spacing: 4
                            visible: root.effectiveProvider(root.fields.HOST, root.fields.PROVIDER) === "ollama"
                            Text { text: Strings.t("hub.aiOllamaHost"); color: Colors.muted; font.family: Fonts.family; font.pixelSize: 11 }
                            Item {
                                width: parent.width
                                implicitHeight: ollamaField.implicitHeight
                                Rectangle {
                                    anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                                    radius: Geometry.radiusSm
                                    visible: root.focusedKey === prow.fkey("ollama") && !ollamaField.input.activeFocus
                                    color: Colors.hover
                                }
                                WSettingsField {
                                    id: ollamaField
                                    width: parent.width
                                    value: root.fields.OLLAMA_HOST
                                    onApplied: (text) => root.setField("OLLAMA_HOST", text)
                                    input.Keys.onTabPressed: root.forceActiveFocus()
                                    input.Keys.onEscapePressed: root.forceActiveFocus()
                                }
                            }
                        }

                        // Only "Use" here — removal already lives at the row's own × in the
                        // header (a second, danger-styled "Remove" sitting right under the
                        // Model field read as if it acted on Model, and duplicated the ×).
                        Row {
                            spacing: 8
                            Pill {
                                id: usePill
                                visible: !prow.isActive
                                label: Strings.t("hub.aiUse")
                                focused: root.focusedKey === prow.fkey("use")
                                onClicked: root.useProfile(prow.modelData.name)
                            }
                        }
                    }
                }
            }

            // + New profile.
            HubRow {
                id: newProfileRow
                width: parent.width
                icon: "list-add"; glyph: String.fromCodePoint(0xf0417)   // nf-md-plus
                label: Strings.t("hub.aiNew")
                actionText: Strings.t("hub.aiCreate")
                focused: root.focusedKey === "newProfile"
                onActivated: root.openPrompt()
            }

            // ── Advanced (ai-extra pack) ─────────────────────────────────────────────
            Column {
                width: col.width
                visible: root.featuresLoaded
                spacing: 10

                HubSection { width: parent.width; text: Strings.t("hub.aiAdvTitle") }

                // Nothing installed — one collapsed row per feature (all disabled) + a
                // single Install CTA, mirroring PacksPanel's install pattern.
                Column {
                    visible: root.advNoneInstalled
                    width: parent.width
                    spacing: 8
                    HubRow {
                        width: parent.width; enabled: false
                        icon: "edit-find"; glyph: String.fromCodePoint(0xf0317)
                        label: Strings.t("hub.aiAdvWebSearch"); sublabel: Strings.t("hub.aiAdvRequiresPack")
                    }
                    HubRow {
                        width: parent.width; enabled: false
                        icon: "accessories-text-editor"; glyph: String.fromCodePoint(0xf0493)
                        label: Strings.t("hub.aiAdvReader"); sublabel: Strings.t("hub.aiAdvRequiresPack")
                    }
                    HubRow {
                        width: parent.width; enabled: false
                        icon: "drive-harddisk"; glyph: String.fromCodePoint(0xefc5)
                        label: Strings.t("hub.aiAdvSemanticMemory"); sublabel: Strings.t("hub.aiAdvRequiresPack")
                    }
                    HubRow {
                        width: parent.width; enabled: false
                        icon: "computer"; glyph: String.fromCodePoint(0xf4bc)
                        label: Strings.t("hub.aiAdvLocalModels"); sublabel: Strings.t("hub.aiAdvRequiresPack")
                    }
                    HubRow {
                        id: installRow
                        width: parent.width
                        icon: "package-x-generic"; glyph: String.fromCodePoint(0xf03d3)
                        label: Strings.t("hub.packs")
                        actionText: Strings.t("hub.install")
                        focused: root.focusedKey === "installPack"
                        onActivated: {
                            Quickshell.execDetached(Term.exec(["sudo", "w-pack", "install", "ai-extra"]));
                            Overlays.close("hub");
                        }
                    }
                }

                // Partially or fully installed — each row reflects its own dependency;
                // SelectRow.enabled dims+blocks the ones whose backing tool is absent.
                Column {
                    visible: !root.advNoneInstalled
                    width: parent.width
                    spacing: 10

                    SelectRow {
                        id: searchRow
                        width: parent.width
                        icon: "edit-find"; glyph: String.fromCodePoint(0xf0317)
                        label: Strings.t("hub.aiAdvWebSearch")
                        enabled: root.feat("ddgs").state === "on"
                        currentId: root.feat("W_AI_SEARCH_PROVIDER", "auto").state
                        options: root.searchOptions
                        value: root.labelOf(root.searchOptions, searchRow.currentId)
                        focused: root.focusedKey === "search"
                        onActivated: menuLayer.openMenu(searchRow, root.searchOptions, searchRow.currentId,
                                                    (id) => root.setFeature("W_AI_SEARCH_PROVIDER", id))
                    }

                    // Brave needs its own API key — same provider-scoped keyring
                    // machinery as the profile editor's key block above, just fixed to
                    // "brave" instead of the profile's effective provider.
                    Column {
                        id: braveKeyCol
                        width: parent.width
                        spacing: 6
                        leftPadding: 32
                        visible: searchRow.currentId === "brave"
                        readonly property bool hasKey: root.keyStatus["brave"] === true

                        Row {
                            spacing: 6
                            Text { text: Strings.t("hub.aiKey"); color: Colors.muted; font.family: Fonts.family; font.pixelSize: 11 }
                            Text {
                                text: braveKeyCol.hasKey ? ("✓ " + Strings.t("hub.aiKeySet")) : Strings.t("hub.aiKeyMissing")
                                color: braveKeyCol.hasKey ? Colors.accentInk : Colors.muted
                                font.family: Fonts.family; font.pixelSize: 11
                            }
                        }
                        Item {
                            width: parent.width - 32
                            implicitHeight: braveKeyField.implicitHeight
                            Rectangle {
                                anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                                radius: Geometry.radiusSm
                                visible: root.focusedKey === "braveKey" && !braveKeyField.input.activeFocus
                                color: Colors.hover
                            }
                            WSecretField {
                                id: braveKeyField
                                width: parent.width
                                placeholder: Strings.t("hub.aiKeyPlaceholder")
                                hasKey: braveKeyCol.hasKey
                                busy: root.keyBusy
                                onSave: (text) => root.saveKey("brave", text)
                                onRemove: root.removeKey("brave")
                                input.Keys.onTabPressed: root.forceActiveFocus()
                                input.Keys.onEscapePressed: root.forceActiveFocus()
                            }
                        }
                        Text {
                            width: parent.width - 32
                            text: root.keyError ? Strings.t("hub.aiKeyError") : Strings.t("hub.aiKeyShared")
                            color: root.keyError ? Colors.dangerBorder : Colors.muted
                            font.family: Fonts.family; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }

                    SelectRow {
                        id: embedRow
                        width: parent.width
                        icon: "drive-harddisk"; glyph: String.fromCodePoint(0xefc5)
                        label: Strings.t("hub.aiAdvSemanticMemory")
                        enabled: root.feat("ollama").state === "on"
                        currentId: root.feat("W_AI_EMBED", "off").state
                        options: root.embedOptions
                        value: root.labelOf(root.embedOptions, embedRow.currentId)
                        focused: root.focusedKey === "embed"
                        onActivated: menuLayer.openMenu(embedRow, root.embedOptions, embedRow.currentId,
                                                    (id) => root.setFeature("W_AI_EMBED", id))
                    }
                    Text {
                        visible: embedRow.currentId === "ollama" && root.feat("embed_model").state !== "on"
                        width: parent.width
                        leftPadding: 32
                        text: root.feat("embed_model").detail + " " + Strings.t("hub.aiAdvModelMissing")
                        color: Colors.muted
                        font.family: Fonts.family; font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    HubRow {
                        width: parent.width
                        icon: "accessories-text-editor"; glyph: String.fromCodePoint(0xf0493)
                        label: Strings.t("hub.aiAdvReader")
                        value: root.feat("trafilatura").state === "on"
                               ? Strings.t("hub.aiAdvReaderReady") : Strings.t("hub.aiAdvReaderMissing")
                    }
                    HubRow {
                        width: parent.width
                        icon: "computer"; glyph: String.fromCodePoint(0xf4bc)
                        label: Strings.t("hub.aiAdvLocalModels")
                        value: root.localModelsValue()
                    }
                }
            }
        }
    }

    // ── Dropdown overlay (field SelectRow menus) ──────────────────────────────────
    // flipUp: this panel's Flickable content routinely exceeds the Hub's capped body
    // height (Web search / Embedding sit near the bottom of the scroll) — same "already
    // at the cap, can't grow further" situation as PowerPanel's last row.
    HubDropdown { id: menuLayer; anchors.fill: parent; flipUp: true; returnFocusTo: root }

    // ── New-profile prompt ─────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        z: 101
        visible: root.promptOpen
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
            MouseArea { anchors.fill: parent }

            Column {
                id: promptCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8

                readonly property bool taken: root.profiles.some(p => p.name === nameField.text)
                readonly property bool nameOk: /^[a-z0-9-]+$/.test(nameField.text) && !taken

                Text {
                    text: Strings.t("hub.aiNew")
                    color: Colors.text; font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
                }
                WTextBox {
                    id: nameField
                    width: parent.width
                    onAccepted: if (promptCol.nameOk) root.createProfile(text)
                    // Tab/Esc hand focus to the prompt's own local roving list
                    // (root.handlePromptKey) instead of typing a tab char or bubbling
                    // Esc up to Hub.back() — same reasoning as every other field wrapper
                    // in this file, and the reason Escape closes the prompt locally too.
                    input.Keys.onTabPressed: root.promptFocusRow(1)
                    input.Keys.onEscapePressed: root.closePrompt()
                }
                Text {
                    width: parent.width
                    text: promptCol.taken ? Strings.t("hub.aiNameTaken") : Strings.t("hub.aiNameHint")
                    color: promptCol.taken ? Colors.dangerBorder : Colors.muted
                    font.family: Fonts.family; font.pixelSize: 11
                }

                Text {
                    visible: root.profiles.length > 0
                    text: Strings.t("hub.aiNewFrom")
                    color: Colors.muted; font.family: Fonts.family; font.pixelSize: 11
                }
                Flow {
                    visible: root.profiles.length > 0
                    width: parent.width
                    spacing: 6
                    Pill {
                        id: blankPill
                        flat: true
                        label: Strings.t("hub.aiNewBlank")
                        selected: root.newFrom === ""
                        focused: root.promptOpen && root.promptFocusIndex === 1
                        onClicked: root.newFrom = ""
                    }
                    Repeater {
                        id: basedOnRepeater
                        model: root.profiles
                        delegate: Pill {
                            required property var modelData
                            required property int index
                            flat: true
                            label: modelData.name
                            selected: root.newFrom === modelData.name
                            focused: root.promptOpen && root.promptFocusIndex === (2 + index)
                            onClicked: root.newFrom = modelData.name
                        }
                    }
                }

                Row {
                    spacing: 8
                    Pill {
                        id: createPill
                        label: Strings.t("hub.aiCreate")
                        enabled: promptCol.nameOk
                        focused: root.promptOpen && root.promptFocusIndex === root.promptTailStart
                        onClicked: root.createProfile(nameField.text)
                    }
                    Pill {
                        id: cancelPill
                        label: Strings.t("hub.cancel")
                        focused: root.promptOpen && root.promptFocusIndex === root.promptTailStart + 1
                        onClicked: root.closePrompt()
                    }
                }
            }
        }
    }
}
