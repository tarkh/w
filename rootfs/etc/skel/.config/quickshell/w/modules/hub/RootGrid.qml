// W Linux — Hub root grid (Control Center glance).
// The Hub's landing screen: a 4×4 grid of tiles. Section tiles drill into their panels;
// Sound/Brightness open their popups (no duplicated inline sliders); the action/link
// tiles run a command or open a popup. It is a pure front-end over the W tools — the
// only state it reads here is the update count (a FileView on updates.json) for the
// Updates badge and the Backlight/KbdBacklight services (to hide Brightness only when
// neither the screen nor the keyboard has one).
//
// Composition (settled by the menu reorganisation, and the reason the numbers are what
// they are): ten section tiles in reading order — look → devices → connectivity → power
// → system → extras — then six quick actions. No divider between the two blocks: the
// tiles are visually uniform, so the seam mid-row does not read, and a caption pair
// would push the grid past the card's height ceiling and make the root glance scroll.
//
// Brightness is deliberately the LAST tile: it is the only conditional one left (Security
// moved into the System panel and took its /etc/default/limine gate with it), so on a
// machine with no backlight at all — a desktop, a VM — the grid degrades to a clean
// 4+4+4+3 with the gap at the very end instead of a hole in the middle.
//
// What is NOT here, and why: Calendar and Screenshot became launcher entries
// (/usr/share/applications/w-calendar.desktop, w-screenshot.desktop) — both are
// app-shaped one-shots rather than system state, and the bar's clock already opens the
// calendar. Security and Date & Time became tabs of the System panel. There is no Lock
// tile either: the power menu (Super+Backspace) already owns lock/logout/suspend/reboot/
// shutdown as one set — a second door to one of them only makes the grid longer.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

