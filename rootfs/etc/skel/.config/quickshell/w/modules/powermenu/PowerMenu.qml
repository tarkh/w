// W Linux — Power Menu popup.
// A centered row of five large icon tiles — lock / log out / suspend / restart /
// shut down — over a tinted, compositor-blurred full-screen backdrop (the
// launcher's pattern). Toggled by a Hyprland global shortcut (Super+Backspace,
// i3-style). While open the card holds exclusive keyboard focus, so the i3-style
// hot keys work only here: L lock, E logout, S suspend, R restart, Ctrl+S shut
// down (Esc / click-outside dismiss; arrows + Enter also navigate). The selection
// is a single accent rectangle that slides between tiles (like the launcher's
// highlight), defaulting to Lock. The card shares the modal-center width
// (Overlays.cardWidth) and top-pin, so it sits in the same place as the launcher /
// clipboard / Hub; the five tiles size to fill that width and stay ~2.5× the other
// popups' rows — this is still a rare, deliberate menu.
//
// The chosen command runs only once the popup is fully hidden (pendingCmd), so a
// lock never captures the menu under its blurred screenshot. Graceful exit goes
// through w-session-exit, which closes windows (editors keep reachable save
// dialogs) and waits before powering down. Lock and suspend run directly.
// All timing and colors follow the Motion/Colors/Fonts singletons.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.shading

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any
    // other popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "powermenu"

    // Keyboard/hover selection. Defaults to 0 (Lock) on open.
    property int currentIndex: 0

    // Command to run once the popup has fully faded out (so lock/suspend don't get
    // captured under hyprlock's blurred screenshot).
    property string pendingCmd: ""

    // The card shares the modal-center width (Overlays.cardWidth) and top-pin so it reads
    // as one surface with the launcher/clipboard/Hub. Tiles size to fill that width: five
    // across, minus the 24px card padding each side and the inter-tile gaps.
    readonly property int gap: 16
    readonly property int pad: 24              // card inner padding each side
    readonly property int tileSize: Math.floor((Overlays.cardWidth - pad * 2 - gap * 4) / 5)
    readonly property int iconSize: 54
    // Top-pin reference: the card top lands at the same screen Y as the launcher/clipboard
    // (their card height, 480), so all the modal-center popups share one top edge.
    readonly property int pinRef: 480

    // Labels resolve through the shared Strings dictionary (key "powermenu.<id>");
    // hints are keyboard shortcuts, not translated.
    readonly property var actions: [
        { id: "lock",     hint: "L",      icon: "system-lock-screen" },
        { id: "logout",   hint: "E",      icon: "system-log-out" },
        { id: "suspend",  hint: "S",      icon: "system-suspend" },
        { id: "reboot",   hint: "R",      icon: "system-reboot" },
        { id: "shutdown", hint: "Ctrl+S", icon: "system-shutdown" },
    ]

    // Toggle from Hyprland:  bind = SUPER, Backspace, global, quickshell:powermenu
    GlobalShortcut {
        appid: "quickshell"
        name: "powermenu"
        onPressed: Overlays.toggle("powermenu")
    }

    // Map PowerMenuConfig.iconMode → ShadedIcon mode for the action tiles.
    function iconModeFor() {
        switch (PowerMenuConfig.iconMode) {
        case "solid":    return ShadedIcon.Solid;
        case "original": return ShadedIcon.Original;
        default:         return ShadedIcon.Tint;   // "tint"
        }
    }

    function run(cmd) {
        Quickshell.execDetached({ command: ["sh", "-c", cmd] });
    }

    // Lock/suspend keep apps running; logout/reboot/shutdown go through
    // w-session-exit (graceful close with reachable save dialogs, then act).
    function cmdFor(id) {
        switch (id) {
        case "lock":     return "loginctl lock-session";
        case "suspend":  return "systemctl suspend";
        case "logout":   return "w-session-exit logout";
        case "reboot":   return "w-session-exit reboot";
        case "shutdown": return "w-session-exit shutdown";
        }
        return "";
    }

    // Defer the command until the popup is fully hidden (see onVisibleChanged).
    function activate(id) {
        root.pendingCmd = root.cmdFor(id);
        Overlays.close("powermenu");
    }

    PanelWindow {
        id: win

        // Stay mapped while fading out, then unmap once invisible.
        visible: root.active || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Layer-shell: overlay above everything, grab keyboard while open so the
        // hot keys fire only here. The namespace is matched by `layerrule = blur`
        // in hyprland.lua for the backdrop blur.
        WlrLayershell.namespace: "quickshell:powermenu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                root.currentIndex = 0;       // default selection: Lock
                card.forceActiveFocus();
            } else if (root.pendingCmd !== "") {
                // Run only now that the overlay is unmapped — a clean frame for the
                // lock screenshot, and the menu never lingers behind the action.
                const c = root.pendingCmd;
                root.pendingCmd = "";
                // Session-ending actions (w-session-exit) begin closing windows now;
                // flag the session as exiting so the bar fades out in step. Lock and
                // suspend keep the session running, so they don't.
                if (c.indexOf("w-session-exit") !== -1) Session.exiting = true;
                root.run(c);
            }
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: root.active ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Click outside the card to dismiss. Tint + blur come from the shared
            // Backdrop surface (modules/overlay), so this layer is input-only.
            MouseArea { anchors.fill: parent; onClicked: Overlays.close("powermenu") }

            // Power menu card.
            Rectangle {
                id: card
                // Shared modal-center width + top-pin (like launcher/clipboard/Hub): fixed
                // width, top edge at the common reference Y, so it sits in the same place as
                // the other popups instead of dead-center + over-wide. Whole-pixel origin
                // keeps the border crisp.
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - root.pinRef) / 2)
                width: Overlays.cardWidth
                height: row.implicitHeight + root.pad * 2
                radius: Geometry.radius
                // Surface translucency from the effects axis (bg only; the tiles/labels
                // are separate items and stay opaque). The scrim+blur backdrop shows
                // softly through the frosted card.
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: PowerMenuConfig.border

                // Entrance: subtle scale-in, top-pinned so the top edge stays put.
                transformOrigin: Item.Top
                scale: root.active ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Hold focus so the hot keys and Esc work while open.
                focus: true
                Keys.onPressed: (e) => {
                    const ctrl = (e.modifiers & Qt.ControlModifier);
                    const n = root.actions.length;
                    switch (e.key) {
                    case Qt.Key_Escape: Overlays.close("powermenu"); e.accepted = true; return;
                    case Qt.Key_Left:   root.currentIndex = (root.currentIndex - 1 + n) % n; e.accepted = true; return;
                    case Qt.Key_Right:  root.currentIndex = (root.currentIndex + 1) % n; e.accepted = true; return;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:  root.activate(root.actions[root.currentIndex].id); e.accepted = true; return;
                    case Qt.Key_L: if (!ctrl) { root.activate("lock");   e.accepted = true; } return;
                    case Qt.Key_E: if (!ctrl) { root.activate("logout"); e.accepted = true; } return;
                    case Qt.Key_R: if (!ctrl) { root.activate("reboot"); e.accepted = true; } return;
                    // Ctrl+S = shut down (i3-style), plain S = suspend.
                    case Qt.Key_S: root.activate(ctrl ? "shutdown" : "suspend"); e.accepted = true; return;
                    }
                }

                // Swallow clicks so they don't reach the dismiss MouseArea.
                MouseArea { anchors.fill: parent }

                // Single accent highlight that slides between tiles (no per-tile
                // blink) — the launcher's pattern, applied to a horizontal row.
                Rectangle {
                    id: highlight
                    width: root.tileSize
                    height: root.tileSize
                    radius: Geometry.radiusSm
                    color: Colors.accent
                    x: row.x + root.currentIndex * (root.tileSize + root.gap)
                    y: row.y
                    Behavior on x {
                        NumberAnimation {
                            duration: Motion.fast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.bezierCurve
                        }
                    }
                }

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: root.gap

                    Repeater {
                        model: root.actions

                        delegate: Item {
                            id: tile
                            required property var modelData
                            required property int index

                            readonly property bool selected: root.currentIndex === index

                            width: root.tileSize
                            height: root.tileSize

                            Column {
                                anchors.centerIn: parent
                                spacing: 10

                                ShadedIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    size: root.iconSize
                                    icon: tile.modelData.icon
                                    // Papirus full-color action icons, recolored into the
                                    // brand by our shader (mode/shape from PowerMenuConfig).
                                    preferSymbolic: false
                                    mode: root.iconModeFor()
                                    // Brand tint unselected; on the accent selection tile
                                    // flip to accentFg so the glyph stays legible.
                                    tint: tile.selected ? Colors.accentFg : Colors.iconTint
                                    strength: PowerMenuConfig.iconStrength
                                    shade: PowerMenuConfig.iconShade
                                    lift: PowerMenuConfig.iconLift
                                    Behavior on tint { ColorAnimation { duration: Motion.fast } }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Strings.t("powermenu." + tile.modelData.id)
                                    color: tile.selected ? Colors.accentFg : Colors.text
                                    font.family: Fonts.family
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.hint
                                    color: tile.selected ? Colors.accentFg : Colors.muted
                                    font.family: Fonts.family
                                    font.pixelSize: 12
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse) root.currentIndex = tile.index
                                onClicked: root.activate(tile.modelData.id)
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
