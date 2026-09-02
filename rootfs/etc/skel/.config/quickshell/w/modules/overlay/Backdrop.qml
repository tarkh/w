// W Linux — shared overlay backdrop.
// One tinted, compositor-blurred full-screen surface PER MONITOR behind the "modal
// center" popups (launcher / clipboard / power menu / hub / … — Overlays.blurGroup).
// Previously each popup carried its own scrim; switching between two of them cross-
// faded two scrims, and at the crossover both fell below blur_ignore_alpha (0.3) at
// once, so the compositor dropped the blur for a frame — a visible unblur→blur flash.
// A single backdrop fixes it: its opacity tracks "is ANY blur-group popup open", so
// switching WITHIN the group keeps it solid (blur never dips); it only fades when the
// whole group opens or closes.
//
// Multi-monitor (Variants over Quickshell.screens, same pattern as Bar.qml): the popup
// itself still opens on Hyprland's currently focused output only (correct — that's
// where the user is looking, and none of the popups set `screen:`), but ALL monitors
// blur while it's open — a menu that only softens half the desktop reads as broken.
// On the popup's own monitor this backdrop instance sits BENEATH the popup's fullscreen
// surface (mounted first in shell.qml, so it commits — and stacks — first) and never
// actually receives input there; the popup's own click-outside-to-dismiss MouseArea
// still owns that monitor exactly as before.
//
// ⚠️ Click-to-dismiss on the OTHER monitor(s) was attempted (a real, non-empty input
// region on this backdrop while Overlays.scrimActive) and does NOT work: verified live
// that a click there never reaches Quickshell at all (no event, no log line) while an
// exclusive-keyboard-focus popup is open elsewhere — a Hyprland-level input-routing
// limit (the compositor doesn't deliver pointer input to other outputs while a layer
// surface holds exclusive keyboard focus on one of them), not something fixable from
// this file. Mask stays permanently empty, purely visual — matches every other popup's
// own fullscreen window (see Osd.qml). Known limitation: a click on the idle monitor
// has no effect; closing still works via the popup's own monitor, Esc, or its trigger.
//
// The surface is mapped ON DEMAND (only while a blur-group popup is open, plus the
// fade-out tail). On-demand mapping matters: Hyprland's layer-blur optimization caches
// the blurred background when the surface is created, so an always-mapped scrim
// (created at startup with nothing behind it) renders no blur — remapping per open
// keeps the blur fresh. It stays mapped and solid across in-group switches (scrimActive
// stays true), so the blur never dips → no flash. Blur comes from
// `quickshell:overlay-scrim` in hyprland.lua (matches by namespace, monitor-agnostic);
// colors/opacity/motion via singletons.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.core

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // Map while the group is open; stay mapped through the fade-out, then unmap.
            visible: Overlays.scrimActive || scrim.opacity > 0.01

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}                     // purely visual — never intercept input

            WlrLayershell.namespace: "quickshell:overlay-scrim"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Tinted scrim. Solid while any blur-group popup is open (compositor blurs what
            // is behind it); fades only across the group's open/close, so in-group switches
            // never disturb it.
            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Qt.rgba(Colors.backdrop.r, Colors.backdrop.g, Colors.backdrop.b, Effects.scrimOpacity)
                opacity: Overlays.scrimActive ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.fast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }
            }
        }
    }
}
