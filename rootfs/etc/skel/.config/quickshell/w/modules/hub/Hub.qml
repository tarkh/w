// W Linux — W Hub (central system-control menu).
// The navigable "W Settings + Control Center" surface: a centered card over the shared
// tinted+blurred backdrop (a sibling of the launcher/clipboard/power menu in
// Overlays.blurGroup — same scrim, same morph crossfade when switching between them).
// Toggled by a Hyprland global shortcut (Super+Space) and by the bar's w-logo button.
//
// Structure: a fixed-width card (Overlays.cardWidth, shared with launcher/clipboard so
// all three read as one centered surface) whose HEIGHT morphs to the current screen's
// content (capped at maxCardH with internal scroll). Navigation is a drill-in stack of
// routes: the root screen holds quick controls + section entries (added in Ф1); a
// section route loads its panel (Ф2+). `HubRegistry` is the ordered source of truth for
// routes → panel sources; a Loader renders the current route's `source`. Esc / Backspace
// go one level up (or dismiss at the root); a deep-link (Overlays.open("hub", { route }))
// jumps straight to a panel.
//
// Ф0 (foundation): the registry is empty, so the Hub opens on its root placeholder —
// enough to verify the surface (opens, shares the blur, matches the width). The drill-in
// slide is wired as an enter-transition here; the simultaneous outgoing-panel slide lands
// with the first real panels (Ф2). All timing/colors come from Motion/Colors/Fonts.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.core
// HubHeader / HubRegistry / HubConfig live in this same module dir (modules/hub/) and
// are used without an explicit import — the codebase convention for co-located shell
// components + singletons (cf. LauncherConfig beside Launcher.qml). Quickshell does not
// register nested subdirs as importable modules, so components stay flat here.

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any other
    // popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "hub"
    // Visually shown: open AND not suspended. Suspended = temporarily stepped aside for
    // a polkit prompt (see runPrivileged) — the surface hides but `active` stays true so
    // navigation/state persist and the Hub restores itself when the prompt resolves.
    readonly property bool shown: root.active && !Overlays.suspended

    // A one-shot command to run once the Hub is FULLY hidden (deferred close), so an
    // action that photographs or blurs the screen (a lock, a screen capture) never
    // catches the fading card and the blurred backdrop behind it. Set via RootGrid's
    // deferredExec; run in onVisibleChanged when the window unmaps. null = nothing owed.
    //
    // Currently NO TILE USES IT: Screenshot moved to the launcher and there has never
    // been a Lock tile. Both this and RootGrid's signal are kept on purpose — the pair
    // is the one worked-out answer to that class of bug (see RootGrid's own note), and
    // wiring a future capture/lock/recording tile back up is then a one-line emit.

    // Step aside for a polkit prompt: hide (suspend), run the privileged command as a
    // tracked process (pkexec blocks until the prompt is answered), and restore + refresh
    // when it exits. Deterministic — no window-sniffing. `onDone` (optional) refreshes the
    // affected reader.
    property var _refreshAfter: null
    function runPrivileged(cmd, onDone) {
        root._refreshAfter = onDone || null;
        Overlays.suspended = true;
        privProc.command = cmd;
        privProc.running = true;
    }
    Process {
        id: privProc
        onExited: {
            Overlays.suspended = false;
            if (root._refreshAfter) { root._refreshAfter(); root._refreshAfter = null; }
        }
    }

    // Like runPrivileged, but the command starts only once the Hub is FULLY hidden
    // (deferred): a command that freezes/screenshots the whole screen (w-theme's
    // grim + w-windowblind crossfade) must not capture the fading card. Suspend hides
    // the Hub; onVisibleChanged launches the command as the same tracked privProc, so
    // the restore + reconcile path (onExited) is shared. Used by the Appearance panel
    // so a theme switch morphs the whole screen A→B at once under the blind.
    property var _suspendedCmd: null
    function runSuspendedDeferred(cmd, onDone) {
        root._refreshAfter = onDone || null;
        root._suspendedCmd = cmd;
        Overlays.suspended = true;
    }

    // Appearance theme switch, dispatched by HubConfig.themeSwitch:
    //   "reveal" — step aside (suspend) so the full-screen w-theme crossfade shows on a
    //              clean screen, then restore.
    //   "live"   — stay open; run the same crossfade with the Hub still visible (it plays
    //              in place, so you watch the whole theme morph). Tracked so we reconcile
    //              the active pin on exit.
    function applyTheme(name, onDone) {
        const cmd = ["w-theme", "set", name];
        if (HubConfig.themeSwitch === "reveal") {
            root.runSuspendedDeferred(cmd, onDone);
        } else {
            root._refreshAfter = onDone || null;
            privProc.command = cmd;
            privProc.running = true;   // no suspend → Hub stays open during the crossfade
        }
    }

    // A panel that needs a file (Appearance → new theme) asks the Hub for one instead
    // of opening anything itself. The picker has to live at WINDOW level, not inside
    // the panel: the card clips its content and morphs its height, so a modal declared
    // in a panel would be cropped and would drag the card's geometry around. Hosting it
    // here also keeps the panel — and the half-filled form on it — alive underneath.
    property var _pickCb: null
    function pickFile(opts, onPicked) {
        root._pickCb = onPicked || null;
        filePicker.request(opts);
    }

    // Navigation stack of route strings; empty = the root screen. `depth` drives the
    // breadcrumb (back is shown only below the root) and the slide direction.
    property var navStack: []
    readonly property string currentRoute: navStack.length ? navStack[navStack.length - 1] : ""
    readonly property int depth: navStack.length

    // Arguments each route was pushed with, kept parallel to navStack. A route is a
    // plain string, which is enough for "open the Appearance panel" but not for
    // "open the theme editor FOR THIS THEME" — the panel needs to know which one.
    // The loaded panel receives them as `navArgs` if it declares the property.
    property var navArgs: []
    readonly property var currentArgs: navArgs.length ? navArgs[navArgs.length - 1] : null

    // Registry entry for the current route (null on the root), giving the panel source
    // + title for the Loader and breadcrumb.
    readonly property var currentPanel: root.currentRoute.length ? HubRegistry.find(root.currentRoute) : null

    // +1 when drilling in (child enters from the right), -1 when going back (from the
    // left). Read by the content enter-transition.
    property int navDir: 1

    // Card geometry — width shared with launcher/clipboard; height morphs to content.
    readonly property int cardW: Overlays.cardWidth
    readonly property int maxCardH: 560
    // Vertical pin reference: the card top is pinned as if the card were `pinRef` tall
    // (top-pinned so the header/root lands at the exact same screen Y as the launcher /
    // clipboard, and the card morphs DOWNWARD as its content grows). Shared with every
    // other modal-center surface — including the file picker that opens over this one.
    readonly property int pinRef: Overlays.cardPin
    readonly property int pad: 16              // card inner margin
    readonly property int headerH: 40
    readonly property int gap: 12              // header → body spacing
    // The root screen carries no heading (the "W Hub" title was dropped) and no back
    // control, so its header collapses entirely — only sub-panels reserve the header row.
    readonly property bool hasHeader: root.depth > 0
    readonly property int chrome: pad * 2 + (hasHeader ? headerH + gap : 0)

    // ── Navigation ────────────────────────────────────────────────────────────────
    // The arguments are assigned BEFORE the stack, and this is not style: writing
    // navStack drives currentRoute → currentPanel → Loader.source → onLoaded
    // synchronously, inside that one assignment. Setting navArgs afterwards means
    // the panel is already loaded and has read the PREVIOUS entry's arguments —
    // which is why the theme editor opened as a blank "new theme" form.
    function push(route, args) {
        if (!HubRegistry.find(route)) return;   // unknown route → no-op
        root.navDir = 1;
        root.navArgs = root.navArgs.concat([args !== undefined ? args : null]);
        root.navStack = root.navStack.concat([route]);
    }
    function pop() {
        if (root.navStack.length === 0) return;
        root.navDir = -1;
        root.navArgs = root.navArgs.slice(0, -1);
        root.navStack = root.navStack.slice(0, -1);
    }
    // Esc / Backspace / breadcrumb: up one level, or dismiss at the root.
    function back() {
        if (root.navStack.length > 0) root.pop();
        else Overlays.close("hub");
    }
    // Hand real keyboard focus to whatever is actually navigable right now: the root
    // grid, or the loaded panel. `card` keeps `focus: true` as the scope's fallback
    // holder (and its own Escape/Backspace still fire via normal Qt Quick bubbling —
    // an unaccepted key on the focus item propagates up the parent chain, and both
    // rootGrid and panelLoader.item are descendants of card), so this only needs to
    // move the ACTIVE item, not touch the Escape/Backspace handling below.
    function focusContent() {
        if (panelLoader.active && panelLoader.item) panelLoader.item.forceActiveFocus();
        else rootGrid.forceActiveFocus();
    }

    // Consume any pending deep-link into a starting stack. Ф0: registry is empty so the
    // first segment never resolves and we open at root; the wiring is here for later
    // phases (Overlays.open("hub", { route: "appearance" })).
    function applyDeepLink() {
        const r = Overlays.pendingRoute;
        Overlays.pendingRoute = null;
        root.navDir = 1;
        root.navStack = (r && HubRegistry.find(String(r).split("/")[0])) ? [String(r)] : [];
        root.navArgs = root.navStack.map(() => null);   // a deep-link carries no arguments
    }

    // Rebuild the nav stack only on a REAL open (active false→true), not on a
    // suspend/restore (active stays true while suspended), so the drill-in position
    // survives a polkit prompt. Same gate re-probes the roving-nav key resolver — the
    // active hotkeys profile (and its menu_up/down/left/right chords) can only have
    // changed while the Hub was closed.
    onActiveChanged: if (root.active) { root.applyDeepLink(); HubNavKeys.refresh(); }

    // Toggle from Hyprland:  bind = SUPER, Space, global, quickshell:hub
    GlobalShortcut {
        appid: "quickshell"
        name: "hub"
        onPressed: Overlays.toggle("hub")
    }

    PanelWindow {
        id: win

        // Stay mapped while fading out, then unmap once invisible.
        visible: root.shown || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Layer-shell: overlay above everything, grab keyboard while shown. Suspended →
        // release the grab so a polkit prompt can take focus. The namespace is matched by
        // `layerrule = blur` in hyprland.lua for the shared backdrop blur.
        WlrLayershell.namespace: "quickshell:hub"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            // The Hub can still be dismissed from outside (the toggle shortcut, the bar
            // button) while the picker is up; drop it so it does not reappear over the
            // next screen the user opens.
            if (!visible) { filePicker.active = false; root._pickCb = null; }
            if (visible) {
                root.focusContent();   // (re-)grab on open and on restore-from-suspend
            } else if (root._suspendedCmd !== null) {
                // Fully hidden while suspended → start the deferred suspended command as a
                // tracked process; the Hub restores + reconciles on its exit (privProc).
                const sc = root._suspendedCmd;
                root._suspendedCmd = null;
                privProc.command = sc;
                privProc.running = true;
            } else if (root.pendingCmd !== null) {
                // Fully hidden now → run a deferred close command on a clean frame, so the
                // fading card is never captured under the lock blur. No caller today; see
                // the note on pendingCmd above for why the path stays.
                const c = root.pendingCmd;
                root.pendingCmd = null;
                Quickshell.execDetached(c);
            }
            // Nav state is intentionally NOT reset on hide: onActiveChanged rebuilds it on
            // the next real open, so the morph back to root stays invisible.
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

            // Click outside the card to dismiss. Tint + blur come from the shared
            // Backdrop surface (modules/overlay), so this layer is input-only.
            MouseArea { anchors.fill: parent; onClicked: Overlays.close("hub") }

            // Hub card — fixed width, height morphs to the current screen's content.
            Rectangle {
                id: card
                // Top-pinned like the launcher/clipboard (pinRef): the top edge lands at
                // the same screen Y as those popups and the card morphs DOWNWARD as its
                // content grows — it no longer re-centers/"floats" per height. Whole-pixel
                // origin keeps the border crisp.
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - root.pinRef) / 2)
                width: root.cardW
                height: Math.min(root.maxCardH, root.chrome + body.contentHeight)
                radius: Geometry.radius
                // Surface translucency from the effects axis (bg only; inner items stay
                // opaque). The scrim+blur backdrop shows softly through the frosted card.
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: HubConfig.border
                clip: true

                // While the file picker is up, this card goes out of focus behind it.
                // Hyprland's layer blur cannot do this — it blurs what is BEHIND a
                // surface, and both live in the same one — so the card is rendered to a
                // layer and blurred in-scene, which is what makes the picker's frosted
                // surface read as frosted instead of merely see-through. Strength comes
                // from the theme's effects axis (Effects.blurRadius), and a theme — or a
                // user — with blur off gets no layer at all; the picker then turns
                // opaque instead (see WFilePicker). The layer exists only while the
                // picker is open.
                layer.enabled: filePicker.active && Effects.blurEnabled
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: Effects.blurRadius
                }

                // Morph the height with the shared base timing on route/content changes.
                Behavior on height {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Entrance: subtle scale-in, top-pinned so the header stays put.
                transformOrigin: Item.Top
                scale: root.shown ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Hold focus so Esc / Backspace navigate while open. Escape is the
                // `menu_back` token (rebindable, see HubNavKeys); Backspace stays a
                // fixed alias here regardless of profile — same "universal idiom, not
                // part of the arrows/hjkl ergonomics story" reasoning as Space/Enter
                // for confirm (see quickshell-hub.md's keyboard-nav section).
                focus: true
                Keys.onPressed: (e) => {
                    switch (e.key) {
                    case HubNavKeys.back:  root.back(); e.accepted = true; return;
                    case Qt.Key_Backspace: root.back(); e.accepted = true; return;
                    }
                }

                // Swallow clicks so they don't reach the dismiss MouseArea.
                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: root.pad
                    spacing: root.gap

                    // ── Breadcrumb header ─────────────────────────────────────
                    // Only on sub-panels: the root has no title (dropped) and nothing to
                    // go back to, so the header is hidden and the Column skips it (no gap).
                    HubHeader {
                        id: header
                        width: parent.width
                        height: root.headerH
                        visible: root.hasHeader
                        canGoBack: root.depth > 0
                        title: root.currentPanel ? Strings.t(root.currentPanel.title) : ""
                        onBack: root.back()
                    }

                    // ── Body: current route's screen (root placeholder for Ф0) ─
                    // Height-capped; long panels scroll internally. `contentHeight`
                    // feeds the card height morph. A drill-in slides the content in
                    // (navDir); the full simultaneous parent/child slide lands in Ф2.
                    Item {
                        id: body
                        width: parent.width
                        height: Math.min(root.maxCardH - root.chrome, contentHeight)

                        readonly property real contentHeight:
                            panelLoader.active
                                ? (panelLoader.item ? panelLoader.item.implicitHeight : 0)
                                : rootGrid.implicitHeight

                        // Slide + fade the content in on every route change.
                        Item {
                            id: slider
                            anchors.fill: parent

                            // Root screen: the Control Center glance grid (quick toggles,
                            // sliders, action/link tiles). Shown whenever no panel route
                            // is active.
                            RootGrid {
                                id: rootGrid
                                width: parent.width
                                visible: !panelLoader.active
                                // Deferred close: close the Hub, run the command only once
                                // it is fully hidden, so the fading card isn't captured.
                                // Unused today — kept with the mechanism (see RootGrid).
                                onDeferredExec: (cmd) => { root.pendingCmd = cmd; Overlays.close("hub"); }
                                // Section entry (Appearance/Network/…) → drill into its panel.
                                onNavigate: (route) => root.push(route)
                            }

                            // Panel screen for the current route (Ф2+; inert while the
                            // registry is empty). Source resolved relative to this dir.
                            Loader {
                                id: panelLoader
                                width: parent.width
                                // A concrete (capped) viewport so a tall panel scrolls
                                // internally instead of overflowing the card; the panel's
                                // implicitHeight still drives the card-height morph.
                                height: body.height
                                active: root.currentPanel !== null
                                source: root.currentPanel ? root.currentPanel.source : ""
                                // Hand the route's arguments to the panel that asked for
                                // them. Panels that declare no `navArgs` are untouched, so
                                // this stays invisible to every existing screen.
                                onLoaded: if (item && item.navArgs !== undefined) item.navArgs = root.currentArgs
                            }

                            // Wire a panel's optional signals into the Hub:
                            //   • switchTheme  (Appearance) → dispatch by the configured
                            //     transition mode.
                            //   • runPrivileged (Network)   → the same suspend/pkexec bracket
                            //     the root grid used (step aside for polkit, restore + refresh).
                            // ignoreUnknownSignals: panels without a given signal are fine.
                            Connections {
                                target: panelLoader.item
                                ignoreUnknownSignals: true
                                function onSwitchTheme(name, onDone) { root.applyTheme(name, onDone); }
                                function onRunPrivileged(cmd, onDone) { root.runPrivileged(cmd, onDone); }
                                // A panel can drill deeper (Input → layout / locale pickers)
                                // or pop itself back once its action completes. `args` is
                                // undefined for the panels whose signal carries only a
                                // route, which push() reads as "no arguments".
                                function onNavigate(route, args) { root.push(route, args); }
                                function onNavigateBack() { root.pop(); }
                                // A panel that grabbed keyboard focus (Hotkeys chord capture)
                                // returns it so Esc / Backspace navigate the Hub again (and,
                                // now, so its own roving-nav Keys.onPressed sees arrows again).
                                function onRestoreFocus() { root.focusContent(); }
                                // A panel that needs a file → the window-level picker.
                                function onPickFile(opts, onPicked) { root.pickFile(opts, onPicked); }
                            }
                        }

                        // Enter-transition: nudge from navDir and fade up, restarted on
                        // each route change.
                        function playEnter() {
                            slider.x = root.navDir * 24;
                            slider.opacity = 0;
                            enterAnim.restart();
                        }
                        ParallelAnimation {
                            id: enterAnim
                            NumberAnimation {
                                target: slider; property: "x"; to: 0
                                duration: Motion.base
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.bezierCurve
                            }
                            NumberAnimation {
                                target: slider; property: "opacity"; to: 1
                                duration: Motion.fast
                            }
                        }
                        Connections {
                            target: root
                            function onCurrentRouteChanged() {
                                body.playEnter();
                                // Move keyboard focus to whatever just became current — the
                                // new panel (already loaded synchronously; see the ordering
                                // notes on push()/applyDeepLink() above) or back to rootGrid
                                // when the stack emptied.
                                root.focusContent();
                            }
                        }
                    }
                }
            }

            // File chooser, stacked above the card (last child = on top). Idle and
            // invisible until a panel asks for it; while it is up it holds the
            // keyboard, so Esc/Backspace navigate the picker and not the Hub.
            WFilePicker {
                id: filePicker
                anchors.fill: parent
                onPicked: (path) => {
                    const cb = root._pickCb;
                    root._pickCb = null;
                    root.focusContent();
                    if (cb) cb(path);
                }
                onDismissed: {
                    root._pickCb = null;
                    root.focusContent();
                }
            }

            // Topmost of all: no hover highlight while the cursor is hidden (so the
            // roving focus is the only mark on screen). Covers the picker too.
            HoverGate { anchors.fill: parent }
        }
    }
}
