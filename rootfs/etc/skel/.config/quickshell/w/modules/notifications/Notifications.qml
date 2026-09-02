// W Linux — Notification daemon (Quickshell).
// Quickshell IS the freedesktop notification server (Quickshell.Services.
// Notifications.NotificationServer) — no external daemon (dunst/mako). Popups
// stack in the top-right corner sharing the shell's card material (Colors/Motion/
// Fonts), exactly like the Volume Control card.
//
// Unlike the other popups this is NOT a toggle: the server is always registered
// and cards appear reactively. The window also differs in one key way — it must
// never grab the keyboard and must let clicks pass THROUGH everywhere except over
// a card, so `mask` is restricted to the card stack (a full-screen backdrop, as
// in Launcher/VolumeControl, would wrongly eat clicks meant for windows beneath).
//
// Ordering: a QML ListModel holds notification ids newest-first; new ones are
// inserted at row 0 so the ListView animates them in at the top while the rest
// slide down (add / displaced / remove transitions). The live Notification object
// is resolved from the server by id, so in-place replaces update bound text with
// no churn. Timeouts come from NotifConfig per urgency (not the client hint);
// hovering a card pauses its dismiss timer.
//
// Do Not Disturb and per-app mute gate only the POPUP: a suppressed notification is
// still recorded in the history file, so turning DND on hides interruptions without
// ever losing information (`w-notify history` / the Hub's Notifications panel replay
// what was missed). This shell is the only writer of that file; w-notify reads it and
// clears it by watermark rather than by editing it — see NotifConfig.qml.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick
import qs.core
import qs.modules.bar

