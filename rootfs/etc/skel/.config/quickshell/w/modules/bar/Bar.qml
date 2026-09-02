// W Linux — status bar.
// A layer-shell panel anchored top or bottom (replacing Waybar), reserving space
// via its exclusive zone. Three zones — start (left), center (true bar center,
// independent of the side widths, like Waybar) and end (right) — are populated
// data-driven from config/bar.json (BarConfig): each entry is { type, settings },
// rendered by a Loader keyed on type, so adding a block = a file in blocks/ + a
// config entry. Transparency lives in the colors (BarConfig.col → token/#hex +
// per-element opacity); the compositor only blurs behind the translucent bar
// (layerrule in hyprland.lua).
//
// Multi-monitor: one PanelWindow per screen (Variants), gated by BarConfig.barOn() —
// always shown on the primary monitor (Displays.isPrimary), plus any monitor with a
// `bar.json → monitors` entry. Per-monitor entries can override only the block
// composition (BarConfig.blocksFor); geometry/colors stay global (BarConfig). The
// screen list is a live binding (barScreens) so hotplug and primary changes are
// reflected without a shell restart. `screen: modelData` is also what makes monitor
// selection deterministic — without it Quickshell picked an arbitrary screen.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.core

Scope {
    id: root

    // Screens the bar should render on: reactive to Quickshell.screens, Displays.primary
    // and BarConfig.monitorCfg (BarConfig.barOn reads both through Displays.isPrimary).
    readonly property var barScreens: Quickshell.screens.filter(s => BarConfig.barOn(s.name))

    Variants {
        model: root.barScreens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            color: "transparent"            // visible bar is the rounded surface below

            anchors {
                top:    BarConfig.position === "top"
                bottom: BarConfig.position === "bottom"
                left:   true
                right:  true
            }
            margins {
                top:    BarConfig.marginTop
                bottom: BarConfig.marginBottom
                left:   BarConfig.marginLeft
                right:  BarConfig.marginRight
            }
            implicitHeight: BarConfig.height
            // Reserve exactly the bar's height; Quickshell offsets the exclusive zone by
            // the anchored-edge margin itself, so adding the margin here double-counts it.
            exclusiveZone:  BarConfig.height

            WlrLayershell.namespace: "quickshell:bar"
            WlrLayershell.layer:     WlrLayer.Top
            // None: the bar has no keyboard input of its own, and OnDemand made it a
            // focus candidate — with follow_mouse=1 merely hovering the bar handed it
            // the keyboard, and leaving it over an empty workspace left the focus stuck
            // there (Hyprland then reports NO active window, so the next window opened
            // unfocused until the pointer crossed it). Every keyboard-taking surface the
            // bar spawns is a window of its own with its own Exclusive focus while shown
            // — the tray menu (TrayMenu.qml), calendar, volume/brightness, hub, launcher.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Bar background — rounded; transparency comes from bgOpacity. Fades out
            // when the session is exiting, in step with Hyprland minimizing the windows.
            Rectangle {
                id: surface
                anchors.fill: parent
                radius: BarConfig.cornerRadius(height)
                color:  BarConfig.col(BarConfig.bgColor, BarConfig.bgOpacity)
                opacity: Session.exiting ? 0 : 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }
                border.width: BarConfig.borderWidth
                border.color: BarConfig.col(BarConfig.borderColor, BarConfig.borderOpacity)

                // Content band, inset by the per-side padding. Blocks fill its height.
                Item {
                    id: content
                    anchors.fill: parent
                    anchors.topMargin:    BarConfig.padTop
                    anchors.bottomMargin: BarConfig.padBottom
                    anchors.leftMargin:   BarConfig.padLeft
                    anchors.rightMargin:  BarConfig.padRight

                    Row {
                        id: startZone
                        anchors.left: parent.left
                        height: parent.height
                        spacing: BarConfig.gap
                        Repeater { model: BarConfig.blocksFor(bar.modelData.name, "start"); delegate: blockDelegate }
                    }
                    Row {
                        id: centerZone
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: parent.height
                        spacing: BarConfig.gap
                        Repeater { model: BarConfig.blocksFor(bar.modelData.name, "center"); delegate: blockDelegate }
                    }
                    Row {
                        id: endZone
                        anchors.right: parent.right
                        height: parent.height
                        spacing: BarConfig.gap
                        Repeater { model: BarConfig.blocksFor(bar.modelData.name, "end"); delegate: blockDelegate }
                    }
                }
            }

            // Shared delegate: load the block QML for its type, hand it its settings.
            Component {
                id: blockDelegate
                Loader {
                    id: ld
                    required property var modelData
                    height: parent ? parent.height : 0
                    width:  item ? item.implicitWidth : 0
                    // Blocks may opt out of taking space when empty (apps/tray with no
                    // items) via a barVisible property; a hidden Loader is skipped by the
                    // Row entirely, so its zone and the surrounding gap collapse too.
                    visible: item && item.barVisible !== undefined ? item.barVisible : true
                    source: BarConfig.blockSource(modelData.type)
                    onLoaded: {
                        if (!item) return;
                        item.settings = modelData.settings;
                        // Zone blocks take their children from a top-level "items"; other
                        // blocks have no itemsModel property, so this is a no-op for them.
                        if (item.itemsModel !== undefined && modelData.items !== undefined)
                            item.itemsModel = modelData.items;
                    }
                }
            }
        }
    }
}