Item {
    id: root
    implicitHeight: grid.implicitHeight

    // Deferred close: run a command only after the Hub is fully hidden.
    //
    // NOTHING EMITS THIS RIGHT NOW — it is kept deliberately. The mechanism (this signal
    // → Hub.pendingCmd → executed from Hub's onVisibleChanged once the window unmaps)
    // exists for commands that photograph or blur the screen: run bare, they capture the
    // Hub's own fading card and the blurred backdrop behind it. The last caller was the
    // Screenshot tile, which moved to the launcher; a lock tile would need the same
    // treatment, as would any future capture/recording action. Kept as the one worked-out
    // answer to that class of bug rather than rediscovered the next time it bites.
    signal deferredExec(var cmd)
    // Drill into a Hub section panel (Appearance / Network / …). Handled by the nav stack.
    signal navigate(var route)

    readonly property int cols: 4
    readonly property int gap: 10
    readonly property real tileW: (width - (cols - 1) * gap) / cols

    // ── Keyboard roving-focus (2D grid) ─────────────────────────────────────────────
    // The Grid positioner already skips `visible:false` children when arranging (a
    // hidden Brightness tile leaves no gap on screen), so the roving order has to be
    // the same COMPACT list — not the fixed declaration order — or arrow nav would
    // drift out of sync with what is actually adjacent on screen. Read through a
    // property binding (not an imperative loop) so it recomputes for free whenever any
    // tile's own `visible` binding changes. Order here MUST match the declaration order
    // in the Grid below.
    readonly property var allTiles: [
        tAppearance, tDisplays, tNotifications, tInput,
        tHotkeys, tNetwork, tPower, tSystem,
        tAi, tPacks, tUpdates, tClipboard,
        tLayouts, tPowerMenu, tSound, tBrightness
    ]
    readonly property var visTiles: root.allTiles.filter((t) => t.visible)
    property int focusIndex: 0
    onVisTilesChanged: root.focusIndex = Math.max(0, Math.min(root.focusIndex, root.visTiles.length - 1))

    function focusTile(i) {
        root.focusIndex = Math.max(0, Math.min(i, root.visTiles.length - 1));
    }

    focus: true
    Keys.onPressed: (e) => {
        const vt = root.visTiles;
        if (vt.length === 0) return;
        switch (e.key) {
        case HubNavKeys.right: root.focusTile(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.left:  root.focusTile(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.down:  root.focusTile(root.focusIndex + root.cols); e.accepted = true; return;
        case HubNavKeys.up:    root.focusTile(root.focusIndex - root.cols); e.accepted = true; return;
        case Qt.Key_Home:  root.focusTile(0); e.accepted = true; return;
        case Qt.Key_End:   root.focusTile(vt.length - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            vt[root.focusIndex].activated();
            e.accepted = true;
            return;
        }
    }

    // ── Updates badge (~/.local/state/w/updates.json) ──────────────────────────────
    property int updRepo: 0
    property int updAur: 0
    readonly property int updCount: updRepo + updAur
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/w/updates.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { const d = JSON.parse(text() || "{}"); root.updRepo = d.repo || 0; root.updAur = d.aur || 0; }
            catch (e) { root.updRepo = 0; root.updAur = 0; }
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────────
    function openPopup(ns) { Hyprland.dispatch('hl.dsp.global("quickshell:' + ns + '")'); }
    function runAndClose(cmd) { Quickshell.execDetached(cmd); Overlays.close("hub"); }

    // ── Layout ─────────────────────────────────────────────────────────────────────
    Grid {
        id: grid
        width: parent.width
        columns: root.cols
        columnSpacing: root.gap
        rowSpacing: root.gap

        // Every tile carries an id (referenced by RootGrid.allTiles above) and a
        // `focused` binding on its own instance's `t*` id — self-reference inside an
        // object's own property list is valid QML (the id is in scope as soon as it's
        // declared) and keeps the roving-index math in one place (allTiles/visTiles)
        // instead of hand-numbering literal indices that would drift the moment the
        // conditional Brightness tile is hidden.

        // ── Sections (drill-in) ────────────────────────────────────────────────────
        Tile {
            id: tAppearance
            width: root.tileW
            icon: "preferences-desktop-theme"; glyph: String.fromCodePoint(0xf0035) // nf-md-palette
            label: Strings.t("hub.appearance")
            focused: root.focusIndex === root.visTiles.indexOf(tAppearance)
            onActivated: root.navigate("appearance")
        }
        Tile {
            id: tDisplays
            width: root.tileW
            icon: "video-display"; glyph: String.fromCodePoint(0xf0379) // nf-md-monitor
            label: Strings.t("hub.displays")
            focused: root.focusIndex === root.visTiles.indexOf(tDisplays)
            onActivated: root.navigate("displays")
        }
        Tile {
            id: tNotifications
            width: root.tileW
            icon: "preferences-desktop-notification"; glyph: String.fromCodePoint(0xf009e) // nf-md-bell
            label: Strings.t("hub.notifications")
            focused: root.focusIndex === root.visTiles.indexOf(tNotifications)
            onActivated: root.navigate("notifications")
        }
        Tile {
            id: tInput
            width: root.tileW
            icon: "input-keyboard"; glyph: String.fromCodePoint(0xf030c) // nf-md-keyboard
            label: Strings.t("hub.input")
            focused: root.focusIndex === root.visTiles.indexOf(tInput)
            onActivated: root.navigate("input")
        }
        Tile {
            id: tHotkeys
            width: root.tileW
            icon: "preferences-desktop-keyboard-shortcuts"; glyph: String.fromCodePoint(0xf030c) // nf-md-keyboard
            label: Strings.t("hub.hotkeys")
            focused: root.focusIndex === root.visTiles.indexOf(tHotkeys)
            onActivated: root.navigate("hotkeys")
        }
        Tile {
            id: tNetwork
            width: root.tileW
            icon: "preferences-system-network"; glyph: String.fromCodePoint(0xf0317) // nf-md-lan
            label: Strings.t("hub.network")
            focused: root.focusIndex === root.visTiles.indexOf(tNetwork)
            onActivated: root.navigate("network")
        }
        Tile {
            id: tPower
            width: root.tileW
            icon: "battery"; glyph: String.fromCodePoint(0xf0241) // nf-md-flash
            label: Strings.t("hub.energy")
            focused: root.focusIndex === root.visTiles.indexOf(tPower)
            onActivated: root.navigate("power")
        }
        Tile {
            id: tSystem
            width: root.tileW
            icon: "preferences-system"; glyph: String.fromCodePoint(0xf0493) // nf-md-cog
            label: Strings.t("hub.system")
            focused: root.focusIndex === root.visTiles.indexOf(tSystem)
            onActivated: root.navigate("system")
        }
        Tile {
            id: tAi
            width: root.tileW
            icon: "system-users"; glyph: String.fromCodePoint(0xf06a9) // nf-md-robot
            label: Strings.t("hub.ai")
            focused: root.focusIndex === root.visTiles.indexOf(tAi)
            onActivated: root.navigate("ai")
        }
        Tile {
            id: tPacks
            width: root.tileW
            icon: "package-x-generic"; glyph: String.fromCodePoint(0xf03d3) // nf-md-package_variant
            label: Strings.t("hub.packs")
            focused: root.focusIndex === root.visTiles.indexOf(tPacks)
            onActivated: root.navigate("packs")
        }

        // ── Quick actions (command / popup links) ──────────────────────────────────
        Tile {
            id: tUpdates
            width: root.tileW
            icon: "system-software-update"; glyph: String.fromCodePoint(0xf01da) // nf-md-download
            label: Strings.t("hub.updates")
            badge: root.updCount
            focused: root.focusIndex === root.visTiles.indexOf(tUpdates)
            onActivated: root.runAndClose(Term.exec(["w-update"]))
        }
        Tile {
            id: tClipboard
            width: root.tileW
            icon: "edit-paste"; glyph: String.fromCodePoint(0xf0192)    // nf-md-clipboard_text
            label: Strings.t("hub.clipboard")
            focused: root.focusIndex === root.visTiles.indexOf(tClipboard)
            onActivated: root.openPopup("clipboard")
        }
        Tile {
            id: tLayouts
            width: root.tileW
            icon: "preferences-system-windows"; glyph: Glyphs.layoutAll
            label: Strings.t("hub.layouts")
            focused: root.focusIndex === root.visTiles.indexOf(tLayouts)
            onActivated: root.openPopup("layouts")
        }
        Tile {
            id: tPowerMenu
            width: root.tileW
            icon: "system-shutdown"; glyph: String.fromCodePoint(0xf0425) // nf-md-power
            label: Strings.t("hub.power")
            focused: root.focusIndex === root.visTiles.indexOf(tPowerMenu)
            onActivated: root.openPopup("powermenu")
        }
        Tile {
            id: tSound
            width: root.tileW
            icon: "audio-volume-high"; glyph: Glyphs.volumeHigh
            label: Strings.t("hub.sound")
            focused: root.focusIndex === root.visTiles.indexOf(tSound)
            onActivated: root.openPopup("volumecontrol")
        }
        // Last on purpose — the grid's only conditional tile (see the file header).
        Tile {
            id: tBrightness
            width: root.tileW
            visible: Backlight.available || KbdBacklight.available
            icon: "display-brightness"; glyph: Glyphs.brightness
            label: Strings.t("hub.brightness")
            focused: root.focusIndex === root.visTiles.indexOf(tBrightness)
            onActivated: root.openPopup("brightnesscontrol")
        }
    }
}