Scope {
    id: root

    // ── Server ───────────────────────────────────────────────────────────────
    NotificationServer {
        id: server
        keepOnReload: true          // survive a shell reload (re-emits last generation)
        imageSupported: true        // advertise image hints (profile pics etc.)
        actionsSupported: true      // advertise actions (we invoke the "default" one on click)
        actionIconsSupported: false
        bodySupported: true
        persistenceSupported: false
        inlineReplySupported: false

        onNotification: (n) => {
            // Record first — history must capture what the popup is about to hide.
            const suppressed = root.suppresses(n);
            root.record(n, suppressed);
            // Suppressed alerts are deliberately left untracked: nothing will ever
            // render them, so keeping them alive on the server would only leak.
            if (suppressed) return;

            n.tracked = true;       // keep it alive and in trackedNotifications

            const existing = root.indexOfId(n.id);
            if (existing >= 0) {
                // In-place replace (same id): un-close it (in case it was fading),
                // bump to the top and restart its timer.
                notifModel.setProperty(existing, "closing", 0);
                notifModel.setProperty(existing, "gen", notifModel.get(existing).gen + 1);
                if (existing !== 0) notifModel.move(existing, 0, 1);
            } else {
                notifModel.insert(0, { "nid": n.id, "gen": 0, "closing": 0 });
            }

            root.trimToCap();
        }
    }

    // Begin closing the oldest cards beyond the visible cap. We flag the row
    // `closing` (delegate fades + collapses, then reaps itself) rather than
    // hard-removing — every card animates out, never blinks.
    function trimToCap() {
        let active = [];
        for (let i = 0; i < notifModel.count; i++)
            if (!notifModel.get(i).closing) active.push(i);
        while (active.length > NotifConfig.maxVisible) {
            const idx = active.pop();          // bottom-most = oldest active
            const n = root.notifById(notifModel.get(idx).nid);
            notifModel.setProperty(idx, "closing", 1);
            if (n) n.expire();
        }
    }

    // When a notification leaves the server (expired / dismissed / closed by the
    // app), start its exit animation instead of yanking the row out.
    Connections {
        target: server.trackedNotifications
        function onValuesChanged() { root.prune(); }
    }

    // ── Model (ids only — the live object is resolved by id) ──────────────────
    ListModel { id: notifModel }

    function indexOfId(id) {
        for (let i = 0; i < notifModel.count; i++)
            if (notifModel.get(i).nid === id) return i;
        return -1;
    }

    function notifById(id) {
        const vals = server.trackedNotifications.values;
        for (let i = 0; i < vals.length; i++)
            if (vals[i].id === id) return vals[i];
        return null;
    }

    // Flag rows whose notification is gone from the server as `closing` so the
    // delegate plays its fade-out. The delegate removes the row when done.
    function prune() {
        const vals = server.trackedNotifications.values;
        for (let i = 0; i < notifModel.count; i++) {
            const row = notifModel.get(i);
            if (row.closing) continue;
            let alive = false;
            for (let j = 0; j < vals.length; j++) if (vals[j].id === row.nid) { alive = true; break; }
            if (!alive) notifModel.setProperty(i, "closing", 1);
        }
    }

    // Actually remove a row once its exit animation has finished (called by the
    // delegate). Looked up by id since indices shift as siblings come and go.
    function reapRow(nid) {
        const i = root.indexOfId(nid);
        if (i >= 0) notifModel.remove(i);
    }

    // ── Do Not Disturb ────────────────────────────────────────────────────────
    // Hyprland reports fullscreen transitions on the event socket, so auto-DND costs
    // one event handler and no polling. The initial state is assumed "not fullscreen"
    // (the socket only reports changes) and self-corrects on the first transition.
    property bool fullscreenActive: false

    Connections {
        target: Hyprland
        enabled: NotifConfig.dndAutoFullscreen
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.fullscreenActive = (event.data || "").trim() === "1";
        }
    }

    readonly property bool quiet: NotifConfig.dndActive
        || (NotifConfig.dndAutoFullscreen && root.fullscreenActive)

    // Should this notification be kept off the screen? Critical alerts may pass DND
    // (allowCritical, on by default) but never a per-app mute — muting an app is an
    // explicit, deliberate choice, whereas DND is a temporary mood.
    function suppresses(n) {
        if (NotifConfig.isMuted(n.appName)) return true;
        if (!root.quiet) return false;
        return !(NotifConfig.dndAllowCritical && n.urgency === NotificationUrgency.Critical);
    }

    // ── History (this shell is the only writer; w-notify only reads) ──────────
    property var history: []
    readonly property int historyCap: 200

    function urgencyName(u) {
        switch (u) {
        case NotificationUrgency.Low:      return "low";
        case NotificationUrgency.Critical: return "critical";
        default:                           return "normal";
        }
    }

    function record(n, suppressed) {
        // The image hint is a temporary pixmap whose path dies with the notification,
        // so history keeps only the app-icon NAME — resolvable again later.
        const entry = {
            "id": n.id,
            "ts": Math.floor(Date.now() / 1000),
            "app": n.appName || "",
            "icon": n.appIcon || "",
            "summary": n.summary || "",
            "body": root.stripMarkup(n.body),
            "urgency": root.urgencyName(n.urgency),
            "suppressed": suppressed
        };
        root.history = [entry].concat(root.history).slice(0, root.historyCap);
        histWriter.restart();
    }

    // Coalesce bursts: a flood of notifications must not rewrite the whole file once
    // per card.
    Timer {
        id: histWriter
        interval: 800
        onTriggered: histFile.setText(JSON.stringify(root.history))
    }

    FileView {
        id: histFile
        path: NotifConfig.historyPath
        printErrors: false          // absent until the first notification is recorded
        // No watch: we are the sole writer. `w-notify history clear` does not touch
        // this file — it records a watermark in the state file, which we honour below.
        onLoaded: {
            try {
                const a = JSON.parse(histFile.text() || "[]");
                root.history = Array.isArray(a) ? a : [];
            } catch (e) {
                root.history = [];
            }
            root.pruneCleared();
        }
    }

    function pruneCleared() {
        const c = NotifConfig.historyClearedAt;
        if (!c) return;
        const kept = root.history.filter(e => (e.ts || 0) > c);
        if (kept.length !== root.history.length) {
            root.history = kept;
            histWriter.restart();
        }
    }

    // Mirror the watermark so its handler fires here (a Connections on a singleton
    // would type-clash with Connections.target being a plain QObject).
    readonly property double clearedAt: NotifConfig.historyClearedAt
    onClearedAtChanged: root.pruneCleared()

    // ── Helpers ───────────────────────────────────────────────────────────────
    function timeoutFor(urgency) {
        switch (urgency) {
        case NotificationUrgency.Low:      return NotifConfig.timeoutLow;
        case NotificationUrgency.Critical: return NotifConfig.timeoutCritical;
        default:                           return NotifConfig.timeoutNormal;
        }
    }

    function clip(s, max) {
        s = s || "";
        return s.length > max ? s.slice(0, max - 1) + "…" : s;
    }

    // Body may carry basic markup even though we don't advertise it — strip tags.
    function stripMarkup(s) {
        return (s || "").replace(/<[^>]*>/g, "");
    }

    // LMB: invoke the "default" action (open the source), then close unless the
    // notification asked to stay (resident). With no default action, just dismiss.
    function activate(n) {
        if (!n) return;
        let def = null;
        for (let i = 0; i < n.actions.length; i++)
            if (n.actions[i].identifier === "default") { def = n.actions[i]; break; }
        // invoke() itself dismisses the notification unless it is resident; with no
        // default action there's nothing to open, so just close the card.
        if (def) def.invoke();
        else n.dismiss();
    }

    function dismissAll() {
        const live = [];
        for (let i = 0; i < notifModel.count; i++) {
            const n = root.notifById(notifModel.get(i).nid);
            if (n) live.push(n);
        }
        for (let i = 0; i < live.length; i++) live[i].dismiss();
    }

    // ── Window ────────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        // Always mapped (the daemon's surface), but click-through: input is limited
        // to the card stack via `mask`, so empty stack = nothing interactive.
        visible: true

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None   // never grab the keyboard

        // Only the card stack accepts pointer input; everywhere else passes through.
        mask: Region { item: list }

        ListView {
            id: list
            anchors {
                top: parent.top
                right: parent.right
                topMargin: BarConfig.contentTop + NotifConfig.marginTopOffset
                rightMargin: NotifConfig.marginRight
            }
            width: NotifConfig.cardWidth
            height: Math.min(contentHeight, parent.height - BarConfig.contentTop - NotifConfig.marginTop)
            spacing: NotifConfig.gap
            interactive: false
            model: notifModel
            // Keep delegates alive so add/remove transitions can animate fully.
            cacheBuffer: 100000

            // Entrance fade is driven by the delegate's own opacity (Behavior +
            // Component.onCompleted) rather than an `add` ViewTransition: a fast
            // burst of notifications interrupts/cancels an in-flight add transition
            // and leaves opacity frozen mid-fade. A Behavior always settles to its
            // target no matter how many times it is re-triggered.
            // Existing cards smoothly slide down to make room (and up when one leaves).
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Motion.base
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                }
            }
            addDisplaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Motion.base
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                }
            }
            // Exit fade is delegate-driven (opacity + height collapse), not a
            // `remove` transition: the ListView reliably animates a remove only for
            // one item, so when several cards close at once the lower ones blinked
            // out. removeDisplaced still tidies up any residual reflow on reap.
            removeDisplaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Motion.base
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                }
            }

            // ── Card delegate ─────────────────────────────────────────────────
            delegate: Item {
                id: card
                required property int index
                required property var model

                // Live object — used for click actions; null once the server drops it.
                readonly property var notif: root.notifById(model.nid)

                // Cached display fields: copied from `notif` while it exists and
                // frozen afterwards, so the card keeps its text/image through the
                // fade-out instead of blanking the instant the notification leaves
                // the server (which made the text vanish a frame before the fade).
                property string cSummary: ""
                property string cBody: ""
                property string cAppName: ""
                property string cImage: ""
                property string cIcon: ""
                property int cUrgency: NotificationUrgency.Normal
                readonly property bool critical: cUrgency === NotificationUrgency.Critical

                // True once the row is flagged for removal: drives the exit anim.
                readonly property bool closing: model.closing ? true : false

                function refresh() {
                    const n = card.notif;
                    if (!n) return;                 // keep cached values once it's gone
                    cSummary = root.clip(n.summary, NotifConfig.titleMaxChars);
                    cBody    = root.clip(root.stripMarkup(n.body), NotifConfig.bodyMaxChars);
                    cAppName = n.appName;
                    cImage   = n.image || "";
                    let ic = "";
                    if (!n.image && n.appIcon) {
                        const ai = n.appIcon;
                        if (Quickshell.hasThemeIcon(ai)) ic = Quickshell.iconPath(ai);
                        else if (ai.startsWith("/") || ai.startsWith("file:")) ic = ai;
                    }
                    cIcon = ic;
                    cUrgency = n.urgency;
                }

                width: NotifConfig.cardWidth

                // Collapses to 0 on exit so the cards below slide up as it fades.
                height: card.closing ? 0 : NotifConfig.cardHeight
                Behavior on height {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Entrance/exit fade (delegate-driven, robust for many cards at once).
                opacity: 0
                Component.onCompleted: { refresh(); opacity = 1; }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Start the fade-out and schedule self-removal when flagged closing;
                // re-entrance if it gets un-flagged (replaced while fading).
                onClosingChanged: {
                    if (closing) { opacity = 0; reaper.start(); }
                    else         { opacity = 1; reaper.stop(); }
                }
                Timer {
                    id: reaper
                    interval: Motion.base + 40
                    onTriggered: root.reapRow(card.model.nid)
                }

                // Re-cache + restart the dismiss timer when replaced in place.
                readonly property int gen: model.gen
                onGenChanged: { refresh(); if (life.interval > 0) life.restart(); }

                Rectangle {
                    id: bg
                    anchors.fill: parent
                    radius: NotifConfig.radius
                    // Critical alerts use the red-shifted danger palette (whole card),
                    // so they stand apart from the brand-purple cards at a glance.
                    // Non-critical cards carry the effects-axis surface translucency
                    // (bg only — text/icons are separate items and stay opaque). Critical
                    // stays fully opaque so urgent alerts never wash out.
                    color: card.critical
                        ? Colors.dangerBg
                        : Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, NotifConfig.surfaceOpacity)
                    border.width: NotifConfig.border
                    border.color: card.critical ? Colors.dangerBorder : Colors.border
                    clip: true

                    Row {
                        anchors { fill: parent; margins: NotifConfig.padding }
                        spacing: 10

                        // Square cover thumbnail (image hint, else app icon).
                        Rectangle {
                            id: thumb
                            width: NotifConfig.cardHeight - 2 * NotifConfig.padding
                            height: width
                            radius: NotifConfig.imageRadius
                            color: Colors.inputBg
                            clip: true
                            visible: img.status === Image.Ready || icon.status === Image.Ready
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: img
                                anchors.fill: parent
                                source: card.cImage
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Image {
                                id: icon
                                anchors.centerIn: parent
                                width: parent.width * 0.62
                                height: width
                                sourceSize.width: width
                                sourceSize.height: width
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: img.status !== Image.Ready && status === Image.Ready
                                source: card.cImage ? "" : card.cIcon
                            }
                        }

                        // Text block: summary (1 line) + body (clamped) + app name.
                        Column {
                            width: parent.width - (thumb.visible ? thumb.width + 10 : 0)
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                text: card.cSummary
                                color: card.critical ? Colors.dangerFg : Colors.text
                                font.family: Fonts.family
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: card.cBody
                                color: card.critical ? Colors.dangerFg : Colors.muted
                                opacity: card.critical ? 0.85 : 1.0
                                font.family: Fonts.family
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: NotifConfig.bodyMaxLines
                            }
                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: card.cAppName
                                color: card.critical ? Colors.dangerFg : Colors.muted
                                opacity: 0.7
                                font.family: Fonts.family
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    // Clicks: LMB open source · RMB dismiss · Middle dismiss all.
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => {
                            if (!card.notif) return;
                            if (m.button === Qt.LeftButton)        root.activate(card.notif);
                            else if (m.button === Qt.RightButton)  card.notif.dismiss();
                            else if (m.button === Qt.MiddleButton) root.dismissAll();
                        }
                    }

                    // Auto-dismiss timer. interval 0 (critical default) = stay forever.
                    // Hovering pauses it so the card can be read / clicked.
                    Timer {
                        id: life
                        interval: root.timeoutFor(card.cUrgency)
                        running: interval > 0 && !hover.containsMouse && card.notif !== null
                        repeat: false
                        onTriggered: if (card.notif) card.notif.expire()
                    }
                }
            }
        }
    }
}
