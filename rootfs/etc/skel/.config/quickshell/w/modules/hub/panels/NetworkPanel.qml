// W Linux — Hub Network panel (Ф3).
// The Network drill-in screen: the privileged network settings that used to live in the
// Hub root now group here — DNS provider + DNS-over-TLS mode (w-dns), the firewall
// default zone (w-firewall) and the machine hostname — plus a link out to
// nm-connection-editor for the things we deliberately don't reinvent (Wi-Fi / VPN /
// wired connections, owned by NetworkManager).
//
// Each multi-state setting is a full-width SelectRow with a dropdown (HubMenu, hosted in
// this panel's menuLayer). It is a pure front-end over the W tools: state is read cheaply
// (`w-conf list dns --porcelain` for the DoT mode + provider — the MERGED layered
// value, not the raw /etc/w file, which holds only deviations since the split — a
// `firewall-cmd --get-default-zone` probe, `w-dns list` for the provider catalog,
// a FileView on /etc/hostname) and privileged changes are handed up to the Hub via `runPrivileged`,
// which suspends for the polkit prompt and restores + refreshes on exit. Hostname has
// no dedicated `w-*` CLI — it's one `hostnamectl` call plus mirroring the change into
// /etc/hosts' 127.0.1.1 line (hostnamectl deliberately never touches that file), both
// inlined as capability `hostname-set` in w-actuate-lib.sh next to `fwupd-refresh`
// (same precedent: a raw system command doesn't earn its own wrapper script).
//
// Loaded by the Hub via HubRegistry (Loader{source:"panels/NetworkPanel.qml"}); as a
// subdir file it is not a module type, so the shared hub components (SelectRow, HubMenu)
// come in through `import qs.modules.hub` — the same way SelectRow pulls qs.modules.shading.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.hub
import qs.modules.shading

