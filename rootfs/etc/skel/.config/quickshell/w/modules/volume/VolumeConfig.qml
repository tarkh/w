pragma Singleton

// W Linux — Volume Control behaviour config for the Quickshell shell.
// Like LauncherConfig/NotifConfig, this is a USER-OWNED config: w-style/w-theme
// never touch it. Edit volume.json and the running shell picks it up live via
// FileView{watchChanges}. Defaults below mirror the committed volume.json, so the
// popup behaves sanely even if the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Command run by the "Open Mixer" button (Quickshell.execDetached form: argv
    // array, first element is the program). Default opens the wiremix TUI in W's
    // terminal — swap this in volume.json to point at any other mixer without
    // touching QML (e.g. ["pwvucontrol"] to bypass the terminal). Terminal TUIs go
    // through w-term so they follow the active terminal + its systemd fast path.
    property var mixerCommand: ["w-term", "-e", "wiremix"]

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (Array.isArray(c.mixerCommand) && c.mixerCommand.length > 0)
                root.mixerCommand = c.mixerCommand;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/volume.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
