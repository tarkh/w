// W Linux — unified authentication prompt.
// The single system password dialog: one centered card for every polkit request
// (pkexec, mounting, w-hub-actuate, sudo-in-GUI…), replacing hyprpolkitagent's GTK
// window. It is driven entirely by the w-authd daemon (systemd --user service),
// which IS the polkit agent and forwards prompts as newline-JSON over a unix socket
// ($XDG_RUNTIME_DIR/w/authd.sock). The typed password goes back over the same socket
// — never through argv. Fingerprint needs no special handling: w-authd runs the PAM
// stack (pam_fprintd sufficient), so a "Place your finger" info message simply lands
// in the hint line and a successful scan closes the card without any typing.
//
// Placement: a full-screen overlay layer-surface (lands on the focused monitor, like
// the launcher), the card true-centered. The rest of the screen is only DIMMED (not
// blurred) so the context ("what am I authorizing") stays legible; blur is applied
// ONLY under the card via a per-namespace ignore_alpha rule in hyprland.lua (the dim's
// low alpha stays below the blur threshold, the denser card clears it → frosted card,
// dimmed surroundings). Auth outranks every popup: while it is up, Overlays.suspended
// hides any open launcher/Hub, which restore when it closes.
//
// The card always names the account it is asking for, and offers the other identities
// polkit will accept when the session's own user is not one of them (a non-admin
// triggering an auth_admin action) — see the "whose password" block below.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import qs.core
import qs.modules.shading

