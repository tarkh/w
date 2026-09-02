// W Linux — On-Screen Display (Quickshell).
// Transient feedback for volume / mute / brightness. Deliberately a SIBLING of the
// app-notification card, not a clone: it shares the shell's material (Colors/Motion/
// Fonts, same radius/border) but sits top-CENTER, is a single self-replacing popup
// (a new value resets the existing one instead of stacking), and shows a progress
// bar instead of title/body — so it reads as "system feedback", never an app message.
//
// Volume/mute come natively from PipeWire (no subprocess), like VolumeControl.
// Brightness comes from the shared core.Backlight singleton (brightnessctl autodetect
// + sysfs, same source as the bar block and the Brightness Control popup) — no config,
// auto-hidden on machines without a backlight (desktops, VMs). The popup is purely
// visual: `mask` is empty so it never intercepts a click.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Io
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.shading

Scope {
    id: root

    // Set true while the Volume Control popup is open (wired in shell.qml) so
    // adjusting volume there doesn't also throw an OSD.
    property bool suppress: false

    property bool shown: false
    property string label: ""
    property string glyph: ""
    property real value: 0          // 0..1
    property bool muted: false

    // Ignore PipeWire/brightness bindings firing once at startup (avoids an OSD
    // popping on login). Becomes true a moment after the shell settles.
    property bool ready: false
    Timer { id: initTimer; interval: 1500; running: true; onTriggered: root.ready = true }

    Timer { id: hideTimer; interval: NotifConfig.timeoutOsd; onTriggered: root.shown = false }

    function present(glyph, val, isMuted, text) {
        if (!NotifConfig.enableOsd || root.suppress) return;
        root.glyph = glyph;
        root.value = Math.max(0, Math.min(1, val));
        root.muted = isMuted;
        root.label = text;
        root.shown = true;
        hideTimer.restart();
    }

    // ── Volume / mute (native PipeWire) ───────────────────────────────────────
    // Track the default sink so its volume/muted stay reactive (see VolumeControl).
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property real sinkVol: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    readonly property bool sinkMuted: Pipewire.defaultAudioSink?.audio?.muted ?? false

    // The level thresholds live in Glyphs.volume() so the bar, this OSD and the
    // audio popup cannot drift apart about what "low" means.
    onSinkVolChanged: if (root.ready) root.present(Glyphs.volume(sinkVol, sinkMuted), sinkVol, sinkMuted, Strings.t("osd.volume"))
    onSinkMutedChanged: if (root.ready) root.present(Glyphs.volume(sinkVol, sinkMuted), sinkVol, sinkMuted, sinkMuted ? Strings.t("osd.muted") : Strings.t("osd.volume"))

    // ── Brightness (shared core.Backlight singleton — autodetected, no config) ─
    Connections {
        target: Backlight
        function onValueChanged() {
            if (root.ready && Backlight.available)
                root.present(Glyphs.brightness, Backlight.value, false, Strings.t("osd.brightness"));
        }
    }

    // ── Keyboard backlight (shared core.KbdBacklight singleton) ───────────────
    // The keys that drive this are the only way to change it, and on a dark
    // keyboard "did that press register?" is otherwise unanswerable — so the OSD
    // matters more here than for the screen. Silent on machines without one.
    Connections {
        target: KbdBacklight
        function onValueChanged() {
            if (root.ready && KbdBacklight.available)
                root.present(Glyphs.kbdBacklight, KbdBacklight.value, false, Strings.t("osd.kbdBrightness"));
        }
    }

    // ── Window ────────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.shown || card.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {}   // purely visual — never intercept input

        Rectangle {
            id: card
            anchors {
                top: parent.top
                topMargin: BarConfig.contentTop + NotifConfig.osdMarginTopOffset
                horizontalCenter: parent.horizontalCenter
            }
            width: 340   // matches VolumeControl.cardW so both popups share one footprint
            height: 56
            radius: NotifConfig.radius
            // Surface translucency from the effects axis (bg only; the icon/bar/label
            // children are separate items and stay opaque).
            color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, NotifConfig.surfaceOpacity)
            border.color: Colors.border
            border.width: NotifConfig.border

            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                }
            }
            transformOrigin: Item.Top
            scale: root.shown ? 1 : 0.96
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.base
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                }
            }

            Row {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 12

                ChromeIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 24
                    glyph: root.glyph
                    tint: Colors.text
                    opacity: root.muted ? 1 : 0.85
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 12 - 40 - 12
                    spacing: 6

                    Text {
                        text: root.label
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    // Progress bar — the defining OSD element. Track (right of the
                    // fill) is a dim recessed groove; fill (left, "how much is set")
                    // is the accent.
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Colors.inputBg
                        Rectangle {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: parent.width * root.value
                            height: parent.height
                            radius: parent.radius
                            color: root.muted ? Colors.muted : Colors.accent
                            Behavior on width {
                                NumberAnimation {
                                    duration: Motion.fast
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: root.muted ? "—" : Math.round(root.value * 100) + "%"
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 13
                }
            }
        }
    }
}
