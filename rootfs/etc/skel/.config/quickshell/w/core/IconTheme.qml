pragma Singleton

// W Linux — makes themed icons survive a dark↔light theme switch.
//
// The problem, in three parts:
//
//   1. Qt resolves themed icons against a theme name it reads at startup from
//      qt6ct. qt6ct DOES re-apply it live (its plugin calls
//      QIconLoader::updateSystemTheme), but only through a filesystem watcher on
//      ~/.config/qt6ct with a THREE SECOND debounce — so Qt inside the shell
//      learns about Papirus-Dark → Papirus-Light a few seconds after w-style
//      wrote it, not immediately.
//   2. Quickshell hands QML the provider URL `image://icon/<name>` rather than a
//      file path (Quickshell.iconPath returns a request string). That URL is
//      byte-identical before and after the switch.
//   3. QQuickPixmapCache is keyed by URL, so every already-drawn icon keeps its
//      old pixmap forever — which is why the tray icons only followed the theme
//      after restarting the shell.
//
// Nothing here can shorten qt6ct's debounce, so the shell notices the icon theme
// changed (Colors.iconTheme, written by w-style's quickshell axis) and bumps
// `revision` a few seconds later — twice, because the exact moment Qt picks the
// new theme up depends on when qt6ct's timer started relative to our own write.
// ShadedIcon threads `revision` through its lookups, so a bump re-requests every
// icon in the shell: tray, launcher, menus, everything.
//
// The cost is zero while nothing changes: the timer only runs during the settle
// window after an actual icon-theme change, and a switch between two themes of
// the same appearance does not touch it at all.
import QtQuick
import Quickshell

Singleton {
    id: root

    // Bumped when the shell should re-resolve every themed icon it draws.
    property int revision: 0

    // How long after the theme change to re-request, in ms — measured, not guessed.
    // The clock that matters is qt6ct's: 3000 ms after the last write to its config
    // directory. That write (the `qt` axis, band 400) lands 0.2 s after the one this
    // shell sees (colors.json, band 100), so the earliest moment Qt can possibly
    // know the new theme is ~3.2 s from here. The second pass is insurance against
    // a slow bundle, and costs one re-request nobody sees.
    readonly property var settleDelays: [3400, 6000]
    property int _pass: 0

    // A theme switch between two themes of the same appearance keeps the same icon
    // theme, and then there is nothing to re-request — hence the comparison rather
    // than reacting to every colours reload.
    readonly property string themeName: Colors.iconTheme
    property string _applied: ""
    onThemeNameChanged: {
        if (root._applied === "" || root.themeName === root._applied) {
            root._applied = root.themeName;   // first resolve, or the same theme again
            return;
        }
        root._applied = root.themeName;
        root._pass = 0;
        settle.interval = root.settleDelays[0];
        settle.restart();
    }
    Component.onCompleted: root._applied = root.themeName

    Timer {
        id: settle
        repeat: false
        onTriggered: {
            root.revision++;
            root._pass++;
            if (root._pass < root.settleDelays.length) {
                settle.interval = root.settleDelays[root._pass] - root.settleDelays[root._pass - 1];
                settle.start();
            }
        }
    }

    // Themed-icon lookups that a binding can depend on. Quickshell's own functions
    // are plain calls with no notify signal, so a binding using them directly would
    // never re-evaluate; reading `revision` on the way through is what makes these
    // reactive. The comparison is not a guard — it is the property read.
    function has(name) {
        return root.revision >= 0 && Quickshell.hasThemeIcon(name);
    }

    function path(name) {
        return root.revision >= 0 ? Quickshell.iconPath(name) : "";
    }

    // Vary a provider URL so the pixmap cache treats it as a new request.
    //
    // `?fallback=` is the one query the icon provider accepts alongside a bare
    // name, and it is only consulted when the primary lookup FAILS — which callers
    // have already ruled out (ShadedIcon checks hasThemeIcon first). So the value
    // is free to be a cache-busting token. A URL that already carries a query is
    // left alone: the provider parses `?path=` positionally and appending to it
    // would corrupt the request rather than bust it.
    function bust(url) {
        if (!url.startsWith("image://icon/") || url.indexOf("?") !== -1) return url;
        return url + "?fallback=w-icon-rev-" + root.revision;
    }

    // True for provider URLs bust() cannot vary — those must skip the pixmap cache
    // instead, or they would never refresh. Rare (a tray item that ships its own
    // IconThemePath), so the lost caching costs nothing measurable.
    function needsUncached(url) {
        return url.startsWith("image://icon/") && url.indexOf("?") !== -1;
    }
}
