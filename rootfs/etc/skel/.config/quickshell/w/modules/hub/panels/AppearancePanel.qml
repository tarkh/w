// W Linux — Hub Appearance panel (Ф2 theme picker + Settings tab).
// A Pill-switch (as DisplaysPanel's scope switch) picks between two tabs:
//   Themes   — grids of large preview tiles, split into the system collection and
//              the user's own (see below).
//   Settings — per-user overrides that beat the active theme (bar position, blur,
//              animations), a sibling file (AppearanceSettingsSection.qml) loaded
//              on demand, same split as DisplaysPanel/NightLightSection.qml.
//
// Themes tab: each tile shows the theme's preview.webp (hard 4:3 via
// PreserveAspectCrop — a non-4:3 file just covers) with rounded corners (theme
// geometry) and the theme name centered over a legibility scrim; hover lifts it,
// the active theme wears an accent ring.
//
// Two collections, two sections (HubSection captions, as in Hub → System): the
// system themes shipped with W, and the ones this user generated from their own
// wallpapers. The split is not cosmetic — only the personal ones can be created
// or deleted from here (`w-theme new/rm` write ~/.config/w/themes without any
// privilege), while a system theme needs `sudo w-theme` on the CLI. So the Add
// button and the per-tile ✕ live in the personal section only, and the panel
// never has to ask for a password.
//
// Switching hands `w-theme set <name>` up to the Hub via the `switchTheme` signal; the
// Hub runs the crossfade in the transition mode from HubConfig.themeSwitch ("live" =
// Hub stays open and the theme morphs in place · "reveal" = Hub steps aside for a clean
// full-screen crossfade). Switch is per-user; system scope stays CLI-only.
//
// It is a pure front-end over `w-theme`: the theme list + which one is active come from
// `w-theme list --porcelain` (loaded on open, reloaded after a switch). The active
// highlight is optimistic on click and reconciled from the CLI on reload.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/AppearancePanel.qml"}), so a
// subdir is fine here (it is not imported as a type). Scrolls with the shared WScrollBar
// when the grid overflows the card.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub

