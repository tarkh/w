// W Linux — tray context menu overlay.
// One shell-wide overlay that renders the open tray item's menu (TrayMenuState).
// Like the Volume Control popup it is a full-screen, transparent layer-shell surface
// (Overlay layer): the backdrop catches outside clicks to dismiss and the surface
// takes exclusive keyboard focus while open so Escape closes it — the proven,
// grab-free pattern (a small window + focus grab conflicts with the bar on the
// Top layer, which is why the platform/QsMenuAnchor menu never showed). The menu
// card (TrayMenuList) anchors under the originating tray button — or above it for a
// bottom bar — clamped to stay on screen.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.core

PanelWindow {
    id: win

    readonly property bool open: TrayMenuState.open
    readonly property int gap: BarConfig.windowGap

    visible: open || list.opacity > 0.01

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "quickshell:traymenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) keyCatcher.forceActiveFocus()

    // Outside click dismisses.
    MouseArea { anchors.fill: parent; onClicked: TrayMenuState.close() }

    // Escape dismisses (focused on open).
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: TrayMenuState.close()

        TrayMenuList {
            id: list
            menu: TrayMenuState.menu
            screenW: win.width
            screenH: win.height

            // Horizontally: right-align the card's right edge to the button's right
            // edge, clamped on screen. Vertically: anchored to the screen edge on the
            // bar's side — top bar drops from contentTop (reserved zone + Hyprland
            // gap), bottom bar rises from contentBottom — exactly like OSD /
            // notifications. marginOffset grows (+) or shrinks (-) that offset.
            readonly property rect a: TrayMenuState.anchor
            x: Math.max(win.gap,
                        Math.min(a.x + a.width - implicitWidth, win.width - implicitWidth - win.gap))
            y: BarConfig.position === "top"
               ? BarConfig.contentTop + TrayMenuConfig.marginOffset
               : win.height - BarConfig.contentBottom - implicitHeight - TrayMenuConfig.marginOffset

            opacity: win.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }
            transformOrigin: BarConfig.position === "top" ? Item.Top : Item.Bottom
            scale: win.open ? 1 : 0.94
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.base
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            onRequestClose: TrayMenuState.close()
        }
    }
}
