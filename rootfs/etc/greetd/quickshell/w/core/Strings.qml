pragma Singleton

// W Linux — greeter localization.
// Minimal, JSON-driven i18n (matches the project's colors.json/motion.json style).
// i18n.json maps a string key → { "<lang>": "text", … }. The active language is
// the 2-letter code of the system locale ($LC_MESSAGES/$LANG, exported by
// w-greeter-wrapper.sh from /etc/locale.conf), falling back to English. To add a
// language, add its code to each key in i18n.json — no QML changes.
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
        onLoaded: root.apply(text())
    }
}