Scope {
    id: root

    // curId ≥ 0 while a prompt is open; -1 when idle. Only messages carrying the
    // current id are honoured (a stale prompt's late messages are ignored).
    property int curId: -1
    property string message: ""
    property string actionId: ""
    property string iconName: ""
    property string promptText: ""
    property string infoText: ""
    property string errorText: ""
    property bool checking: false          // response sent, waiting on the verdict
    property int failCount: 0              // failed tries this prompt → cooldown hint
    property string promptKind: "password" // "password" | "confirm" (gcr keyring)
    property string choiceLabel: ""        // checkbox label ("" = no checkbox)
    property bool choiceChecked: false     // e.g. "Automatically unlock this key…"

    // ── fingerprint mode ─────────────────────────────────────────────────────
    // The daemon says on `begin` whether PAM will really try a finger (fp) — it
    // asks fprintd, so this is a fact about the machine, not a guess from prompt
    // text. While fpMode holds, the card shows a glyph and a line of guidance and
    // NO input: there is nothing to type yet, and a password field standing next
    // to "touch the reader" is exactly the ambiguity this mode removes.
    //
    // Two things end it, both honest:
    //   • `request` — pam_fprintd gave up (bad swipes / timeout) and PAM moved on
    //     to the password. This is the "finger failed a few times" path, and it
    //     converts the card in place rather than opening a second window.
    //   • the user asking for it (usePassword) — see root.usePassword().
    property bool fpAvailable: false
    property bool fpUserOptedOut: false
    readonly property bool fpMode: root.fpAvailable && !root.fpUserOptedOut
                                   && root.promptText.length === 0

    // The opt-out normally produces a password prompt within a blink (the daemon
    // restarts PAM with the reader skipped), so the "still waiting" note must not
    // flash on the healthy path. It appears only if the switch did NOT land —
    // an old daemon without the skip support, or a PAM stack deployed without the
    // gate — where the honest answer really is "your password is queued".
    property bool fpOptOutStalled: false
    onFpUserOptedOutChanged: {
        root.fpOptOutStalled = false;
        if (root.fpUserOptedOut) stallTimer.restart(); else stallTimer.stop();
    }
    Timer { id: stallTimer; interval: 1200; onTriggered: root.fpOptOutStalled = true }

    // Whose password is being asked for, and — when the answer isn't "yours" — who else
    // may answer. A polkit auth_admin action raised on a NON-admin's session sends the
    // machine's administrators here: without the name the card asked for "the password"
    // and the user typed their own, got refused and learned nothing; without the list
    // an administrator standing right there had no way to authenticate at all. `users`
    // is empty whenever the session's own user is among the identities (the ordinary
    // case, nothing to choose) and for gcr/keyring prompts, which carry no identity.
    //
    // `authSelf` is what keeps that label from becoming noise: on the ordinary prompt
    // the account IS the person at the keyboard, and "Password for user w" tells them
    // something they cannot not know. The line earns its space only when the identity
    // is somebody else, or when it heads a picker. Default false — an older daemon
    // that does not send the flag keeps the old, more talkative behaviour rather than
    // silently hiding a name that mattered.
    property string authUser: ""
    property var authUsers: []
    property bool authSelf: false
    property bool pickerOpen: false

    readonly property bool active: root.curId >= 0

    // Auth is top-priority: suspend whatever popup is open so it steps aside, and
    // restore it when the prompt closes. (Idempotent with the Hub's own suspend when
    // the Hub itself triggered the pkexec.)
    onActiveChanged: Overlays.suspended = root.active

    // ── socket to w-authd ────────────────────────────────────────────────────
    // NB: `connected` is driven IMPERATIVELY, never bound to a literal `true`. A
    // declarative `connected: true` binding pins the property, so after the daemon
    // restarts (socket drops) the reconnect check `!sock.connected` can never be
    // true and the shell never re-attaches. We open on start and re-open on drop.
    Socket {
        id: sock
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/w/authd.sock"
        parser: SplitParser { onRead: (line) => root.onMessage(line) }
    }
    // Poll: attach whenever down. Covers both startup ordering (daemon not up yet
    // when the shell launches) and a daemon restart (socket drops mid-session). A
    // steady 2s poll is simpler and more robust than event-driven start/stop, which
    // relies on a disconnect signal that may not fire on an abrupt server exit.
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!sock.connected) sock.connected = true
    }
    // On a wrong password polkit re-initiates with a fresh id within a moment; if no
    // new "begin" arrives after a failure, the attempt is truly over → close.
    Timer { id: closeTimer; interval: 1500; onTriggered: root.dismiss() }

    function send(obj) { sock.write(JSON.stringify(obj) + "\n"); }

    function onMessage(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        if (m.type === "begin") {
            const retry = closeTimer.running;   // this begin is a post-failure retry
            closeTimer.stop();
            root.curId = m.id;
            root.message = m.message || "";
            root.actionId = m.action || "";
            root.iconName = m.icon || "";
            root.promptKind = m.kind || "password";
            root.choiceLabel = m.choice || "";
            root.choiceChecked = false;
            root.authUser = m.user || "";
            root.authUsers = m.users || [];
            root.authSelf = m.self === true;
            root.pickerOpen = false;
            root.promptText = "";
            root.infoText = "";
            root.fpAvailable = !!m.fp;
            root.fpUserOptedOut = false;
            if (!retry) { root.errorText = ""; root.failCount = 0; }   // fresh prompt
            root.checking = false;
            field.text = "";
            card.focusRow(card.fieldRowIndex());
            return;
        }
        if (m.id !== root.curId) return;
        switch (m.type) {
        case "request":
            // PAM is asking for a password, which is also the signal that the
            // fingerprint module has given up. Setting promptText ends fpMode, so
            // route focus into the field that just appeared — nothing else does it,
            // and without this the roving cursor would sit on a row that no longer
            // exists and typing would go nowhere.
            root.promptText = m.prompt || "";
            card.focusRow(card.fieldRowIndex());
            break;
        case "info":    root.infoText = m.text || ""; break;
        case "error":                             // a try failed; daemon retries in place
            root.errorText = m.text || Strings.t("auth.failed");
            root.checking = false;
            // A bad SWIPE is not a bad password: pam_fprintd reports each mismatch
            // while it still owns the conversation, and counting those toward the
            // faillock hint would warn about a lockout that nothing is approaching.
            // The password counter starts once PAM actually asks for a password.
            if (!root.fpMode) {
                root.failCount += 1;
                field.text = "";                  // clear so the next try starts empty
                // A retry is a FRESH PAM conversation, and the stack starts at
                // pam_fprintd again — so the reader really is being waited on once
                // more, and the card says so instead of showing a password field
                // that will sit unanswered for several seconds. Whoever explicitly
                // asked for the password keeps it: fpUserOptedOut is not reset here,
                // only by the next `begin`.
                root.promptText = "";
                root.infoText = "";
                card.focusRow(card.fieldRowIndex());
            }
            break;
        case "end":
            if (m.result === "ok" || m.result === "cancel") {
                root.dismiss();
            } else {                              // terminal failure (tries exhausted)
                root.checking = false;
                if (!root.errorText) root.errorText = Strings.t("auth.failed");
                root.failCount += 1;
                field.text = "";
                closeTimer.restart();
            }
            break;
        }
    }

    // Leave fingerprint mode on the user's initiative (reader unreachable, wrong
    // hand, plain preference). The daemon does the real work: it restarts the PAM
    // session with pam_fprintd skipped, so the password prompt arrives at once
    // instead of after the reader's 30s timeout (see w-fp-gate). Nothing outside
    // PAM can interrupt pam_fprintd mid-conversation — running the stack again
    // without it is the whole mechanism.
    //
    // The field is revealed immediately rather than waiting for that round trip:
    // typing may start straight away, and a password submitted before `request`
    // lands is held by the daemon in `pending` and answered the moment PAM asks.
    function usePassword() {
        if (root.curId < 0 || !root.fpMode) return;
        root.fpUserOptedOut = true;
        root.send({ type: "skipfp", id: root.curId });
        card.focusRow(card.fieldRowIndex());
    }

    function submit() {
        if (root.curId < 0 || root.checking) return;
        root.send({ type: "response", id: root.curId,
                    password: field.text, choice: root.choiceChecked });
        root.checking = true;
        root.errorText = "";
    }

    // Switch to another administrator: the daemon rebuilds its PolkitAgent.Session for
    // that identity (the session is bound to it) and re-sends `begin`, which resets the
    // card exactly as a fresh prompt would.
    function selectUser(name) {
        root.pickerOpen = false;
        if (root.curId < 0 || name === root.authUser) return;
        root.send({ type: "select", id: root.curId, user: name });
    }

    function cancel() {
        if (root.curId < 0) return;
        root.send({ type: "cancel", id: root.curId });
        root.dismiss();
    }

    function dismiss() { closeTimer.stop(); root.curId = -1; }

    // ── surface ──────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.active || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Overlay above everything, exclusive keyboard grab while active. hyprland.lua
        // attaches a blur rule with a raised ignore_alpha so only the card frosts.
        WlrLayershell.namespace: "quickshell:auth"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Focus routing itself is driven by onMessage's "begin" handler (fires on every
        // open/retry/user-switch); here we only re-probe the active hotkeys profile's
        // menu_* chords, since this card isn't opened through the Hub (no other caller
        // does this on its behalf — see Hub.qml's onActiveChanged).
        onVisibleChanged: if (visible) HubNavKeys.refresh()

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

            // Plain dim (no blur). An auth prompt is a deliberate modal decision point,
            // not an ephemeral popup — like GNOME/KDE/macOS it does NOT dismiss on a
            // click outside (that would risk an accidental cancel). Dismiss is explicit:
            // Esc or the Cancel button. The MouseArea just absorbs stray clicks.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Colors.backdrop.r, Colors.backdrop.g, Colors.backdrop.b, AuthConfig.dim)
                MouseArea { anchors.fill: parent }
            }

            // Auth card — true-centered, compact.
            Rectangle {
                id: card
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - height) / 2)
                width: AuthConfig.cardWidth
                height: col.implicitHeight + 40
                radius: Geometry.radius
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: AuthConfig.border

                // ── Keyboard roving-focus (flat list, top→bottom) ───────────────────
                // Bespoke roving over HubNavKeys directly (not the Hub's buildContent()/
                // focusedKey machinery — this card isn't a Hub panel), same pattern as
                // VolumeControl/BrightnessControl. Unlike those, one row (the password
                // field) needs REAL Qt keyboard focus to accept typed characters —
                // focusRow() explicitly routes real focus to `field` only while it's the
                // current row, and to `card` itself everywhere else, so Space/Enter act
                // as roving commands instead of being typed into the password field.
                readonly property var rows: {
                    const r = [];
                    if (root.authUsers.length > 1 && root.promptKind !== "confirm") {
                        r.push({ type: "pickerHeader" });
                        if (root.pickerOpen)
                            for (let i = 0; i < root.authUsers.length; i++)
                                r.push({ type: "pickerRow", index: i });
                    }
                    // Fingerprint mode has no input at all: the only moves are
                    // "let me type instead" and "cancel". Authenticate is absent
                    // rather than disabled — there is nothing for it to send.
                    if (root.fpMode) {
                        r.push({ type: "usePasswordBtn" });
                        r.push({ type: "cancelBtn" });
                        return r;
                    }
                    if (root.promptKind !== "confirm") r.push({ type: "field" });
                    if (root.choiceLabel.length > 0) r.push({ type: "choice" });
                    r.push({ type: "authBtn" });
                    r.push({ type: "cancelBtn" });
                    return r;
                }
                property int focusIndex: 0
                onRowsChanged: card.focusRow(card.focusIndex)

                readonly property var focusedRow: card.rows[card.focusIndex] ?? null
                readonly property bool pickerHeaderFocused: card.focusedRow?.type === "pickerHeader"
                readonly property bool choiceFocused: card.focusedRow?.type === "choice"
                readonly property bool authBtnFocused: card.focusedRow?.type === "authBtn"
                readonly property bool cancelBtnFocused: card.focusedRow?.type === "cancelBtn"
                readonly property bool usePasswordBtnFocused: card.focusedRow?.type === "usePasswordBtn"
                function pickerRowFocused(i) {
                    return card.focusedRow?.type === "pickerRow" && card.focusedRow.index === i;
                }

                // Default entry point for a fresh/retried prompt: the field wherever it
                // sits in `rows` (after the picker header, if one is present) — so typing
                // the password works immediately, same as before this roving landed.
                function fieldRowIndex() {
                    for (let i = 0; i < card.rows.length; i++)
                        if (card.rows[i].type === "field") return i;
                    return 0;
                }

                function focusRow(i) {
                    card.focusIndex = Math.max(0, Math.min(i, card.rows.length - 1));
                    if (card.rows[card.focusIndex]?.type === "field") field.forceActiveFocus();
                    else card.forceActiveFocus();
                }

                function activateFocused() {
                    const row = card.focusedRow;
                    if (!row) return;
                    switch (row.type) {
                    case "pickerHeader": root.pickerOpen = !root.pickerOpen; return;
                    case "pickerRow": root.selectUser(root.authUsers[row.index]); return;
                    case "choice": root.choiceChecked = !root.choiceChecked; return;
                    case "authBtn": root.submit(); return;
                    case "usePasswordBtn": root.usePassword(); return;
                    case "cancelBtn": root.cancel(); return;
                    }
                }

                focus: true
                Keys.onEscapePressed: root.cancel()
                Keys.onPressed: (e) => {
                    switch (e.key) {
                    case HubNavKeys.down: card.focusRow(card.focusIndex + 1); e.accepted = true; return;
                    case HubNavKeys.up:   card.focusRow(card.focusIndex - 1); e.accepted = true; return;
                    case HubNavKeys.confirm:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        card.activateFocused();
                        e.accepted = true;
                        return;
                    }
                }

                transformOrigin: Item.Center
                scale: root.active ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Swallow clicks so they don't reach the dismiss MouseArea.
                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 20
                    spacing: 14

                    // ── header: icon + title ──────────────────────────────────
                    Row {
                        width: parent.width
                        spacing: 14

                        ShadedIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 40
                            icon: root.iconName
                            fallbackGlyph: String.fromCodePoint(0xf033e)   // nf-md-lock
                            mode: ShadedIcon.Tint
                            tint: Colors.iconTint
                            strength: 0.9
                            shade: 0.45
                            lift: 0.20
                        }

                        Column {
                            width: parent.width - 54
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: Strings.t("auth.title")
                                color: Colors.text
                                font.family: Fonts.family
                                font.pixelSize: 17
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: root.message.length > 0
                                text: root.message
                                color: Colors.muted
                                font.family: Fonts.family
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ── whose password ────────────────────────────────────────
                    // Named only when the name answers a question the user actually
                    // has. Authenticating as yourself — the overwhelmingly common
                    // prompt — is not one: the card is session-modal, there is exactly
                    // one person in front of it, and a line spelling out their own
                    // login is pure furniture. It appears when the identity is somebody
                    // else (an auth_admin action on a non-admin's session), and when the
                    // daemon sent alternatives, where it doubles as the picker header
                    // that expands in place — the card's height follows its content, so
                    // no overlay/positioning machinery is needed for a list this small.
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: root.authUser.length > 0 && root.promptKind !== "confirm"
                                 && (!root.authSelf || root.authUsers.length > 1)

                        MouseArea {
                            width: parent.width
                            height: idRow.implicitHeight
                            enabled: root.authUsers.length > 1
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.pickerOpen = !root.pickerOpen

                            Rectangle {
                                anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                                radius: Geometry.radiusSm
                                visible: card.pickerHeaderFocused
                                color: Colors.hover
                            }

                            Row {
                                id: idRow
                                width: parent.width
                                spacing: 6

                                Text {
                                    width: parent.width - (chevron.visible ? chevron.width + parent.spacing : 0)
                                    // Name what is actually being asked for. In
                                    // fingerprint mode "password for w" is simply
                                    // untrue, and the identity still matters: PAM
                                    // matches THAT account's enrolled finger.
                                    text: Strings.t(root.fpMode ? "auth.fingerprintFor" : "auth.passwordFor")
                                          .replace("%1", root.authUser)
                                    color: Colors.muted
                                    font.family: Fonts.family
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: chevron
                                    visible: root.authUsers.length > 1
                                    text: String.fromCodePoint(0xf0140)   // nf-md-chevron_down
                                    color: Colors.accent
                                    font.family: Fonts.family
                                    font.pixelSize: 14
                                    rotation: root.pickerOpen ? 180 : 0
                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: Motion.fast
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Motion.bezierCurve
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 2
                            visible: root.pickerOpen && root.authUsers.length > 1

                            Repeater {
                                model: root.authUsers

                                Rectangle {
                                    id: userRow
                                    required property string modelData
                                    required property int index
                                    readonly property bool focused: card.pickerRowFocused(userRow.index)
                                    width: parent.width
                                    height: 32
                                    radius: Geometry.radiusSm
                                    color: userRow.modelData === root.authUser ? Colors.selection
                                           : (userRow.focused ? Colors.hover : Colors.alpha(Colors.hover, 0))
                                    border.width: userRow.focused ? 2 : 0
                                    border.color: Colors.accentInk

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        verticalAlignment: Text.AlignVCenter
                                        text: userRow.modelData
                                        color: userRow.modelData === root.authUser ? Colors.text : Colors.muted
                                        font.family: Fonts.family
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectUser(userRow.modelData)
                                    }
                                }
                            }
                        }
                    }

                    // ── fingerprint stage ─────────────────────────────────────
                    // The minimal state of this card: one glyph, one line, no input.
                    // A GLYPH rather than a themed icon on purpose — it is drawn in
                    // the Nerd Font at the brand accent, so it follows a theme change
                    // exactly like the rest of the shell chrome, with no dependency on
                    // whatever the icon theme happens to carry for "fingerprint".
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.fpMode

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: String.fromCodePoint(0xf0237)   // nf-md-fingerprint
                            color: Colors.accent
                            font.family: Fonts.mono
                            font.pixelSize: 64

                            // A slow pulse: the card is waiting on a physical act, and
                            // a still glyph reads as a picture rather than a prompt.
                            SequentialAnimation on opacity {
                                running: root.fpMode
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 0.45; duration: 900
                                                  easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.45; to: 1.0; duration: 900
                                                  easing.type: Easing.InOutSine }
                            }
                        }

                        // PAM's own wording when it sent any ("Place your finger on
                        // the fingerprint reader"), our string until then — the info
                        // message arrives a beat after the card opens, and an empty
                        // gap under the glyph would read as a hung dialog.
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: root.infoText.length > 0 ? root.infoText
                                                           : Strings.t("auth.fingerprintHint")
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Opted out of the finger but PAM has not asked yet: the field is
                    // already there and typing is already being kept, so say plainly
                    // why the submit has not gone through instead of looking stuck.
                    Text {
                        width: parent.width
                        visible: root.fpAvailable && root.fpUserOptedOut
                                 && root.promptText.length === 0 && root.fpOptOutStalled
                        text: Strings.t("auth.fingerprintStillWaiting")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    // ── password field ────────────────────────────────────────
                    // A gcr "confirm" prompt (e.g. create/unlock a keyring) has no
                    // password — only a message and Continue/Cancel — so hide the field.
                    Rectangle {
                        width: parent.width
                        height: 46
                        radius: Geometry.radiusSm
                        visible: root.promptKind !== "confirm" && !root.fpMode
                        color: Colors.inputBg
                        border.width: root.errorText.length > 0 ? 1 : (field.activeFocus ? 2 : 0)
                        border.color: root.errorText.length > 0 ? Colors.dangerBorder : Colors.accentInk

                        TextField {
                            id: field
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            background: null
                            enabled: !root.checking
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            color: Colors.text
                            placeholderText: Strings.t("auth.passwordPlaceholder")
                            placeholderTextColor: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 16
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.accentFg

                            // The password row is the one place this prompt is a mode-B
                            // surface: while it holds focus the card's bare-chord switch
                            // is unreachable, so the moves are resolved here instead of
                            // being left to bubble. Bubbling only ever worked on the
                            // `default` profile — on i3-vim the card matches Qt.Key_J for
                            // "down", which a bare arrow never produces (and a typed `j`
                            // belongs to the password). See core/HubNavKeys.qml.
                            Keys.onPressed: (e) => {
                                switch (HubNavKeys.fieldAction(e)) {
                                case "down":    card.focusRow(card.focusIndex + 1); e.accepted = true; return;
                                case "up":      card.focusRow(card.focusIndex - 1); e.accepted = true; return;
                                case "confirm": root.submit(); e.accepted = true; return;
                                case "back":    root.cancel(); e.accepted = true; return;
                                }
                            }
                        }
                    }

                    // ── choice checkbox (gcr "Automatically unlock this key…") ─
                    // Native to the prompt protocol (choice-label / choice-chosen):
                    // ticking it makes gcr-ssh-agent persist the passphrase into the
                    // login keyring, so a checked box must round-trip back to the caller.
                    MouseArea {
                        width: parent.width
                        height: choiceRow.implicitHeight
                        visible: root.choiceLabel.length > 0 && !root.fpMode
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choiceChecked = !root.choiceChecked

                        Rectangle {
                            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                            radius: Geometry.radiusSm
                            visible: card.choiceFocused
                            color: Colors.hover
                        }

                        Row {
                            id: choiceRow
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 5
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.choiceChecked ? Colors.accent : Colors.inputBg
                                border.width: root.choiceChecked ? 0 : 1
                                border.color: Colors.border
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.choiceChecked
                                    text: String.fromCodePoint(0xf012c)   // nf-md-check
                                    color: Colors.accentFg
                                    font.family: Fonts.family
                                    font.pixelSize: 14
                                }
                            }
                            Text {
                                width: parent.width - 30
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.choiceLabel
                                color: Colors.muted
                                font.family: Fonts.family
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── PAM info hint (password stage) ────────────────────────
                    // The compact form, for when PAM still has something to say after
                    // the card became a password prompt. In fingerprint mode the same
                    // text is the caption under the big glyph instead of a second copy.
                    Row {
                        width: parent.width
                        spacing: 8
                        visible: root.infoText.length > 0 && !root.fpMode
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xf0237)   // nf-md-fingerprint
                            color: Colors.accent
                            font.family: Fonts.family
                            font.pixelSize: 16
                        }
                        Text {
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.infoText
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }

                    // ── error line ────────────────────────────────────────────
                    Text {
                        width: parent.width
                        visible: root.errorText.length > 0
                        text: root.errorText
                        color: Colors.dangerFg
                        font.family: Fonts.family
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }

                    // ── cooldown hint ─────────────────────────────────────────
                    // After repeated failures, remind that Arch's faillock temporarily
                    // blocks sign-in (then even a correct password fails until it clears).
                    // The exact remaining time isn't available to a user-space daemon
                    // (faillock tally is root-only), so this is an honest static note.
                    Text {
                        width: parent.width
                        visible: root.failCount >= 2
                        text: Strings.t("auth.lockoutHint")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    // ── buttons ───────────────────────────────────────────────
                    // Keyboard-navigable via card's roving (Up/Down + Enter/Space), a
                    // focus ring marks the target, Esc always cancels. (RightToLeft is
                    // visual only; roving order follows `card.rows`: Authenticate before
                    // Cancel.)
                    Row {
                        width: parent.width
                        spacing: 10
                        layoutDirection: Qt.RightToLeft

                        // Authenticate (primary). Absent in fingerprint mode: there
                        // is no input to submit, so the primary action becomes the
                        // opt-out below.
                        Rectangle {
                            id: authBtn
                            visible: !root.fpMode
                            width: 128
                            height: 40
                            radius: Geometry.radiusSm
                            opacity: root.checking ? 0.6 : 1
                            color: Colors.accent
                            border.width: card.authBtnFocused ? 2 : 0
                            border.color: Colors.accentFg
                            Text {
                                anchors.centerIn: parent
                                text: root.checking ? Strings.t("auth.checking") : Strings.t("auth.authenticate")
                                color: Colors.accentFg
                                font.family: Fonts.family
                                font.pixelSize: 14
                                font.bold: true
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.submit() }
                        }

                        // Use password instead (primary while the finger is awaited).
                        Rectangle {
                            id: usePasswordBtn
                            visible: root.fpMode
                            width: 168
                            height: 40
                            radius: Geometry.radiusSm
                            color: Colors.accent
                            border.width: card.usePasswordBtnFocused ? 2 : 0
                            border.color: Colors.accentFg
                            Text {
                                anchors.centerIn: parent
                                text: Strings.t("auth.usePassword")
                                color: Colors.accentFg
                                font.family: Fonts.family
                                font.pixelSize: 14
                                font.bold: true
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.usePassword() }
                        }

                        // Cancel (secondary).
                        Rectangle {
                            id: cancelBtn
                            width: 100
                            height: 40
                            radius: Geometry.radiusSm
                            color: Colors.inputBg
                            border.width: card.cancelBtnFocused ? 2 : 0
                            border.color: Colors.accent
                            Text {
                                anchors.centerIn: parent
                                text: Strings.t("auth.cancel")
                                color: Colors.text
                                font.family: Fonts.family
                                font.pixelSize: 14
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.cancel() }
                        }
                    }
                }
            }
        }
    }
}
