pragma Singleton

// W Linux — shell localization (user-space).
// Minimal, JSON-driven i18n shared by the whole Quickshell shell, matching the
// project's colors.json/motion.json singleton style (and the greeter's Strings).
// i18n.json maps a namespaced key ("module.thing") → { "<lang>": "text", … }.
// The active language is the 2-letter code of the system locale ($LC_MESSAGES/
// $LANG), falling back to English. To add a language, add its code to each key in
// i18n.json — no QML changes. Names the locale already knows (month/weekday names,
// week start) come from Qt.locale(), NOT this dictionary — only our own UI strings
// live here. watchChanges live-reloads the dictionary so edits show without restart;
// the active language is read once from the env (a future system-language switch
// takes effect on relogin, standard locale semantics).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string lang: "en"
    property var table: ({})

    // 2-letter language code from the system locale (e.g. "ru_RU.UTF-8" → "ru").
    function detectLang() {
        const l = Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en";
        return l.slice(0, 2).toLowerCase();
    }

    // Translate a key for the active language; fall back to English, then the key.
    function t(key) {
        const e = root.table[key];
        if (!e) return key;
        return e[root.lang] || e["en"] || key;
    }

    function apply(jsonText) {
        try { root.table = JSON.parse(jsonText); } catch (e) { /* keep keys as-is */ }
    }

    Component.onCompleted: root.lang = root.detectLang()

    FileView {
        path: Qt.resolvedUrl("i18n.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
