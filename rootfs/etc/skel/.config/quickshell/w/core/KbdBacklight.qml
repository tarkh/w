pragma Singleton

// W Linux — keyboard backlight service.
// The led-class sibling of core/Backlight.qml, and deliberately the same shape:
// a one-shot detection at startup, a FileView on sysfs for live updates without
// polling, `available` false on machines that have no keyboard light (desktops,
// VMs, most laptops) so consumers hide themselves.
//
// Detection goes through `w-kbdlight device` rather than brightnessctl directly:
// led-class devices are vendor-named (smc::/tpacpi::/dell::kbd_backlight) and
// `brightnessctl -c leds` returns the FIRST led, which is normally an indicator
// (numlock), not the backlight. That resolution lives in one place — the same
// script the media keys and the initramfs hook use — so the shell can never
// disagree with the keyboard about which LED is "the keyboard backlight".
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string device: ""              // e.g. "smc::kbd_backlight"; "" → none
    property real max: 1
    property int raw: 0

    readonly property bool available: root.device !== ""
    readonly property real value: root.raw / root.max   // 0..1

    Process {
        running: true
        command: ["w-kbdlight", "device"]
        stdout: StdioCollector {
            onStreamFinished: root.device = (this.text || "").trim().split("\n")[0] || ""
        }
    }

    FileView {
        path: root.device ? "/sys/class/leds/" + root.device + "/max_brightness" : ""
        onLoaded: root.max = Math.max(1, parseInt(text()) || 1)
    }
    FileView {
        path: root.device ? "/sys/class/leds/" + root.device + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.raw = parseInt(text()) || 0
    }

    // Set from a 0..1 fraction. No floor here, unlike the screen: a dark keyboard
    // is a legitimate state (and the only way to turn the light off), whereas a
    // black screen would leave the user with nothing to look at.
    function set(v) {
        if (!root.available) return;
        Quickshell.execDetached(["w-kbdlight", "set", Math.max(0, Math.round(v * 100)) + "%"]);
    }
}
