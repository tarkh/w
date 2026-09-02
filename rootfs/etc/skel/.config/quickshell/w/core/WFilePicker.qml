// W Linux — WFilePicker: the shell's own file chooser.
//
// A modal browser meant to be stacked INSIDE an existing full-screen shell
// surface (anchors.fill on the host's content Item), not opened as a window of
// its own. That is the whole point of it:
//
//   • QtQuick.Dialogs' FileDialog cannot be used here — our surfaces are
//     layer-shell, and the dialog's open() is accepted while the window never
//     maps (verified with and without a FloatingWindow parent).
//   • Handing the job to a terminal file manager (yazi in chooser mode) put the
//     chooser BEHIND the calling popup: the Hub is a keyboard-exclusive overlay
//     layer with a blurred backdrop, so the terminal was neither visible nor
//     reachable without closing the very screen that asked for a file.
//
// Living inside the caller's surface makes both problems disappear: the picker
// is simply an Item with a higher stacking order, it inherits the surface's
// keyboard grab, and the screen underneath keeps its state while it is up.
//
// Generic on purpose — the theme-authoring screen is only the first consumer:
//   `nameFilters` is a plain glob list ([] = every file), and any file the
//   filter admits can be picked. Files whose suffix looks like an image get a
//   thumbnail tile; everything else gets a glyph tile, so a picker for configs
//   or fonts reads just as well as one for wallpapers.
//
// The card is FIXED height (a modal that resizes itself as folders change would
// be seasick), so the grid scrolls internally on the shared WScrollBar, using
// the same edge convention as every other scrolling Hub surface: the view
// extends into the card's right padding and the cells inset the same amount, so
// the pill lands near the card edge without touching the content.
//
// Usage:
//   WFilePicker {
//       anchors.fill: parent
//       onPicked: (path) => …
//       onDismissed: …
//   }
//   picker.request({ title: "…", filters: ["*.png"] })
//
// The picker draws the scrim; taking the host's OWN content out of focus is the
// host's job (the Hub blurs its card in-scene while `active` — the compositor
// cannot, since both are one surface). Everything visual here — scrim, surface
// translucency, whether there is blur at all — comes from the theme's effects
// axis, so the picker matches the desktop it opened on.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core

