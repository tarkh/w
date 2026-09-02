pragma Singleton

// W Linux — launcher usage chart (launch-frequency ranking).
// A map of desktop-entry id → launch count. Each launch bumps its entry; the launcher
// sorts most-used first when LauncherConfig.rankByUsage is on.
//
// This is RUNTIME STATE, not config and not theme. It is a thin domain wrapper over the
// universal Store (core/Store.qml) under the "launcher.usage" key — the single
// place all userspace state is persisted. counts is a binding on Store.get, so it stays
// reactive as the store loads and on every bump.
import Quickshell
import qs.core

Singleton {
    id: root

    // entry id → launch count.
    readonly property var counts: Store.get("launcher.usage", ({}))

    function count(id) {
        return (id && root.counts[id]) || 0;
    }

    // +1 for this entry id. Reassign a fresh object so the store notices the change.
    function bump(id) {
        if (!id) return;
        const next = Object.assign({}, root.counts);
        next[id] = (next[id] || 0) + 1;
        Store.set("launcher.usage", next);
    }
}
