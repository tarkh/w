// W Linux — Hub → Appearance → build or rebuild a theme.
//
// Two routes, one screen: "appearance.new" collects a name and an image and runs
// `w-theme new`; "appearance.edit" (pushed with { theme: <name> }) rebuilds an
// existing generated theme's palette with `w-theme edit`, keeping its wallpaper.
// The screens differ only in which fields are askable, so they are one file.
//
// A thin front-end either way: the CLI owns naming rules, palette extraction, the
// wallpaper conversion and where the theme lands. This screen collects choices,
// shows what the palette will look like, and reports what the CLI said.
//
// The image is chosen through the shell's own picker (core/WFilePicker.qml),
// which the Hub hosts at window level — this screen only says WHICH files it
// will accept and gets a path back. It deliberately does not open anything
// itself: a chooser started as a separate process (a terminal running yazi, the
// first implementation) lands BEHIND the Hub's keyboard-exclusive overlay layer,
// so it was neither visible nor reachable without closing this very form, and
// QtQuick.Dialogs' FileDialog never maps at all on a layer-shell surface.
//
// The accepted suffixes mirror `wallpaper_validate` in w-theme's wallpaper.sh —
// the UI must not offer a file the CLI will refuse.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/ThemeCreatePanel.qml"}).
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.core
import qs.modules.hub

