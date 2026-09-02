// W Linux — Quickshell login screen (greetd frontend).
//
// One job: authenticate a user, then launch their session. Everything else a
// shell would carry (bar, launcher, menus, global shortcuts, arbitrary exec) is
// deliberately absent. The only outbound actions are the greetd protocol
// (Quickshell.Services.Greetd) and two power buttons (systemctl reboot/poweroff).
//
// Layout: the active system theme's wallpaper fills every screen (drawn here, no
// hyprpaper); a centered card on the primary screen holds the clock, the user and
// session dropdowns, the password field (focused by default), the Log In button
// and the power row.
//
// Seamless transitions are choreographed entirely from GreeterConfig (no hardcoded
// pauses). Wallpaper and interface fade INDEPENDENTLY and bridge through black so
// the two compositors hand off without a flash:
//   in : initPause → wallpaper fades in → (uiDelay) → interface fades in
//   out: interface fades out → (uiDelay) → wallpaper fades out → (postPause) →
//        Greetd.launch() exits quickshell and starts the user session (also black
//        → its own wallpaper fades in). The brief black before the desktop appears
//        is the user compositor's cold start, not a greeter pause.
//
// All texts come from Strings (system-locale i18n); fade easing from Motion.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Controls
import qs.core

Scope {
    id: root

    // ── Auth state ────────────────────────────────────────────────────────────
    property string username: ""
    property string pendingResponse: ""    // password held until greetd asks for it
    property string errorText: ""
    property bool busy: false               // request in flight (createSession…launch)

    // ── Transition state (wallpaper and interface fade independently) ───────────
    property bool bgShown: false
    property bool uiShown: false
    property bool leaving: false
    property bool launched: false           // guard: launch the session exactly once

    // ── Users (real login accounts parsed from /etc/passwd) ─────────────────────
    property var users: []
    property var userOptions: root.users.map(u => ({ label: u.label, value: u.name }))

    // ── Wallpaper manifest (per-tier resolved paths, written by `w-wallpaper set`) ─
    // Same selection logic as hyprpaper: pick the first tier whose minWidth the
    // monitor meets. Each path already has the theme's fallback applied, so any
    // non-empty theme yields a wallpaper for every monitor.
    property var wpTiers: []                 // [{minWidth, path}], widest-first
    function wallpaperFor(physWidth) {
        for (const t of root.wpTiers) if (physWidth >= t.minWidth && t.path) return t.path;
        return "";
    }
    FileView {
        path: "/run/w/wallpaper/manifest.json"
        onLoaded: { try { root.wpTiers = JSON.parse(text()); } catch (e) { root.wpTiers = []; } }
    }

    // Monitor that holds the login card: configured connector name, else the
    // monitor at the layout origin (0,0), else the first screen.
    function primaryScreen() {
        const list = Quickshell.screens;
        if (!list || list.length === 0) return null;
        const want = GreeterConfig.primaryMonitor;
        if (want) for (const s of list) if (s.name === want) return s;
        for (const s of list) if (s.x === 0 && s.y === 0) return s;
        return list[0];
    }

    // ── Sessions + effective launch command ─────────────────────────────────────
    property var sessions: []
    property var sessionOptions: root.sessions.map(s => ({ label: s.name, value: s.name }))
    property var sessionCmd: GreeterConfig.sessionCommand
    property string sessionName: "Hyprland"

    function refreshUsers() {
        const out = [];
        for (const line of passwd.text().split("\n")) {
            if (!line) continue;
            const f = line.split(":");
            if (f.length < 7) continue;
            const uid = parseInt(f[2]);
            if (isNaN(uid) || uid < 1000 || uid >= 60000) continue;
            if (/(nologin|false)$/.test(f[6])) continue;       // no-login shells
            const gecos = (f[4] || "").split(",")[0];
            out.push({ name: f[0], label: gecos.length ? gecos : f[0] });
        }
        root.users = out;
        // Preselect the last successful user if still present, else the first.
        let pick = out.length ? out[0].name : "";
        for (const u of out) if (u.name === GreeterState.lastUser) { pick = u.name; break; }
        root.username = pick;
    }

    function selectSession(name) {
        for (const s of root.sessions)
            if (s.name === name) { root.sessionCmd = s.command; root.sessionName = name; return; }
    }

    function parseSessions(out) {
        const list = [];
        for (const line of out.split("\n")) {
            if (!line) continue;
            const t = line.split("\t");
            if (t.length < 2) continue;
            list.push({ name: t[0] || t[1], command: t[1].split(" ").filter(s => s.length) });
        }
        root.sessions = list;
        if (!list.length) return;
        // Preselect the last successful session if still present, else the first.
        let pick = list[0].name;
        for (const s of list) if (s.name === GreeterState.lastSession) { pick = s.name; break; }
        root.selectSession(pick);
    }

    // ── Auth flow ───────────────────────────────────────────────────────────────
    // Enter / Log In → start a session, then answer the password prompt when greetd
    // asks (respond() is only valid once a response is required). After a failure
    // greetd discards the session (auth_error), so state returns to Inactive and the
    // next submit starts a fresh session — we must NOT cancelSession here (that would
    // poke a dead session and surface a raw IO error).
    function submit() {
        if (root.busy || root.username === "") return;
        root.errorText = "";
        root.busy = true;
        root.pendingResponse = pwd.text;
        if (Greetd.state === GreetdState.Authenticating)
            Greetd.respond(pwd.text);
        else
            Greetd.createSession(root.username);
    }

    function startLeave() {
        GreeterState.remember(root.username, root.sessionName);
        root.leaving = true;
        root.uiShown = false;        // interface fades out first…
        tBgOut.start();              // …then the wallpaper after uiDelay (visual)
        // launchDelay: a number → launch at a fixed offset from auth (may overlap the
        // fade); false → launch is driven by the fade-out completion (tBgOut→tLaunch).
        if (GreeterConfig.launchDelay !== false) {
            tFixedLaunch.interval = GreeterConfig.launchDelay;
            tFixedLaunch.start();
        }
    }
    function doLaunch() {
        if (root.launched) return;
        root.launched = true;
        Greetd.launch(root.sessionCmd, GreeterConfig.sessionEnv, true);
    }

    function power(verb) { Quickshell.execDetached(["systemctl", verb]); }

    // Real login accounts come from /etc/passwd (world-readable; no shell-out).
    FileView { id: passwd; path: "/etc/passwd"; onLoaded: root.refreshUsers() }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired)
                Greetd.respond(echoResponse ? root.username : root.pendingResponse);
            else if (error)
                root.errorText = Strings.t("error");
        }
        function onReadyToLaunch() { root.startLeave(); }
        function onAuthFailure(message) {
            root.errorText = Strings.t("authFailed");
            root.busy = false;
            pwd.text = "";
            pwd.forceActiveFocus();
        }
        function onError(e) {
            console.log("greeter: greetd error:", e);
            root.errorText = Strings.t("error");
            root.busy = false;
        }
    }

    // ── Independent fade controllers (durations from config) ────────────────────
    // Wallpaper opacity = bgCtl.v; interface opacity = uiCtl.v. When the wallpaper
    // fade-OUT finishes we wait postPause then launch (a clean black frame).
    Item {
        id: bgCtl
        property real v: root.bgShown ? 1 : 0
        Behavior on v {
            NumberAnimation {
                duration: GreeterConfig.bgFade
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.bezierCurve
            }
        }
    }
    Item {
        id: uiCtl
        property real v: root.uiShown ? 1 : 0
        Behavior on v {
            NumberAnimation {
                duration: GreeterConfig.uiFade
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.bezierCurve
            }
        }
    }

    // Sequencing timers. Reveal: bg at initPause, ui uiDelay later. Leave: bg out
    // uiDelay after ui out; launch postPause after bg is black.
    Timer { id: tBgIn;   interval: GreeterConfig.initPause; onTriggered: { root.bgShown = true; tUiIn.start(); } }
    Timer { id: tUiIn;   interval: GreeterConfig.uiDelay;   onTriggered: root.uiShown = true }
    // Leave: hide the wallpaper, then launch once it has faded out (bgFade) plus the
    // configured post-pause. Timer-driven (not animation-completion) so it still
    // fires when bgFade is 0.
    Timer { id: tBgOut;  interval: GreeterConfig.uiDelay;   onTriggered: { root.bgShown = false; if (GreeterConfig.launchDelay === false) tLaunch.start(); } }
    Timer { id: tLaunch; interval: GreeterConfig.bgFade + GreeterConfig.postPause; onTriggered: root.doLaunch() }
    // Absolute launch timer (used only when launchDelay is a number).
    Timer { id: tFixedLaunch; onTriggered: root.doLaunch() }

    Component.onCompleted: tBgIn.start()

    // Live clock (locale-formatted to the system language).
    property string timeStr: ""
    property string dateStr: ""
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            const d = new Date();
            const loc = Qt.locale(Strings.lang);
            root.timeStr = d.toLocaleTimeString(loc, "HH:mm");
            root.dateStr = d.toLocaleDateString(loc, Locale.LongFormat);
        }
    }

    // Optional session source: read wayland-sessions only when the picker is on, so
    // the default secure path spawns no helper process at all.
    Loader {
        active: GreeterConfig.showSessionPicker
        sourceComponent: Process {
            running: true
            command: ["sh", "-c",
                "for f in /usr/share/wayland-sessions/*.desktop; do " +
                "n=$(sed -n 's/^Name=//p' \"$f\" | head -1); " +
                "e=$(sed -n 's/^Exec=//p' \"$f\" | head -1); " +
                "[ -n \"$e\" ] && printf '%s\\t%s\\n' \"$n\" \"$e\"; done"]
            stdout: StdioCollector { onStreamFinished: root.parseSessions(text) }
        }
    }

    // ── Wallpaper: one background layer-surface per screen ──────────────────────
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "w-greeter-bg"
            WlrLayershell.layer: WlrLayer.Background
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "black"        // the black both transitions bridge through

            Image {
                anchors.fill: parent
                // Per-monitor pick by physical width (logical × dpr) so tiers match
                // hyprpaper's hyprctl widths; fall back to the single symlink.
                source: {
                    const p = root.wallpaperFor(Math.round(modelData.width * modelData.devicePixelRatio));
                    return p ? "file://" + p : "file:///run/w/wallpaper/wallpaper";
                }
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
                opacity: bgCtl.v
            }
        }
    }

    // ── Login card: primary screen, holds keyboard focus ────────────────────────
    PanelWindow {
        id: win
        screen: root.primaryScreen()
        WlrLayershell.namespace: "w-greeter"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        onVisibleChanged: if (visible) pwd.forceActiveFocus()

        Item {
            id: content
            anchors.fill: parent
            opacity: uiCtl.v
            visible: opacity > 0.01

            // Clock — top center.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.round(parent.height * 0.16)
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.timeStr
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 92      // match hyprlock's clock
                    font.weight: Font.Light
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.dateStr
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 18
                }
            }

            // Card — centered.
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 360
                height: col.implicitHeight + 48
                radius: Geometry.radius
                // Background-only opacity (inputs/buttons keep their own full alpha),
                // so the compositor blur can show the wallpaper softly through it.
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, GreeterConfig.cardOpacity)
                border.color: Colors.border
                border.width: Geometry.border

                transformOrigin: Item.Center
                scale: root.uiShown ? 1 : 0.97
                Behavior on scale {
                    NumberAnimation {
                        duration: GreeterConfig.uiFade
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                Column {
                    id: col
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 14

                    // User — dropdown when >1 account, else a static label.
                    Item {
                        width: parent.width
                        height: 46

                        Dropdown {
                            anchors.fill: parent
                            visible: root.users.length > 1
                            model: root.userOptions
                            currentValue: root.username
                            onActivated: (v) => root.username = v
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.users.length <= 1
                            // Inline binding (reactive on users/username) — a function
                            // call would not re-evaluate when /etc/passwd loads.
                            text: {
                                for (const u of root.users) if (u.name === root.username) return u.label;
                                return root.username;
                            }
                            color: Colors.text
                            font.family: Fonts.family
                            font.pixelSize: 18
                            font.weight: Font.Medium
                        }
                    }

                    // Password — focused by default; Enter submits. Same fixed-width
                    // focus ring as Dropdown/Login/power buttons (see Dropdown.qml).
                    Rectangle {
                        width: parent.width
                        height: 54                  // match hyprlock's input-field
                        radius: Geometry.radiusSm
                        color: Colors.inputBg
                        border.width: 1.5
                        border.color: root.errorText.length ? Colors.dangerBorder : (pwd.activeFocus ? Colors.accent : "transparent")
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        TextField {
                            id: pwd
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            // Centered like hyprlock's dots_center: the masked dots
                            // (and placeholder) grow out from the middle, not the left.
                            horizontalAlignment: TextInput.AlignHCenter
                            background: null
                            echoMode: TextInput.Password
                            enabled: !root.busy
                            color: Colors.text
                            placeholderText: Strings.t("password")
                            placeholderTextColor: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 16
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.accentFg
                            focus: true

                            onTextChanged: root.errorText = ""
                            Keys.onReturnPressed: root.submit()
                            Keys.onEnterPressed: root.submit()
                            // Up/Down (and Ctrl+J/K for power users) jump to the
                            // previous/next focusable via the same chain Tab already
                            // walks — see Dropdown.qml for why this is per-item
                            // instead of one shared handler (no cross-file scope).
                            Keys.onPressed: (event) => {
                                const fwd = event.key === Qt.Key_Down || (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier));
                                const bwd = event.key === Qt.Key_Up   || (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier));
                                if (fwd) { pwd.nextItemInFocusChain(true).forceActiveFocus(); event.accepted = true; }
                                else if (bwd) { pwd.nextItemInFocusChain(false).forceActiveFocus(); event.accepted = true; }
                            }
                        }
                    }

                    // Error message (collapses when empty).
                    Text {
                        width: parent.width
                        visible: root.errorText.length > 0
                        height: visible ? implicitHeight : 0
                        text: root.errorText
                        color: Colors.dangerBorder
                        font.family: Fonts.family
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Session — dropdown above Log In (only when enabled and present).
                    Dropdown {
                        width: parent.width
                        visible: GreeterConfig.showSessionPicker && root.sessions.length > 0
                        height: visible ? 46 : 0
                        placeholder: Strings.t("session")
                        model: root.sessionOptions
                        currentValue: root.sessionName
                        onActivated: (v) => root.selectSession(v)
                    }

                    // Log In. Reachable via Tab too, even though Enter in the password
                    // field already triggers the same submit() — no HubNavKeys here
                    // (see Dropdown.qml), just activeFocusOnTab + Enter/Space. Same
                    // fixed-width focus ring as Dropdown/Password/power buttons — the
                    // ring reads against the lightened hover/focus fill because it
                    // stays the un-lightened accent (one shade darker than the fill).
                    Rectangle {
                        id: loginBtn
                        width: parent.width
                        height: 46
                        radius: Geometry.radiusSm
                        color: (loginMa.containsMouse || loginBtn.activeFocus) && !root.busy ? Qt.lighter(Colors.accent, 1.18) : Colors.accent
                        opacity: root.busy ? 0.6 : 1
                        border.width: 1.5
                        border.color: (loginMa.containsMouse || loginBtn.activeFocus) && !root.busy ? Colors.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        activeFocusOnTab: !root.busy
                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                        Keys.onSpacePressed: root.submit()
                        Keys.onPressed: (event) => {
                            const fwd = event.key === Qt.Key_Down || (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier));
                            const bwd = event.key === Qt.Key_Up   || (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier));
                            if (fwd) { loginBtn.nextItemInFocusChain(true).forceActiveFocus(); event.accepted = true; }
                            else if (bwd) { loginBtn.nextItemInFocusChain(false).forceActiveFocus(); event.accepted = true; }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.busy ? Strings.t("authenticating") : Strings.t("login")
                            color: Colors.accentFg
                            font.family: Fonts.family
                            font.pixelSize: 16
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: loginMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit()
                        }
                    }
                }
            }

            // Power row — bottom center: restart / shut down.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(parent.height * 0.08)
                spacing: 16

                Repeater {
                    model: [
                        { verb: "reboot",   key: "reboot" },
                        { verb: "poweroff", key: "shutdown" },
                    ]
                    delegate: Rectangle {
                        id: powerBtn
                        required property var modelData
                        width: label.implicitWidth + 32
                        height: 38
                        radius: Geometry.radiusSm
                        // Same fixed-width focus ring as Dropdown/Password/Login —
                        // width never changes, only color, so it never pops.
                        color: Colors.surface
                        border.width: 1.5
                        border.color: (powerMa.containsMouse || powerBtn.activeFocus) ? Colors.accent : Colors.border
                        opacity: 0.9
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        activeFocusOnTab: true
                        Keys.onReturnPressed: root.power(powerBtn.modelData.verb)
                        Keys.onEnterPressed: root.power(powerBtn.modelData.verb)
                        Keys.onSpacePressed: root.power(powerBtn.modelData.verb)
                        Keys.onPressed: (event) => {
                            const fwd = event.key === Qt.Key_Down || (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier));
                            const bwd = event.key === Qt.Key_Up   || (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier));
                            if (fwd) { powerBtn.nextItemInFocusChain(true).forceActiveFocus(); event.accepted = true; }
                            else if (bwd) { powerBtn.nextItemInFocusChain(false).forceActiveFocus(); event.accepted = true; }
                        }

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: Strings.t(powerBtn.modelData.key)
                            color: (powerMa.containsMouse || powerBtn.activeFocus) ? Colors.text : Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 14
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        MouseArea {
                            id: powerMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.power(powerBtn.modelData.verb)
                        }
                    }
                }
            }
        }
    }
}
