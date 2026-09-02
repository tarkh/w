pragma Singleton

// W Linux — shared state for the tray context menu.
// The tray menu is a single, shell-wide overlay (TrayMenu.qml) rather than one
// platform menu per button: SNI/QsMenuAnchor platform menus and small grab popups
// both proved unreliable on the Top-layer bar (focus/grab conflicts — same reason
// the Volume Control uses a full-screen overlay). A tray button hands us the item's
// menu handle and the button's global rect (for placement), then we show the
// overlay. Look (radius/opacity/icon shading) is its own config, TrayMenuConfig.
// close() hides it.
import Quickshell
import QtQuick

Singleton {
    id: root

    // The QsMenuHandle of the tray item whose menu is open (null when closed).
    property var menu: null
    // Global rect of the originating tray button — the menu anchors under/over it.
    property rect anchor: Qt.rect(0, 0, 0, 0)
    property bool open: false

    function show(menu, anchor) {
        root.menu = menu;
        root.anchor = anchor;
        root.open = true;
    }

    function close() {
        root.open = false;
    }
}
