// W Linux — tray context menu list (recursive).
// Renders one level of an SNI menu natively (themed, no platform QMenu) from a
// QsMenuHandle via QsMenuOpener. Every entry type is covered: separators, plain
// items (with optional app icon), checkbox / radiobutton items (state from
// checkState) and submenus (hasChildren → a nested flyout, this same file loaded
// recursively on hover). App-provided entry icons go through ShadedIcon with the
// originating tray block's shading settings, so menu icons recolor identically to
// the tray icons. Triggering a leaf emits triggered() and closes the whole menu;
// disabled entries are inert. Styling is theme-driven (Colors/Fonts), matching the
// Volume Control card.
import Quickshell
import QtQuick
import qs.core
import qs.modules.shading

Item {
    id: root

    property var menu: null                 // QsMenuHandle for this level
    property int depth: 0                    // nesting level (0 = root)
    property real screenW: 0                 // overlay width, for flyout overflow
    property real screenH: 0                 // overlay height, for flyout vertical clamp

    signal requestClose()                   // bubbles up to dismiss the whole menu

    readonly property int menuWidth: 260
    readonly property int rowH: 28
    readonly property int pad: 4

    // Apply the configured translucency to a theme color's alpha only.
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    // Menu icon shading mode (string → ShadedIcon enum), from TrayMenuConfig.
    // "smart" (mono ? Solid : Original) has no mono signal for raw SNI sources, so
    // here it resolves to Original — keep the applet's own icon colors untouched.
    function iconMode() {
        switch (TrayMenuConfig.iconMode) {
        case "tint":  return ShadedIcon.Tint;
        case "solid": return ShadedIcon.Solid;
        case "smart": return ShadedIcon.Original;
        default:      return ShadedIcon.Original;
        }
    }

    // Whether the separator at index i should be drawn. SNI menus (esp. GTK applets:
    // nm-applet, blueman) emit leading/trailing and back-to-back separators with
    // nothing between them — drawing them all yields empty strips and doubled lines.
    // Rule: show a separator only if it has a non-separator entry both before AND
    // after it, and the immediately preceding entry is not itself a separator (so a
    // run of separators collapses to a single line). Hidden separators take 0 height.
    function sepVisible(i) {
        const v = opener.children.values;
        if (!v || i < 0 || i >= v.length) return false;
        let before = false;
        for (let j = 0; j < i; j++) if (!v[j].isSeparator) { before = true; break; }
        if (!before) return false;
        let after = false;
        for (let j = i + 1; j < v.length; j++) if (!v[j].isSeparator) { after = true; break; }
        if (!after) return false;
        return !v[i - 1].isSeparator;   // collapse consecutive separators to one
    }

    // The entry whose submenu is currently open (null = none), and its Y within the
    // card — the flyout aligns to it. Reset only when another parent item is hovered,
    // so moving the cursor into the flyout itself does not collapse it.
    property var openEntry: null
    property real openY: 0

    implicitWidth: menuWidth
    implicitHeight: card.height

    QsMenuOpener {
        id: opener
        menu: root.menu
    }

    Rectangle {
        id: card
        width: root.menuWidth
        height: col.implicitHeight + root.pad * 2
        radius: TrayMenuConfig.radius
        color: root.withAlpha(Colors.surface, TrayMenuConfig.opacity)
        border.color: root.withAlpha(Colors.border, TrayMenuConfig.opacity)
        border.width: TrayMenuConfig.border

        Column {
            id: col
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                margins: root.pad
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: itemRoot
                    required property var modelData
                    required property int index
                    readonly property var entry: modelData
                    readonly property bool isSep: entry.isSeparator
                    // A separator only takes space/draws when not redundant (see sepVisible).
                    readonly property bool sepShown: isSep && root.sepVisible(index)
                    readonly property bool isCheck: entry.buttonType === QsMenuButtonType.CheckBox
                    readonly property bool isRadio: entry.buttonType === QsMenuButtonType.RadioButton
                    readonly property bool hasSub: entry.hasChildren
                    readonly property bool isEnabled: entry.enabled
                    readonly property bool checked: entry.checkState === Qt.Checked
                    readonly property bool hasIcon: !isCheck && !isRadio
                                                    && entry.icon !== undefined && entry.icon.length > 0

                    width: col.width
                    height: isSep ? (sepShown ? 9 : 0) : root.rowH

                    // ── Separator ────────────────────────────────────────
                    Rectangle {
                        visible: itemRoot.sepShown
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: 6; anchors.rightMargin: 6
                        height: 1
                        color: Colors.border
                        opacity: 0.5
                    }

                    // ── Row (everything else) ────────────────────────────
                    Rectangle {
                        visible: !itemRoot.isSep
                        anchors.fill: parent
                        radius: Geometry.radiusSm
                        color: (ma.containsMouse && itemRoot.isEnabled)
                               || root.openEntry === itemRoot.entry
                               ? Colors.hover : Colors.alpha(Colors.hover, 0)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 8

                            // Leading slot: app icon, or checkbox / radio indicator.
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16

                                ShadedIcon {
                                    visible: itemRoot.hasIcon
                                    anchors.fill: parent
                                    source: itemRoot.hasIcon ? itemRoot.entry.icon : ""
                                    size: 16
                                    mode: root.iconMode()
                                    tint: Colors.iconTint
                                    strength: TrayMenuConfig.iconStrength
                                    shade:    TrayMenuConfig.iconShade
                                    lift:     TrayMenuConfig.iconLift
                                }

                                // Checkbox: accent-filled rounded box with a check when checked.
                                Rectangle {
                                    visible: itemRoot.isCheck
                                    anchors.centerIn: parent
                                    width: 14; height: 14; radius: 3
                                    color: itemRoot.checked ? Colors.accent : "transparent"
                                    border.color: itemRoot.checked ? "transparent" : Colors.border
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        visible: itemRoot.checked
                                        text: "✓"
                                        color: Colors.accentFg
                                        font.family: Fonts.family
                                        font.pixelSize: 11
                                    }
                                }

                                // Radio: circle with an accent dot when selected.
                                Rectangle {
                                    visible: itemRoot.isRadio
                                    anchors.centerIn: parent
                                    width: 14; height: 14; radius: 7
                                    color: "transparent"
                                    border.color: itemRoot.checked ? Colors.accent : Colors.border
                                    border.width: 1
                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: itemRoot.checked
                                        width: 6; height: 6; radius: 3
                                        color: Colors.accent
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16 - (itemRoot.hasSub ? 14 : 0) - 16
                                text: itemRoot.entry.text
                                color: itemRoot.isEnabled ? Colors.text : Colors.muted
                                font.family: Fonts.family
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            // Submenu chevron.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: itemRoot.hasSub
                                text: "›"
                                color: Colors.muted
                                font.family: Fonts.family
                                font.pixelSize: 16
                            }
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: itemRoot.isEnabled
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                if (itemRoot.hasSub) {
                                    root.openY = itemRoot.y;
                                    root.openEntry = itemRoot.entry;
                                } else {
                                    root.openEntry = null;   // collapse any sibling flyout
                                }
                            }
                            onClicked: {
                                if (itemRoot.hasSub) {
                                    root.openY = itemRoot.y;
                                    root.openEntry = itemRoot.entry;
                                } else {
                                    itemRoot.entry.triggered();
                                    root.requestClose();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Submenu flyout (recursive) ───────────────────────────────────────
    // Placement is computed imperatively (updatePlacement) rather than via a live
    // binding: it depends on mapToGlobal(), a non-notifying call — a binding would
    // latch its first (pre-layout, ~0,0) result and never flip. We recompute on load
    // and on every sibling switch, by then the card is positioned for real.
    property bool subFlipLeft: false   // open the flyout to the left (away from the edge)
    property real subY: 0              // flyout Y within this list, clamped on screen

    Loader {
        id: subLoader
        active: root.openEntry !== null
        source: active ? Qt.resolvedUrl("TrayMenuList.qml") : ""

        readonly property real subW: item ? item.implicitWidth : root.menuWidth
        x: root.subFlipLeft ? -subW - 2 : card.width + 2
        y: root.subY

        onLoaded: {
            root.bindSub();
            root.updatePlacement();
            item.requestClose.connect(root.requestClose);   // once per load
        }
    }

    // SNI submenu entries populate asynchronously, so the flyout's height grows after
    // it loads — re-clamp its vertical position whenever that height settles.
    Connections {
        target: subLoader.item
        function onHeightChanged() { root.updatePlacement(); }
    }

    onOpenEntryChanged: if (subLoader.item) { bindSub(); updatePlacement(); }

    // Decide the flyout's side and vertical position from the card's real on-screen
    // location. Horizontal: open right by default, flip left when the right side would
    // overflow the screen (i.e. always away from the nearest edge — the tray sits at
    // the right). Vertical: start aligned to the hovered row, then nudge up if the
    // flyout would spill past the bottom edge (and never above the top).
    function updatePlacement() {
        const it = subLoader.item;
        if (!it) return;
        const subW = it.implicitWidth;
        const subH = it.height;
        if (root.screenW > 0) {
            const rightX = root.mapToGlobal(card.width + 2, 0).x;
            root.subFlipLeft = rightX + subW > root.screenW;
        }
        let y = card.y + root.openY;
        if (root.screenH > 0) {
            const topG = root.mapToGlobal(0, y).y;
            const over = (topG + subH) - root.screenH;
            if (over > 0) y -= over;
            if (root.mapToGlobal(0, y).y < 0) y -= root.mapToGlobal(0, y).y;
        }
        root.subY = y;
    }

    // (Re)bind the flyout's inputs — runs on load and when switching to a sibling
    // submenu without reloading. Signal wiring is done once in onLoaded.
    function bindSub() {
        const it = subLoader.item;
        if (!it) return;
        it.menu = root.openEntry;
        it.depth = root.depth + 1;
        it.screenW = root.screenW;
        it.screenH = root.screenH;
    }
}