Item {
    id: root
    // +8 mirrors the Flickable's own contentHeight padding below (focus-wash bleed
    // slack) — see quickshell-hub.md's Ф-Keyboard gotcha #6.
    implicitHeight: col.implicitHeight + 8

    // Emitted when the theme is created or rebuilt — the Hub pops back to
    // Appearance, which reloads its list on becoming visible again.
    signal navigateBack()
    // Up on the topmost roving position hands the cursor to the header's "?" button
    // (Hub.qml's focusHeaderHelp). A route with no `help` entry has no button and the
    // Hub answers false — the cursor simply stays where it is.
    signal focusHeader()


    // Route arguments (Hub.push): { theme: <name> } puts the screen in edit mode.
    //
    // editTheme is assigned from the handler rather than bound to navArgs, because
    // a change handler is NOT guaranteed to run after the bindings that depend on
    // the same property: reacting to navArgs while reading a derived `editing`
    // binding saw the stale value and the screen never loaded the theme.
    property var navArgs: null
    property string editTheme: ""
    readonly property bool editing: root.editTheme !== ""

    property string themeName: ""
    property string wallpaper: ""
    property string appearance: "dark"
    property string contrast: "medium"
    property int seedIndex: 0
    // The surfaces' own colour, split from the accents': which tone they wear
    // ("accent" = the base colour's, else a wallpaper tone's hex) and how much of
    // it (neutral = graphite/paper). The defaults are the single-hue theme.
    property string surface: "accent"
    property string tint: "full"
    // How colourful the accents, icons and ANSI colours are; balanced = calibrated.
    property string saturation: "balanced"
    property bool busy: false
    property string error: ""

    // The whole preview matrix from one CLI run: every base colour the image
    // offers × surface tone × tint, dark and light, at every contrast level. Every
    // control on this screen is then a lookup rather than another extraction —
    // the difference between a preview that reacts and one that stalls on every
    // click.
    property var seeds: []
    property bool mono: false
    readonly property var activeSeed: (root.seedIndex >= 0 && root.seedIndex < root.seeds.length)
                                      ? root.seeds[root.seedIndex] : null
    // The tone row: the base colour's own tone first, then the wallpaper's.
    readonly property var toneChoices: root.activeSeed
        ? [{ id: "accent", swatch: root.activeSeed.source }].concat(root.activeSeed.tones || []) : []
    readonly property bool showTones: !root.mono && root.toneChoices.length > 1
    // A base colour offers its own tone list; a tone picked under another one
    // falls back to the accent rather than pointing at a palette that is not there.
    onToneChoicesChanged: if (!root.toneChoices.some(t => t.id === root.surface)) root.surface = "accent"

    // The matrix cell the current choices select: the accent tone at full tint is
    // the plain `appearance` matrix, every other pair lives under `tinted`.
    readonly property var activeMatrix: {
        const s = root.activeSeed;
        if (!s) return null;
        if (root.surface === "accent" && root.tint === "full") return s.appearance;
        return ((s.tinted || {})[root.surface] || {})[root.tint] || null;
    }

    // Another saturation changes only the chromatic slots; the matrix carries the
    // ones the palette row shows apart (`saturated`), laid over the cell above.
    readonly property var saturatedSlots: {
        const s = root.activeSeed;
        if (!s || root.saturation === "balanced") return {};
        const bySat = (((s.saturated || {})[root.surface] || {})[root.tint] || {})[root.saturation] || {};
        return (bySat[root.appearance] || {})[root.contrast] || {};
    }

    // The pigments shown as the palette row, in the order a theme reads: two
    // surfaces, the accent pair, the secondary accent, text, danger.
    readonly property var swatchRoles: ["SURFACE_1", "SURFACE_3", "ACCENT_CONTAINER", "ACCENT",
                                        "VIVID", "TEXT", "DANGER"]
    readonly property var swatches: {
        if (!root.activeMatrix) return [];
        const byLevel = root.activeMatrix[root.appearance] || {};
        const p = Object.assign({}, byLevel[root.contrast] || {}, root.saturatedSlots);
        return root.swatchRoles.map(k => p[k]).filter(c => !!c);
    }

    readonly property bool canSubmit: !root.busy && root.seeds.length > 0
                                      && /^[a-z][a-z0-9-]{0,31}$/.test(root.themeName)
                                      && (root.editing || root.wallpaper !== "")

    // ── Keyboard roving-focus (flat, heterogeneous list inside a Flickable) ────────
    // Name field, choose-file button, 2 appearance segments, 3 contrast segments
    // (only once a preview exists), a variable Repeater of seed swatches (only
    // once the image offers more than one), 3 saturation and 3 tint segments (not for a greyscale
    // image), a variable Repeater of tone swatches (only when the image offers a
    // tone apart from the base colour), then submit/cancel — a mix no single
    // fixed id array or single Repeater could describe on its own, so this follows
    // DisplaysPanel's flat-descriptor idiom (`buildContent()`/`contentIndexOf`,
    // quickshell-hub.md's Ф-Keyboard checklist item 2, second variant) rather than
    // PowerPanel's plain id array. The read-only palette-preview row underneath
    // has no MouseArea at all, so it is never part of this list.
    function buildContent() {
        const arr = [{ kind: "field", key: "name" }];
        if (!root.editing) arr.push({ kind: "button", ref: "choose", key: "choose" });
        arr.push({ kind: "appr", idx: 0, key: "appr:0" }, { kind: "appr", idx: 1, key: "appr:1" });
        if (root.seeds.length > 0)
            arr.push({ kind: "contrast", idx: 0, key: "contrast:0" }, { kind: "contrast", idx: 1, key: "contrast:1" },
                     { kind: "contrast", idx: 2, key: "contrast:2" });
        if (root.seeds.length > 1)
            for (let i = 0; i < root.seeds.length; i++) arr.push({ kind: "seed", idx: i, key: "seed:" + i });
        if (root.seeds.length > 0 && !root.mono) {
            for (let i = 0; i < 3; i++) arr.push({ kind: "saturation", idx: i, key: "saturation:" + i });
            for (let i = 0; i < 3; i++) arr.push({ kind: "tint", idx: i, key: "tint:" + i });
        }
        if (root.showTones)
            for (let i = 0; i < root.toneChoices.length; i++) arr.push({ kind: "tone", idx: i, key: "tone:" + i });
        arr.push({ kind: "button", ref: "submit", key: "submit" }, { kind: "button", ref: "cancel", key: "cancel" });
        return arr;
    }
    readonly property var contentDesc: root.buildContent()
    readonly property var contentIndexOf: {
        const m = {};
        for (let i = 0; i < root.contentDesc.length; i++) m[root.contentDesc[i].key] = i;
        return m;
    }
    property int focusIndex: 0
    // Which control focusIndex currently points at, by its own descriptor key —
    // NOT just the clamp below. Edit mode loads its preview asynchronously
    // (`loadTheme()`/`previewProc`), so contrast/seed rows can appear AFTER the
    // screen is already up and the cursor has moved; those rows are spliced in
    // BEFORE submit/cancel, so a plain numeric clamp would leave focusIndex
    // pointing at whatever now occupies its old slot instead of following the
    // control the cursor was actually on.
    property string focusedKey: ""
    onContentDescChanged: {
        const at = root.contentIndexOf[root.focusedKey];
        root.focusIndex = at !== undefined ? at : Math.max(0, Math.min(root.focusIndex, root.contentDesc.length - 1));
        root.focusedKey = (root.contentDesc[root.focusIndex] || {}).key || "";
    }

    function contentItemFor(d) {
        if (!d) return null;
        switch (d.kind) {
        case "field": return nameField;
        case "button": return d.ref === "choose" ? chooseBtn : (d.ref === "submit" ? submitBtn : cancelBtn);
        case "appr": return apprRepeater.itemAt(d.idx);
        case "contrast": return contrastRepeater.itemAt(d.idx);
        case "seed": return seedRepeater.itemAt(d.idx);
        case "saturation": return saturationRepeater.itemAt(d.idx);
        case "tint": return tintRepeater.itemAt(d.idx);
        case "tone": return toneRepeater.itemAt(d.idx);
        }
        return null;
    }
    // True-edge-first reasoning as InputPanel/PowerPanel.scrollIntoView — a
    // HubSection header sits above the first row.
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
    // Up/Down must move the cursor in the name field, not steal the roving index
    // (same reasoning as NetworkPanel's hostField guard).
    readonly property bool editingText: nameField.input.activeFocus

    focus: true
    Keys.onPressed: (e) => {
        if (root.editingText) return;
        const cd = root.contentDesc;
        if (cd.length === 0) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:
            if (root.focusIndex === 0) { root.focusHeader(); e.accepted = true; return; }
            root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = root.contentItemFor(cd[root.focusIndex]);
            if (!item) { e.accepted = true; return; }
            if (cd[root.focusIndex].kind === "field") item.input.forceActiveFocus();
            else if (item.activated !== undefined) item.activated();
            else if (item.clicked !== undefined) item.clicked();
            e.accepted = true;
            return;
        }
        }
    }

    // NOT Component.onCompleted: a Loader completes its item BEFORE it assigns the
    // properties the Hub hands it, so at completion navArgs is still null and the
    // screen would decide it is building a new theme. The arguments arriving IS the
    // event to react to — and what they say is read straight out of them here, not
    // through a binding that may not have caught up yet.
    onNavArgsChanged: {
        root.editTheme = (root.navArgs && root.navArgs.theme) ? String(root.navArgs.theme) : "";
        if (root.editTheme !== "") root.loadTheme();
    }

    // ── Editing an existing theme ─────────────────────────────────────────────────
    // `w-theme edit --json` reports both the matrix and which cell of it the theme
    // currently occupies, so the form opens on the settings the theme actually has
    // rather than on the defaults.
    function loadTheme() {
        root.themeName = root.editTheme;
        root.busy = true;
        previewProc.command = ["w-theme", "edit", root.editTheme, "--json"];
        previewProc.running = true;
    }

    // ── Picking a file ────────────────────────────────────────────────────────────
    // Ask the Hub for its window-level picker; it answers with an absolute path.
    signal pickFile(var opts, var onPicked)

    // Same roster as wallpaper_validate's, so the picker cannot offer a file the
    // CLI would then reject.
    readonly property var imageFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.avif",
                                         "*.heic", "*.heif", "*.tif", "*.tiff", "*.bmp", "*.jxl"]

    function choose() {
        root.error = "";
        root.pickFile({ title: Strings.t("pick.image"), filters: root.imageFilters }, (path) => {
            root.wallpaper = path;
            root.seeds = [];
            root.seedIndex = 0;
            // A name the user has not typed yet is seeded from the file, which is
            // nearly always what they wanted to call it.
            if (!root.themeName) {
                const base = path.split("/").pop().replace(/\.[^.]+$/, "").toLowerCase();
                root.themeName = base.replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32);
            }
            root.preview();
        });
    }

    // ── Palette preview ───────────────────────────────────────────────────────────
    // The extraction runs for real and writes nothing, so the swatches below are
    // the actual pigments the theme would get. It runs exactly once per image:
    // every control on this screen picks a cell out of what it returned.
    function preview() {
        if (root.editing) { root.loadTheme(); return; }
        if (!root.wallpaper) return;
        root.busy = true;
        previewProc.command = ["w-theme", "new", "--json", "--wallpaper", root.wallpaper];
        previewProc.running = true;
    }

    // The exit code decides, not the presence of stderr output: `w-theme new`
    // reports its progress there (which source colour, which scheme), so treating
    // any stderr as failure would flag every successful preview as an error.
    Process {
        id: previewProc
        command: ["true"]
        stdout: StdioCollector { id: previewOut }
        stderr: StdioCollector { id: previewErr }
        onExited: (code) => {
            root.busy = false;
            if (code !== 0) {
                const t = (previewErr.text || "").trim();
                root.seeds = [];
                root.error = t ? t.split("\n").pop() : Strings.t("appear.createFailed");
                return;
            }
            try {
                const d = JSON.parse(previewOut.text || "{}");
                root.mono = !!d.mono;
                root.seeds = d.seeds || [];
                // An existing theme opens on the settings it was built with —
                // present only when editing, and the run happens once, so there
                // is no later reload to overwrite a choice made since.
                if (d.current) {
                    root.appearance = d.current.appearance || "dark";
                    root.contrast = d.current.contrast || "medium";
                    root.seedIndex = d.current.seed_index || 0;
                    root.tint = d.current.tint || "full";
                    root.saturation = d.current.saturation || "balanced";
                }
                if (root.seedIndex >= root.seeds.length) root.seedIndex = 0;
                // Last: the tone list follows the base colour, so the tone is only
                // valid once the seed it belongs to is selected.
                if (d.current) root.surface = d.current.surface || "accent";
            } catch (e) {
                // An empty form with no explanation is the worst outcome here: say
                // so rather than leaving every control hidden with no reason given.
                root.seeds = [];
                root.error = Strings.t("appear.createFailed");
            }
        }
    }

    // ── Creating / rebuilding ─────────────────────────────────────────────────────
    function submit() {
        if (!root.canSubmit) return;
        root.busy = true;
        root.error = "";
        const palette = ["--appearance", root.appearance, "--contrast", root.contrast,
                         "--seed-index", String(root.seedIndex),
                         "--surface", root.surface, "--tint", root.tint,
                         "--saturation", root.saturation];
        createProc.command = root.editing
            ? ["w-theme", "edit", root.editTheme, "--rename", root.themeName].concat(palette)
            : ["w-theme", "new", root.themeName, "--wallpaper", root.wallpaper].concat(palette);
        createProc.running = true;
    }

    Process {
        id: createProc
        command: ["true"]
        stderr: StdioCollector { id: createErr }
        onExited: (code) => {
            root.busy = false;
            if (code === 0) {
                root.navigateBack();
            } else {
                const t = (createErr.text || "").trim();
                root.error = t ? t.split("\n").pop() : Strings.t("appear.createFailed");
            }
        }
    }

    // ── Shared segmented control ──────────────────────────────────────────────────
    // The shared pill (core/WPill.qml) with the Hub's outline width; `active` is
    // the filled current segment. Was a file-local copy of the same Rectangle.
    component Segment: WPill { borderWidth: HubConfig.border }

    // A clickable colour swatch (base colour, surface tone).
    component Swatch: Rectangle {
        id: swatch
        property bool on: false
        property bool focused: false
        // Same "give a bare Item the SelectRow/HubRow `activated()` contract" fix
        // as quickshell-hub.md's Ф-Keyboard gotcha #10, so the panel's
        // confirm-dispatcher can drive it uniformly.
        signal activated()
        width: 34; height: 34
        radius: Geometry.radiusSm
        // The selected swatch is marked by its ring, not by a tick: a glyph would
        // have to be legible on an arbitrary colour. Keyboard focus reuses the same
        // ring as selection (mirrors AppearancePanel.ThemeTile's `current ||
        // focused` merge) — PLUS a scale lift (WPill's own focused idiom): a thin
        // ring alone can vanish against a swatch close to the accent's own hue, the
        // size change reads regardless of colour.
        scale: swatch.focused ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        border.width: (swatch.on || swatch.focused) ? 3 : 1
        border.color: (swatch.on || swatch.focused) ? Colors.accentInk : Colors.border
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: swatch.activated()
        }
    }

    // ── Layout (scrolls; same bleed/scroll contract as PowerPanel/InputPanel —
    // quickshell-hub.md's Ф-Keyboard checklist item 7, NOT Flickable.topMargin/
    // bottomMargin, see gotcha #3) ───────────────────────────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: -12
        anchors.leftMargin: -8
        clip: true
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: col
            x: 8
            y: 4
            width: flick.width - 12 - 8
            spacing: 12

            HubSection {
                width: parent.width
                text: root.editing ? Strings.t("appear.editTheme") : Strings.t("appear.newTheme")
            }

            Text {
                width: parent.width
                text: root.editing ? Strings.t("appear.editHint") : Strings.t("appear.newHint")
                color: Colors.muted
                font.family: Fonts.family
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Name. Editable while editing too — renaming a theme is a directory move
            // and a fresh pin, which the CLI does as part of the same rebuild.
            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: Strings.t("appear.themeName")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                WTextBox {
                    id: nameField
                    width: parent.width
                    placeholder: "my-theme"
                    text: root.themeName
                    // The CLI is the authority on collisions (it checks both
                    // collections); this only flags the shape while typing.
                    valid: root.themeName === "" || /^[a-z][a-z0-9-]{0,31}$/.test(root.themeName)
                    // Roving-cursor tint before real Qt focus enters the field —
                    // WTextBox has no separate `focused` prop (real activeFocus
                    // already drives its ring), so this overrides its own default
                    // background binding, same as any QML component's defaults.
                    color: (root.contentIndexOf["name"] === root.focusIndex && !nameField.input.activeFocus)
                           ? Colors.hover : Colors.inputBg
                    onTextChanged: root.themeName = text
                    input.Keys.onTabPressed: root.forceActiveFocus()
                    input.Keys.onEscapePressed: root.forceActiveFocus()
                }
            }

            // Wallpaper — the editor keeps the theme's own, so there is nothing to pick.
            Column {
                width: parent.width
                spacing: 6
                visible: !root.editing
                Text {
                    text: Strings.t("appear.wallpaper")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Row {
                    width: parent.width
                    spacing: 8
                    WButton {
                        id: chooseBtn
                        label: Strings.t("appear.chooseFile")
                        enabled: !root.busy
                        focused: root.contentIndexOf["choose"] === root.focusIndex
                        onClicked: root.choose()
                    }
                    Text {
                        width: parent.width - 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wallpaper || Strings.t("appear.noFile")
                        color: root.wallpaper ? Colors.text : Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 12
                        elide: Text.ElideLeft
                    }
                }
                Text {
                    width: parent.width
                    text: Strings.t("appear.wallpaperHint")
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // Appearance.
            Row {
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("appear.mode")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Repeater {
                    id: apprRepeater
                    model: [{ key: "dark", label: Strings.t("appear.mode.dark") },
                            { key: "light", label: Strings.t("appear.mode.light") }]
                    delegate: Segment {
                        id: apprCell
                        required property var modelData
                        required property int index
                        label: modelData.label
                        active: root.appearance === modelData.key
                        focused: root.contentIndexOf["appr:" + apprCell.index] === root.focusIndex
                        onClicked: root.appearance = modelData.key
                    }
                }
            }

            // Contrast. How much the surfaces are tinted and how far apart the tones
            // sit — low is the pastel end, high the crisp one. Instant: every level is
            // already in the matrix.
            Row {
                spacing: 8
                visible: root.seeds.length > 0
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("appear.contrast")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Repeater {
                    id: contrastRepeater
                    model: [{ key: "low", label: Strings.t("appear.contrast.low") },
                            { key: "medium", label: Strings.t("appear.contrast.medium") },
                            { key: "high", label: Strings.t("appear.contrast.high") }]
                    delegate: Segment {
                        id: contrastCell
                        required property var modelData
                        required property int index
                        label: modelData.label
                        active: root.contrast === modelData.key
                        focused: root.contentIndexOf["contrast:" + contrastCell.index] === root.focusIndex
                        onClicked: root.contrast = modelData.key
                    }
                }
            }

            // Base colour. One clickable swatch per dominant colour the image actually
            // carries — hidden when it carries only one, because a choice of one is not
            // a choice. The palette row below follows the selection.
            Column {
                width: parent.width
                spacing: 6
                visible: root.seeds.length > 1
                Text {
                    text: Strings.t("appear.baseColor")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Row {
                    spacing: 6
                    Repeater {
                        id: seedRepeater
                        model: root.seeds
                        delegate: Swatch {
                            id: seedCell
                            required property int index
                            required property var modelData
                            on: root.seedIndex === seedCell.index
                            focused: root.contentIndexOf["seed:" + seedCell.index] === root.focusIndex
                            onActivated: root.seedIndex = seedCell.index
                            color: modelData.source
                        }
                    }
                }
            }

            // Saturation. How colourful the accents, icons and terminal colours are —
            // muted, the calibrated balance, or vivid. The background keeps its tint;
            // a greyscale image has no colour to saturate.
            Row {
                spacing: 8
                visible: root.seeds.length > 0 && !root.mono
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("appear.saturation")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Repeater {
                    id: saturationRepeater
                    model: [{ key: "muted", label: Strings.t("appear.saturation.muted") },
                            { key: "balanced", label: Strings.t("appear.saturation.balanced") },
                            { key: "vivid", label: Strings.t("appear.saturation.vivid") }]
                    delegate: Segment {
                        id: saturationCell
                        required property var modelData
                        required property int index
                        label: modelData.label
                        active: root.saturation === modelData.key
                        focused: root.contentIndexOf["saturation:" + saturationCell.index] === root.focusIndex
                        onClicked: root.saturation = modelData.key
                    }
                }
            }

            // Surface tint. How much colour the canvas, cards and text wear —
            // neutral is graphite (or paper) with a trace of the tone, under the base
            // colour's accents. A greyscale image is neutral already, so it offers
            // no choice.
            Row {
                spacing: 8
                visible: root.seeds.length > 0 && !root.mono
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("appear.tint")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Repeater {
                    id: tintRepeater
                    model: [{ key: "neutral", label: Strings.t("appear.tint.neutral") },
                            { key: "subtle", label: Strings.t("appear.tint.subtle") },
                            { key: "full", label: Strings.t("appear.tint.full") }]
                    delegate: Segment {
                        id: tintCell
                        required property var modelData
                        required property int index
                        label: modelData.label
                        active: root.tint === modelData.key
                        focused: root.contentIndexOf["tint:" + tintCell.index] === root.focusIndex
                        onClicked: root.tint = modelData.key
                    }
                }
            }

            // Surface tone. Which colour that tint is: the base colour's own, or one
            // the wallpaper is painted in — the ground of a dark picture with one
            // bright spot, the sky of a garden whose accents are its gold (at the
            // neutral tint: warm or cool graphite). Hidden when the image offers no
            // tone apart from the base colour.
            Column {
                width: parent.width
                spacing: 6
                visible: root.showTones
                Text {
                    text: Strings.t("appear.surfaceTone")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
                Row {
                    spacing: 6
                    Repeater {
                        id: toneRepeater
                        model: root.toneChoices
                        delegate: Swatch {
                            id: toneCell
                            required property int index
                            required property var modelData
                            on: root.surface === modelData.id
                            focused: root.contentIndexOf["tone:" + toneCell.index] === root.focusIndex
                            onActivated: root.surface = modelData.id
                            color: modelData.swatch
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: Strings.t("appear.surfaceToneHint")
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // Palette preview — the real pigments, straight from the engine. Read-only
            // (no MouseArea), so it never joins the roving list (checklist's grep-for-
            // MouseArea audit, gotcha #10).
            Row {
                width: parent.width
                spacing: 6
                visible: root.swatches.length > 0
                Repeater {
                    model: root.swatches
                    delegate: Rectangle {
                        required property string modelData
                        width: 34; height: 34
                        radius: Geometry.radiusSm
                        color: modelData
                        border.width: 1
                        border.color: Colors.border
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.error !== ""
                text: root.error
                color: Colors.dangerFg
                font.family: Fonts.family
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: 8
                WButton {
                    id: submitBtn
                    label: root.busy ? Strings.t("appear.working")
                                     : (root.editing ? Strings.t("appear.apply") : Strings.t("appear.create"))
                    enabled: root.canSubmit
                    focused: root.contentIndexOf["submit"] === root.focusIndex
                    onClicked: root.submit()
                }
                WButton {
                    id: cancelBtn
                    label: Strings.t("hub.cancel")
                    enabled: !root.busy
                    focused: root.contentIndexOf["cancel"] === root.focusIndex
                    onClicked: root.navigateBack()
                }
            }
        }
    }
}
