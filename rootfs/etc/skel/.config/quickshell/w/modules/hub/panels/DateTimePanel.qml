// W Linux — Hub Date & Time panel.
// A top-level Hub section (its own root-grid tile, not nested under System): the
// timezone, the NTP on/off switch and the NTP server set, all fronted by the w-time
// CLI. Timezone drills into a searchable picker (TimezonePicker, like the locale one);
// NTP mode and the server set are dropdown SelectRows. Manual clock-setting is left to
// the `w-time set-time` CLI on purpose (with NTP on it is unnecessary, and a live time
// editor in a settings popup is fiddly for a rare action).
//
// Pure front-end over w-time: state is read cheaply (a one-shot `timedatectl show` for
// the zone + NTP flag, `w-conf list time --porcelain` for the server catalog + active
// set, a 1 s ticker for the displayed local time) and privileged changes are handed up
// to the Hub via runPrivileged (pkexec → w-hub-actuate → polkit prompt). The polkit
// path lives in w-actuate-lib.sh as capabilities timezone-set / ntp-toggle / ntp-servers.
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/DateTimePanel.qml"}); shared
// hub components (SelectRow, HubMenu, HubSection, HubRow) come via `import qs.modules.hub`.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // Grow the card to fit an open dropdown when it reaches past the rows (see NetworkPanel).
    implicitHeight: Math.max(col.implicitHeight, menuLayer.menuBottom)

    // Drill into the timezone picker; privileged actuation handed to the Hub.
    signal navigate(var route)
    signal runPrivileged(var cmd, var onDone)

    // ── Keyboard roving-focus (short fixed list, no Flickable — never scrolls) ──────
    readonly property var focusables: [tzRow, ntpRow, srvRow]
    property int focusIndex: 0

    focus: true
    Keys.onPressed: (e) => {
        const vf = root.focusables;
        switch (e.key) {
        case HubNavKeys.down: root.focusIndex = Math.min(root.focusIndex + 1, vf.length - 1); e.accepted = true; return;
        case HubNavKeys.up:   root.focusIndex = Math.max(root.focusIndex - 1, 0);              e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const item = vf[root.focusIndex];
            if (item.activated !== undefined) item.activated();
            e.accepted = true;
            return;
        }
        }
    }

    // ── Timezone + NTP state (timedatectl show) ─────────────────────────────────────
    // Read once (re-read explicitly after an actuation): a machine-readable KV dump.
    property string timezone: ""
    property string ntp: ""             // "on" | "off" | ""
    readonly property bool ntpAvailable: ntp.length > 0
    readonly property var ntpOptions: [
        { id: "on",  label: Strings.t("hub.ntp.on") },
        { id: "off", label: Strings.t("hub.ntp.off") },
    ]
    Process {
        id: tdShow
        running: true
        command: ["timedatectl", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text || "";
                const tz = t.match(/^Timezone=(\S+)/m);   root.timezone = tz ? tz[1] : "";
                const n = t.match(/^NTP=(\S+)/m);          root.ntp = n ? (n[1] === "yes" ? "on" : "off") : "";
            }
        }
    }
    function reloadState() { tdShow.running = false; tdShow.running = true; }

    // ── NTP server set (layered config, via w-conf) ─────────────────────────────────
    // NOT a FileView on /etc/w/time.conf any more: since the vendor/admin split that
    // file holds only this machine's deviations, so reading it directly would show an
    // empty catalog on a machine that never customised one. `w-conf list --porcelain`
    // returns the MERGED view (KEY<TAB>VALUE<TAB>LAYER), which is what the subsystem
    // itself acts on. See w-conf.md.
    property string serversSel: ""      // active set name (SERVERS=)
    property var serverOptions: []      // [{id,label}] from the NTP_<name> catalog
    property bool serversLocked: false  // fleet policy owns SERVERS (porcelain field 4)
    Process {
        id: timeConf
        running: true
        command: ["w-conf", "list", "time", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const opts = [];
                let sel = "", locked = false;
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 2) continue;
                    if (f[0] === "SERVERS") { sel = f[1]; locked = f[3] === "locked"; }
                    const m = f[0].match(/^NTP_([A-Za-z0-9_-]+)$/);
                    if (m) opts.push({ id: m[1], label: m[1] });
                }
                root.serversSel = sel;
                root.serverOptions = opts;
                root.serversLocked = locked;
            }
        }
    }
    function reloadTimeConf() { timeConf.running = false; timeConf.running = true; }

    // ── Live local time (display only) ──────────────────────────────────────────────
    property string clock: Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm:ss")
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.clock = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm:ss")
    }

    // ── Layout ───────────────────────────────────────────────────────────────────────
    Column {
        id: col
        width: parent.width
        spacing: 12

        // Timezone — drills into the searchable picker.
        HubSection { width: parent.width; text: Strings.t("hub.timezone") }
        HubRow {
            id: tzRow
            width: parent.width
            icon: "preferences-system-time"; glyph: String.fromCodePoint(0xf0954)  // nf-md-clock_outline
            label: Strings.t("hub.timezone")
            sublabel: root.clock
            value: root.timezone || "—"
            actionText: Strings.t("hub.change")
            focused: root.focusIndex === root.focusables.indexOf(tzRow)
            onActivated: root.navigate("datetime.timezone")
        }

        // Network time (NTP): on/off + which server set.
        HubSection { width: parent.width; text: Strings.t("hub.ntp") }
        SelectRow {
            id: ntpRow
            width: parent.width
            icon: "emblem-synchronizing"; glyph: String.fromCodePoint(0xf04e6)   // nf-md-sync
            label: Strings.t("hub.ntp")
            enabled: root.ntpAvailable
            currentId: root.ntp
            options: root.ntpOptions
            value: root.ntpAvailable ? Strings.t("hub.ntp." + root.ntp) : "—"
            focused: root.focusIndex === root.focusables.indexOf(ntpRow)
            onActivated: menuLayer.openMenu(ntpRow, root.ntpOptions, root.ntp, (id) => {
                root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "ntp-toggle", id],
                                   () => root.reloadState());
            })
        }
        SelectRow {
            id: srvRow
            width: parent.width
            icon: "network-server"; glyph: String.fromCodePoint(0xf048d)   // nf-md-server
            label: Strings.t("hub.ntpServers")
            enabled: root.serverOptions.length > 0
            locked: root.serversLocked
            lockedHint: Strings.t("hub.lockedByPolicy")
            currentId: root.serversSel
            options: root.serverOptions
            value: root.serversSel || "—"
            focused: root.focusIndex === root.focusables.indexOf(srvRow)
            onActivated: menuLayer.openMenu(srvRow, root.serverOptions, root.serversSel, (id) => {
                // Explicit refresh: the old FileView picked the new selection up via
                // watchChanges, a Process has to be re-run.
                root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "ntp-servers", id],
                                   () => root.reloadTimeConf());
            })
        }
    }

    // ── Dropdown overlay layer (above the rows) ────────────────────────────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }
}
