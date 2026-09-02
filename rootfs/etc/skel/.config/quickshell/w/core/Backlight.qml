pragma Singleton

// W Linux — screen backlight service.
// Quickshell has no native backlight service, so this shared singleton wraps the same
// sysfs approach used across the shell: a one-shot `brightnessctl -m -c backlight` at
// startup auto-detects the default backlight device (no config), then a FileView on its
// sysfs `brightness` gives live updates (no polling). `available` is false on machines
// without a backlight (desktops, VMs) — consumers hide their controls. Writes go through
// `brightnessctl set N%` (udev-permitted, no root). One home for brightness so the Hub
// tile, the Brightness Control popup (and later the bar block) share one detection.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string device: ""              // e.g. "intel_backlight"; "" → no backlight
    property real max: 1
    property int raw: 0

    readonly property bool available: root.device !== ""
    readonly property real value: root.raw / root.max   // 0..1

    // Detect the default backlight device once. `-c backlight` ignores led-class
    // (keyboard) devices; the machine-readable line is "name,class,current,percent,max".
    Process {
        running: true
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (this.text || "").trim().split("\n")[0] || "";
                root.device = line ? (line.split(",")[0] || "") : "";
            }
        }
    }

    FileView {
        path: root.device ? "/sys/class/backlight/" + root.device + "/max_brightness" : ""
        onLoaded: root.max = Math.max(1, parseInt(text()) || 1)
    }
    FileView {
        path: root.device ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.raw = parseInt(text()) || 0
    }

    // Set brightness from a 0..1 fraction. Floor at 1% so the slider can never black the
    // screen out entirely.
    function set(v) {
        if (!root.available) return;
        const pct = Math.max(1, Math.round(v * 100));
        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
    }
}
