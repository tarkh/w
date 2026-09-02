pragma Singleton

// W Linux — universal userspace state store.
// A single persisted key→value map for RUNTIME STATE that the shell writes itself:
// launcher usage counts, the bar clock's chosen face, and any future per-user
// preference the shell needs to remember. This is NOT config and NOT theme — it is
// never hand-edited and never touched by w-style/w-theme. It lives in Quickshell's
// per-shell state dir (~/.local/state/quickshell/by-shell/<id>/w-state.json), so it is
// created on demand, survives restarts and never ships in skel.
//
// Keys are dotted namespaces ("launcher.usage", "clock.face.default"). Values are any
// JSON-serialisable value. Read with get(key, fallback); write with set(key, value).
// Persisted via the canonical FileView+JsonAdapter pattern: get() reads adapter.data,
// so bindings that call it re-evaluate both when the file loads and on every set();
// set() reassigns a NEW object so the adapter emits adapterUpdated and writes back
// (mutating in place would not trigger the signal).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Current value for a dotted key, or `def` when unset.
    function get(key, def) {
        const v = adapter.data[key];
        return v !== undefined ? v : def;
    }

    // Store a value under a dotted key (reassign a fresh object to trigger a write).
    function set(key, value) {
        const next = Object.assign({}, adapter.data);
        next[key] = value;
        adapter.data = next;
    }

    FileView {
        path: Quickshell.stateDir + "/w-state.json"
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: adapter
            property var data: ({})
        }
    }
}