Item {
    id: root

    // ── API ───────────────────────────────────────────────────────────────────────
    property bool active: false            // the modal is up (host may read it)
    property string title: ""
    property var nameFilters: []           // globs; [] = every file
    property int columns: 3

    signal picked(string path)             // absolute path, raw (argv-safe)
    signal dismissed()                     // closed without a pick

    // Open the picker. `opts`: { title, filters, folder } — all optional; without
    // a folder it resumes wherever the user was last time.
    function request(opts) {
        const o = opts || {};
        root.title = o.title || "";
        root.nameFilters = o.filters || [];
        root.setFolder(o.folder || Store.get("picker.lastDir", root._home + "/Pictures"));
        root.gridFocusIdx = 0;
        root.focusRegion = "grid";
        root.active = true;
        places.running = true;
        root.forceActiveFocus();
    }
    function close() {
        root.active = false;
        root.dismissed();
    }

    visible: root.active
    focus: root.active

    // ── Location ──────────────────────────────────────────────────────────────────
    // The model speaks URLs and hands them back (fileUrl / parentFolder), so the URL
    // is the state and the readable path is derived from it. Percent-encoding each
    // segment (rather than the whole string) keeps names with spaces, '#' or
    // non-ASCII intact in both directions.
    readonly property string _home: Quickshell.env("HOME") || "/"
    property url folderUrl: ""
    readonly property string folderPath:
        decodeURIComponent(String(root.folderUrl).replace(/^file:\/\//, "")) || "/"

    function setFolder(path) {
        root.folderUrl = "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }
    function enter(url) {
        root.folderUrl = url;
        Store.set("picker.lastDir", root.folderPath);
    }

    // Places are offered only when they exist — a chip leading to an empty view is
    // worse than no chip. One sweep per open, so a folder made meanwhile shows up.
    property var _places: []
    readonly property var _candidates: [
        { path: root._home,                 key: "pick.home" },
        { path: root._home + "/Pictures",   key: "pick.pictures" },
        { path: root._home + "/Downloads",  key: "pick.downloads" },
        { path: root._home + "/Documents",  key: "pick.documents" }
    ]
    Process {
        id: places
        command: ["sh", "-c", 'for d in "$HOME" "$HOME/Pictures" "$HOME/Downloads" "$HOME/Documents"; do [ -d "$d" ] && echo "$d"; done']
        stdout: StdioCollector {
            onStreamFinished: root._places = (this.text || "").trim().split("\n").filter(p => p.length > 0)
        }
    }

    FolderListModel {
        id: files
        folder: root.folderUrl
        nameFilters: root.nameFilters
        showDirs: true
        showDirsFirst: true
        showFiles: true
        showHidden: false
        showDotAndDotDot: false
        showOnlyReadable: true
        caseSensitive: false          // so *.png also lists .PNG
        sortCaseSensitive: false
        sortField: FolderListModel.Name
    }

    // Suffixes that get a thumbnail instead of a glyph. Deliberately wider than what
    // Qt can decode: a format Qt has no plugin for simply fails to load and the tile
    // falls back to its name, which is still better than pretending it is not an image.
    readonly property var _imageSuffixes: ["png", "jpg", "jpeg", "webp", "avif", "heic",
                                           "heif", "tif", "tiff", "bmp", "jxl", "gif"]
    function _isImage(name) {
        const i = name.lastIndexOf(".");
        return i > 0 && root._imageSuffixes.indexOf(name.slice(i + 1).toLowerCase()) >= 0;
    }

    readonly property bool canGoUp: root.folderPath !== "/"
    function goUp() { if (root.canGoUp) root.enter(files.parentFolder); }

    // ── Keyboard roving-focus (two regions: a horizontal toolbar — up chip, then
    // the places — above a 2D grid; HubNavKeys, hjkl on i3-vim like every other
    // Hub surface. This file is `qs.core`, not `qs.modules.hub`, but HubNavKeys
    // lives in `qs.core` too, so no extra import is needed) ─────────────────────
    property string focusRegion: "grid"   // "toolbar" | "grid"
    property int toolbarIdx: 0
    property int gridFocusIdx: 0
    // Entering a folder resets the cursor to its first tile — the old index would
    // otherwise point at an unrelated file in the new listing.
    onFolderUrlChanged: root.gridFocusIdx = 0

    // The up chip is always in the layout (disabled, not hidden, at "/"), so the
    // toolbar always has at least one stop — unlike the grid, this never needs an
    // empty-list guard.
    readonly property int toolbarCount: 1 + placesRepeater.count
    function toolbarItem(i) { return i === 0 ? upChip : placesRepeater.itemAt(i - 1); }
    function moveToolbar(delta) {
        root.toolbarIdx = Math.max(0, Math.min(root.toolbarCount - 1, root.toolbarIdx + delta));
    }

    function moveGridH(delta) {
        if (files.count === 0) return;
        root.gridFocusIdx = Math.max(0, Math.min(files.count - 1, root.gridFocusIdx + delta));
        grid.positionViewAtIndex(root.gridFocusIdx, GridView.Contain);
    }
    function moveGridV(rows) {
        if (files.count === 0) return;
        root.gridFocusIdx = Math.max(0, Math.min(files.count - 1, root.gridFocusIdx + rows * root.columns));
        grid.positionViewAtIndex(root.gridFocusIdx, GridView.Contain);
    }
    // Reads straight off FolderListModel (`isFolder`/`get`, not the realized
    // delegate) so this works even for an index currently outside the view's
    // cache. Only `filePath`/`fileIsDir` are used — the two roles FolderListModel
    // itself documents for `get()`; `setFolder()` derives the URL from the path
    // the exact same way `enter()`'s callers already do (see FileTile's own
    // MouseArea), so nothing new is required from the model.
    function activateFocused() {
        if (files.count === 0) return;
        const i = root.gridFocusIdx;
        if (files.isFolder(i)) {
            root.setFolder(files.get(i, "filePath"));
            Store.set("picker.lastDir", root.folderPath);
        } else {
            const p = files.get(i, "filePath");
            Store.set("picker.lastDir", root.folderPath);
            root.active = false;
            root.picked(p);
        }
    }

    // menu_back (Esc on every shipped profile) closes, Backspace goes up — the picker
    // holds focus while it is open, so neither reaches the surface underneath. Both stay
    // region-independent (a global "leave"/"up a folder" action, not tied to where the
    // cursor is). Backspace is the one place in W where the fixed "also back" alias is
    // deliberately overridden: inside a file browser "up a level" is the stronger idiom,
    // and leaving still has a key of its own on every profile.
    //
    // `back` is matched before the switch, not as a case in it: on the default profile it
    // IS Qt.Key_Escape, and two identical case labels would silently make the second dead.
    Keys.onPressed: (e) => {
        if (e.key === HubNavKeys.back) { root.close(); e.accepted = true; return; }
        switch (e.key) {
        case Qt.Key_Escape:    root.close(); e.accepted = true; return;
        case Qt.Key_Backspace: root.goUp(); e.accepted = true; return;
        case HubNavKeys.left:
            if (root.focusRegion === "toolbar") root.moveToolbar(-1); else root.moveGridH(-1);
            e.accepted = true; return;
        case HubNavKeys.right:
            if (root.focusRegion === "toolbar") root.moveToolbar(1); else root.moveGridH(1);
            e.accepted = true; return;
        case HubNavKeys.down:
            if (root.focusRegion === "toolbar") root.focusRegion = "grid";
            else root.moveGridV(1);
            e.accepted = true; return;
        case HubNavKeys.up:
            if (root.focusRegion === "grid" && root.gridFocusIdx < root.columns) {
                root.focusRegion = "toolbar";
                root.toolbarIdx = Math.min(root.toolbarIdx, root.toolbarCount - 1);
            } else if (root.focusRegion === "grid") root.moveGridV(-1);
            e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (root.focusRegion === "toolbar") {
                const it = root.toolbarItem(root.toolbarIdx);
                if (it) it.activated();
            } else root.activateFocused();
            e.accepted = true; return;
        }
    }

    // ── Chrome ────────────────────────────────────────────────────────────────────
    // Scrim: dims the surface below (which keeps its state) and swallows the clicks
    // that would otherwise dismiss it. Same tint the full-screen overlays use.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Effects.scrimOpacity)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        id: card
        width: Overlays.cardWidth
        height: Math.min(520, root.height - 64)
        x: Math.round((root.width - width) / 2)
        // Top-pinned on the shared modal-center edge, NOT centred on its own height —
        // otherwise the picker would sit a little higher than the surface it opened
        // from (see Overlays.cardPin).
        y: Math.round((root.height - Overlays.cardPin) / 2)
        radius: Geometry.radius
        // Frosted while the theme has blur (the host blurs what is underneath), opaque
        // when it does not — translucency without blur would leave a legible screen
        // showing through the modal, which is the one thing it must not do.
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b,
                       Effects.blurEnabled ? Effects.surfaceOpacity : 1.0)
        border.color: Colors.border
        border.width: Geometry.border
        clip: true

        transformOrigin: Item.Top          // scale in from the pinned edge, like the Hub
        scale: root.active ? 1 : 0.96
        Behavior on scale {
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.bezierCurve
            }
        }

        MouseArea { anchors.fill: parent }   // clicks stay inside the card

        readonly property int pad: 16

        // Title + close.
        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: card.pad }
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 30
                text: root.title
                color: Colors.text
                font.family: Fonts.family
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: String.fromCodePoint(0xf00d)          // nf-fa-times
                color: closeMa.containsMouse ? Colors.text : Colors.muted
                font.family: Fonts.mono
                font.pixelSize: 14
                MouseArea {
                    id: closeMa
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // Navigation row: up, the current path, and the places.
        Item {
            id: nav
            anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; margins: card.pad }
            height: 26

            Row {
                id: navLeft
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 8
                width: parent.width - placesRow.width - 12

                Chip {
                    id: upChip
                    glyph: String.fromCodePoint(0xf062)     // nf-fa-arrow-up
                    enabled: root.canGoUp
                    focused: root.focusRegion === "toolbar" && root.toolbarIdx === 0
                    onActivated: root.goUp()
                }
                // A Row does not centre its children vertically, so the label carries
                // the chip's height and centres its own text inside it.
                Text {
                    width: navLeft.width - upChip.width - navLeft.spacing
                    height: upChip.height
                    verticalAlignment: Text.AlignVCenter
                    text: root.folderPath.replace(root._home, "~")
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 12
                    elide: Text.ElideLeft
                }
            }

            Row {
                id: placesRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                Repeater {
                    id: placesRepeater
                    model: root._candidates.filter(c => root._places.indexOf(c.path) >= 0)
                    delegate: Chip {
                        id: placeCell
                        required property var modelData
                        required property int index
                        label: Strings.t(modelData.key)
                        current: root.folderPath === modelData.path
                        focused: root.focusRegion === "toolbar" && root.toolbarIdx === placeCell.index + 1
                        onActivated: root.enter("file://" + modelData.path.split("/").map(encodeURIComponent).join("/"))
                    }
                }
            }
        }

        // ── The grid ──────────────────────────────────────────────────────────────
        GridView {
            id: grid
            anchors {
                top: nav.bottom; topMargin: 12
                left: parent.left; right: parent.right; bottom: parent.bottom
                leftMargin: card.pad; rightMargin: card.pad - 12; bottomMargin: card.pad
            }
            clip: true
            model: files
            cacheBuffer: 1200
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: WScrollBar {}

            readonly property int gap: 10
            // The view reaches into the card's right padding so the scrollbar pill sits
            // near the edge; the cells are laid out over the inset width, which keeps
            // the content padding symmetric.
            readonly property int cellW: Math.floor((width - 12) / root.columns)

            cellWidth: grid.cellW
            cellHeight: Math.round((grid.cellW - grid.gap) * 9 / 16) + grid.gap

            delegate: FileTile {}

            Text {
                anchors.centerIn: parent
                visible: files.count === 0
                text: Strings.t("pick.empty")
                color: Colors.muted
                font.family: Fonts.family
                font.pixelSize: 12
            }
        }
    }

    // ── Parts ─────────────────────────────────────────────────────────────────────
    // A small pill used by both the up control and the places (label OR glyph).
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property string glyph: ""
        property bool current: false
        // Keyboard roving-focus indicator, same contract as Tile/SelectRow/HubRow —
        // set by the panel's roving index.
        property bool focused: false
        // qmllint disable property-override
        property bool enabled: true
        // qmllint enable property-override
        signal activated()

        implicitWidth: chipText.implicitWidth + 18
        implicitHeight: 24
        radius: Geometry.radiusSm
        opacity: chip.enabled ? 1 : 0.35
        color: chip.current ? Colors.accent
               : ((chipMa.containsMouse || chip.focused) && chip.enabled ? Colors.hover : Colors.alpha(Colors.hover, 0))
        border.width: chip.focused ? 2 : Geometry.border
        border.color: chip.focused ? Colors.accentInk : (chip.current ? Colors.accent : Colors.border)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.glyph || chip.label
            color: chip.current ? Colors.accentFg : Colors.text
            font.family: chip.glyph ? Fonts.mono : Fonts.family
            font.pixelSize: 11
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (chip.enabled) chip.activated()
        }
    }

    // One entry: a folder, a picture, or any other file the filter admitted.
    component FileTile: Item {
        id: cell
        // Injected by the view from the FolderListModel roles.
        required property string fileName
        required property string filePath
        required property url fileUrl
        required property bool fileIsDir
        // GridView-supplied model index (same idiom as AppearancePanel.ThemeTile).
        required property int index

        readonly property bool isImage: !cell.fileIsDir && root._isImage(cell.fileName)
        readonly property bool focused: root.gridFocusIdx === cell.index

        width: grid.cellW
        height: grid.cellHeight

        Item {
            id: thumb
            width: grid.cellW - grid.gap
            height: grid.cellHeight - grid.gap
            anchors.centerIn: parent
            readonly property int rad: Geometry.radiusSm

            scale: ma.containsMouse ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: thumb.rad
                color: Colors.inputBg
            }

            // Picture: cover-cropped thumbnail, rounded with a MultiEffect alpha mask
            // (a Rectangle's clip is rectangular and would square the corners).
            Image {
                id: shot
                anchors.fill: parent
                source: cell.isImage ? cell.fileUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false                 // a folder of 5K masters must not be held in RAM
                sourceSize.width: 320        // decode small: this is a 225px tile
                visible: false
            }
            MultiEffect {
                anchors.fill: shot
                source: shot
                maskEnabled: true
                maskSource: shotMask
                visible: shot.status === Image.Ready
            }
            Item {
                id: shotMask
                anchors.fill: shot
                layer.enabled: true
                visible: false
                Rectangle { anchors.fill: parent; radius: thumb.rad; antialiasing: true }
            }

            // Glyph for a folder, and for a file with no (or not yet loaded) preview.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height / 2 - height)
                visible: cell.fileIsDir || shot.status !== Image.Ready
                text: cell.fileIsDir ? String.fromCodePoint(0xf07b)     // nf-fa-folder
                                     : String.fromCodePoint(0xf016)     // nf-fa-file-o
                color: cell.fileIsDir ? Colors.border : Colors.muted
                font.family: Fonts.mono
                font.pixelSize: 20
            }

            // Legibility scrim, only where a picture would otherwise swallow the name.
            Rectangle {
                anchors.fill: parent
                radius: thumb.rad
                visible: shot.status === Image.Ready
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                }
            }

            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                horizontalAlignment: Text.AlignHCenter
                text: cell.fileName
                color: shot.status === Image.Ready ? "#ffffff" : Colors.text
                font.family: Fonts.family
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }

            // Hover / keyboard-focus ring, drawn ON TOP of the thumbnail — the base
            // Rectangle above sits BEHIND the image and its legibility scrim, so a
            // border painted there is invisible on any tile with a preview (only
            // empty/glyph tiles showed it). Same fix AppearancePanel.ThemeTile
            // already uses for its own active/focus ring.
            Rectangle {
                anchors.fill: parent
                radius: thumb.rad
                color: "transparent"
                border.width: cell.focused ? 3 : (ma.containsMouse ? Geometry.border : 0)
                border.color: cell.focused ? Colors.accentInk : Colors.border
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (cell.fileIsDir) {
                        root.enter(cell.fileUrl);
                    } else {
                        Store.set("picker.lastDir", root.folderPath);
                        root.active = false;
                        root.picked(cell.filePath);
                    }
                }
            }
        }
    }
}
