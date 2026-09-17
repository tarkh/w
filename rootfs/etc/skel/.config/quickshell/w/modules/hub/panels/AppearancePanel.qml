// W Linux — Hub Appearance panel (Ф2 theme picker + Bar tab + Settings tab).
// A Pill-switch (as DisplaysPanel's scope switch) picks between three tabs:
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
// never has to ask for a password. The ✕ raises the Hub's shared HubConfirm —
// the one way every destructive action in the Hub asks — rather than the
// tile-local plate this panel used to draw over its own thumbnail.
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
                                     : root.tab === "bar"
                                       // +8 mirrors barView's own contentHeight slack (2x4
                                       // focus-wash bleed) — without it the tab is 8px
                                       // shorter than its content and scrolls forever
                                       // (quickshell-hub.md Ф-Keyboard gotcha 6).
                                       ? (barLoader.item ? barLoader.item.implicitHeight + 8 : 0)
                                       : (settingsLoader.item ? settingsLoader.item.implicitHeight : 0)
    implicitHeight: Math.max(header.height + 12 + contentH, menuLayer.menuBottom, confirm.contentBottom)

    // The Hub card, handed over by Hub.qml on load — the delete confirmation dims it,
    // and needs its real rectangle and corner radius to do that without square corners.
    property Item hubSurface: null

    // Order here IS the pill order and the "tab" region's index space — moveH maps
    // the roving index straight through it, so the two cannot drift apart.
    readonly property var tabs: ["themes", "bar", "settings"]
    property string tab: "themes"   // one of `tabs`

    readonly property int cols: 4
    readonly property int gap: 10

    // Active theme name — optimistic on click, authoritative from the porcelain reload.
    property string activeName: ""

    // Drill into the theme-creation screen (registry route "appearance.new").
    // `args` reaches the drilled-into panel as its `navArgs` (see Hub.push): the
    // editor has to be told WHICH theme it is editing.
    signal navigate(var route, var args)
    // Up on the topmost roving position hands the cursor to the header's "?" button
    // (Hub.qml's focusHeaderHelp). A route with no `help` entry has no button and the
    // Hub answers false — the cursor simply stays where it is.
    signal focusHeader()


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
    // "settings" is a flat region (blur/motion/rgb, +rgb-level while RGB is on),
    // owned here per quickshell-hub.md's Ф-Keyboard gotcha #8 — the section only
    // reads `focusedField` back (see the Binding near settingsLoader below) and
    // exposes activateField(). Its field list is DYNAMIC for the same reason the
    // Bar tab's (BarSection.qml) is: the section computes it (rgb-level only
    // exists while RGB is on) and this panel reads it back — the index still
    // lives only here.
    property string focusRegion: "tab"   // "tab" | "system" | "user" | "add" | "bar" | "settings"
    property int focusIdx: 0
    readonly property var settingsFields: settingsLoader.item ? settingsLoader.item.fields : ["blur", "motion", "rgb"]
    readonly property var barFields: barLoader.item ? barLoader.item.fields : []

    // Same true-edge-first reasoning as DisplaysPanel.scrollContentIntoView — the
    // hint text and a section header sit above the first row, so "row 0 is visible"
    // and "we are scrolled to the top" are different conditions.
    function scrollBarIntoView() {
        if (!barLoader.item) return;
        const item = barLoader.item.rowItem(root.barFields[root.focusIdx]);
        if (!item) return;
        if (root.focusIdx === 0) { barView.contentY = 0; return; }
        if (root.focusIdx === root.barFields.length - 1) {
            barView.contentY = Math.max(0, barView.contentHeight - barView.height);
            return;
        }
        const pt = item.mapToItem(barView.contentItem, 0, 0);
        if (pt.y - 4 < barView.contentY) barView.contentY = pt.y - 4;
        else if (pt.y + item.height + 4 > barView.contentY + barView.height)
            barView.contentY = pt.y + item.height + 4 - barView.height;
    }

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
            root.focusIdx = Math.max(0, Math.min(root.tabs.length - 1, root.focusIdx + delta));
            root.tab = root.tabs[root.focusIdx];
            return;
        }
        if (root.focusRegion === "add" || root.focusRegion === "settings"
            || root.focusRegion === "bar") return;
        root.focusIdx = Math.max(0, Math.min(root.regionCount(root.focusRegion) - 1, root.focusIdx + delta));
    }
    function moveDown() {
        if (root.focusRegion === "tab") {
            if (root.tab === "settings") { root.focusRegion = "settings"; root.focusIdx = 0; return; }
            if (root.tab === "bar") {
                root.focusRegion = "bar"; root.focusIdx = 0; root.scrollBarIntoView(); return;
            }
            root.enterRegion(root.firstNonEmptyRegion(), false);
            return;
        }
        if (root.focusRegion === "settings") {
            root.focusIdx = Math.min(root.focusIdx + 1, root.settingsFields.length - 1);
            return;
        }
        if (root.focusRegion === "bar") {
            root.focusIdx = Math.min(root.focusIdx + 1, root.barFields.length - 1);
            root.scrollBarIntoView();
            return;
        }
        if (root.focusRegion === "add") return;
        const next = root.focusIdx + root.cols;
        if (next < root.regionCount(root.focusRegion)) { root.focusIdx = next; return; }
        root.enterRegion(root.nextRegion(root.focusRegion), false);
    }
    function moveUp() {
        if (root.focusRegion === "tab") { root.focusHeader(); return; }
        if (root.focusRegion === "settings") {
            if (root.focusIdx > 0) { root.focusIdx--; return; }
            root.focusRegion = "tab"; root.focusIdx = root.tabs.indexOf("settings");
            return;
        }
        if (root.focusRegion === "bar") {
            if (root.focusIdx > 0) { root.focusIdx--; root.scrollBarIntoView(); return; }
            root.focusRegion = "tab"; root.focusIdx = root.tabs.indexOf("bar");
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
        // While the confirmation is up it owns the keyboard — Escape/Backspace close IT
        // rather than popping the panel (Ф-Keyboard gotcha 14's local-guard shape).
        if (confirm.open) { confirm.handleKey(e); return; }
        switch (e.key) {
        case HubNavKeys.left:  root.moveH(-1); e.accepted = true; return;
        case HubNavKeys.right: root.moveH(1);  e.accepted = true; return;
        case HubNavKeys.down:  root.moveDown(); e.accepted = true; return;
        case HubNavKeys.up:    root.moveUp();   e.accepted = true; return;
        // Second keyboard verb on a "user" tile, mirroring InputPanel's ring-removal —
        // opens the very same confirmation the ✕ badge opens on a click. One step, not
        // two: the modal IS the confirmation, so there is nothing left to "arm".
        case HubNavKeys.del: {
            if (root.focusRegion === "user") {
                const t = userThemes.get(root.focusIdx);
                if (t) root.askRemove(t.name);
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
            if (root.focusRegion === "bar" && barLoader.item)
                barLoader.item.activateField(root.barFields[root.focusIdx]);
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
            label: Strings.t("appear.tab.bar"); active: root.tab === "bar"
            focused: root.focusRegion === "tab" && root.focusIdx === 1
            onClicked: { root.tab = "bar"; root.focusRegion = "tab"; root.focusIdx = 1; }
        }
        Pill {
            label: Strings.t("appear.tab.settings"); active: root.tab === "settings"
            focused: root.focusRegion === "tab" && root.focusIdx === 2
            onClicked: { root.tab = "settings"; root.focusRegion = "tab"; root.focusIdx = 2; }
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
    // so the panel does not have to sequence that — but the confirmation still names
    // it, because a delete that also changes the visible theme should not surprise.
    property string askName: ""
    function askRemove(name) {
        root.askName = name;
        confirm.ask({
            title:   Strings.t("appear.deleteTitle").replace("%n%", name),
            message: Strings.t("appear.deleteBody"),
            actions: [{ key: "remove", label: Strings.t("appear.delete") }],
        });
    }

    Process {
        id: remover
        command: ["true"]
        onExited: root.reload()
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
                onClicked: root.pick(cell.name)
            }

            // Tile affordances: badges that only appear on hover, so the grid stays
            // clean. Edit rebuilds the palette (base colour / contrast / dark-light)
            // keeping the wallpaper; delete raises the Hub's shared confirmation,
            // because it throws away a generated theme (and possibly the active one).
            Row {
                anchors { top: parent.top; right: parent.right; margins: 6 }
                spacing: 4
                visible: ma.containsMouse || editMa.containsMouse || xMa.containsMouse

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
                        onClicked: root.askRemove(cell.name)
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
    // ── Bar tab: per-monitor bar composition (BarSection.qml) ────────────────────
    // Its own Flickable, unlike the Settings tab: the row count is outputs × blocks,
    // which passes the card's height ceiling on the very first monitor. Same viewport
    // geometry as themesView (the -12 right margin puts the scrollbar pill on the
    // card edge, the column insets back).
    Flickable {
        id: barView
        visible: root.tab === "bar"
        anchors { top: header.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        // Right: extend into the card padding so the scrollbar pill sits on the window
        // edge. Left: extend the CLIP RECT by the same 8px a row's focus wash bleeds
        // (SelectRow's -8 margin), or `clip:true` cuts the highlight off flush with the
        // row's leading icon — the content is put back with Loader.x, so nothing visibly
        // moves (quickshell-hub.md Ф-Keyboard gotcha 2, the recipe DisplaysPanel uses).
        anchors.rightMargin: -12
        anchors.leftMargin: -8
        clip: true
        // Vertical bleed slack the same way: +8 here (2x4) and Loader.y below, NEVER
        // Flickable.topMargin/bottomMargin — those make Qt centre the content and the
        // first frame renders already scrolled (gotcha 3).
        contentHeight: barLoader.height + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: WScrollBar {}

        Loader {
            id: barLoader
            active: root.tab === "bar"
            x: 8
            y: 4
            width: barView.width - 12 - 8
            source: "BarSection.qml"
            onLoaded: item.menuLayer = menuLayer
        }
    }

    Binding {
        target: barLoader.item
        property: "focusedField"
        value: root.focusRegion === "bar" ? (root.barFields[root.focusIdx] || "") : ""
        when: barLoader.status === Loader.Ready
    }

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
    // flipUp: the Bar tab's content routinely exceeds the card ceiling (outputs x
    // blocks), so the last rows' menus cannot grow the card — with no flip they were
    // drawn past its bottom edge and clipped. The flip only fires when a menu genuinely
    // does not fit downward, so the short Themes/Settings tabs are unaffected.
    HubDropdown { id: menuLayer; anchors.fill: parent; flipUp: true; returnFocusTo: root }

    // ── Delete confirmation (tints the whole Hub card, above the grid) ────────────
    HubConfirm {
        id: confirm
        anchors.fill: parent
        surface: root.hubSurface
        onChose: root.removeTheme(root.askName)
    }
}