Item {
    id: root

    // Fixed header (tab switch) + whichever tab's content drives the card morph
    // together — same contract as DisplaysPanel's topCol/col/menuLayer.menuBottom.
    readonly property real contentH: root.tab === "themes" ? themesCol.implicitHeight
                                     : (settingsLoader.item ? settingsLoader.item.implicitHeight : 0)
    implicitHeight: Math.max(header.height + 12 + contentH, menuLayer.menuBottom)

    property string tab: "themes"   // "themes" | "settings"

    readonly property int cols: 4
    readonly property int gap: 10

    // Active theme name — optimistic on click, authoritative from the porcelain reload.
    property string activeName: ""

    // Drill into the theme-creation screen (registry route "appearance.new").
    // `args` reaches the drilled-into panel as its `navArgs` (see Hub.push): the
    // editor has to be told WHICH theme it is editing.
    signal navigate(var route, var args)

    // The shared pill (core/WPill.qml) carrying the Hub's configured outline width.
    // The body used to live here, byte-for-byte in four panels; see WPill for the
    // state contract it now implements once.
    component Pill: WPill { borderWidth: HubConfig.border }

    // ── Keyboard roving-focus ─────────────────────────────────────────────────────
    // The Themes tab reads as one continuous grid (system tiles, then the user's
    // own, then "Add") even though it is backed by two separate GridViews + a
    // button — `focusRegion` names which one currently owns the cursor, `focusIdx`
    // is the position within it ("tab"/"add" only ever use index 0/1). Coverage now
    // includes the Settings tab (AppearanceSettingsSection.qml, a Loader-child):
    // "settings" is a flat 3-row region (bar/blur/motion), owned here per
    // quickshell-hub.md's Ф-Keyboard gotcha #8 — the section only reads
    // `focusedField` back (see the Binding near settingsLoader below) and exposes
    // activateField().
    property string focusRegion: "tab"   // "tab" | "system" | "user" | "add" | "settings"
    property int focusIdx: 0
    readonly property var settingsFields: ["bar", "blur", "motion"]

    function regionCount(r) { return r === "system" ? systemThemes.count : (r === "user" ? userThemes.count : 0); }
    function firstNonEmptyRegion() {
        if (systemThemes.count > 0) return "system";
        if (userThemes.count > 0) return "user";
        return "add";
    }
    function nextRegion(r) { return r === "system" ? (userThemes.count > 0 ? "user" : "add") : "add"; }
    function prevRegion(r) {
        if (r === "add") return userThemes.count > 0 ? "user" : (systemThemes.count > 0 ? "system" : "tab");
        if (r === "user") return systemThemes.count > 0 ? "system" : "tab";
        return "tab";
    }
    // `fromBelow`: entering via Up (from the region below) lands on the LAST tile
    // (the row you were just below), entering via Down lands on the first — an
    // exact same-column landing would need each grid's per-row geometry, which is
    // more precision than a handful of theme tiles is worth (see HubDropdown's own
    // note on skipping auto-scroll-into-view for a similarly narrow case).
    function enterRegion(r, fromBelow) {
        root.focusRegion = r;
        root.focusIdx = (r === "add" || r === "tab") ? 0 : (fromBelow ? Math.max(0, root.regionCount(r) - 1) : 0);
    }
    function moveH(delta) {
        if (root.focusRegion === "tab") {
            root.focusIdx = Math.max(0, Math.min(1, root.focusIdx + delta));
            root.tab = root.focusIdx === 0 ? "themes" : "settings";
            return;
        }
        if (root.focusRegion === "add" || root.focusRegion === "settings") return;
        root.focusIdx = Math.max(0, Math.min(root.regionCount(root.focusRegion) - 1, root.focusIdx + delta));
    }
    function moveDown() {
        if (root.focusRegion === "tab") {
            if (root.tab === "settings") { root.focusRegion = "settings"; root.focusIdx = 0; return; }
            root.enterRegion(root.firstNonEmptyRegion(), false);
            return;
        }
        if (root.focusRegion === "settings") {
            root.focusIdx = Math.min(root.focusIdx + 1, root.settingsFields.length - 1);
            return;
        }
        if (root.focusRegion === "add") return;
        const next = root.focusIdx + root.cols;
        if (next < root.regionCount(root.focusRegion)) { root.focusIdx = next; return; }
        root.enterRegion(root.nextRegion(root.focusRegion), false);
    }
    function moveUp() {
        if (root.focusRegion === "tab") return;
        if (root.focusRegion === "settings") {
            if (root.focusIdx > 0) { root.focusIdx--; return; }
            root.focusRegion = "tab"; root.focusIdx = 1;   // land back on the Settings pill
            return;
        }
        if (root.focusRegion !== "add") {
            const prev = root.focusIdx - root.cols;
            if (prev >= 0) { root.focusIdx = prev; return; }
        }
        root.enterRegion(root.prevRegion(root.focusRegion), true);
    }

    focus: true
    Keys.onPressed: (e) => {
        // A delete confirmation is armed on the focused tile (see HubNavKeys.del
        // below) — Escape/Backspace cancel it here instead of their usual "pop
        // this panel" meaning (same two keys Hub.qml's card checks for `back`),
        // so backing out of "are you sure?" doesn't also leave Appearance.
        if (root.pendingDelete !== "" && (e.key === HubNavKeys.back || e.key === Qt.Key_Backspace)) {
            root.pendingDelete = "";
            e.accepted = true;
            return;
        }
        switch (e.key) {
        case HubNavKeys.left:  root.moveH(-1); e.accepted = true; return;
        case HubNavKeys.right: root.moveH(1);  e.accepted = true; return;
        case HubNavKeys.down:  root.moveDown(); e.accepted = true; return;
        case HubNavKeys.up:    root.moveUp();   e.accepted = true; return;
        // Second keyboard verb on a "user" tile, mirroring InputPanel's
        // ring-removal — arms the same inline confirmation the ✕ badge opens on a
        // click; pressing it again on the already-armed tile backs out (a second
        // way out, alongside Escape/Backspace above).
        case HubNavKeys.del: {
            if (root.focusRegion === "user") {
                const t = userThemes.get(root.focusIdx);
                if (t) root.pendingDelete = (root.pendingDelete === t.name) ? "" : t.name;
            }
            e.accepted = true;
            return;
        }
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            if (root.focusRegion === "system") { root.pick(systemThemes.get(root.focusIdx).name); e.accepted = true; return; }
            if (root.focusRegion === "user") {
                const t = userThemes.get(root.focusIdx);
                if (!t) { e.accepted = true; return; }
                // Confirm on the SAME tile that HubNavKeys.del armed executes the
                // delete — matching the moved-away-is-not-armed-elsewhere mouse
                // behaviour (only the armed tile's own inline button can delete
                // it; picking/editing a different tile leaves an armed one alone).
                if (t.name === root.pendingDelete) { root.removeTheme(t.name); e.accepted = true; return; }
                // Shift+confirm reaches the ✎ badge's route (rebuild this theme's
                // palette) — plain confirm keeps its existing "switch to it"
                // meaning, the tile's primary and far more common action. Not
                // wired through HubNavKeys: there is no spare token for a second
                // "open" verb in the fixed 7-token `menu` category (adding one
                // means a w-hotkeys catalog change, out of scope here), and a
                // Shift-modified confirm needs no new token — `confirm` itself
                // already resolves through the profile.
                if ((e.modifiers & Qt.ShiftModifier) && t.generated) root.navigate("appearance.edit", { theme: t.name });
                else root.pick(t.name);
                e.accepted = true;
                return;
            }
            if (root.focusRegion === "add") { root.navigate("appearance.new", null); e.accepted = true; return; }
            if (root.focusRegion === "settings" && settingsLoader.item)
                settingsLoader.item.activateField(root.settingsFields[root.focusIdx]);
            e.accepted = true;
            return;
        }
        }
    }

    Row {
        id: header
        anchors { top: parent.top; left: parent.left }
        spacing: 8
        Pill {
            label: Strings.t("appear.tab.themes"); active: root.tab === "themes"
            focused: root.focusRegion === "tab" && root.focusIdx === 0
            onClicked: { root.tab = "themes"; root.focusRegion = "tab"; root.focusIdx = 0; }
        }
        Pill {
            label: Strings.t("appear.tab.settings"); active: root.tab === "settings"
            focused: root.focusRegion === "tab" && root.focusIdx === 1
            onClicked: { root.tab = "settings"; root.focusRegion = "tab"; root.focusIdx = 1; }
        }
    }

    // Ask the Hub to switch to a theme; the Hub owns the transition mode (see
    // HubConfig.themeSwitch) and reconciles the active pin via onDone.
    signal switchTheme(string name, var onDone)

    ListModel { id: systemThemes }
    ListModel { id: userThemes }

    // ── Load themes (name / scope / dir / active) from the CLI ──────────────────────
    function reload() { lister.running = true; }
    Component.onCompleted: reload()

    Process {
        id: lister
        command: ["w-theme", "list", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                systemThemes.clear();
                userThemes.clear();
                let active = "";
                const lines = (this.text || "").split("\n");
                for (const line of lines) {
                    if (!line.trim()) continue;
                    const f = line.split("\t");
                    if (f.length < 4) continue;
                    const name = f[0], scope = f[1], dir = f[2], isActive = f[3] === "1";
                    // Only a generated theme can be rebuilt; a hand-authored one has no
                    // palette settings to edit, and the CLI refuses it (see w-theme edit).
                    const row = { name: name, dir: dir, preview: "file://" + dir + "/preview.webp",
                                  generated: f[4] === "1" };
                    (scope === "local" ? userThemes : systemThemes).append(row);
                    if (isActive) active = name;
                }
                root.activeName = active;
            }
        }
    }

    // ── Delete a personal theme ────────────────────────────────────────────────────
    // `w-theme rm` handles the awkward case itself: deleting the theme this session
    // is wearing resets the pin (with the usual crossfade) before removing anything,
    // so the panel does not have to sequence that. Confirmation is inline on the
    // tile rather than a modal — opening the shared Infobox would replace the Hub,
    // which is the wrong shape for "are you sure" about one tile.
    property string pendingDelete: ""

    Process {
        id: remover
        command: ["true"]
        onExited: { root.pendingDelete = ""; root.reload(); }
    }

    function removeTheme(name) {
        remover.command = ["w-theme", "rm", name];
        remover.running = true;
    }

    // Switch this user's theme: highlight the pick immediately, then hand it to the Hub
    // (which applies the configured transition mode); reconcile the active pin on return.
    function pick(name) {
        if (name === root.activeName) return;
        root.activeName = name;                                   // optimistic
        root.switchTheme(name, () => root.reload());
    }

    // ── One preview tile ──────────────────────────────────────────────────────────
    // Inline component so both grids share it without a separate file (a subdir
    // file could not be imported as a type here — see the header of Hub.qml).
    component ThemeTile: Item {
        id: cell
        required property string name
        required property string preview
        required property bool generated
        required property int index          // GridView-supplied model index
        property bool deletable: false
        property int cellW: 160
        property string region: "system"      // "system" | "user" — set per GridView below

        readonly property bool current: cell.name === root.activeName
        readonly property bool focused: root.focusRegion === cell.region && root.focusIdx === cell.index
        readonly property bool confirming: root.pendingDelete === cell.name
        // Editing rebuilds the palette in place, which only makes sense for a theme
        // this tool generated, and only in the collection this user owns (a system
        // theme would need sudo, so it stays a CLI operation).
        readonly property bool editable: cell.deletable && cell.generated

        width: cell.cellW
        height: Math.round((cell.cellW - root.gap) * 3 / 4) + root.gap

        Item {
            id: thumb
            width: cell.cellW - root.gap
            height: Math.round((cell.cellW - root.gap) * 3 / 4)
            anchors.centerIn: parent
            readonly property int rad: Geometry.radiusSm

            // Hover lift.
            scale: ma.containsMouse ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

            // Cover color behind / if the webp is missing.
            Rectangle { anchors.fill: parent; radius: thumb.rad; color: Colors.inputBg }

            // Preview. A Rectangle's `clip` is rectangular (ignores radius), so the
            // photo is rounded with a MultiEffect alpha mask instead.
            Image {
                id: preview
                anchors.fill: parent
                source: cell.preview
                fillMode: Image.PreserveAspectCrop   // hard 4:3 via layout → cover
                asynchronous: true
                cache: true
                sourceSize.width: 512                 // retina headroom, downscaled
                visible: false
            }
            MultiEffect {
                anchors.fill: preview
                source: preview
                maskEnabled: true
                maskSource: mask
                visible: preview.status === Image.Ready
            }
            Item {
                id: mask
                anchors.fill: preview
                layer.enabled: true
                visible: false
                Rectangle { anchors.fill: parent; radius: thumb.rad; antialiasing: true }
            }

            // Legibility scrim under the name (stronger toward the bottom). A
            // Rectangle renders its radius natively, so its corners stay rounded.
            Rectangle {
                anchors.fill: parent
                radius: thumb.rad
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.15) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.7) }
                }
            }

            // Theme name, centered.
            Text {
                anchors.centerIn: parent
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                visible: !cell.confirming
                text: cell.name.charAt(0).toUpperCase() + cell.name.slice(1)
                color: "#ffffff"
                font.family: Fonts.family
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.6)
            }

            // Active ring / hover border.
            Rectangle {
                anchors.fill: parent
                radius: thumb.rad
                color: "transparent"
                // Keyboard focus reuses the accent ring (the Hub-wide convention for
                // "roving cursor is here" — Tile/SelectRow/HubRow/WButton/WPill all
                // do the same); mouse hover keeps its existing neutral border so this
                // doesn't recolor hover for every mouse user along the way.
                border.color: (cell.current || cell.focused) ? Colors.accentInk
                            : (ma.containsMouse ? Colors.border : Colors.alpha(Colors.border, 0))
                border.width: cell.current ? 3 : (cell.focused ? 2 : (ma.containsMouse ? 2 : 0))
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !cell.confirming
                onClicked: root.pick(cell.name)
            }

            // Tile affordances: badges that only appear on hover, so the grid stays
            // clean. Edit rebuilds the palette (base colour / contrast / dark-light)
            // keeping the wallpaper; delete asks first, in-tile, because it throws
            // away a generated theme (and possibly the active one).
            Row {
                anchors { top: parent.top; right: parent.right; margins: 6 }
                spacing: 4
                visible: !cell.confirming
                       && (ma.containsMouse || editMa.containsMouse || xMa.containsMouse)

                Rectangle {
                    visible: cell.editable
                    width: 20; height: 20; radius: 10
                    color: editMa.containsMouse ? Colors.accentInk : Qt.rgba(0, 0, 0, 0.55)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                    Text {
                        anchors.centerIn: parent
                        text: "✎"
                        color: "#ffffff"
                        font.family: Fonts.family
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: editMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigate("appearance.edit", { theme: cell.name })
                    }
                }

                Rectangle {
                    visible: cell.deletable
                    width: 20; height: 20; radius: 10
                    color: xMa.containsMouse ? Colors.dangerBorder : Qt.rgba(0, 0, 0, 0.55)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "#ffffff"
                        font.family: Fonts.family
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: xMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pendingDelete = cell.name
                    }
                }
            }

            // Confirmation, drawn over the tile itself.
            Rectangle {
                anchors.fill: parent
                radius: thumb.rad
                visible: cell.confirming
                color: Qt.rgba(0, 0, 0, 0.78)

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    width: parent.width - 16

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: Strings.t("appear.deleteConfirm")
                        color: "#ffffff"
                        font.family: Fonts.family
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        WButton {
                            label: Strings.t("appear.delete")
                            tone: "danger"
                            onClicked: root.removeTheme(cell.name)
                        }
                        WButton {
                            label: Strings.t("hub.cancel")
                            onClicked: root.pendingDelete = ""
                        }
                    }
                }
            }
        }
    }

    // ── Themes tab: system collection, then this user's own ───────────────────────
    Flickable {
        id: themesView
        visible: root.tab === "themes"
        anchors { top: header.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        // Extend into the card's right padding so the scrollbar pill sits near the
        // window edge; the column insets the same amount (shared Hub convention).
        anchors.rightMargin: -12
        clip: true
        contentHeight: themesCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Column {
            id: themesCol
            width: themesView.width - 12
            spacing: 10

            readonly property int cellW: Math.floor(width / root.cols)

            HubSection { width: parent.width; text: Strings.t("appear.section.system") }

            // Both grids are non-interactive: the outer Flickable owns scrolling, so
            // a wheel over a grid moves the page instead of getting swallowed.
            GridView {
                width: parent.width
                height: contentHeight
                interactive: false
                cacheBuffer: 2000
                model: systemThemes
                cellWidth: themesCol.cellW
                cellHeight: Math.round((themesCol.cellW - root.gap) * 3 / 4) + root.gap
                // `name`/`preview`/`index` are required properties of ThemeTile, so the
                // view injects them from the model roles — declaring them here again
                // would shadow the component's own.
                delegate: ThemeTile { cellW: themesCol.cellW; region: "system" }
            }

            HubSection { width: parent.width; text: Strings.t("appear.section.user") }

            GridView {
                width: parent.width
                height: contentHeight
                visible: userThemes.count > 0
                interactive: false
                cacheBuffer: 2000
                model: userThemes
                cellWidth: themesCol.cellW
                cellHeight: Math.round((themesCol.cellW - root.gap) * 3 / 4) + root.gap
                delegate: ThemeTile { cellW: themesCol.cellW; deletable: true; region: "user" }
            }

            Text {
                width: parent.width
                visible: userThemes.count === 0
                text: Strings.t("appear.noUserThemes")
                color: Colors.muted
                font.family: Fonts.family
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            WButton {
                id: addBtn
                label: Strings.t("appear.addTheme")
                focused: root.focusRegion === "add"
                onClicked: root.navigate("appearance.new", null)
            }
        }
    }

    // ── Settings tab (per-user overrides) ───────────────────────────────────────
    Loader {
        id: settingsLoader
        active: root.tab === "settings"
        visible: active
        anchors { top: header.bottom; topMargin: 12; left: parent.left; right: parent.right }
        source: "AppearanceSettingsSection.qml"
        onLoaded: item.menuLayer = menuLayer
    }
    // AppearancePanel stays the sole owner of the roving index (see the framework
    // comment above `focusRegion`) — the loaded section only reads back which of
    // its own rows is currently focused.
    Binding {
        target: settingsLoader.item
        property: "focusedField"
        value: root.focusRegion === "settings" ? root.settingsFields[root.focusIdx] : ""
        when: settingsLoader.status === Loader.Ready
    }

    // ── Dropdown overlay layer (above the content; sized to the viewport) ─────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }
}
