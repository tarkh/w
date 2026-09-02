// W Linux — application launcher.
// A search popup over a tinted, compositor-blurred full-screen backdrop. Layer-
// shell overlay with exclusive keyboard focus (grabs input in Hyprland); toggled
// by a Hyprland global shortcut ($mod+D). Searches desktop entries, shows an icon
// + name list with an accent-highlighted selection, launches via uwsm so apps
// land in their own app-graphical.slice scope (W session model). The card's top
// (search field) stays fixed; the list area below morphs (height-animated) as the
// result count changes. All timing comes from Motion, synced with Hyprland.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import qs.core
import qs.modules.shading

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any
    // other popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "launcher"

    // Visually shown: open AND not suspended. Suspended = stepped aside for a higher-
    // priority modal (the auth prompt) — the card hides + releases keyboard focus but
    // stays logically open (state preserved), then restores when the modal closes.
    // Same contract the Hub uses. Without this the card would sit UNDER the auth prompt
    // and keep the keyboard grab.
    readonly property bool shown: root.active && !Overlays.suspended

    // Resolve the per-icon ShadedIcon mode from LauncherConfig.iconMode. "smart"
    // keeps colorful app logos original and only brand-tints system icons, detected
    // reliably by the presence of a "<name>-symbolic" twin (system/utility icons
    // ship one; app logos do not).
    function iconModeFor(mono) {
        switch (LauncherConfig.iconMode) {
        case "original": return ShadedIcon.Original;
        case "solid":    return ShadedIcon.Solid;
        case "smart":    return mono ? ShadedIcon.Solid : ShadedIcon.Original;
        default:         return ShadedIcon.Tint;   // "tint"
        }
    }


    // Last pointer position in SCENE coords, for genuine-movement hover detection
    // (see the results MouseArea). Reset on open so opening under the cursor does
    // not count as movement.
    property var lastPointer: null

    // Card geometry (used to size + morph the card). Width is the shared
    // Overlays.cardWidth so launcher/clipboard/hub read as one centered surface.
    readonly property int cardW: Overlays.cardWidth
    readonly property int rowH: 44
    readonly property int maxCardH: 480
    readonly property int chrome: 84          // col margins (12+12) + header (48) + spacing (12)

    // Toggle from Hyprland:  bind = SUPER, D, global, quickshell:launcher
    GlobalShortcut {
        appid: "quickshell"
        name: "launcher"
        onPressed: Overlays.toggle("launcher")
    }

    // Filtered + ranked application list (recomputed reactively on query change).
    // DesktopEntries.applications already excludes Hidden/NoDisplay entries.
    //
    // Empty query (browse): when LauncherConfig.rankByUsage is on, most-launched
    // first (LauncherUsage chart), then alphabetical — so never-used apps (count 0)
    // naturally fall below the used ones, alphabetically. Off → plain alphabetical.
    // With a query: fuzzy score dominates; usage breaks ties before the alphabet.
    function appList() {
        const q = search.text.trim().toLowerCase();
        const all = DesktopEntries.applications.values;
        if (q === "") {
            const byName = (a, b) => a.name.localeCompare(b.name);
            if (!LauncherConfig.rankByUsage)
                return all.slice().sort(byName);
            return all.slice().sort((a, b) =>
                LauncherUsage.count(b.id) - LauncherUsage.count(a.id) || byName(a, b));
        }
        return all
            .map(e => ({ e: e, s: root.score(e, q) }))
            .filter(x => x.s >= 0)
            .sort((a, b) => b.s - a.s
                || LauncherUsage.count(b.e.id) - LauncherUsage.count(a.e.id)
                || a.e.name.localeCompare(b.e.name))
            .map(x => x.e);
    }

    // Cheap fuzzy score over name, with keywords/genericName as weaker fallbacks
    // (so "browser" finds Firefox). prefix > substring > subsequence; -1 = no match.
    function score(entry, q) {
        let best = root.scoreField(entry.name.toLowerCase(), q);
        const extra = (entry.keywords || []).concat(entry.genericName || []);
        for (const f of extra) {
            // Discount non-name matches so a real name hit always wins.
            const s = root.scoreField(String(f).toLowerCase(), q) - 50;
            if (s > best) best = s;
        }
        return best;
    }

    function scoreField(text, q) {
        const idx = text.indexOf(q);
        if (idx === 0) return 1000;
        if (idx > 0) return 500 - idx;
        let qi = 0;
        for (let i = 0; i < text.length && qi < q.length; i++)
            if (text[i] === q[qi]) qi++;
        return qi === q.length ? 100 - text.length : -1;
    }

    // Terminal apps (Terminal=true → entry.runInTerminal, e.g. yazi) are TUIs: run
    // bare they get no tty and exit immediately. Route them to W's terminal via
    // Term.exec → `w-term -e`, the single entry point that opens the active
    // terminal on its fastest path (for ghostty: a surface of the pre-warmed daemon,
    // which already owns its systemd scope — no `uwsm app --` wrapper needed). GUI
    // apps still go through `uwsm app --` for proper per-app cgroup scoping.
    function launch(entry) {
        if (!entry) return;
        LauncherUsage.bump(entry.id);
        const cmd = entry.runInTerminal
            ? Term.exec(entry.command)
            : ["uwsm", "app", "--"].concat(entry.command);
        Quickshell.execDetached({
            command: cmd,
            workingDirectory: entry.workingDirectory,
        });
        Overlays.close("launcher");
    }

    PanelWindow {
        id: win

        // Stay mapped while fading out, then unmap once invisible.
        visible: root.shown || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Layer-shell: overlay above everything, grab keyboard. The namespace is
        // matched by `layerrule = blur` in hyprland.lua for the backdrop blur.
        WlrLayershell.namespace: "quickshell:launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                // Focus on open (the list is already full — text was cleared on hide,
                // so the card opens at full height without a morph). Arm pointer
                // tracking so appearing under the cursor isn't treated as movement.
                list.currentIndex = 0;
                root.lastPointer = null;
                search.input.forceActiveFocus();
            } else if (!root.active) {
                // Reset only on a REAL close (not a suspend) so a restored launcher keeps
                // its query. Once fully hidden → the morph back to full height is invisible.
                search.text = "";
            }
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Click outside the card to dismiss. The tint + blur now come from the
            // shared Backdrop surface (modules/overlay), so this layer is input-only.
            MouseArea { anchors.fill: parent; onClicked: Overlays.close("launcher") }

            // Launcher card. Top is pinned (centered as if full height) so the search
            // field never moves; only the bottom edge moves as the height morphs.
            Rectangle {
                id: card
                // Round to whole pixels — a fractional origin (odd screen widths)
                // makes the top/left border render subpixel-blurred ("thicker").
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - root.maxCardH) / 2)
                width: root.cardW
                height: Math.min(root.maxCardH, root.chrome + Math.max(1, list.count) * root.rowH)
                radius: Geometry.radius
                // Surface translucency from the effects axis (bg only; the search field,
                // list rows and icons are separate items and stay opaque). The scrim+blur
                // backdrop shows softly through the frosted card.
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: LauncherConfig.border
                clip: true

                // Morph the height with the shared base timing on query changes.
                Behavior on height {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Entrance: subtle scale-in from the top (keeps the search field put).
                transformOrigin: Item.Top
                scale: root.shown ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Swallow clicks so they don't reach the dismiss MouseArea.
                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // ── Search field ──────────────────────────────────────────
                    WQueryField {
                        id: search
                        width: parent.width
                        placeholder: Strings.t("launcher.searchPlaceholder")

                        onTextChanged: list.currentIndex = 0

                        // Mode B: the field owns the keyboard the whole time the palette
                        // is open, so bare ↑↓/Enter/Esc plus Ctrl+<profile chord> — one
                        // resolver for every W palette, see core/HubNavKeys.qml. Ctrl+←/→
                        // is left to the field's own word-jump: the launcher has nothing
                        // horizontal to navigate.
                        input.Keys.onPressed: (e) => {
                            switch (HubNavKeys.fieldAction(e)) {
                            case "down":    list.incrementCurrentIndex(); e.accepted = true; return;
                            case "up":      list.decrementCurrentIndex(); e.accepted = true; return;
                            case "confirm": root.launch(list.model[list.currentIndex]); e.accepted = true; return;
                            case "back":    Overlays.close("launcher"); e.accepted = true; return;
                            }
                        }
                    }

                    // ── Results ───────────────────────────────────────────────
                    // A single `highlight` item slides between rows (no per-delegate
                    // color blink). ApplyRange keeps the current row in view and lets
                    // ListView own the scrolling. Hover-select uses onPositionChanged
                    // (real mouse movement only) — NOT onEntered, which would also fire
                    // when rows move under a stationary cursor (on open / scroll / key
                    // nav), hijacking the selection.
                    ListView {
                        id: list
                        // Extend into the card's right padding (margin 12 → pill ~4px from
                        // the edge); delegates inset the same 8 so rows stay put and only
                        // the shared scrollbar moves near the window edge.
                        width: parent.width + 8
                        height: parent.height - search.height - parent.spacing
                        clip: true
                        model: root.appList()
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false

                        // Shared scroll indicator (auto-hides when it fits).
                        ScrollBar.vertical: WScrollBar {}

                        // Smooth vertical slide of the selection.
                        highlightMoveDuration: Motion.fast
                        highlightResizeDuration: 0
                        highlightFollowsCurrentItem: true
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: height
                        highlight: Rectangle {
                            radius: Geometry.radiusSm
                            color: Colors.accent
                        }

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            width: ListView.view.width - 8   // inset the view's gutter extension
                            height: root.rowH

                            readonly property bool current: ListView.isCurrentItem

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                ShadedIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 28
                                    icon: row.modelData.icon || ""
                                    // No themed icon resolves → default app glyph.
                                    fallbackGlyph: String.fromCodePoint(0xf08c6)   // nf-md-application
                                    // System/utility icons have a "-symbolic" twin; app
                                    // logos don't — a reliable monochrome detector.
                                    readonly property bool mono: icon.length > 0
                                        && Quickshell.hasThemeIcon(icon + "-symbolic")
                                    mode: root.iconModeFor(mono)
                                    // Solid (symbolic glyphs) renders the clean -symbolic twin.
                                    preferSymbolic: mode === ShadedIcon.Solid
                                    // Theme brand color (W_QS_ICON_TINT); shape from config.
                                    tint: Colors.iconTint
                                    strength: LauncherConfig.iconStrength
                                    shade: LauncherConfig.iconShade
                                    lift: LauncherConfig.iconLift
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.name
                                    color: row.current ? Colors.accentFg : Colors.text
                                    font.family: Fonts.family
                                    font.pixelSize: 16
                                    elide: Text.ElideRight
                                    width: row.width - 64
                                    // Soft text recolor as the highlight slides over.
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                            }

                            // On top so clicks/hover register; wheel passes through to
                            // the ListView. Hover-select ONLY on genuine pointer
                            // movement: compare the pointer in SCENE coords (stable
                            // when the cursor is still, even as rows scroll under it).
                            // This rejects the synthetic move emitted when the surface
                            // opens under the cursor and the moves caused by content
                            // scrolling during keyboard navigation.
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: (mouse) => {
                                    const p = row.mapToItem(null, mouse.x, mouse.y);
                                    if (root.lastPointer === null) { root.lastPointer = p; return; }
                                    if (Math.abs(p.x - root.lastPointer.x) + Math.abs(p.y - root.lastPointer.y) < 2)
                                        return;
                                    root.lastPointer = p;
                                    list.currentIndex = row.index;
                                }
                                onClicked: root.launch(row.modelData)
                            }
                        }
                    }
                }
            }

            // Topmost of all: no hover highlight while the cursor is hidden, so the
            // keyboard selection is the only mark on screen (see core/HoverGate).
            HoverGate { anchors.fill: parent }
        }
    }
}