Item {
    id: root
    // The card morphs to this. While a dropdown is open it can extend past the rows (this
    // panel is short and the card clips), so we grow to fit the menu's bottom — the card
    // expands under it instead of clipping. `menuBottom` is the open menu's lower edge in
    // panel coords (0 when closed).
    implicitHeight: Math.max(col.implicitHeight, menuLayer.menuBottom)

    // Privileged actuation: hand the pkexec command up to the Hub, which suspends for the
    // polkit prompt and restores + refreshes on exit. onDone re-reads the affected state.
    signal runPrivileged(var cmd, var onDone)

    // ── Keyboard roving-focus (flat list, top→bottom) ───────────────────────────────
    // Ordered refs to the panel's five focusable rows — filled in below once each is
    // declared (id references are valid anywhere after declaration within the same
    // component, including inside this array literal since it is only evaluated when
    // read, by which point the whole tree exists).
    readonly property var focusables: [connBtn, dnsRow, provRow, fwRow, hostRow]
    property int focusIndex: 0

    function focusRow(i) { root.focusIndex = Math.max(0, Math.min(i, root.focusables.length - 1)); }
    function openConnections() { Quickshell.execDetached(["nm-connection-editor"]); Overlays.close("hub"); }

    focus: true
    Keys.onPressed: (e) => {
        // hostField.input may still hold REAL Qt focus and just not consume this key
        // (e.g. a single-line TextField ignoring Up/Down) — let it bubble here
        // unhandled rather than silently steal the roving cursor while the user is
        // mid-edit; Tab/Esc on the field itself already return focus explicitly.
        if (hostField.input.activeFocus) return;
        switch (e.key) {
        case HubNavKeys.down: root.focusRow(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.up:   root.focusRow(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            switch (root.focusIndex) {
            case 0: root.openConnections(); break;
            case 1: dnsRow.activated(); break;
            case 2: provRow.activated(); break;
            case 3: fwRow.activated(); break;
            case 4: hostField.input.forceActiveFocus(); break;   // enter edit mode
            }
            e.accepted = true;
            return;
        }
    }

    // ── DNS state (/etc/w/dns.conf) ────────────────────────────────────────────────
    property string dnsDot: ""          // "opportunistic" | "strict" | "off" | ""
    property string dnsProvider: ""     // active resolver name (PROVIDER=)
    readonly property bool dnsAvailable: dnsDot.length > 0
    // Map the conf value to a menu id ("opportunistic" shows as "on").
    readonly property string dnsCurrentId: dnsDot === "opportunistic" ? "on" : dnsDot
    readonly property var dnsModeOptions: [
        { id: "on",     label: Strings.t("hub.dnsMode.on") },
        { id: "strict", label: Strings.t("hub.dnsMode.strict") },
        { id: "off",    label: Strings.t("hub.dnsMode.off") },
    ]

    // NOT a FileView on /etc/w/dns.conf any more: since the vendor/admin split that
    // file holds only this machine's deviations, so a machine running W's defaults
    // would read as "no DNS configured". `w-conf list --porcelain` returns the MERGED
    // view (KEY<TAB>VALUE<TAB>LAYER) the subsystem itself acts on. See w-conf.md.
    // Keys a fleet policy has locked (w-conf's `policy` layer, field 4 of the
    // porcelain). Both DNS knobs are system-scope, so the only question the Hub
    // has to ask about them is whether the local machine may still decide.
    property var dnsLocked: ({})
    Process {
        id: dnsConf
        running: true
        command: ["w-conf", "list", "dns", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                let dot = "", prov = "";
                const locked = {};
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 2) continue;
                    if (f[3] === "locked") locked[f[0]] = true;
                    if (f[0] === "DOT") dot = f[1];
                    else if (f[0] === "PROVIDER") prov = f[1];
                }
                root.dnsDot = dot;
                root.dnsProvider = prov;
                root.dnsLocked = locked;
            }
        }
    }
    function reloadDnsConf() { dnsConf.running = false; dnsConf.running = true; }

    // Provider catalog from the CLI (names only; the active one comes from the conf). The
    // list is static, so it is read once on open and needs no refresh after a switch.
    property var providerOptions: []
    Process {
        id: provRead
        running: true
        command: ["w-dns", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Each catalog line is a single token (optionally marked "* " when active);
                // the header line has several words and is skipped by the whole-line match.
                const opts = [];
                for (const line of (this.text || "").split("\n")) {
                    const m = line.match(/^\s*\*?\s*([A-Za-z0-9_]+)\s*$/);
                    if (m) opts.push({ id: m[1], label: m[1] });
                }
                root.providerOptions = opts;
            }
        }
    }

    // ── Hostname state (/etc/hostname) ──────────────────────────────────────────────
    // Read once, no watchChanges: a live watch would clobber the field while the user
    // is typing (same reasoning as AIProfilesPanel's free-text fields). Reloaded
    // explicitly after a successful apply via runPrivileged's onDone.
    property string hostnameCurrent: ""
    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        onLoaded: root.hostnameCurrent = (text() || "").trim()
    }
    function applyHostname(name) {
        root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "hostname-set", name],
                           () => hostnameFile.reload());
    }

    // ── Firewall state (default zone) ──────────────────────────────────────────────
    property string fwZone: ""          // "home" | "public" | ""
    readonly property bool fwAvailable: fwZone.length > 0
    readonly property var fwOptions: [
        { id: "home",   label: Strings.t("hub.zone.home") },
        { id: "public", label: Strings.t("hub.zone.public") },
    ]
    Process {
        id: fwRead
        running: true
        command: ["firewall-cmd", "--get-default-zone"]
        stdout: StdioCollector { onStreamFinished: root.fwZone = (this.text || "").trim() }
    }

    // ── Layout ─────────────────────────────────────────────────────────────────────
    Column {
        id: col
        width: parent.width
        spacing: 12

        // Connections → NetworkManager's editor (Wi-Fi / VPN / wired). Launch detached and
        // close the Hub so focus lands on the editor window.
        Rectangle {
            id: connBtn
            width: parent.width
            height: 38
            radius: Geometry.radiusSm
            color: (connMa.containsMouse || root.focusIndex === 0) ? Colors.hover : Colors.alpha(Colors.hover, 0)
            border.color: root.focusIndex === 0 ? Colors.accentInk : Colors.border
            border.width: root.focusIndex === 0 ? 2 : HubConfig.border
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            Row {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 10
                ChromeIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 22
                    icon: "network-wired"
                    glyph: String.fromCodePoint(0xf0317)   // nf-md-lan
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("hub.connections")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: String.fromCodePoint(0xf0142)   // nf-md-chevron_right
                font.family: Fonts.mono
                font.pixelSize: 16
                color: Colors.muted
            }
            MouseArea {
                id: connMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openConnections()
            }
        }

        // DNS: DoT mode + resolver, under one section header.
        HubSection { width: parent.width; text: Strings.t("hub.dns") }
        SelectRow {
            id: dnsRow
            width: parent.width
            icon: "network-vpn"; glyph: String.fromCodePoint(0xf1063)   // nf-md-dns
            label: Strings.t("hub.mode")
            enabled: root.dnsAvailable
            locked: root.dnsLocked["DOT"] === true
            lockedHint: Strings.t("hub.lockedByPolicy")
            currentId: root.dnsCurrentId
            options: root.dnsModeOptions
            value: root.dnsAvailable ? Strings.t("hub.dnsMode." + root.dnsCurrentId) : "—"
            focused: root.focusIndex === 1
            onActivated: menuLayer.openMenu(dnsRow, root.dnsModeOptions, root.dnsCurrentId, (id) => {
                root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "dns-mode", id],
                                   // Explicit refresh: the old FileView picked the change up via
                                   // watchChanges, a Process has to be re-run.
                                   () => root.reloadDnsConf());
            })
        }
        SelectRow {
            id: provRow
            width: parent.width
            icon: "network-server"; glyph: String.fromCodePoint(0xf048d)   // nf-md-server
            label: Strings.t("hub.dnsProvider")
            enabled: root.dnsAvailable && root.providerOptions.length > 0
            locked: root.dnsLocked["PROVIDER"] === true
            lockedHint: Strings.t("hub.lockedByPolicy")
            currentId: root.dnsProvider
            options: root.providerOptions
            value: (root.dnsAvailable && root.dnsProvider) ? root.dnsProvider : "—"
            focused: root.focusIndex === 2
            onActivated: menuLayer.openMenu(provRow, root.providerOptions, root.dnsProvider, (id) => {
                root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "dns-provider", id],
                                   // Explicit refresh: the old FileView picked the change up via
                                   // watchChanges, a Process has to be re-run.
                                   () => root.reloadDnsConf());
            })
        }

        // Firewall default zone.
        HubSection { width: parent.width; text: Strings.t("hub.firewall") }
        SelectRow {
            id: fwRow
            width: parent.width
            icon: "security-high"; glyph: String.fromCodePoint(0xf0498)  // nf-md-shield
            label: Strings.t("hub.zoneLabel")
            enabled: root.fwAvailable
            currentId: root.fwZone
            options: root.fwOptions
            value: root.fwAvailable ? Strings.t("hub.zone." + root.fwZone) : "—"
            focused: root.focusIndex === 3
            onActivated: menuLayer.openMenu(fwRow, root.fwOptions, root.fwZone, (id) => {
                root.runPrivileged(["pkexec", "/usr/lib/w/w-hub-actuate", "firewall-zone", id],
                                   () => fwRead.running = true);
            })
        }

        // Hostname: free-text field pre-filled with /etc/hostname, "Change" enabled
        // only once the field differs from the current value and passes the same
        // RFC1123-label check the actuator enforces server-side.
        HubSection { width: parent.width; text: Strings.t("hub.hostname") }
        // Wrapped (not a bare WSettingsField) so the roving cursor has something to
        // highlight while parked on this row but not yet editing — WSettingsField
        // itself carries no `focused` prop (unlike Tile/SelectRow/HubRow), its real
        // Qt activeFocus IS the "entered" state, which needs its own, later visual.
        Item {
            id: hostRow
            width: parent.width
            height: hostField.implicitHeight

            Rectangle {
                anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                radius: Geometry.radiusSm
                visible: root.focusIndex === 4 && !hostField.input.activeFocus
                color: Colors.hover
            }

            WSettingsField {
                id: hostField
                width: parent.width
                value: root.hostnameCurrent
                validator: (text) => /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(text)
                borderWidth: HubConfig.border
                onApplied: (text) => root.applyHostname(text)
                // Tab/Esc hand focus back to the row roving-nav instead of typing a
                // tab char or bubbling Esc up to Hub.back() (which would close the
                // whole panel while the user only meant to stop editing the field).
                input.Keys.onTabPressed: root.forceActiveFocus()
                input.Keys.onEscapePressed: root.forceActiveFocus()
            }
        }
    }

    // ── Dropdown overlay layer (above the rows) ────────────────────────────────────
    HubDropdown { id: menuLayer; anchors.fill: parent; returnFocusTo: root }
}
