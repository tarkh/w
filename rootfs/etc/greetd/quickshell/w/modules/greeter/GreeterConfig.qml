pragma Singleton

// W Linux — greeter behaviour config.
// USER/ADMIN-owned (like the user shell's LauncherConfig): w-style/w-theme never
// touch it. Edit config/greeter.json. Defaults below keep the greeter working if
// the file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Show a session picker on the login card. Off by default — the system ships a
    // single session (Hyprland). When on, sessions are read from
    // /usr/share/wayland-sessions and the chosen one's Exec is launched.
    property bool showSessionPicker: false

    // Connector name of the monitor that shows the login card (e.g. "DP-1"). Empty
    // = auto: the monitor at the layout origin (0,0), else the first screen. The
    // wallpaper always fills every monitor regardless of this.
    // primaryMonitorCfg = raw greeter.json value (admin default); primaryMonitor is
    // the EFFECTIVE value Greeter.qml reads — the /etc/w/monitors-greeter.json
    // override (`w-monitor greeter primary`, see w-monitor.md §Этап 4) wins over it
    // when non-empty, same override-vs-admin-default pattern as cardOpacity below.
    property string primaryMonitorCfg: ""
    property string primaryMonitorOverride: ""
    readonly property string primaryMonitor: primaryMonitorOverride !== "" ? primaryMonitorOverride : primaryMonitorCfg

    // Opacity of the card BACKGROUND only (0..1) — the inputs/buttons stay opaque.
    // Below 1 the compositor blur (layerrule on w-greeter) shows the wallpaper
    // softly through the card. 1 = solid (no blur visible).
    // cardOpacityCfg = raw greeter.json value (number or token "surface"/"scrim"); cardOpacity is a
    // LIVE binding via Effects.op (tracks json AND theme) — never resolve eagerly (load-order bug).
    property var  cardOpacityCfg: "surface"
    readonly property real cardOpacity: Effects.op(cardOpacityCfg, Effects.surfaceOpacity)

    // ── Login flow timing (milliseconds) — the whole choreography lives here, no
    //    hardcoded pauses in QML. Sequence:
    //      in:  initPause → wallpaper fades in → (uiDelay) → interface fades in
    //      out: interface fades out → (uiDelay) → wallpaper fades out →
    //           (postPause) → launch the user session
    //    bgFade/uiFade are the fade DURATIONS of the wallpaper / interface. ────────
    property int initPause: 0      // before anything appears
    property int uiDelay:   1000   // gap between wallpaper and interface (both ways)
    property int postPause: 0      // after the wallpaper is fully black, before launch
    property int bgFade:    400    // wallpaper fade-in/out duration
    property int uiFade:    300    // interface fade-in/out duration

    // When to launch the user session, measured from successful authentication
    // (readyToLaunch ≈ the Log In press):
    //   false      — tied to the wallpaper fade-out (launch only once it is fully
    //                black: uiDelay + bgFade + postPause). Guarantees a black frame
    //                at hand-off. Default.
    //   <number ms>— absolute delay from auth; launch this many ms after confirmation
    //                regardless of the fade (0 = immediately). Lets the user session's
    //                cold start overlap the tail of the fade to cut black time. The
    //                fade still plays but is cut short when the session takes over.
    property var launchDelay: false

    // Default session launch command + extra environment, used when the picker is
    // off (or before a session is chosen). Mirrors the Hyprland wayland-session
    // entry (uwsm-managed systemd user session — see hyprland.desktop). greetd runs
    // this as the authenticated user under a fresh PAM session.
    property var sessionCommand: ["uwsm", "start", "-N", "Hyprland", "-D", "Hyprland", "--", "Hyprland"]
    property var sessionEnv: ["UWSM_SILENT_START=1"]

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.showSessionPicker !== undefined)  root.showSessionPicker = c.showSessionPicker;
            if (c.primaryMonitor !== undefined)     root.primaryMonitorCfg = c.primaryMonitor;
            if (c.cardOpacity !== undefined)        root.cardOpacityCfg    = c.cardOpacity;  // raw; binding resolves live
            if (Array.isArray(c.sessionCommand))    root.sessionCommand    = c.sessionCommand;
            if (Array.isArray(c.sessionEnv))        root.sessionEnv        = c.sessionEnv;
            if (c.initPause !== undefined)          root.initPause         = c.initPause;
            if (c.uiDelay   !== undefined)          root.uiDelay           = c.uiDelay;
            if (c.postPause !== undefined)          root.postPause         = c.postPause;
            if (c.bgFade    !== undefined)          root.bgFade            = c.bgFade;
            if (c.uiFade    !== undefined)          root.uiFade            = c.uiFade;
            if (c.launchDelay !== undefined)        root.launchDelay       = c.launchDelay;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/greeter.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    // Greeter-scope monitor override, written by `w-monitor greeter primary`/`sync`
    // (root, /etc/w/, see w-monitor.md §Этап 4) — absolute path, not admin-config-
    // relative like greeter.json above. Absent (fresh install, `greeter reset`) is
    // the normal case: primaryMonitor just falls back to primaryMonitorCfg.
    FileView {
        path: "/etc/w/monitors-greeter.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.primaryMonitorOverride = c.primary || "";
            } catch (e) {
                root.primaryMonitorOverride = "";
            }
        }
        onLoadFailed: root.primaryMonitorOverride = ""
    }
}
